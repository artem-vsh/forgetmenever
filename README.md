# ForgetMeNever

ForgetMeNever is a lightweight macOS menu bar app for voice‑driven to‑do capture. Trigger it from anywhere with a global shortcut, speak your reminder, and the app will transcribe and parse it into add/update/remove actions on a local to‑do list via the FastAPI service in `backend/`. The recognized text and your current to‑do list are shown side‑by‑side in the window, with recent changes highlighted.

## Highlights
- Status bar app with customizable global shortcut (default `⌘⌥⌃T`).
- Instant capture: recorder window appears and starts listening immediately (voice isolation enabled when available).
- Natural‑language to‑do capture: say “remember to call Alice tomorrow”, “update ‘buy milk’ to ‘buy oat milk’ for Friday”, or “forget about Alex”.
- Live transcript preview plus in‑window to‑do list; items changed by your last command are highlighted.
- Local FastAPI backend with OpenAI‑compatible providers (transcription + text processing).
- Configuration lives in `Sources/ForgetMeNeverApp/Resources/AppConfig.json` with environment overrides for secrets and endpoints.

## Getting Started
Prerequisites:
- macOS 13+
- Xcode 15+ or Swift toolchain 6.2+

Install dependencies (system frameworks only) and build:
```bash
swift build
```
Start the backend service (from `backend/`):
```bash
uvicorn app.main:app --reload --port 8000
```
Run the app from the command line:
```bash
swift run ForgetMeNever
```
You should see `[ForgetMeNever] Bootstrapping application…` followed by `[ForgetMeNever] Ready…` in stdout, confirming launch.
The app lives in the menu bar; use the configured shortcut (default `⌘⌥⌃T`) to summon the recorder window.

### Backend configuration
The macOS client expects the FastAPI service in `backend/` to be running locally (for example via `uvicorn app.main:app --port 8000`). Edit `Sources/ForgetMeNeverApp/Resources/AppConfig.json`:
```json
{
  "backend_url": "http://127.0.0.1:8000",
  "api_key": "",
  "hotkey": {
    "key_code": 17,
    "modifier_flags": ["command", "option", "control"]
  }
}
```
- `backend_url`: Either the API base (e.g. `http://127.0.0.1:8000`) or the full transcript endpoint (e.g. `http://127.0.0.1:8000/transcript`). The client derives `/process` and `/todos` from the base; if you point directly at `/transcript`, the base is inferred automatically.
- `api_key`: Optional Bearer token added as the `Authorization` header; leave blank for unsecured local development. You can also set `FMN_API_KEY` to override at runtime.
- `hotkey.key_code`: macOS virtual key code (17 = `T`).
- `hotkey.modifier_flags`: Any of `command`, `option`, `control`, `shift`.

Set `FMN_BACKEND_URL` to override the endpoint at runtime (useful when pointing at a remote host). Reload the app (quit and re-run) after adjusting configuration.

The FastAPI app reads its own configuration from environment variables or `.env`. At minimum provide:
```bash
export OPENAI_API_KEY=...
export OPENAI_API_URL=https://api.sambanova.ai/v1
export OPENAI_MODEL=DeepSeek-V3.1           # optional; defaults to this value
export OPENAI_TRANSCRIPTION_MODEL=Whisper-Large-v3  # optional; defaults to this value
```
(See `backend/app/config.py` for the full list and defaults.)

### Keeping secrets out of git
To keep credentials outside the repository, copy the config to your user profile and point the app at it:
1. Create `~/Library/Application Support/ForgetMeNever/` (macOS will expand `~`).
2. Move your sensitive `AppConfig.json` there and edit it in place.
3. (Optional) set `FMN_CONFIG_PATH=/full/path/to/AppConfig.json` if you prefer an alternative location.

On launch ForgetMeNever resolves configuration in this order:
- `FMN_CONFIG_PATH` environment variable if it points to an existing file.
- `~/Library/Application Support/ForgetMeNever/AppConfig.json`.
- Bundled default config (shipped with the binary).

This lets you keep the repository copy generic (or scrubbed) while your local secrets stay outside git.

### Shortcut tips
Use `key_code` values from Apple’s virtual key code table (e.g. `36` for Return, `49` for Space). The UI displays the resolved shortcut so you can confirm your selection.

### Using the app (to‑do workflow)
1. Summon the recorder with the global shortcut (default `⌘⌥⌃T`).
2. Speak a command, e.g. “remember to water the flowers this evening”.
3. Press Space to send. The app:
   - Saves audio as `.m4a` and calls `POST /transcript` on the backend.
   - Sends the recognized text to `POST /process` to add/update/remove items.
   - Refreshes `GET /todos` and highlights changes.
4. Press Esc to cancel/hide the window at any time.

### REST API quick reference
- `GET /todos` → returns the current list

```json
{ "items": [ { "text": "Buy milk", "due": "2024-11-01" } ] }
```

- `POST /process` with natural‑language prompt

Request:

```json
{ "prompt": "Add 'Call Alice' due 2024-06-01" }
```

Response:

```json
{
  "type": "updated",
  "new_list": { "items": [ { "text": "Call Alice", "due": "2024-06-01" } ] },
  "updated": [ { "text": "Call Alice", "due": "2024-06-01" } ],
  "removed": null
}
```

- `POST /transcript` (multipart `file`) → `{ "text": "..." }`
- `POST /clear` → clears all items and returns an event with `type: "removed"`

### Building a redistributable app bundle
SwiftPM builds an executable. To ship as a `.app`, create an Xcode project wrapping the `Sources/ForgetMeNeverApp` target and include an Info.plist that declares:
- `LSUIElement = true` (keeps the dock icon hidden)
- `NSMicrophoneUsageDescription` (required for microphone access prompt)

## Troubleshooting
- **Microphone prompt never appears**: ensure the app bundle you ship contains `NSMicrophoneUsageDescription` in its Info.plist.
- **401 / auth errors**: verify your API key via the configuration options above.
- **Shortcut conflicts**: choose a key combination not already claimed by macOS or other apps; edit `AppConfig.json` accordingly.
- **To‑do items don’t change**: confirm the backend is running and reachable at your `backend_url`; check `/process` responses in the app logs.

## Development Notes
- Source lives under `Sources/ForgetMeNeverApp`.
- Resources are bundled via SwiftPM (`Bundle.module`).
- Backend service lives under `backend/` (FastAPI + SQLAlchemy). Endpoints: `/transcript`, `/process`, `/todos`, `/clear`.
- Tests are included under `backend/tests`. They require a real `OPENAI_API_KEY` in `.env` for the provider you use (see `backend/tests/conftest.py`).
