extends Node3D

var camera_position:Vector3
var camera_rotation:Vector3

var zoom:float = 30.0 # 30 = Standard zoom level, in meters

const MIN_ZOOM:float = 15.0
const MAX_ZOOM:float = 80.0
const ZOOM_STEP:float = 5.0
const TRACKPAD_PAN_SPEED:float = 0.08
const TOUCH_PAN_SPEED:float = 0.008
const TOUCH_ROTATE_DEADZONE:float = 0.15

@onready var camera = $Camera

var active_touches := {}

func _ready():
	
	camera_rotation = rotation_degrees # Initial rotation
	
	pass

func _process(delta):
	
	# Set position and rotation to targets
	
	position = position.lerp(camera_position, delta * 8)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	
	# Smoothly update zoom
	
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), delta * 8)
	
	handle_input(delta)

# Handle input

func handle_input(_delta):
	
	# Rotation
	
	var input := Vector3.ZERO
	
	input.x = Input.get_axis("camera_left", "camera_right")
	input.z = Input.get_axis("camera_forward", "camera_back")
	
	input = input.rotated(Vector3.UP, rotation.y).normalized()
	
	camera_position += input / 4
	
	# Zoom in/out
	
	if Input.is_action_just_released("zoom_in"):
		zoom = clampf(zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		
	if Input.is_action_just_released("zoom_out"):
		zoom = clampf(zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	
	# Back to center
	
	if Input.is_action_pressed("camera_center"):
		camera_position = Vector3()

func _input(event):
	
	# Rotate camera using mouse (hold 'middle' mouse button)
	
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("camera_rotate"):
			camera_rotation += Vector3(0, -event.relative.x / 10, 0)

	if event is InputEventPanGesture:
		var pan := Vector3(-event.delta.x, 0, -event.delta.y)
		camera_position += pan.rotated(Vector3.UP, rotation.y) * TRACKPAD_PAN_SPEED

	if event is InputEventMagnifyGesture:
		zoom = clampf(zoom / event.factor, MIN_ZOOM, MAX_ZOOM)

	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
		else:
			active_touches.erase(event.index)

	if event is InputEventScreenDrag:
		apply_touch_camera_gesture(event.index, event.position)

func apply_touch_camera_gesture(index:int, new_position:Vector2):
	if not active_touches.has(index):
		return

	if active_touches.size() != 2:
		active_touches[index] = new_position
		return

	var touch_indices = active_touches.keys()
	var first_index:int = touch_indices[0]
	var second_index:int = touch_indices[1]

	var old_first_position:Vector2 = active_touches[first_index]
	var old_second_position:Vector2 = active_touches[second_index]

	active_touches[index] = new_position

	var new_first_position:Vector2 = active_touches[first_index]
	var new_second_position:Vector2 = active_touches[second_index]

	var old_center := (old_first_position + old_second_position) / 2.0
	var new_center := (new_first_position + new_second_position) / 2.0
	var center_delta := new_center - old_center
	var pan := Vector3(-center_delta.x, 0, -center_delta.y)
	camera_position += pan.rotated(Vector3.UP, rotation.y) * TOUCH_PAN_SPEED * (zoom / 30.0)

	var old_distance := old_first_position.distance_to(old_second_position)
	var new_distance := new_first_position.distance_to(new_second_position)
	if old_distance > 0.0 and new_distance > 0.0:
		zoom = clampf(zoom / (new_distance / old_distance), MIN_ZOOM, MAX_ZOOM)

	var old_angle := (old_second_position - old_first_position).angle()
	var new_angle := (new_second_position - new_first_position).angle()
	var angle_delta := wrapf(new_angle - old_angle, -PI, PI)
	if absf(rad_to_deg(angle_delta)) >= TOUCH_ROTATE_DEADZONE:
		camera_rotation += Vector3(0, rad_to_deg(angle_delta), 0)
