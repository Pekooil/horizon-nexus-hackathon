# Webcam "frame" gesture → Take Photo (web build)

Lets the player trigger **Take Polaroid** by making a two-handed *frame* gesture
(each hand an L of thumb + index; bring the two corners together) in front of the
webcam. Detection runs in the browser (MediaPipe Tasks Vision) and is bridged into
Godot via `JavaScriptBridge`. The on-screen button still works as a fallback.

**Activation:** the webcam turns on when the player opens a camera screen (the
full-screen room view) and pauses when they go back to the monitor wall. The first
open triggers the browser's camera permission prompt — that works because opening a
screen is itself a click. The stream is kept warm between screens so reopening is
instant (to instead fully release the camera on close, change `stopGestureCamera()`
in `web_head_include.html` to stop the stream's tracks).

## Pieces

| File | Role |
|------|------|
| `export/web_head_include.html` | The detector. Goes in the Web export's **Head Include**. Self-contained (loads MediaPipe from a CDN), so the itch.io zip needs no extra files. |
| `scripts/gesture_input_web.gd` | Godot ↔ JS bridge node. Emits `frame_gesture_detected` / `camera_status_changed`. Web-only; no-op natively. |
| `scripts/main.gd` | Spawns the bridge node (web only). **Activates detection in `_open_detail` and pauses it in `_close_detail`**, so the webcam gesture only works while a camera screen is open. Routes the gesture to `_take_photo` and draws the top-right camera indicator. |
| `web/test_detector.html` | Standalone harness to tune thresholds / verify detection without exporting. |

## Test the detector first (no Godot needed)

```bash
cd web
python3 -m http.server 8000
# open http://localhost:8000/test_detector.html  (localhost is a secure context)
```
Click **Enable camera**, grant access, and confirm the frame gesture logs `PHOTO`
once per gesture (no rapid repeats). Tune `HOLD_FRAMES`, `COOLDOWN_MS`, `CORNER_DIST`
at the top of the script if needed, then copy the same values into
`export/web_head_include.html`.

## Export for the web

1. Project → Export → Add… → **Web**.
2. **Disable "Thread Support"** in the preset. Threaded web builds need
   `SharedArrayBuffer` (cross-origin isolation / COOP+COEP), which both complicates
   itch.io embedding and can block the MediaPipe CDN under `COEP: require-corp`.
   Single-threaded GL-Compatibility is fine for this game.
3. Set **HTML → Head Include** to the contents of `export/web_head_include.html`.
4. Export the project, then zip the output folder (index.html, .wasm, .pck, .js, …).

## Upload to itch.io

New project → Kind: **HTML** → upload the zip → check **"This file will be played in
the browser"** → set a viewport (e.g. 1280×720) and enable the fullscreen button.

## ⚠️ Camera in the itch.io iframe — the main risk

itch.io embeds HTML games in a **cross-origin iframe**. Since Chrome 64, `getUserMedia`
in such an iframe is blocked unless the iframe carries `allow="camera"` — and that
attribute is set by itch.io, not by us. Symptom: instant `NotAllowedError`, no prompt.

Fallback ladder:
1. Upload and test the embedded player. If the prompt appears and the feed works, done.
2. If blocked, host the **identical** build where you control the page
   (GitHub Pages / Netlify / Vercel) — there it's a top-level document and the camera
   works. Link to it from the itch page.
3. The detector already reports `status:off` on failure, the HUD shows "Camera off —
   use the button", and the **Take Polaroid button keeps working**. The gesture is
   never the only way to act.

Notes: `getUserMedia` requires HTTPS (itch is HTTPS; use `localhost` for local tests,
not `file://`).
