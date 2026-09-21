extends CharacterBody3D

const STOP_SPEED := 0.05
const MOVING_SPEED := 0.1
const UPSHIFT_RATIO := 0.94
const DOWNSHIFT_RATIO := 0.90
const WALL_NORMAL_LIMIT := 0.5
const COLLISION_SPEED_RETENTION := 0.7
const MIN_WALL_ESCAPE_SPEED := 0.8

@export_category("Driving")
@export var max_speed: float = 11.0
@export var backward_speed: float = 3.0
@export var friction: float = 1.6
@export var braking_power: float = 5.0
@export var turn_speed: float = 3.6
@export_range(0.0, 1.0, 0.01) var low_speed_steering: float = 0.30
@export_range(0.0, 1.0, 0.01) var high_speed_steering: float = 0.38
@export var grip: float = 8.0

@export_category("Transmission")
@export var gear_speeds: Array[float] = [3.0, 5.2, 7.4, 9.4, 11.0]
@export var gear_accelerations: Array[float] = [1.5, 1.0, 0.7, 0.4, 0.2]
var current_gear: int = 1

@export_category("Engine")
@export var idle_rpm: float = 1000.0
@export var max_rpm: float = 7200.0
@export var redline_rpm: float = 6500.0
var current_rpm: float = 1000.0

@export_category("Presentation")
@export var position_step_size: float = 0.05
@export var rotation_steps: int = 256
@export var horizon_scroll_speed: float = 600.0
@export var speed_unit_multiplier: float = 16.0
@export var use_mph: bool = false
@export_range(0.0, 1.0, 0.01) var steer_max_ratio_threshold: float = 0.45

@onready var camera: Camera3D = $Camera3D
@onready var sprite: AnimatedSprite2D = $CanvasLayer/car
@onready var shadow: ColorRect = $CanvasLayer/Shadow
@onready var parallax: Parallax2D = $Background/Parallax2D
@onready var speedometer: Label = $HUD/Speed
@onready var gear_label: Label = $HUD/gear
@onready var tachometer: TextureProgressBar = $HUD/tacho

@onready var camera_base_position: Vector3 = camera.position
@onready var camera_base_rotation: Vector3 = camera.rotation

var current_speed := 0.0
var current_steering := 0.0

func _ready() -> void:
	assert(
		not gear_speeds.is_empty() and gear_speeds.size() == gear_accelerations.size(),
        "Gear speeds and accelerations must be non-empty and have matching lengths."
	)
	current_gear = clampi(current_gear, 1, gear_speeds.size())
	camera.top_level = true
	tachometer.min_value = 0.0
	tachometer.max_value = max_rpm
	
	center_sprite_on_screen()
	get_viewport().size_changed.connect(center_sprite_on_screen)


