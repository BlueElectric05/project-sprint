extends CharacterBody3D

# --- DRIVING STATS (Mazda Miata NA - Balanced for Gameplay) ---
@export var max_speed: float = 11.0
@export var backward_speed: float = 3.0
@export var friction: float = 2.6
@export var braking_power: float = 5.0 
@export var turn_speed: float = 3.6
@export var grip: float = 8.0           
@export var bounciness: float = 0.3    

# --- MAZDA MIATA NA 5-SPEED MANUAL TRANSMISSION ---
@export var gear_speeds: Array[float] = [3.0, 5.2, 7.4, 9.4, 11.0]
@export var gear_accelerations: Array[float] = [1.8, 1.45, 1.15, 0.9, 0.72]

var current_gear: int = 1

# --- ENGINE & RPM STATS ---
@export var idle_rpm: float = 1000.0
@export var max_rpm: float = 7200.0
@export var redline_rpm: float = 6500.0
var current_rpm: float = 1000.0

# --- MODE 7 JITTER SETTINGS ---
@export var position_step_size: float = 0.05 
@export var rotation_steps: int = 256 

# --- PARALLAX HORIZON SETTINGS ---
@export var horizon_scroll_speed: float = 600.0

# --- SPEEDOMETER MULTIPLIER ---
@export var speed_unit_multiplier: float = 16.0
@export var use_mph: bool = false 

# --- NODES ---
@onready var camera: Camera3D = $Camera3D
@onready var sprite: Sprite2D = $CanvasLayer/Sprite2D
@onready var parallax: Parallax2D = $Background/Parallax2D
@onready var speedometer: Label = $HUD/Speed
@onready var gear_label: Label = $HUD/gear
@onready var tachometer: TextureProgressBar = $HUD/tacho

@onready var camera_base_pos: Vector3 = camera.position
@onready var camera_base_rot: Vector3 = camera.rotation

var current_speed: float = 0.0

func _ready() -> void:
	camera.top_level = true
	
	# Configure TextureProgressBar bounds automatically
	if tachometer:
		tachometer.min_value = 0
		tachometer.max_value = max_rpm
	
	center_sprite_on_screen()
	get_viewport().size_changed.connect(center_sprite_on_screen)

func center_sprite_on_screen() -> void:
	if not sprite:
		return
	var viewport_size = get_viewport().get_visible_rect().size
	sprite.global_position = Vector2(viewport_size.x / 2.0, viewport_size.y * 0.75).round()

func update_speedometer() -> void:
	if not speedometer:
		return
		
	var raw_speed: float = absf(current_speed)
	var display_speed: float = roundf(raw_speed * speed_unit_multiplier)

	var gear_text = "R" if current_speed < -0.1 else str(current_gear)
	if gear_label:
		gear_label.text = "%s A/T" % gear_text

	if use_mph:
		display_speed *= 0.621371
		speedometer.text = "%03d MPH" % display_speed
	else:
		speedometer.text = "%03d KM/H" % display_speed

func calculate_rpm() -> void:
	var abs_speed = absf(current_speed)
	
	# 1. Stopped / Idling State
	if abs_speed < 0.05:
		current_rpm = idle_rpm
	# 2. Reversing State
	elif current_speed < -0.1:
		var reverse_pct = abs_speed / backward_speed
		current_rpm = lerp(idle_rpm, redline_rpm, clampf(reverse_pct, 0.0, 1.0))
	# 3. Forward Gears State
	else:
		var min_gear_speed: float = 0.0
		if current_gear > 1:
			min_gear_speed = gear_speeds[current_gear - 2]
		
		var max_gear_speed: float = gear_speeds[current_gear - 1]
		
		# Normalize current speed to a 0.0 - 1.0 ratio inside the active gear's speed band
		var gear_pct = (abs_speed - min_gear_speed) / (max_gear_speed - min_gear_speed)
		gear_pct = clampf(gear_pct, 0.0, 1.0)
		
		# Upshift entry RPM drops to ~4000 RPM, sweeping up to redline (7000 RPM)
		var gear_start_rpm = idle_rpm if current_gear == 1 else 4000.0
		var target_rpm = lerp(gear_start_rpm, redline_rpm, gear_pct)
		
		# Add a subtle rev-bounce if holding max speed in 5th gear
		if current_gear == gear_speeds.size() and gear_pct >= 0.99:
			target_rpm += randf_range(-150.0, 150.0)
			
		current_rpm = target_rpm

	# 4. Update UI Gauge
	if tachometer:
		tachometer.value = current_rpm

