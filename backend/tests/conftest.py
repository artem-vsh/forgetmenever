from __future__ import annotations

import os
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Callable, Dict

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.config import get_settings
from app.db import Base, reset_engine
from app.main import app

ENV_PATH = ROOT / ".env"
PLACEHOLDER_KEY = "replace-with-your-sambanova-key"


def _load_env_file(path: Path) -> OrderedDict[str, str]:
    if not path.exists():
        pytest.fail(f"Expected environment file at {path}")

    values: OrderedDict[str, str] = OrderedDict()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _write_env_file(path: Path, values: OrderedDict[str, str]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


@pytest.fixture(scope="session")
def real_env_values() -> OrderedDict[str, str]:
    values = _load_env_file(ENV_PATH)
    key = values.get("OPENAI_API_KEY", "").strip()
    if not key or key == PLACEHOLDER_KEY:
        pytest.fail("OPENAI_API_KEY in .env must contain a real SambaNova credential for tests.")
    return values


@pytest.fixture
def sample_env(real_env_values, monkeypatch, tmp_path) -> Dict[str, object]:
    env_values = OrderedDict(real_env_values)

    env_values.setdefault("REFERENCE_DATETIME", "2024-08-19T09:00:00Z")

    for key in list(env_values.keys()):
        monkeypatch.delenv(key, raising=False)

    db_url = env_values.get("DATABASE_URL", "sqlite:///./todo.db")
    if db_url.startswith("sqlite:///"):
        base_path = Path(db_url.replace("sqlite:///", ""))
        db_path = tmp_path / f"{base_path.stem}-sample{base_path.suffix or '.db'}"
    else:
        db_path = tmp_path / "todo-sample.db"

    env_values["DATABASE_URL"] = f"sqlite:///{db_path}"

    env_path = tmp_path / ".env.sample"
    _write_env_file(env_path, env_values)

    monkeypatch.setenv("APP_ENV_FILE", str(env_path))
    get_settings.cache_clear()
    reset_engine()

    yield {
        "values": env_values,
        "env_path": env_path,
        "db_path": db_path,
    }

    monkeypatch.delenv("APP_ENV_FILE", raising=False)
    get_settings.cache_clear()
    reset_engine()


@pytest.fixture
def test_client(sample_env):
    with TestClient(app) as client:
        yield client


@pytest.fixture
def db_session_factory(sample_env) -> Callable[[], Session]:
    db_url = sample_env["values"]["DATABASE_URL"]
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    TestingSessionLocal = sessionmaker(bind=engine, expire_on_commit=False, class_=Session)

    def factory() -> Session:
        return TestingSessionLocal()

    yield factory

    engine.dispose()
