from __future__ import annotations

import json
from dataclasses import dataclass
from io import BytesIO
from typing import Any, Dict, Iterable, List
from datetime import datetime, timezone

import httpx
from openai import NotFoundError, OpenAI

from app.config import Settings


class LLMError(RuntimeError):
    """Raised when an LLM call fails or returns unexpected data."""


@dataclass
class LLMClient:
    settings: Settings

    _SYSTEM_PROMPT_TEMPLATE: str = (
        "You manage a to-do list. Always respond with JSON matching this schema: "
        "{{\"action\": one of [\"add\",\"update\",\"remove\",\"retrieve\",\"clear\",\"mixed\",\"none\"], "
        "\"add_items\": [{{\"text\": string, \"due\": YYYY-MM-DD or null}}], "
        "\"update_items\": [{{\"match_text\": string, \"new_text\": string|null, \"new_due\": YYYY-MM-DD|null}}], "
        "\"remove_items\": [string, ...] }}. Use ISO-8601 dates. "
        "Incoming text originated from an automatic speech recognizer and may contain transcription mistakes—"
        "interpret the most plausible intended tasks and dates. Current date/time (UTC): {reference_ts}. "
        "Treat this timestamp as the only source of truth for \"now\" and resolve every relative temporal reference "
        "against it. When you have no further changes to request, respond with {{\"action\": \"none\", "
        "\"add_items\": [], \"update_items\": [], \"remove_items\": []}}. Never include extra prose."
    )

    def __post_init__(self) -> None:
        api_key = (self.settings.openai_api_key or "").strip()
        has_key = bool(api_key)
        if self.settings.output_debug and api_key:
            print(f"[LLM] Using API key: {api_key}")
        base_url = (self.settings.openai_api_url or "https://api.sambanova.ai/v1").strip() or "https://api.sambanova.ai/v1"
        base_url = self._normalise_base_url(base_url)
        self._client = OpenAI(api_key=api_key or None, base_url=base_url)
        self._rest_client = httpx.Client(base_url=base_url, headers=self._default_headers(api_key), timeout=60.0)
        self._chat_model = self._sanitize_model(self.settings.openai_model, fallback="DeepSeek-V3.1")
        self._transcription_model = self._sanitize_model(
            self.settings.openai_transcription_model, fallback="Whisper-Large-v3"
        )
        self._system_prompt = self._build_system_prompt()
        print(f"[LLM] API key provided: {has_key}")
        print(f"[LLM] Base URL: {base_url}")
        print(f"[LLM] Chat model: {self._chat_model}")
        print(f"[LLM] Transcription model (initial): {self._transcription_model}")

    @staticmethod
    def _default_headers(api_key: str) -> Dict[str, str]:
        headers: Dict[str, str] = {"Accept": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        return headers

    @staticmethod
    def _normalise_base_url(value: str) -> str:
        stripped = value.rstrip('/')
        if not stripped.endswith('/v1'):
            return stripped + '/v1'
        return stripped

    @staticmethod
    def _sanitize_model(value: str, fallback: str) -> str:
        trimmed = (value or "").strip()
        return trimmed or fallback

    @property
    def system_prompt(self) -> str:
        return self._system_prompt

    def _build_system_prompt(self) -> str:
        reference_ts = self.settings.reference_datetime
        if not reference_ts:
            reference_ts = datetime.now(timezone.utc).isoformat()
        return self._SYSTEM_PROMPT_TEMPLATE.format(reference_ts=reference_ts)

    def process_messages(self, messages: List[Dict[str, str]]) -> Dict[str, Any]:
        try:
            response = self._client.chat.completions.create(
                model=self._chat_model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.1,
            )
        except Exception as exc:  # pragma: no cover - external dependency failure
            print(f"[LLM] Chat completion error: {exc!r}")
            raise LLMError(str(exc)) from exc

        try:
            content = response.choices[0].message.content
        except (AttributeError, IndexError) as exc:  # pragma: no cover - defensive guard
            raise LLMError("Invalid response shape from LLM") from exc

        return self._parse_json_payload(content)

    def process_prompt(self, prompt: str) -> Dict[str, Any]:
        messages = [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": prompt},
        ]
        return self.process_messages(messages)

    def transcribe_audio(self, file_bytes: bytes, filename: str) -> str:
        last_error: Exception | None = None
        for model_name in self._candidate_transcription_models():
            print(f"[LLM] Trying transcription model: {model_name}")
            try:
                return self._transcribe(file_bytes, filename, model_name)
            except NotFoundError as exc:
                body = getattr(exc, "body", None)
                print(f"[LLM] Model not found via SDK: {model_name} (body={body})")
                last_error = exc
                continue
            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                detail = exc.response.text
                print(f"[LLM] HTTP {status} for model {model_name}: {detail}")
                if status == 404:
                    last_error = LLMError(f"Model not found: {model_name}")
                    continue
                raise LLMError(f"HTTP {status}: {detail}") from exc
            except Exception as exc:  # pragma: no cover - external dependency failure
                print(f"[LLM] Unexpected transcription error for model {model_name}: {exc!r}")
                raise LLMError(str(exc)) from exc
        if last_error is not None:
            raise LLMError(str(last_error))
        raise LLMError("Unable to obtain transcription")

    def _candidate_transcription_models(self) -> Iterable[str]:
        base = self._transcription_model
        lower = base.lower()
        slug = lower.replace("_", "-")
        camel = "-".join(part.capitalize() for part in slug.split("-"))
        defaults = ["Whisper-Large-v3", "whisper-large-v3"]
        variants = defaults + [base, lower, slug, camel]
        seen: set[str] = set()
        for variant in variants:
            if variant and variant not in seen:
                seen.add(variant)
                yield variant

    def _transcribe(self, file_bytes: bytes, filename: str, model_name: str) -> str:
        buffer = BytesIO(file_bytes)
        buffer.name = filename
        # Try SDK first
        try:
            response = self._client.audio.transcriptions.create(
                model=model_name,
                file=buffer,
            )
            text = getattr(response, "text", None)
            if text:
                return text
        except NotFoundError:
            raise
        except Exception as exc:
            print(f"[LLM] SDK transcription failed for {model_name}: {exc!r}, falling back to HTTP")
        # Reset buffer for HTTP fallback
        buffer.seek(0)
        files = {"file": (filename or "audio.m4a", buffer.read(), "audio/m4a")}
        data = {"model": model_name}
        http_response = self._rest_client.post("/audio/transcriptions", files=files, data=data)
        http_response.raise_for_status()
        payload = http_response.json()
        text = payload.get("text") or payload.get("data")
        if isinstance(text, list) and text:
            text = text[0]
        if not text:
            raise LLMError("Transcription response did not contain text")
        return text

    @staticmethod
    def _parse_json_payload(content: str) -> Dict[str, Any]:
        try:
            return json.loads(content)
        except json.JSONDecodeError as exc:
            raise LLMError("LLM response was not valid JSON") from exc
