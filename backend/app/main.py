from __future__ import annotations

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile

from app.config import Settings, get_settings
from app.db import get_session, init_db
from app.instrumentation import FutureAGIInstrumentation, provide_instrumentation
from app.llm import LLMClient, LLMError
from app.schemas import ProcessRequest, ToDoListEvent, TranscriptResponse
from app.todo_service import ToDoService

app = FastAPI(title="ToDo LLM Service", version="0.1.0")


@app.on_event("startup")
def on_startup() -> None:
    init_db()


def get_llm_client(settings: Settings = Depends(get_settings)) -> LLMClient:
    return LLMClient(settings)


def get_instrumentation_dependency(
    settings: Settings = Depends(get_settings),
) -> FutureAGIInstrumentation | None:
    return provide_instrumentation(settings)


def get_todo_service(
    session=Depends(get_session),
    llm_client: LLMClient = Depends(get_llm_client),
    instrumentation: FutureAGIInstrumentation | None = Depends(get_instrumentation_dependency),
) -> ToDoService:
    return ToDoService(session=session, llm_client=llm_client, instrumentation=instrumentation)


@app.post("/transcript", response_model=TranscriptResponse)
async def transcript(
    file: UploadFile = File(...),
    llm_client: LLMClient = Depends(get_llm_client),
) -> TranscriptResponse:
    file_bytes = await file.read()
    try:
        text = llm_client.transcribe_audio(file_bytes, file.filename or "audio")
    except LLMError as exc:
        print(f"[Backend] Transcription error: {exc}")
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return TranscriptResponse(text=text)



@app.get("/todos", response_model=ToDoList)
async def list_todos(service: ToDoService = Depends(get_todo_service)) -> ToDoList:
    return ToDoList(items=service.list_items())


@app.post("/process", response_model=ToDoListEvent)
async def process_prompt(
    request: ProcessRequest,
    service: ToDoService = Depends(get_todo_service),
) -> ToDoListEvent:
    try:
        return service.process(request)
    except LLMError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.post("/clear", response_model=ToDoListEvent)
async def clear_list(service: ToDoService = Depends(get_todo_service)) -> ToDoListEvent:
    return service.clear()
