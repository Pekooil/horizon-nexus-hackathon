# CLAUDE.md

Handoff notes for continuing work on this project in a future session.

## What this is

**Ferret Casino Royale** — a Godot 4.7 (GL Compatibility) game. The player runs casino
security: a wall of 6 monitor screens shows live feeds of 6 rooms (Entrance, Bar,
Lounge, Poker, Roulette, Slot Machines). Patrons ("ferrets") occasionally start
cheating; click a screen to bring up that room full-screen and use a limited supply
of "Take Polaroid" photos to catch the cheater (reward) or risk falsely accusing an
innocent patron (penalty). Money drains while a ferret is active and trickles in
passively otherwise; survive `MAX_NIGHTS` (5) without running out of money to win.

On **web exports only**, the player can also trigger a photo by making a two-handed
"frame" gesture in front of their webcam instead of clicking the button — see
[Webcam gesture feature](#webcam-frame-gesture--take-photo-web-export-only) below.

## Project layout

- `project.godot` — `run/main_scene` is `res://scenes/StartScreen.tscn`. `GameManager`
  is registered as an autoload singleton (persists across scene changes).
- `scenes/StartScreen.tscn` + `scripts/start_screen.gd` — title screen, one button,
  `change_scene_to_file("res://scenes/Main.tscn")`.
- `scenes/Main.tscn` + `scripts/main.gd` — the root gameplay scene. Builds the 6 live
  camera feeds, the monitor wall, the full-screen room/detail view with the Polaroid
  mechanic, the HUD (incl. the camera-gesture indicator), and the win/lose overlay.
  **This is the file most gameplay/UI work touches.**
- `scenes/Rooms/{Entrance,Bar,Lounge,Poker,Roulette,"Slot Machines"}.tscn` — 6 distinct
  room scenes, each a `Node2D` root running `scripts/room.gd`. Each contains a
  `RoomBackground` (procedurally drawn placeholder art) and a `Seats` node with 3
  `CasinoPlayer` instances.
- `scenes/CasinoPlayer.tscn` + `scripts/casino_player.gd` — one patron. Toggles
  visibility of `Tell` (cheater giveaway) and `Caught` (busted marker) child nodes.
- `scripts/game_manager.gd` — autoload singleton. Owns money, night/clock timers,
  photo count, ferret bookkeeping, win/lose. Emits `money_changed`, `night_changed`,
  `clock_changed`, `photos_changed`, `game_over`.
- `scripts/monitor_quad.gd` — one clickable screen on the wall (`Area2D` hitbox +
  textured quad showing a room's live feed texture).
- `scripts/room_background.gd` — `@tool` script drawing placeholder room art
  (480x270). Meant to be deleted/replaced once real art exists.
- `scripts/gesture_input_web.gd` — web-only bridge Node between the in-page MediaPipe
  hand detector and Godot. No-op on native platforms. See gesture section below.
- `export/web_head_include.html` — the actual webcam hand-gesture detector (plain JS +
  MediaPipe Tasks Vision). Lives outside `scripts/` because its destination is the
  **Web export preset's HTML Head Include**, not the Godot project itself.
- `web/test_detector.html` + `web/README.md` — standalone browser test harness for the
  gesture detector, and setup/export/itch.io notes for that feature.

## How the click → room-page flow works (scripts/main.gd)

1. `_unhandled_input()` (~line 91) detects a left-click and calls
   `_get_screen_at_point()` to find which `Screen0..Screen5` was hit.
2. `_open_detail(i)` (~line 348) is the trigger function — it switches the *view*
   (not a real Godot scene change) to show room `i` full-screen: sets the detail
   texture, updates the label to the room's name, hides the monitor wall, and (web
   only) starts the webcam gesture detector for this screen.
3. `_take_photo()` (~line 371) implements the Polaroid mechanic against
   `rooms[current_detail]` — calls `GameManager.use_photo()`, then
   `room.get_active_ferret()` to check for a cheater, then `catch_ferret()` /
   `false_accuse()` accordingly. This is the **single trigger function** for a photo —
   both the "Take Polaroid" button and the webcam gesture call it directly.
4. `_close_detail()` (~line 361) is "Back to wall" — restores the monitor view and
   (web only) pauses the gesture detector.

**Important architectural decision (confirmed with user):** room navigation stays
*inside* `Main.tscn` by swapping visibility, rather than doing a real
`get_tree().change_scene_to_file()` to the room's own `.tscn`. Reason: the live
`Room` instances (with current ferret/cheater state) only exist as children of the
`SubViewport`s built in `_build_feeds()`. A real scene change would instantiate a
*fresh* room with no memory of which patron is cheating, desyncing it from
`GameManager.active_ferrets`. If a future request asks for a "zoom" animation or a
true separate page per room, raise this constraint again before changing the
approach.

## Webcam "frame" gesture → Take Photo (web export only)

Added this session. Lets the player snap a Polaroid by making a two-handed framing
gesture (each hand forms an L with thumb + index extended; the two L's corners are
brought together into a rectangle) in front of their webcam — **only when exported as
a Web/HTML5 build**. On native desktop exports the feature is fully absent (gated by
`OS.has_feature("web")`); there is no Python/native camera path in this project.

**Why web-only:** Godot has no built-in hand tracking. Detection runs as plain
JavaScript in the browser page (MediaPipe Tasks Vision `HandLandmarker`, loaded from
the jsDelivr CDN, against a `getUserMedia` webcam stream) and is bridged into the
Godot WASM runtime via the `JavaScriptBridge` singleton. This cannot work in a native
build — there is no browser/JS context to host the detector.

**Activation model:** the webcam turns on when a room screen is opened
(`_open_detail` → `gesture_input.request_camera()`) and pauses when the player goes
back to the wall (`_close_detail` → `gesture_input.stop_camera()`). The underlying
browser camera *stream* is kept warm across opens/closes (only the detection loop
pauses), so re-opening a screen doesn't re-prompt or re-warm the camera. The first
`request_camera()` call happens inside the click that opened a screen, which is what
lets the browser's permission prompt fire (browsers require a user gesture to ask).

**Wiring:**
- `scripts/gesture_input_web.gd` — exposes `request_camera()` / `stop_camera()` and
  signals `frame_gesture_detected` and `camera_status_changed(status: String)` (`"on"` /
  `"off"` / `"error"`). Created as a child of `main.gd` only when `OS.has_feature("web")`.
- `scripts/main.gd`: `_setup_gesture_input()` (~line 266) creates the node and connects
  `frame_gesture_detected → _take_photo` (same callback the button uses — no duplicated
  game logic) and `→ _flash_camera_indicator`; `camera_status_changed → _on_camera_status_changed`
  (~line 423) drives a small top-right HUD label built in `_build_camera_indicator()`
  (~line 252), shown only while a room screen is open.
- `export/web_head_include.html` is the detector itself: debounces the gesture (must
  hold ~8 frames, then a release + ~1.5s cooldown before it can fire again) so a stray
  pose doesn't burn one of the limited photos-per-night.

**Export preset:** `export_presets.cfg`'s `[preset.0]` ("Web") now has
`html/head_include` populated with the full contents of `export/web_head_include.html`
(escaped onto one line). **If you ever re-author that head-include HTML, regenerate
this field too** — editing the `.html` file alone does nothing unless it's also copied
into the preset (or pasted by hand into Godot's Export dialog → Web → HTML → Head
Include). `variant/thread_support=false` is intentionally set: a threaded web build
needs cross-origin-isolation headers that fight both itch.io's iframe embedding and the
MediaPipe CDN load — don't flip this on without re-testing the gesture feature.

**Known biggest risk — not yet resolved:** itch.io embeds HTML games in a
cross-origin iframe, and `getUserMedia` is blocked there unless the iframe carries
`allow="camera"` (set by itch.io, not by us). This has **not been tested on an actual
itch.io upload yet**. `web/README.md` documents a fallback ladder (test embedded → if
blocked, host the identical build on GitHub Pages/Netlify/Vercel and link to it from
the itch page) — the on-screen "Take Polaroid" button always still works regardless, so
the gesture failing is degraded, not broken.

**Testing without re-exporting from Godot every time:** `web/test_detector.html` is a
standalone page (no Godot) for tuning the gesture thresholds — serve `web/` over
`python3 -m http.server` and open it at `http://localhost:<port>/test_detector.html`
(camera requires a secure context: `localhost` works, `file://` does not).

**Verification status:** all of the above was checked by static reading and by
serving the exported build locally over `http://localhost` in this session, but **no
one has yet confirmed in front of an actual webcam that the frame gesture reliably
fires `_take_photo()` end-to-end in the exported game** (the local server used for that
test was killed before a result came back). **Next session: do that check first** —
open `horizon nexus hackathon.html` over localhost, open a room, make the gesture, and
confirm the HUD flashes and a photo is consumed. If the gesture is too strict/loose,
tune `HOLD_FRAMES` / `COOLDOWN_MS` / `CORNER_DIST` at the top of
`export/web_head_include.html` (and mirror the same constants in
`web/test_detector.html`), then redo the escaping step into `export_presets.cfg`.

## Past fix: `ROOM_SCENE` → `ROOM_SCENES` (still relevant — order unverified)

`scripts/main.gd` used to have `const ROOM_SCENE := preload("res://scenes/Room.tscn")`
but `scenes/Room.tscn` had been deleted in favor of 6 separate files under
`scenes/Rooms/`. Fixed by introducing `ROOM_SCENES: Array[PackedScene]` (one preload
per room file) plus a parallel `ROOM_NAMES` array, both indexed to match
`Screen0..Screen5`; `_build_feeds()` instantiates `ROOM_SCENES[i]` per screen.

**Still unverified / needs a human pass in the Godot editor:** the `ROOM_SCENES` /
`ROOM_NAMES` array order (Entrance, Bar, Lounge, Poker, Roulette, Slot Machines) is a
placeholder guess — there was no naming hint tying `Screen0..Screen5` in `Main.tscn`
(`MonitorScreen/WallCenter/ScreenLayout`) to a specific room. If the in-game wall shows
the wrong room name/feed on a given screen, reorder the two arrays at the top of
`scripts/main.gd` — no other code depends on the order.

## Known rough edges / pending state

- **Exported web build binaries are committed to git** (`horizon nexus hackathon.wasm`
  at ~38MB, `.pck`, `.js`, plus a `horizon-nexus-hackathon.zip`). This happened as part
  of testing the gesture feature this session (needed a real exported build to serve
  locally) and was committed (`92e7c64`, "added hand gesture test") rather than
  `.gitignore`d. Fine for now, but these will go stale the moment the project changes —
  consider re-exporting before any itch.io upload rather than trusting the committed
  copy, and consider whether large binaries belong in git history long-term.
- The root-level `horizon nexus hackathon.html` currently has the gesture detector
  injected via a one-off Python script (mid-session, before the `export_presets.cfg`
  fix existed) rather than via a normal Godot export. It is **functionally fine** (the
  HTML is well-formed, verified with one `</head>` tag and the detector script present)
  but it's a hand-patched artifact, not reproducible from the editor as-is. The next
  *real* export from Godot (Project → Export → Web → Export Project) will now pick up
  the detector automatically from the fixed preset and overwrite this file cleanly —
  do that rather than re-patching by hand.
- No Godot CLI is available in this environment — all GDScript changes (gesture
  feature included) were verified by static reading, not by running the game inside
  the editor. **Open the project in Godot and playtest** before trusting any of this,
  especially the screen-to-room mapping above and the gesture feature.
- An empty untracked 0-byte file named `HTTP` sits in the project root (pre-existing,
  unrelated to any of this work — likely a stray artifact from an earlier curl/test
  command). Harmless; delete or ignore whenever convenient.
- `room_background.gd` draws placeholder art procedurally and is explicitly marked
  for deletion/replacement once real room art exists.
- HUD money display in `main.gd` (`_build_money_display`, `_on_money_changed`) uses
  per-digit sprite textures (`assets/money_digits/...`) — somewhat fragile if money
  ever exceeds 6 digits (`"%06d" % value`).
