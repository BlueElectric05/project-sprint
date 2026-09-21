extends Node

# --- PITCH & VOLUME SETTINGS ---
@export var min_pitch: float = 1.0          # Pitch at idle (1000 RPM)
@export var max_pitch: float = 6.2          # Pitch at redline (7200 RPM)
@export var pitch_smooth_speed: float = 15.0 

# --- MUSIC SETTINGS ---
@export var mus_state: int = 0
# Add any future music tracks to this array in the inspector or right here!
@onready var music_tracks: Array[AudioStreamPlayer] = [$Music/Race01] 

@onready var engine_sound: AudioStreamPlayer = $SFX/Engine01
var active_car: Node = null


func _ready() -> void:
	if engine_sound and not engine_sound.playing:
		engine_sound.pitch_scale = min_pitch
		engine_sound.play()
		
	# Apply initial music state
	update_music_state()


# --- INPUT HANDLING ---
func _unhandled_input(event: InputEvent) -> void:
	# Use event-driven input instead of checking every frame in _process
	if event.is_action_pressed("mus_change"):
		cycle_music()


# --- PER-FRAME UPDATES ---
func _process(delta: float) -> void:
	update_engine_sound(delta)


# --- MUSIC LOGIC ---
func cycle_music() -> void:
	# Cycles: 0 (Off) -> 1 (Track 1) -> 2 (Track 2) -> Back to 0
	mus_state = (mus_state + 1) % (music_tracks.size() + 1)
	update_music_state()
	print("Music state changed to: ", mus_state)

func update_music_state() -> void:
	# 1. Stop all tracks first to prevent overlapping audio
	for track in music_tracks:
		if track and track.playing:
			track.stop()
			
	# 2. Play the selected track (mus_state > 0 means music is ON)
	if mus_state > 0:
		var active_track = music_tracks[mus_state - 1]
		if active_track and not active_track.playing:
			active_track.play()


# --- ENGINE & CAR SEARCH LOGIC ---
func update_engine_sound(delta: float) -> void:
	if not is_instance_valid(active_car):
		active_car = find_active_car(get_tree().current_scene)
		return

	if not engine_sound:
		return

	# Use .get() to safely pull variables. If missing, fallback to defaults.
	var current_rpm: float = active_car.get("current_rpm") if active_car.get("current_rpm") != null else 1000.0
	var idle_rpm: float = active_car.get("idle_rpm") if active_car.get("idle_rpm") != null else 1000.0
	var max_rpm: float = active_car.get("max_rpm") if active_car.get("max_rpm") != null else 7200.0

	var rpm_range: float = max_rpm - idle_rpm
	if rpm_range <= 0.0:
		return

	var rpm_pct: float = clampf((current_rpm - idle_rpm) / rpm_range, 0.0, 1.0)
	var target_pitch: float = lerpf(min_pitch, max_pitch, rpm_pct)
	
	engine_sound.pitch_scale = move_toward(engine_sound.pitch_scale, target_pitch, pitch_smooth_speed * delta)


func find_active_car(node: Node) -> Node:
	# 1. Search by Group (Fastest method)
	var cars = get_tree().get_nodes_in_group("player_car")
	if cars.size() > 0:
		return cars[0]

	# 2. Fallback Recursive Search (Combined from your previous code)
	if not node: 
		return null
		
	if "current_rpm" in node:
		return node
		
	for child in node.get_children():
		var result = find_active_car(child)
		if result:
			return result
			
	return null
