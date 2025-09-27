from __future__ import annotations

from datetime import date
from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class ToDoItem(BaseModel):
    text: str
    due: Optional[date] = Field(default=None, description="Due date for the to-do item")


class ToDoList(BaseModel):
    items: List[ToDoItem] = Field(default_factory=list)


class ToDoListEvent(BaseModel):
    type: Literal["updated", "removed", "retrieved", "none"]
    new_list: ToDoList
    updated: Optional[List[ToDoItem]] = None
    removed: Optional[List[ToDoItem]] = None


class ProcessRequest(BaseModel):
    prompt: str


class ProcessPayloadItem(BaseModel):
    text: str
    due: Optional[date] = None


class UpdatePayloadItem(BaseModel):
    match_text: str
    new_text: Optional[str] = None
    new_due: Optional[date] = None


class ProcessPayload(BaseModel):
    action: Literal["add", "update", "remove", "retrieve", "clear", "mixed", "none"] = "none"
    add_items: List[ProcessPayloadItem] = Field(default_factory=list)
    update_items: List[UpdatePayloadItem] = Field(default_factory=list)
    remove_items: List[str] = Field(default_factory=list, description="Texts of items to remove")


class TranscriptResponse(BaseModel):
    text: str
