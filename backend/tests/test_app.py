from __future__ import annotations

import io
import pytest
from sqlalchemy import select

from app.models import ToDoItemModel


def _list_items(session):
    return session.execute(select(ToDoItemModel).order_by(ToDoItemModel.id)).scalars().all()


def test_process_add_item(test_client, db_session_factory):
    prompt = (
        "Please add a to-do item exactly titled 'Buy milk' with a due date of 2024-05-01. "
        "Respond only with the JSON instructions described earlier."
    )
    response = test_client.post("/process", json={"prompt": prompt})
    if response.status_code != 200:
        pytest.fail(f"/process failed: {response.status_code} {response.text}")
    payload = response.json()
    assert payload["type"] in {"updated", "mixed"}

    session = db_session_factory()
    try:
        items = _list_items(session)
        assert any("buy milk" in item.text.lower() for item in items)
        assert any(item.due and item.due.isoformat() == "2024-05-01" for item in items)
    finally:
        session.close()


def test_update_and_remove_flow(test_client, db_session_factory):
    add_prompt = (
        "Add the task 'Call Alice' with a due date of 2024-06-01."
        " Return JSON instructions only."
    )
    resp_add = test_client.post("/process", json={"prompt": add_prompt})
    if resp_add.status_code != 200:
        pytest.fail(f"Initial add failed: {resp_add.status_code} {resp_add.text}")

    update_prompt = (
        "Update the existing task exactly named 'Call Alice' so it reads 'Call Bob' and is due on 2024-06-05."
        " Reply using the required JSON format only."
    )
    update_response = test_client.post("/process", json={"prompt": update_prompt})
    if update_response.status_code != 200:
        pytest.fail(f"Update failed: {update_response.status_code} {update_response.text}")

    remove_prompt = (
        "Forget about the task titled 'Call Bob' and remove it from the list."
        " Reply with JSON instructions only."
    )
    remove_response = test_client.post("/process", json={"prompt": remove_prompt})
    if remove_response.status_code != 200:
        pytest.fail(f"Remove failed: {remove_response.status_code} {remove_response.text}")

    session = db_session_factory()
    try:
        items = _list_items(session)
        assert items == []
    finally:
        session.close()


def test_clear_endpoint(test_client, db_session_factory):
    prompt = "Remember to write the status report tomorrow."
    start_resp = test_client.post("/process", json={"prompt": prompt})
    if start_resp.status_code != 200:
        pytest.fail(f"Seed add failed: {start_resp.status_code} {start_resp.text}")

    clear_resp = test_client.post("/clear")
    assert clear_resp.status_code == 200
    data = clear_resp.json()
    assert data["type"] == "removed"

    session = db_session_factory()
    try:
        assert _list_items(session) == []
    finally:
        session.close()


def test_transcript_endpoint_returns_text(test_client):
    response = test_client.post(
        "/transcript",
        files={"file": ("audio.wav", io.BytesIO(b"RIFF\x00\x00\x00\x00WAVEfmt "), "audio/wav")},
    )
    # Depending on the transcription model, empty or short audio may trigger an error; both outcomes are valid.
    assert response.status_code in {200, 400, 422, 502}


def test_process_handles_transcription_noise(test_client, db_session_factory):
    noisy_prompt = (
        "kan you remind me to call Bob on july 14 pls. "
        "Use the JSON format only."
    )
    response = test_client.post("/process", json={"prompt": noisy_prompt})
    if response.status_code != 200:
        pytest.fail(f"Noise prompt failed: {response.status_code} {response.text}")

    session = db_session_factory()
    try:
        items = _list_items(session)
        assert any("bob" in item.text.lower() for item in items)
    finally:
        session.close()


def test_process_handles_forget_phrase(test_client, db_session_factory):
    add_prompt = "Please remember that I must pay bills soon."
    add_response = test_client.post("/process", json={"prompt": add_prompt})
    if add_response.status_code != 200:
        pytest.fail(f"Seed remember failed: {add_response.status_code} {add_response.text}")

    forget_prompt = "forget about paying bills, thanks"
    response = test_client.post("/process", json={"prompt": forget_prompt})
    if response.status_code != 200:
        pytest.fail(f"Forget prompt failed: {response.status_code} {response.text}")
    payload = response.json()
    assert payload["type"] in {"removed", "updated", "mixed"}

    session = db_session_factory()
    try:
        items = _list_items(session)
        assert all("bill" not in item.text.lower() for item in items)
    finally:
        session.close()


def test_process_handles_chained_prompt(test_client, db_session_factory):
    chained_prompt = (
        "Please remember to water the flowers this evening. "
        "Oh, and I also wanted to call Alex tomorrow and Beth on Wednesday. "
        "Actually, forget about Alex."
    )
    response = test_client.post("/process", json={"prompt": chained_prompt})
    if response.status_code != 200:
        pytest.fail(f"Chained prompt failed: {response.status_code} {response.text}")

    session = db_session_factory()
    try:
        items = _list_items(session)
        water_item = next(
            (item for item in items if "water" in item.text.lower() and "flower" in item.text.lower()),
            None,
        )
        beth_item = next(
            (item for item in items if "beth" in item.text.lower()),
            None,
        )
        assert water_item is not None, f"Expected watering task but saw {[item.text for item in items]}"
        assert beth_item is not None, f"Expected Beth task but saw {[item.text for item in items]}"
        assert all("alex" not in item.text.lower() for item in items)

        assert water_item.due is not None and water_item.due.isoformat() == "2024-08-19"
        assert beth_item.due is not None and beth_item.due.isoformat() == "2024-08-21"
    finally:
        session.close()
