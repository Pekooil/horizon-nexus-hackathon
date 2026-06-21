extends Node
## Global game state: money, nights, clock, ferret accounting, win/lose.
## Registered as an autoload singleton named "GameManager" (see project.godot),
## so any scene can read/update it.

signal money_changed(amount: float)
signal night_changed(night: int)
signal clock_changed(text: String)
signal photos_changed(count: int)
signal hour_changed(hour: int)
signal game_over(won: bool)

const MAX_NIGHTS := 5
const NIGHT_HOURS := 6                 # in-game hours per night (12AM -> 6AM)
const SECONDS_PER_HOUR := 5.0          # real seconds per in-game hour
const NIGHT_DURATION := NIGHT_HOURS * SECONDS_PER_HOUR   # 30 real seconds per night
const PHOTOS_PER_NIGHT := 5            # Polaroids available each night
const START_MONEY := 1400.0
const PASSIVE_INCOME := 14.0          # $/sec earned when no ferret is active
const FERRET_DRAIN := 36.0            # $/sec lost per active ferret
const CATCH_BONUS := 150.0            # reward for catching a ferret
const FALSE_ACCUSE_PENALTY := 90.0    # cost of photographing an innocent

var money := START_MONEY
var current_night := 1
var night_time_left := NIGHT_DURATION
var photos_left := PHOTOS_PER_NIGHT
var running := false
var active_ferrets: Array = []        # CasinoPlayer nodes currently cheating
var _last_hour := 0

func start_game() -> void:
	money = START_MONEY
	current_night = 1
	_begin_night()

func _begin_night() -> void:
	night_time_left = NIGHT_DURATION
	photos_left = PHOTOS_PER_NIGHT
	active_ferrets.clear()
	running = true
	_last_hour = 0
	emit_signal("night_changed", current_night)
	emit_signal("money_changed", money)
	emit_signal("clock_changed", _format_clock())
	emit_signal("photos_changed", photos_left)

## Tries to consume one Polaroid. Returns false (and changes nothing) when out of film.
func use_photo() -> bool:
	if photos_left <= 0:
		return false
	photos_left -= 1
	emit_signal("photos_changed", photos_left)
	return true

func _process(delta: float) -> void:
	if not running:
		return

	night_time_left -= delta

	if active_ferrets.is_empty():
		money += PASSIVE_INCOME * delta
	else:
		money -= FERRET_DRAIN * active_ferrets.size() * delta

	emit_signal("money_changed", money)
	emit_signal("clock_changed", _format_clock())

	var hour := mini(int((NIGHT_DURATION - night_time_left) / SECONDS_PER_HOUR), NIGHT_HOURS)
	if hour != _last_hour:
		_last_hour = hour
		emit_signal("hour_changed", hour)

	if money <= 0.0:
		money = 0.0
		emit_signal("money_changed", money)
		running = false
		emit_signal("game_over", false)
		return

	if night_time_left <= 0.0:
		_end_night()

func _end_night() -> void:
	running = false
	if current_night >= MAX_NIGHTS:
		emit_signal("game_over", true)
	else:
		current_night += 1
		_begin_night()

func register_ferret(npc) -> void:
	if npc not in active_ferrets:
		active_ferrets.append(npc)

## Re-points active_ferrets at a ferret's new seat after they move rooms.
func transfer_ferret(old_npc, new_npc) -> void:
	active_ferrets.erase(old_npc)
	if new_npc not in active_ferrets:
		active_ferrets.append(new_npc)

func catch_ferret(npc) -> void:
	active_ferrets.erase(npc)
	money += CATCH_BONUS
	emit_signal("money_changed", money)

func false_accuse() -> void:
	money -= FALSE_ACCUSE_PENALTY
	emit_signal("money_changed", money)

func _format_clock() -> String:
	var elapsed := NIGHT_DURATION - night_time_left
	var hour := mini(int(elapsed / SECONDS_PER_HOUR), NIGHT_HOURS)   # 0..6
	var display := 12 if hour == 0 else hour
	return "%d:00 AM" % display
