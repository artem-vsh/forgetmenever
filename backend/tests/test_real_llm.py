from __future__ import annotations

import os
from pathlib import Path

import pytest
from collections import OrderedDict

from app.config import get_settings
from app.llm import LLMClient, LLMError

ROOT = Path(__file__).resolve().parents[1]

if not (ROOT / ".env").exists():
    pytest.skip("Real LLM tests require a .env file with valid SambaNova credentials", allow_module_level=True)

pytestmark = pytest.mark.integration


def _load_env_values(path: Path) -> OrderedDict[str, str]:
    values: OrderedDict[str, str] = OrderedDict()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


@pytest.fixture(scope="session")
def real_llm_client():
    env_path = ROOT / ".env"
    values = _load_env_values(env_path)
    placeholder = "replace-with-your-sambanova-key"
    api_key = values.get("OPENAI_API_KEY", "").strip()
    if not api_key or placeholder in api_key:
        pytest.fail(
            "OPENAI_API_KEY in .env must be set to a real SambaNova credential before running tests."
        )

    values.setdefault("REFERENCE_DATETIME", "2024-08-19T09:00:00Z")

    previous_env = {key: os.environ.get(key) for key in values.keys()}
    previous_app_env = os.environ.get("APP_ENV_FILE")

    try:
        for key in values.keys():
            os.environ.pop(key, None)
        os.environ["APP_ENV_FILE"] = str(env_path)
        for key, value in values.items():
            os.environ[key] = value

        get_settings.cache_clear()
        settings = get_settings()
        client = LLMClient(settings)
        yield client
    finally:
        get_settings.cache_clear()
        for key, value in previous_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        if previous_app_env is None:
            os.environ.pop("APP_ENV_FILE", None)
        else:
            os.environ["APP_ENV_FILE"] = previous_app_env


@pytest.mark.parametrize(
    "prompt",
    [
        "Please remind me to submit the expense report tomorrow.",
        "Can you remember to call Alice next Tuesday?",
        "I want to finish the draft on 2024-10-01.",
        "plz remnd me to send timesheet tmrw",  # intentionally noisy
    ],
)
def test_real_llm_add_intents(real_llm_client: LLMClient, prompt: str):
    try:
        payload = real_llm_client.process_prompt(prompt)
    except LLMError as exc:
        pytest.fail(f"LLM call failed for add-intent prompt {prompt!r}: {exc}")
    assert "action" in payload, "Payload missing required 'action' field"
    assert payload["action"] in {"add", "mixed"}, payload
    assert payload.get("add_items"), "Expected add_items to contain at least one entry"
    for item in payload["add_items"]:
        assert item.get("text"), "LLM must provide text for added item"


@pytest.mark.parametrize(
    "prompt",
    [
        "Forget about calling Alice.",
        "Please remove the reminder to submit the expense report.",
        "stop remnding me abt the timesheet",  # noisy removal
    ],
)
def test_real_llm_remove_intents(real_llm_client: LLMClient, prompt: str):
    try:
        payload = real_llm_client.process_prompt(prompt)
    except LLMError as exc:
        pytest.fail(f"LLM call failed for remove-intent prompt {prompt!r}: {exc}")
    assert "action" in payload
    assert payload["action"] in {"remove", "mixed"}, payload
    assert payload.get("remove_items"), "Expected remove_items to contain at least one entry"
    for text in payload["remove_items"]:
        assert isinstance(text, str) and text.strip(), "Remove items must be non-empty strings"


def test_real_llm_handles_invalid_credentials():
    bad_settings_path = ROOT / ".env.invalid"
    if not bad_settings_path.exists():
        pytest.skip("Create .env.invalid with invalid credentials to exercise failure path.")

    with pytest.raises(LLMError):
        client = LLMClient(get_settings(env_file=bad_settings_path))
        client.process_prompt("Please remind me to test invalid credentials")
