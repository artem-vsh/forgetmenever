from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from langgraph.graph import END, StateGraph
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.llm import LLMClient
from app.models import ToDoItemModel
from app.schemas import (
    ProcessPayload,
    ProcessRequest,
    ToDoItem,
    ToDoList,
    ToDoListEvent,
)


@dataclass
class ApplyResult:
    updated: List[ToDoItem]
    removed: List[ToDoItem]


class ToDoService:
    """Service responsible for managing to-do items using an LLM for intents."""

    MAX_LLM_TURNS = 5

    def __init__(self, session: Session, llm_client: LLMClient):
        self.session = session
        self.llm_client = llm_client

    def list_items(self) -> List[ToDoItem]:
        items = self.session.execute(
            select(ToDoItemModel).order_by(ToDoItemModel.id)
        ).scalars().all()
        return [ToDoItem(text=item.text, due=item.due) for item in items]

    def process(self, payload: ProcessRequest) -> ToDoListEvent:
        """Process prompt through iterative LLM calls until no more instructions are emitted."""

        snapshot = self._snapshot_for_prompt()
        initial_messages: List[Dict[str, str]] = [
            {"role": "system", "content": self.llm_client.system_prompt},
            {
                "role": "user",
                "content": self._build_initial_user_message(payload.prompt, snapshot),
            },
        ]

        graph_state: Dict[str, Any] = {
            "messages": initial_messages,
            "todo_snapshot": snapshot,
            "turn": 0,
            "finished": False,
        }

        all_updated: List[ToDoItem] = []
        all_removed: List[ToDoItem] = []
        last_payload: Optional[Dict[str, Any]] = None

        builder = StateGraph(dict)

        def call_model(state: Dict[str, Any]) -> Dict[str, Any]:
            nonlocal last_payload
            response_payload = self.llm_client.process_messages(state["messages"])
            last_payload = response_payload
            messages = state["messages"] + [
                {"role": "assistant", "content": self._format_json(response_payload)}
            ]
            return {
                **state,
                "messages": messages,
                "turn": state["turn"] + 1,
            }

        def after_model(state: Dict[str, Any]) -> str:
            action = (last_payload or {}).get("action", "none")
            if action in {"none", "retrieve"}:
                return END
            return "apply_payload"

        def apply_payload_node(state: Dict[str, Any]) -> Dict[str, Any]:
            if last_payload is None:
                return state
            payload_model = ProcessPayload.model_validate(last_payload)
            apply_result = self._apply_payload(payload_model)
            all_updated.extend(apply_result.updated)
            all_removed.extend(apply_result.removed)

            new_snapshot = self._snapshot_for_prompt()
            followup_message = self._build_followup_user_message(new_snapshot, last_payload)
            messages = state["messages"] + [{"role": "user", "content": followup_message}]
            finished = state["turn"] >= self.MAX_LLM_TURNS
            return {
                **state,
                "messages": messages,
                "todo_snapshot": new_snapshot,
                "finished": finished,
            }

        def after_apply(state: Dict[str, Any]) -> str:
            if state.get("finished"):
                return END
            return "call_model"

        builder.add_node("call_model", call_model)
        builder.add_node("apply_payload", apply_payload_node)
        builder.set_entry_point("call_model")
        builder.add_conditional_edges(
            "call_model",
            after_model,
            {
                "apply_payload": "apply_payload",
                END: END,
            },
        )
        builder.add_conditional_edges(
            "apply_payload",
            after_apply,
            {
                "call_model": "call_model",
                END: END,
            },
        )

        graph = builder.compile()
        graph.invoke(graph_state)

        current_list = ToDoList(items=self.list_items())

        if last_payload and last_payload.get("action") == "retrieve":
            return ToDoListEvent(
                type="retrieved",
                new_list=current_list,
                updated=None,
                removed=None,
            )

        event_type = self._determine_event_type(all_updated, all_removed)
        return ToDoListEvent(
            type=event_type,
            new_list=current_list,
            updated=all_updated or None,
            removed=all_removed or None,
        )

    def clear(self) -> ToDoListEvent:
        removed_items = self._clear_items()
        return ToDoListEvent(
            type="removed",
            new_list=ToDoList(items=[]),
            removed=removed_items or None,
            updated=None,
        )

    def _apply_payload(self, payload: ProcessPayload) -> ApplyResult:
        if payload.action == "retrieve":
            return ApplyResult(updated=[], removed=[])

        if payload.action == "clear":
            removed_items = self._clear_items()
            return ApplyResult(updated=[], removed=removed_items)

        updated_items: List[ToDoItem] = []
        removed_items: List[ToDoItem] = []

        if payload.add_items:
            for item in payload.add_items:
                new_model = ToDoItemModel(text=item.text.strip(), due=item.due)
                self.session.add(new_model)
                self.session.flush()
                updated_items.append(ToDoItem(text=new_model.text, due=new_model.due))

        if payload.update_items:
            for update in payload.update_items:
                match = self._find_item(update.match_text)
                if not match:
                    continue
                update_data = update.model_dump(exclude_unset=True)
                if "new_text" in update_data:
                    match.text = (update.new_text or "").strip()
                if "new_due" in update_data:
                    match.due = update.new_due
                self.session.flush()
                updated_items.append(ToDoItem(text=match.text, due=match.due))

        if payload.remove_items:
            for remove_text in payload.remove_items:
                match = self._find_item(remove_text)
                if not match:
                    continue
                removed_items.append(ToDoItem(text=match.text, due=match.due))
                self.session.delete(match)

        self.session.commit()
        return ApplyResult(updated=updated_items, removed=removed_items)

    def _clear_items(self) -> List[ToDoItem]:
        items = self.session.execute(select(ToDoItemModel)).scalars().all()
        removed_items = [ToDoItem(text=item.text, due=item.due) for item in items]
        for item in items:
            self.session.delete(item)
        self.session.commit()
        return removed_items

    def _snapshot_for_prompt(self) -> List[Dict[str, Any]]:
        items = self.list_items()
        return [
            {
                "text": item.text,
                "due": item.due.isoformat() if item.due else None,
            }
            for item in items
        ]

    def _build_initial_user_message(self, user_prompt: str, snapshot: List[Dict[str, Any]]) -> str:
        snapshot_json = self._format_json(snapshot)
        return (
            "User request:\n"
            f"{user_prompt}\n\n"
            "Current to-do list (JSON array with fields 'text' and 'due'):\n"
            f"{snapshot_json}\n\n"
            "Provide the next set of JSON instructions. If no changes are required, respond with action \"none\"."
        )

    def _build_followup_user_message(
        self, snapshot: List[Dict[str, Any]], applied_payload: Dict[str, Any]
    ) -> str:
        snapshot_json = self._format_json(snapshot)
        payload_json = self._format_json(applied_payload)
        return (
            "Applied your previous instructions:\n"
            f"{payload_json}\n\n"
            "Updated to-do list:\n"
            f"{snapshot_json}\n\n"
            "If further changes are needed, respond with the next JSON instructions."
            " Otherwise respond with action \"none\" and empty arrays."
        )

    @staticmethod
    def _format_json(data: Any) -> str:
        return json.dumps(data, indent=2, sort_keys=True, default=str)

    def _find_item(self, match_text: str) -> Optional[ToDoItemModel]:
        if not match_text:
            return None
        stmt = (
            select(ToDoItemModel)
            .where(func.lower(ToDoItemModel.text) == func.lower(match_text.strip()))
            .order_by(ToDoItemModel.id)
        )
        return self.session.execute(stmt).scalars().first()

    @staticmethod
    def _determine_event_type(updated: List[ToDoItem], removed: List[ToDoItem]) -> str:
        if removed and not updated:
            return "removed"
        if updated:
            return "updated"
        return "none"
