from functools import lru_cache
from pathlib import Path
import os

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


DEFAULT_ENV_FILE = Path(".env")


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    api_host: str = Field(default="0.0.0.0", description="Host for FastAPI server")
    api_port: int = Field(default=8000, description="Port for FastAPI server")

    openai_api_key: str = Field(default="", alias="OPENAI_API_KEY", description="API key for OpenAI-compatible endpoint")
    openai_api_url: str = Field(
        default="https://api.sambanova.ai/v1",
        alias="OPENAI_API_URL",
        description="Base URL for OpenAI-compatible endpoint",
    )
    openai_model: str = Field(
        default="DeepSeek-V3.1",
        alias="OPENAI_MODEL",
        description="Model name for text processing",
    )
    openai_transcription_model: str = Field(
        default="Whisper-Large-v3",
        alias="OPENAI_TRANSCRIPTION_MODEL",
        description="Model name for speech-to-text",
    )
    reference_datetime: str | None = Field(
        default=None,
        alias="REFERENCE_DATETIME",
        description="Optional ISO-8601 timestamp that the LLM should treat as the current time",
    )
    output_debug: bool = Field(
        default=False,
        alias="OUTPUT_DEBUG",
        description="Emit verbose logging, including sensitive values when true",
    )

    database_url: str = Field(
        default="sqlite:///./todo.db", alias="DATABASE_URL", description="SQLAlchemy database URL"
    )
    model_config = SettingsConfigDict(
        env_file=DEFAULT_ENV_FILE, env_file_encoding="utf-8", extra="ignore", case_sensitive=False
    )


@lru_cache
def get_settings(env_file: str | os.PathLike[str] | None = None) -> Settings:
    """Lazily load and cache application settings."""

    if env_file is not None:
        return Settings(_env_file=Path(env_file), _env_file_encoding="utf-8")

    override_env = os.getenv("APP_ENV_FILE")
    if override_env:
        return Settings(_env_file=Path(override_env), _env_file_encoding="utf-8")

    return Settings()
