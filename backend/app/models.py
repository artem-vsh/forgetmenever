from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import Column, Date, DateTime, Integer, String

from app.db import Base


class ToDoItemModel(Base):
    __tablename__ = "todo_items"

    id = Column(Integer, primary_key=True, index=True)
    text = Column(String, nullable=False)
    due = Column(Date, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    def to_schema(self) -> dict:
        return {
            "text": self.text,
            "due": self.due,
        }


def ensure_date(value) -> date | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value
    return date.fromisoformat(value)
