extends RefCounted
class_name IDMSimulationClock

## Fixed-step clock: rendering frame rate does not determine how many domain
## ticks elapse. Consumers advance domain systems only for returned steps.
const FIXED_STEP_SECONDS := 0.1
const MAX_STEPS_PER_ADVANCE := 25
const VALID_SPEEDS := [1, 5, 10, 50, 100]

static func normalize_saved_speed(value: int) -> int:
	# Old releases offered 2× and some saves used 4×. Keep the nearest
	# conservative supported value when restoring those records.
	if value == 2:
		return 1
	if value == 4:
		return 5
	return value if value in VALID_SPEEDS else 1

var paused := false
var speed := 1
var simulation_seconds := 0.0
var _accumulator := 0.0

func set_speed(value: int) -> bool:
	if value not in VALID_SPEEDS:
		return false
	speed = value
	return true

func set_paused(value: bool) -> void:
	paused = value

func advance(real_delta_seconds: float) -> int:
	if paused or real_delta_seconds <= 0.0:
		return 0
	_accumulator += real_delta_seconds * float(speed)
	var count := 0
	while _accumulator + 0.0000001 >= FIXED_STEP_SECONDS and count < MAX_STEPS_PER_ADVANCE:
		_accumulator -= FIXED_STEP_SECONDS
		simulation_seconds += FIXED_STEP_SECONDS
		count += 1
	return count

func clear_accumulator() -> void:
	_accumulator = 0.0