func _process(_delta: float) -> void:
	update_speedometer()
	calculate_rpm()

	# Mode 7 Camera Position & Rotation
	var smooth_cam_pos = global_position + (global_transform.basis * camera_base_pos)
	var smooth_cam_rot = global_rotation + camera_base_rot
	
	var step_angle = TAU / float(rotation_steps)
	
	camera.global_position = smooth_cam_pos.snapped(Vector3(position_step_size, position_step_size, position_step_size))
	camera.global_rotation.y = round(smooth_cam_rot.y / step_angle) * step_angle
	camera.global_rotation.x = smooth_cam_rot.x
	camera.global_rotation.z = smooth_cam_rot.z

	# Parallax Horizon Scrolling
	if is_instance_valid(parallax):
		var scroll_pct = rotation.y / TAU
		var pixel_offset = round(scroll_pct * horizon_scroll_speed)
		parallax.scroll_offset.x = pixel_offset

func _physics_process(delta: float) -> void:
	var gas_input = Input.get_action_strength("accelerate")
	var reverse_input = Input.get_action_strength("brake")
	var turn_input = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	
	update_gear_state()
	var current_accel = gear_accelerations[current_gear - 1]
	var target_max = gear_speeds[current_gear - 1]
	
	if reverse_input > 0:
		if current_speed > 1.0:
			current_speed = move_toward(current_speed, 0.0, braking_power * delta)
		else:
			current_speed = move_toward(current_speed, -backward_speed, current_accel * delta)
	elif gas_input > 0:
		current_speed = move_toward(current_speed, target_max, current_accel * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, friction * delta)
		
	var speed_ratio = current_speed / max_speed
	
	if abs(current_speed) > 0.1:
		var weight_multiplier = lerp(1.0, 0.38, clamp(abs(speed_ratio), 0.0, 1.0))
		rotate_y(turn_input * turn_speed * speed_ratio * weight_multiplier * delta)

	var forward_dir = (transform.basis * Vector3(0, 0, -1)).normalized()
	var target_velocity = forward_dir * current_speed
	
	velocity = velocity.lerp(target_velocity, grip * delta)
	velocity.y = 0.0 
	
	move_and_slide()
	
	# 6. WALL BOUNCING & SMOOTH SPEED LOSS
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var normal = collision.get_normal()
		
		# Check if collision is a wall (normal is horizontal, not a floor/ceiling)
		if normal.y < 0.5: 
			# Reflect the 3D velocity vector off the wall
			velocity = velocity.bounce(normal) * bounciness
			
			# Extract remaining forward/backward momentum along the car's facing direction
			var energy_along_facing = velocity.dot(forward_dir)
			
			# Keep 70% of the remaining momentum to prevent instant stops (smooth flow)
			current_speed = energy_along_facing * 0.7
			
			# Force a minimum speed threshold if scraping a wall so the car doesn't get glued to it
			if absf(current_speed) < 0.5 and gas_input > 0:
				current_speed = 0.8 * signf(energy_along_facing if energy_along_facing != 0 else 1.0)

func update_gear_state() -> void:
	if current_speed <= 0.1:
		current_gear = 1
		return
		
	if current_gear > 1 and current_speed < gear_speeds[current_gear - 2] * 0.9:
		current_gear -= 1
	elif current_gear < gear_speeds.size() and current_speed >= gear_speeds[current_gear - 1] * 0.94:
		current_gear += 1