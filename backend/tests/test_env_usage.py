from __future__ import annotations

import pytest

from app.config import get_settings


def test_settings_reads_sample_env(sample_env):
    settings = get_settings()
    assert settings.database_url.endswith("-sample.db")
    assert settings.openai_api_key == sample_env["values"]["OPENAI_API_KEY"]
    assert settings.openai_api_url == sample_env["values"]["OPENAI_API_URL"]
    assert settings.openai_model == sample_env["values"]["OPENAI_MODEL"]
    assert settings.openai_transcription_model == sample_env["values"]["OPENAI_TRANSCRIPTION_MODEL"]
    assert settings.reference_datetime == sample_env["values"]["REFERENCE_DATETIME"]


def test_database_file_created_after_requests(test_client, sample_env):
    response = test_client.post(
        "/process",
        json={"prompt": "Please remember to plan our vacation."},
    )
    if response.status_code != 200:
        pytest.fail(f"Process endpoint returned {response.status_code}: {response.text}")

    db_path = sample_env["db_path"]
    assert db_path.exists(), "Expected sample database file to be created"
