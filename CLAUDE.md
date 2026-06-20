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

## Project layout

- `project.godot` — `run/main_scene` is `res://scenes/StartScreen.tscn`. `GameManager`
  is registered as an autoload singleton (persists across scene changes).
- `scenes/StartScreen.tscn` + `scripts/start_screen.gd` — title screen, one button,
  `change_scene_to_file("res://scenes/Main.tscn")`.
- `scenes/Main.tscn` + `scripts/main.gd` — the root gameplay scene. Builds the 6 live
  camera feeds, the monitor wall, the full-screen room/detail view with the Polaroid
  mechanic, the HUD, and the win/lose overlay. **This is the file most gameplay/UI
  work touches.**
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

## How the click → room-page flow works (scripts/main.gd)

This is the core mechanic that was just fixed/wired up:

1. `_unhandled_input()` (~line 76) detects a left-click and calls
   `_get_screen_at_point()` (~line 337) to find which `Screen0..Screen5` was hit.
2. `_open_detail(i)` (~line 245) is the trigger function — it switches the *view*
   (not a real Godot scene change) to show room `i` full-screen: sets the detail
   texture, updates the label to the room's name, hides the monitor wall.
3. `_take_photo()` (~line 258) implements the Polaroid mechanic against
   `rooms[current_detail]` — calls `GameManager.use_photo()`, then
   `room.get_active_ferret()` to check for a cheater, then `catch_ferret()` /
   `false_accuse()` accordingly.
4. `_close_detail()` (~line 252) is "Back to wall" — restores the monitor view.

**Important architectural decision (confirmed with user):** room navigation stays
*inside* `Main.tscn` by swapping visibility, rather than doing a real
`get_tree().change_scene_to_file()` to the room's own `.tscn`. Reason: the live
`Room` instances (with current ferret/cheater state) only exist as children of the
`SubViewport`s built in `_build_feeds()`. A real scene change would instantiate a
*fresh* room with no memory of which patron is cheating, desyncing it from
`GameManager.active_ferrets`. If a future request asks for a "zoom" animation or a
true separate page per room, raise this constraint again before changing the
approach.

## Recent fix (this session)

`scripts/main.gd` had `const ROOM_SCENE := preload("res://scenes/Room.tscn")` — but
`scenes/Room.tscn` had been deleted from the working tree in favor of 6 separate
files under `scenes/Rooms/`. This broke the project entirely (wouldn't even parse).

Fixed by:
- Replacing `ROOM_SCENE` with `ROOM_SCENES: Array[PackedScene]`, one preload per room
  file, plus a parallel `ROOM_NAMES` array — both indexed to match `Screen0..Screen5`.
- `_build_feeds()` now instantiates `ROOM_SCENES[i]` instead of one shared template.
- `_open_detail()` label now shows the room's name instead of "CAM %d".

**Unverified / needs a human pass in the Godot editor:** the `ROOM_SCENES` /
`ROOM_NAMES` array order (Entrance, Bar, Lounge, Poker, Roulette, Slot Machines) is a
placeholder guess — there was no naming hint tying `Screen0..Screen5` in
`Main.tscn` (`MonitorScreen/WallCenter/ScreenLayout`) to a specific room. If the
in-game wall shows the wrong room name/feed on a given screen, just reorder the two
arrays at the top of `scripts/main.gd` — no other code depends on the order.

## Known rough edges / pending git state

- Working tree (uncommitted) has: `project.godot` modified (Godot version bumped
  4.6 → 4.7), `scenes/Room.tscn` deleted, `scripts/main.gd` modified (the fix above),
  `scenes/Rooms/` untracked (new room scene files). None of this is committed yet.
- No Godot CLI is available in this environment — changes were verified by static
  reading of the code, not by actually running the game. **Open the project in the
  Godot editor and playtest** before trusting this is fully correct, especially the
  screen-to-room mapping above.
- `room_background.gd` draws placeholder art procedurally and is explicitly marked
  for deletion/replacement once real room art exists.
- HUD money display in `main.gd` (`_build_money_display`, `_on_money_changed`) uses
  per-digit sprite textures (`assets/money_digits/...`) — somewhat fragile if money
  ever exceeds 6 digits (`"%06d" % value`).
