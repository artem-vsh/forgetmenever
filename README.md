# ForgetMeNever

ForgetMeNever is a lightweight macOS menu bar app that captures quick voice notes. Trigger it from anywhere with a global shortcut, record immediately, and ship the audio to the local FastAPI service in `backend/` (which can in turn talk to any OpenAI-compatible transcription endpoint). The recognized text is rendered in the app window for quick review or copy.

## Highlights
- Status bar app with customizable global shortcut (default `⌘⌥⌃T`).
- Automatically shows a floating window and begins recording as soon as it appears.
- Captures compressed AAC (`.m4a`) audio suitable for Whisper-style APIs.
- Stop via the on-screen **Send** button or the space bar; hide/cancel with **Esc** or by shifting focus.
- Streams the captured audio file to a local REST backend (default `POST /transcript`) and displays the transcription result inside the window.
- Configuration lives in `Sources/ForgetMeNeverApp/Resources/AppConfig.json` and supports environment overrides.

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
- `backend_url`: Base URL for the REST API. If it already ends with `/transcript` the client uses it verbatim; otherwise `/transcript` is appended when calling the service.
- `api_key`: Optional Bearer token added as the `Authorization` header; leave blank for unsecured local development. You can also set `FMN_API_KEY` to override at runtime.
- `hotkey.key_code`: macOS virtual key code (17 = `T`).
- `hotkey.modifier_flags`: Any of `command`, `option`, `control`, `shift`.

Set `FMN_BACKEND_URL` to override the endpoint at runtime (useful when pointing at a remote host). Reload the app (quit and re-run) after adjusting configuration.

The FastAPI app reads its own configuration from environment variables or `.env`. At minimum provide:
```bash
export OPENAI_API_KEY=...
export OPENAI_API_URL=https://api.sambanova.ai/v1
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

### Building a redistributable app bundle
SwiftPM builds an executable. To ship as a `.app`, create an Xcode project wrapping the `Sources/ForgetMeNeverApp` target and include an Info.plist that declares:
- `LSUIElement = true` (keeps the dock icon hidden)
- `NSMicrophoneUsageDescription` (required for microphone access prompt)

## Troubleshooting
- **Microphone prompt never appears**: ensure the app bundle you ship contains `NSMicrophoneUsageDescription` in its Info.plist.
- **401 / auth errors**: verify your API key via the configuration options above.
- **Shortcut conflicts**: choose a key combination not already claimed by macOS or other apps; edit `AppConfig.json` accordingly.

## Development Notes
- Source lives under `Sources/ForgetMeNeverApp`.
- Resources are bundled via SwiftPM (`Bundle.module`).
- Tests are currently not included; integration hinges on the configured transcription backend.
