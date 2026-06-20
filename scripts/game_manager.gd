extends Node
## Global game state: money, nights, clock, ferret accounting, win/lose.
## Registered as an autoload singleton named "GameManager" (see project.godot),
## so any scene can read/update it.

signal money_changed(amount: float)
signal night_changed(night: int)
signal clock_changed(text: String)
signal game_over(won: bool)

const MAX_NIGHTS := 5
const NIGHT_DURATION := 90.0          # real seconds per night (12AM -> 6AM)
const START_MONEY := 1000.0
const PASSIVE_INCOME := 12.0          # $/sec earned when no ferret is active
const FERRET_DRAIN := 45.0            # $/sec lost per active ferret
const CATCH_BONUS := 150.0            # reward for catching a ferret
const FALSE_ACCUSE_PENALTY := 120.0   # cost of photographing an innocent

var money := START_MONEY
var current_night := 1
var night_time_left := NIGHT_DURATION
var running := false
var active_ferrets: Array = []        # CasinoPlayer nodes currently cheating

func start_game() -> void:
	money = START_MONEY
	current_night = 1
	_begin_night()

func _begin_night() -> void:
	night_time_left = NIGHT_DURATION
	active_ferrets.clear()
	running = true
	emit_signal("night_changed", current_night)
	emit_signal("money_changed", money)
	emit_signal("clock_changed", _format_clock())

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

func catch_ferret(npc) -> void:
	active_ferrets.erase(npc)
	money += CATCH_BONUS
	emit_signal("money_changed", money)

func false_accuse() -> void:
	money -= FALSE_ACCUSE_PENALTY
	emit_signal("money_changed", money)

func _format_clock() -> String:
	var elapsed := NIGHT_DURATION - night_time_left
	var hour := int(elapsed / NIGHT_DURATION * 6.0)   # 0..6
	var display := 12 if hour == 0 else hour
	return "%d:00 AM" % display