# --- VISUALS & UI ---
func _process(_delta: float) -> void:
	var speed := absf(current_speed)

	# 1. Update HUD (Speedometer & Gear)
	var display_speed := int(roundf(speed * speed_unit_multiplier))
	if use_mph:
		display_speed = int(roundf(display_speed * 0.621371))
		speedometer.text = "%03d MPH" % display_speed
	else:
		speedometer.text = "%03d KM/H" % display_speed

	var gear_text := "R" if current_speed < -MOVING_SPEED else str(current_gear)
	gear_label.text = "%s A/T" % gear_text

	# 2. Update RPM & Tachometer
	if speed < STOP_SPEED:
		current_rpm = idle_rpm
	elif current_speed < -MOVING_SPEED:
		var reverse_ratio := clampf(speed / maxf(backward_speed, 0.001), 0.0, 1.0)
		current_rpm = lerpf(idle_rpm, redline_rpm, reverse_ratio)
	else:
		var gear_index := current_gear - 1
		var gear_min_speed := 0.0 if gear_index == 0 else gear_speeds[gear_index - 1]
		var gear_range := maxf(gear_speeds[gear_index] - gear_min_speed, 0.001)
		var gear_ratio := clampf((speed - gear_min_speed) / gear_range, 0.0, 1.0)
		var gear_start_rpm := idle_rpm if gear_index == 0 else 4000.0
		current_rpm = lerpf(gear_start_rpm, redline_rpm, gear_ratio)

	tachometer.value = current_rpm

	# 3. Update Sprite Animation
	var is_moving := speed > MOVING_SPEED
	var speed_ratio := clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0)
	
	var target_animation: StringName = sprite.animation

	if is_moving:
		sprite.speed_scale = remap(speed_ratio, 0.0, 1.0, 0.4, 1.8)
		
		if absf(current_steering) > 0.2:
			sprite.flip_h = current_steering > 0.0
			
			if absf(current_steering) >= steer_max_ratio_threshold:
				# --- TRANSITION LOGIC ---
				if sprite.animation == &"move" or sprite.animation == &"idle":
					# 1. If coming from straight, force steer_min to play first
					target_animation = &"steer_min"
				elif sprite.animation == &"steer_min" and sprite.is_playing():
					# 2. If steer_min is currently playing, wait for it to finish!
					target_animation = &"steer_min"
				else:
					# 3. Min has finished playing, safe to upgrade to max
					target_animation = &"steer_max"
			else:
				target_animation = &"steer_min"
		else:
			sprite.flip_h = false
			target_animation = &"move"
	else:
		sprite.speed_scale = 1.0
		sprite.flip_h = false
		target_animation = &"idle"

	# Only call play() if the animation state actually needs to change
	if sprite.animation != target_animation:
		sprite.play(target_animation)

	# 4. Update Mode 7 Camera & Parallax Horizon
	var camera_position := global_position + global_transform.basis * camera_base_position
	var camera_rotation := global_rotation + camera_base_rotation
	var rotation_step := TAU / maxf(float(rotation_steps), 1.0)

	camera.global_position = camera_position.snapped(Vector3.ONE * position_step_size)
	camera.global_rotation = Vector3(
		camera_rotation.x,
		round(camera_rotation.y / rotation_step) * rotation_step,
		camera_rotation.z
	)

	var scroll_ratio := rotation.y / TAU
	parallax.scroll_offset.x = round(scroll_ratio * horizon_scroll_speed)


# --- PHYSICS & MOVEMENT ---
func _physics_process(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	var steering := Input.get_axis("steer_right", "steer_left")

	current_steering = move_toward(current_steering, steering, 6.0 * delta)

	# 1. Update Gear State
	if current_speed <= MOVING_SPEED:
		current_gear = 1
	else:
		var gear_index := current_gear - 1
		if current_gear > 1 and current_speed < gear_speeds[gear_index - 1] * DOWNSHIFT_RATIO:
			current_gear -= 1
		elif current_gear < gear_speeds.size() and current_speed >= gear_speeds[gear_index] * UPSHIFT_RATIO:
			current_gear += 1

	# 2. Update Speed & Acceleration
	var gear_acceleration := gear_accelerations[current_gear - 1]
	var gear_max_speed := gear_speeds[current_gear - 1]

	if throttle > 0.0:
		if current_speed < 0.0:
			current_speed = move_toward(current_speed, 0.0, braking_power * throttle * delta) - abs(current_steering) * 0.01
		else:
			current_speed = move_toward(current_speed, gear_max_speed, gear_acceleration * throttle * delta) - abs(current_steering) * 0.02
	elif brake > 0.0:
		if current_speed > 0.0:
			current_speed = move_toward(current_speed, 0.0, braking_power * brake * delta)
		else:
			current_speed = move_toward(current_speed, -backward_speed, gear_acceleration * brake * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, friction * delta) + abs(current_steering) * 0.01

	# 3. Apply Steering
	if absf(current_steering) > 0.01 and absf(current_speed) > MOVING_SPEED:
		var speed_ratio := clampf(absf(current_speed) / maxf(max_speed, 0.001), 0.0, 1.0)
		var steering_response := lerpf(low_speed_steering, high_speed_steering, speed_ratio)
		var travel_direction := signf(current_speed)
		rotate_y(current_steering * turn_speed * steering_response * travel_direction * delta)

	# 4. Apply 3D Movement
	var forward_direction := (transform.basis * Vector3.FORWARD).normalized()
	var target_velocity := forward_direction * current_speed
	var traction := clampf(grip * delta, 0.0, 1.0)

	velocity = velocity.lerp(target_velocity, traction)
	velocity.y = 0.0
	move_and_slide()

	

	

# (Keep this separate because it is used as a Callable for a signal)
func center_sprite_on_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	sprite.global_position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.75).round()
	shadow.global_position = Vector2(viewport_size.x / 2.2, viewport_size.y * 0.73).round()
