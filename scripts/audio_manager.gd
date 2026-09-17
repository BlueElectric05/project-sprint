extends Node

# --- PITCH & VOLUME SETTINGS ---
@export var min_pitch: float = 1.0          # Pitch at idle (1000 RPM)
@export var max_pitch: float = 6.2          # Pitch at redline (7200 RPM)
@export var pitch_smooth_speed: float = 15.0 

var active_car: Node = null

# The engine player lives in this autoload scene.  Keep a single global player
# so the car scene cannot start an unmodulated duplicate of the same sound.
@onready var engine_sound: AudioStreamPlayer = $Engine01

func _ready() -> void:
	if engine_sound and not engine_sound.playing:
		engine_sound.pitch_scale = min_pitch
		engine_sound.play()

func find_active_car() -> void:
	# 1. Search by Group "player_car"
	var cars = get_tree().get_nodes_in_group("player_car")
	if cars.size() > 0:
		active_car = cars[0]
		return

	# 2. Fallback recursive search
	var root = get_tree().current_scene
	if root:
		active_car = _find_car_recursive(root)

func _find_car_recursive(node: Node) -> Node:
	if "current_rpm" in node:
		return node
	for child in node.get_children():
		var result = _find_car_recursive(child)
		if result:
			return result
	return null

func _process(delta: float) -> void:
	# Keep searching every frame until the car is found
	if not is_instance_valid(active_car):
		find_active_car()
		return

	if not engine_sound:
		return

	# DIRECT ACCESS (Fixes the .get() issue)
	var current_rpm: float = active_car.current_rpm if "current_rpm" in active_car else 1000.0
	var idle_rpm: float = active_car.idle_rpm if "idle_rpm" in active_car else 1000.0
	var max_rpm: float = active_car.max_rpm if "max_rpm" in active_car else 7200.0

	# Guard against division by zero if max_rpm == idle_rpm
	var rpm_range: float = max_rpm - idle_rpm
	if rpm_range <= 0.0:
		return

	# Normalize RPM percentage   (0.0 to 1.0)
	var rpm_pct: float = clampf((current_rpm - idle_rpm) / rpm_range, 0.0, 1.0)

	# Calculate and apply pitch smoothly
	var target_pitch: float = lerp(min_pitch, max_pitch, rpm_pct)
	engine_sound.pitch_scale = move_toward(engine_sound.pitch_scale, target_pitch, pitch_smooth_speed * delta)
