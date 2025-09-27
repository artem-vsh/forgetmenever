from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from app.config import Settings
from app.schemas import ToDoListEvent

logger = logging.getLogger(__name__)

try:  # pragma: no cover - optional dependency
    from fi import client as fi_client
    from fi.utils.types import Environments, ModelTypes
except ImportError:  # pragma: no cover - executed when package missing
    fi_client = None
    ModelTypes = None
    Environments = None


_INSTRUMENTATION_CACHE: Optional["FutureAGIInstrumentation"] = None
_INSTRUMENTATION_FINGERPRINT: Optional[Tuple] = None


class FutureAGIInstrumentation:
    """Encapsulates optional logging to FutureAGI."""

    def __init__(
        self,
        client: "fi_client.Client",
        model_id: str,
        model_type: "ModelTypes",
        environment: "Environments",
        model_version: Optional[str],
        base_tags: Optional[Dict[str, str]],
    ) -> None:
        self._client = client
        self._model_id = model_id
        self._model_type = model_type
        self._environment = environment
        self._model_version = model_version
        self._base_tags = base_tags or {}

    def log_interaction(
        self,
        prompt: str,
        messages: List[Dict[str, str]],
        event: ToDoListEvent,
    ) -> None:
        """Send the interaction to FutureAGI in the expected schema."""

        chat_history: List[Dict[str, str]] = []
        for message in messages:
            role = message.get("role")
            content = message.get("content")
            if not isinstance(role, str) or content is None:
                continue
            if not isinstance(content, str):
                try:
                    content = json.dumps(content, ensure_ascii=False)
                except TypeError:
                    content = str(content)
            chat_history.append({"role": role, "content": content})

        # Include a structured summary of the applied event so FutureAGI can evaluate correctness.
        event_summary = json.dumps(event.model_dump(), ensure_ascii=False)
        chat_history.append({"role": "assistant", "content": event_summary})

        # Ensure the original user prompt is captured even if missing from the message list.
        if not any(item["role"] == "user" for item in chat_history):
            chat_history.insert(0, {"role": "user", "content": prompt})

        payload_tags = dict(self._base_tags)
        payload_tags.setdefault("event_type", event.type)
        payload_tags.setdefault("updated_count", str(len(event.updated or [])))
        payload_tags.setdefault("removed_count", str(len(event.removed or [])))

        try:
            self._client.log(
                model_id=self._model_id,
                model_type=self._model_type,
                environment=self._environment,
                model_version=self._model_version,
                prediction_timestamp=int(datetime.now(timezone.utc).timestamp()),
                conversation={"chat_history": chat_history},
                tags=payload_tags,
            )
        except Exception:  # pragma: no cover - do not interrupt primary flow
            logger.exception("FutureAGI instrumentation failed")


def _parse_enum(value: str, enum_cls, fallback):
    if enum_cls is None:
        return fallback
    if not isinstance(value, str):
        return fallback
    normalized = value.replace("-", "_").replace(" ", "_").upper()
    for member in enum_cls:
        candidates = {member.name.upper(), member.value.upper() if isinstance(member.value, str) else str(member.value)}
        if normalized in candidates:
            return member
    try:
        # Allow direct value casting, e.g. numeric environments
        return enum_cls(value)
    except Exception:
        return fallback


def _parse_tags(raw: Optional[str]) -> Optional[Dict[str, str]]:
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return {str(k): str(v) for k, v in parsed.items()}
        logger.warning("Ignoring FUTUREAGI_TAGS because parsed value is not an object")
    except json.JSONDecodeError:
        logger.warning("Ignoring FUTUREAGI_TAGS because it is not valid JSON")
    return None


def _resolve_credentials(settings: Settings) -> Optional[Dict[str, str]]:
    api_key = settings.futureagi_api_key or os.getenv("FUTUREAGI_API_KEY") or os.getenv("FI_API_KEY")
    secret_key = settings.futureagi_secret_key or os.getenv("FUTUREAGI_SECRET_KEY") or os.getenv("FI_SECRET_KEY")
    model_id = settings.futureagi_model_id or os.getenv("FUTUREAGI_MODEL_ID")

    if not (api_key and secret_key and model_id):
        return None

    return {
        "api_key": api_key,
        "secret_key": secret_key,
        "model_id": model_id,
        "base_url": settings.futureagi_base_url or os.getenv("FUTUREAGI_BASE_URL"),
        "model_type": settings.futureagi_model_type,
        "environment": settings.futureagi_environment,
        "model_version": settings.futureagi_model_version or os.getenv("FUTUREAGI_MODEL_VERSION"),
        "tags": _parse_tags(settings.futureagi_tags or os.getenv("FUTUREAGI_TAGS")),
    }


def get_futureagi_instrumentation(settings: Settings) -> Optional[FutureAGIInstrumentation]:
    global _INSTRUMENTATION_CACHE, _INSTRUMENTATION_FINGERPRINT

    if fi_client is None:
        logger.debug("FutureAGI SDK not installed; skipping instrumentation")
        _INSTRUMENTATION_CACHE = None
        _INSTRUMENTATION_FINGERPRINT = None
        return None

    creds = _resolve_credentials(settings)
    if not creds:
        _INSTRUMENTATION_CACHE = None
        _INSTRUMENTATION_FINGERPRINT = None
        return None

    fingerprint = (
        creds["api_key"],
        creds["secret_key"],
        creds["base_url"],
        creds["model_id"],
        creds["model_type"],
        creds["environment"],
        creds["model_version"],
        tuple(sorted((creds["tags"] or {}).items())),
    )

    if _INSTRUMENTATION_CACHE is not None and _INSTRUMENTATION_FINGERPRINT == fingerprint:
        return _INSTRUMENTATION_CACHE

    # Ensure the underlying SDK sees the credentials even if it falls back to environment variables later.
    os.environ.setdefault("FI_API_KEY", creds["api_key"])
    os.environ.setdefault("FI_SECRET_KEY", creds["secret_key"])
    if creds["base_url"]:
        os.environ.setdefault("FI_BASE_URL", creds["base_url"])

    try:
        client = fi_client.Client(
            fi_api_key=creds["api_key"],
            fi_secret_key=creds["secret_key"],
            fi_base_url=creds["base_url"],
        )
    except Exception:  # pragma: no cover - depends on external SDK state
        logger.exception("Unable to initialize FutureAGI client; instrumentation disabled")
        return None

    model_type = _parse_enum(creds["model_type"], ModelTypes, ModelTypes.GENERATIVE_LLM if ModelTypes else None)
    environment = _parse_enum(creds["environment"], Environments, Environments.PRODUCTION if Environments else None)

    if model_type is None or environment is None:
        logger.warning("FutureAGI instrumentation misconfigured; invalid model type or environment")
        _INSTRUMENTATION_CACHE = None
        _INSTRUMENTATION_FINGERPRINT = None
        return None

    instrumentation = FutureAGIInstrumentation(
        client=client,
        model_id=creds["model_id"],
        model_type=model_type,
        environment=environment,
        model_version=creds["model_version"],
        base_tags=creds["tags"],
    )
    _INSTRUMENTATION_CACHE = instrumentation
    _INSTRUMENTATION_FINGERPRINT = fingerprint
    return instrumentation


def provide_instrumentation(settings: Settings) -> Optional[FutureAGIInstrumentation]:
    """Helper used by FastAPI dependency injection"""

    return get_futureagi_instrumentation(settings)
