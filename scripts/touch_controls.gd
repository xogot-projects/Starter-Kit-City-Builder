extends Control

@export var instructions:CanvasItem

const BUTTON_SIZE := Vector2(80, 80)
const EDGE_MARGIN:float = 24.0
const BUTTON_GAP:float = 12.0

const BUTTONS := {
	"SaveButton": {
		"action": "save",
		"texture": "res://sprites/touch_controls/save.png",
	},
	"LoadButton": {
		"action": "load",
		"texture": "res://sprites/touch_controls/load.png",
	},
	"StructurePreviousButton": {
		"action": "structure_previous",
		"texture": "res://sprites/touch_controls/structure_previous.png",
	},
	"RotateButton": {
		"action": "touch_rotate",
		"texture": "res://sprites/touch_controls/rotate.png",
	},
	"StructureNextButton": {
		"action": "structure_next",
		"texture": "res://sprites/touch_controls/structure_next.png",
	},
	"CameraCenterButton": {
		"action": "camera_center",
		"texture": "res://sprites/touch_controls/camera_center.png",
	},
}

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process_input(true)
	configure_buttons()
	position_buttons()
	hide_keyboard_instructions(is_touch_device())
	get_viewport().size_changed.connect(position_buttons)

func _input(event:InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		hide_keyboard_instructions(true)

func _gui_input(event:InputEvent) -> void:
	if not should_block_event(event):
		return

	if contains_button_position(event.position):
		accept_event()

func configure_buttons() -> void:
	for button_name in BUTTONS:
		var config:Dictionary = BUTTONS[button_name]
		var action := StringName(config["action"])
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		var button:TouchScreenButton = get_node(button_name)
		button.action = action
		button.texture_normal = load(config["texture"])
		button.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY as TouchScreenButton.VisibilityMode

func position_buttons() -> void:
	var viewport_size := get_viewport_rect().size
	var x := viewport_size.x - EDGE_MARGIN - BUTTON_SIZE.x

	$SaveButton.position = Vector2(x, EDGE_MARGIN)
	$LoadButton.position = Vector2(x, EDGE_MARGIN + BUTTON_SIZE.y + BUTTON_GAP)

	var right_actions_top := viewport_size.y * 0.5 - BUTTON_SIZE.y - BUTTON_GAP - (BUTTON_SIZE.y * 0.2)
	$StructurePreviousButton.position = Vector2(x, right_actions_top)
	$RotateButton.position = Vector2(x, right_actions_top + BUTTON_SIZE.y + BUTTON_GAP)
	$StructureNextButton.position = Vector2(x, right_actions_top + BUTTON_SIZE.y * 2.0 + BUTTON_GAP * 2.0)

	$CameraCenterButton.position = Vector2(x, viewport_size.y - EDGE_MARGIN - BUTTON_SIZE.y)

func hide_keyboard_instructions(enabled:bool) -> void:
	if instructions:
		instructions.visible = not enabled

func should_block_event(event:InputEvent) -> bool:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return true
	if is_touch_device() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return true

	return false

func contains_button_position(screen_position:Vector2) -> bool:
	for button_name in BUTTONS:
		var button:TouchScreenButton = get_node(button_name)
		var button_size := BUTTON_SIZE
		if button.texture_normal:
			button_size = button.texture_normal.get_size() * button.scale
		var button_rect := Rect2(button.global_position, button_size)
		if button_rect.has_point(screen_position):
			return true

	return false

func is_touch_device() -> bool:
	var os_name := OS.get_name()
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"):
		return true
	if OS.has_feature("web_ios") or OS.has_feature("web_android"):
		return true

	return os_name == "iOS" or os_name == "iPadOS" or os_name == "Android"
