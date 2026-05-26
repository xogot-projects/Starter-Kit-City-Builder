extends Node3D

var camera_position:Vector3
var camera_rotation:Vector3

var zoom:float = 30.0 # 30 = Standard zoom level, in meters

const MIN_ZOOM:float = 15.0
const MAX_ZOOM:float = 80.0
const ZOOM_STEP:float = 5.0
const TRACKPAD_PAN_SPEED:float = 0.08

@onready var camera = $Camera

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
