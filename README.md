# ForgetMeNever

ForgetMeNever is a lightweight macOS menu bar app that captures quick voice notes. Trigger it from anywhere with a global shortcut, record immediately, and ship the audio to any OpenAI-compatible transcription endpoint. The recognized text is rendered in the app window for quick review or copy.

## Highlights
- Status bar app with customizable global shortcut (default `⌘⌥⌃T`).
- Automatically shows a floating window and begins recording as soon as it appears.
- Captures compressed AAC (`.m4a`) audio suitable for Whisper-style APIs.
- Stop via the on-screen **Send** button or the space bar; hide/cancel with **Esc** or by shifting focus.
- Streams the captured audio file to a configurable model endpoint; displays the transcription result inside the window.
- Configuration lives in `Sources/ForgetMeNeverApp/Resources/AppConfig.json` with support for `MODEL_URL` (`model_url`) and `MODEL_VOICE_NAME` (`model_voice_name`).

## Getting Started
Prerequisites:
- macOS 13+
- Xcode 15+ or Swift toolchain 6.2+

Install dependencies (system frameworks only) and build:
```bash
swift build
```
Run the app from the command line:
```bash
swift run ForgetMeNever
```
You should see `[ForgetMeNever] Bootstrapping application…` followed by `[ForgetMeNever] Ready…` in stdout, confirming launch.
The app lives in the menu bar; use the configured shortcut (default `⌘⌥⌃T`) to summon the recorder window.

### API access
Provide an API key via one of the following (first non-empty value wins):
1. `api_key` field inside `AppConfig.json`.
2. `FMN_API_KEY` environment variable.
3. `OPENAI_API_KEY` environment variable.

### Model configuration
Edit `Sources/ForgetMeNeverApp/Resources/AppConfig.json`:
```json
{
  "model_url": "https://api.openai.com/v1/audio/transcriptions",
  "model_voice_name": "Whisper-Large-v3",
  "api_key": "",
  "hotkey": {
    "key_code": 17,
    "modifier_flags": ["command", "option", "control"]
  }
}
```
- `model_url`: HTTP endpoint accepting OpenAI Whisper-style `multipart/form-data` requests (`file` + `model`).
- `model_voice_name`: Passed as the `model` form field (`MODEL_VOICE_NAME`); SambaNova expects exact case (e.g. `Whisper-Large-v3`).
- Audio uploads use `.m4a` (AAC) with `Content-Type: audio/m4a`.
- `hotkey.key_code`: macOS virtual key code (17 = `T`).
- `hotkey.modifier_flags`: Any of `command`, `option`, `control`, `shift`.

Reload the app (quit and re-run) after adjusting configuration.

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
