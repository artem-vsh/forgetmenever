from __future__ import annotations

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, close_all_sessions, declarative_base, sessionmaker

from app.config import get_settings


Base = declarative_base()


def _create_engine():
    settings = get_settings()
    connect_args = {}
    if settings.database_url.startswith("sqlite"):  # allow usage across threads for sqlite
        connect_args = {"check_same_thread": False}
    return create_engine(settings.database_url, connect_args=connect_args, future=True)


_engine = None
_SessionLocal = None


def _get_engine():
    global _engine
    if _engine is None:
        _engine = _create_engine()
    return _engine


def get_session_factory():
    global _SessionLocal
    if _SessionLocal is None:
        _SessionLocal = sessionmaker(bind=_get_engine(), expire_on_commit=False, class_=Session)
    return _SessionLocal


def get_session() -> Generator[Session, None, None]:
    session_factory = get_session_factory()
    session = session_factory()
    try:
        yield session
    finally:
        session.close()


@contextmanager
def session_scope() -> Generator[Session, None, None]:
    session_factory = get_session_factory()
    session = session_factory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def init_db() -> None:
    """Create database tables."""

    engine = _get_engine()
    Base.metadata.create_all(bind=engine)


def reset_engine() -> None:
    """Dispose cached engine/session factory so new settings take effect."""

    global _engine, _SessionLocal
    if _SessionLocal is not None:
        close_all_sessions()
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _SessionLocal = None
