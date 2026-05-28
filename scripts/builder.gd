extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector:Node3D # The 'cursor'
@export var selector_container:Node3D # Node that holds a preview of the structure
@export var view_camera:Camera3D # Used for raycasting mouse
@export var gridmap:GridMap
@export var cash_display:Label

var plane:Plane # Used for raycasting mouse
var pointer_screen_position := Vector2.ZERO
var active_touches := {}
var primary_touch_index:int = -1
var primary_touch_start_position := Vector2.ZERO
var primary_touch_elapsed:float = 0.0
var primary_touch_canceled:bool = false
var primary_touch_long_press_handled:bool = false
var touch_build_requested:bool = false
var pointer_is_touch:bool = false
var mouse_pressing_build:bool = false
var mouse_press_start_position := Vector2.ZERO
var mouse_press_elapsed:float = 0.0
var mouse_press_canceled:bool = false
var mouse_press_long_press_handled:bool = false
var mouse_build_requested:bool = false
var rotate_requested:bool = false
var touch_mouse_suppression_seconds:float = 0.0
var two_finger_tap_active:bool = false
var two_finger_tap_elapsed:float = 0.0
var two_finger_tap_canceled:bool = false
var two_finger_tap_start_positions := {}
var selector_frozen_by_touch:bool = false

const LONG_PRESS_SECONDS:float = 0.55
const TOUCH_MOVE_CANCEL_DISTANCE:float = 24.0
const TOUCH_TAP_MOVE_CANCEL_DISTANCE:float = 18.0
const MOUSE_MOVE_CANCEL_DISTANCE:float = 8.0
const TOUCH_MOUSE_SUPPRESSION_SECONDS:float = 0.75
const TWO_FINGER_TAP_SECONDS:float = 0.25
const TOUCH_ROTATE_ACTION := &"touch_rotate"

func _ready():
	if not InputMap.has_action(TOUCH_ROTATE_ACTION):
		InputMap.add_action(TOUCH_ROTATE_ACTION)
	
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)
	pointer_screen_position = get_viewport().get_mouse_position()
	
	# Create new MeshLibrary dynamically, can also be done in the editor
	# See: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
	
	var mesh_library = MeshLibrary.new()
	
	for structure in structures:
		
		var id = mesh_library.get_last_unused_item_id()
		
		mesh_library.create_item(id)
		mesh_library.set_item_mesh(id, get_mesh(structure.model))
		mesh_library.set_item_mesh_transform(id, Transform3D())
		
	gridmap.mesh_library = mesh_library
	
	update_structure()
	update_cash()

func _process(delta):
	
	# Controls
	
	action_rotate() # Rotates selection 90 degrees
	action_structure_toggle() # Toggles between structures
	
	action_save() # Saving
	action_load() # Loading
	action_load_resources() # Loading from resources
	
	# Map position based on mouse
	
	if active_touches.is_empty() and not pointer_is_touch:
		pointer_screen_position = get_viewport().get_mouse_position()

	var gridmap_position = get_gridmap_position(pointer_screen_position)
	if not selector_frozen_by_touch:
		selector.position = lerp(selector.position, gridmap_position, min(delta * 40, 1.0))

	update_touch_mouse_suppression(delta)
	update_two_finger_tap(delta)
	update_touch_long_press(delta, gridmap_position)
	update_mouse_long_press(delta, gridmap_position)
	
	action_build(gridmap_position)
	action_demolish(gridmap_position)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		pointer_screen_position = event.position
		pointer_is_touch = false
		if mouse_pressing_build and event.position.distance_to(mouse_press_start_position) > MOUSE_MOVE_CANCEL_DISTANCE:
			cancel_mouse_press()

	if event is InputEventMouseButton:
		if should_ignore_mouse_after_touch():
			get_viewport().set_input_as_handled()
			return

		pointer_screen_position = event.position
		pointer_is_touch = false

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_mouse_press(event.position)
			else:
				var should_build:bool = mouse_pressing_build and not mouse_press_canceled and not mouse_press_long_press_handled
				if should_build:
					mouse_build_requested = true
				reset_mouse_press()

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			rotate_requested = true

	if event is InputEventScreenTouch:
		pointer_screen_position = event.position
		pointer_is_touch = true
		touch_mouse_suppression_seconds = TOUCH_MOUSE_SUPPRESSION_SECONDS

		if event.pressed:
			active_touches[event.index] = event.position
			if active_touches.size() == 1:
				start_primary_touch(event.index, event.position)
			elif active_touches.size() == 2:
				cancel_primary_touch()
				start_two_finger_tap()
				freeze_selector_for_touch_gesture()
			else:
				cancel_primary_touch()
				cancel_two_finger_tap()
		else:
			var should_build:bool = event.index == primary_touch_index and not primary_touch_canceled and not primary_touch_long_press_handled
			update_two_finger_tap_position(event.index, event.position)
			active_touches.erase(event.index)
			if active_touches.is_empty():
				finish_two_finger_tap()
				unfreeze_selector_after_touch_gesture()
			if should_build:
				touch_build_requested = true
			if event.index == primary_touch_index:
				reset_primary_touch()

	if event is InputEventScreenDrag:
		pointer_screen_position = event.position
		pointer_is_touch = true
		touch_mouse_suppression_seconds = TOUCH_MOUSE_SUPPRESSION_SECONDS
		if active_touches.has(event.index):
			active_touches[event.index] = event.position
		update_two_finger_tap_position(event.index, event.position)
		if event.index == primary_touch_index and event.position.distance_to(primary_touch_start_position) > TOUCH_MOVE_CANCEL_DISTANCE:
			cancel_primary_touch()

# Retrieve the mesh from a PackedScene, used for dynamically creating a MeshLibrary

func get_mesh(packed_scene):
	var scene_state:SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if(scene_state.get_node_type(i) == "MeshInstance3D"):
			for j in scene_state.get_node_property_count(i):
				var prop_name = scene_state.get_node_property_name(i, j)
				if prop_name == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)
					
					return prop_value.duplicate()

# Build (place) a structure

func action_build(gridmap_position):
	if mouse_build_requested or touch_build_requested:
		mouse_build_requested = false
		touch_build_requested = false
		build_structure(gridmap_position)

# Demolish (remove) a structure

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		demolish_structure(gridmap_position)

func build_structure(gridmap_position):
	var previous_tile = gridmap.get_cell_item(gridmap_position)
	gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))

	if previous_tile != index:
		map.cash -= structures[index].price
		update_cash()

		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

func demolish_structure(gridmap_position):
	if gridmap.get_cell_item(gridmap_position) != -1:
		gridmap.set_cell_item(gridmap_position, -1)

		Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)

func get_gridmap_position(screen_position:Vector2):
	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(screen_position),
		view_camera.project_ray_normal(screen_position))

	return Vector3(round(world_position.x), 0, round(world_position.z))

func start_primary_touch(index:int, position:Vector2):
	primary_touch_index = index
	primary_touch_start_position = position
	primary_touch_elapsed = 0.0
	primary_touch_canceled = false
	primary_touch_long_press_handled = false

func cancel_primary_touch():
	primary_touch_canceled = true

func reset_primary_touch():
	primary_touch_index = -1
	primary_touch_elapsed = 0.0
	primary_touch_canceled = false
	primary_touch_long_press_handled = false

func update_touch_long_press(delta:float, gridmap_position):
	if primary_touch_index == -1 or primary_touch_canceled or primary_touch_long_press_handled:
		return

	if active_touches.size() != 1:
		cancel_primary_touch()
		return

	primary_touch_elapsed += delta
	if primary_touch_elapsed >= LONG_PRESS_SECONDS:
		demolish_structure(gridmap_position)
		primary_touch_long_press_handled = true

func start_two_finger_tap():
	two_finger_tap_active = true
	two_finger_tap_elapsed = 0.0
	two_finger_tap_canceled = false
	two_finger_tap_start_positions.clear()

	for touch_index in active_touches.keys():
		two_finger_tap_start_positions[touch_index] = active_touches[touch_index]

func cancel_two_finger_tap():
	two_finger_tap_active = false
	two_finger_tap_canceled = true

func reset_two_finger_tap():
	two_finger_tap_active = false
	two_finger_tap_elapsed = 0.0
	two_finger_tap_canceled = false
	two_finger_tap_start_positions.clear()

func update_two_finger_tap(delta:float):
	if not two_finger_tap_active:
		return

	two_finger_tap_elapsed += delta
	if two_finger_tap_elapsed > TWO_FINGER_TAP_SECONDS:
		cancel_two_finger_tap()

func update_two_finger_tap_position(index:int, position:Vector2):
	if not two_finger_tap_active or two_finger_tap_canceled:
		return

	if not two_finger_tap_start_positions.has(index):
		cancel_two_finger_tap()
		return

	var start_position:Vector2 = two_finger_tap_start_positions[index]
	if position.distance_to(start_position) > TOUCH_TAP_MOVE_CANCEL_DISTANCE:
		cancel_two_finger_tap()

func finish_two_finger_tap():
	var should_rotate:bool = two_finger_tap_active and not two_finger_tap_canceled and two_finger_tap_elapsed <= TWO_FINGER_TAP_SECONDS
	reset_two_finger_tap()

	if should_rotate:
		rotate_requested = true

func freeze_selector_for_touch_gesture():
	selector_frozen_by_touch = true

func unfreeze_selector_after_touch_gesture():
	selector_frozen_by_touch = false

func start_mouse_press(position:Vector2):
	mouse_pressing_build = true
	mouse_press_start_position = position
	mouse_press_elapsed = 0.0
	mouse_press_canceled = false
	mouse_press_long_press_handled = false

func cancel_mouse_press():
	mouse_press_canceled = true

func reset_mouse_press():
	mouse_pressing_build = false
	mouse_press_elapsed = 0.0
	mouse_press_canceled = false
	mouse_press_long_press_handled = false

func update_mouse_long_press(delta:float, gridmap_position):
	if not mouse_pressing_build or mouse_press_canceled or mouse_press_long_press_handled:
		return

	mouse_press_elapsed += delta
	if mouse_press_elapsed >= LONG_PRESS_SECONDS:
		demolish_structure(gridmap_position)
		mouse_press_long_press_handled = true

func update_touch_mouse_suppression(delta:float):
	if touch_mouse_suppression_seconds > 0.0:
		touch_mouse_suppression_seconds = maxf(touch_mouse_suppression_seconds - delta, 0.0)

func should_ignore_mouse_after_touch():
	return active_touches.size() > 0 or touch_mouse_suppression_seconds > 0.0

# Rotates the 'cursor' 90 degrees

func action_rotate():
	if rotate_requested or Input.is_action_just_pressed(TOUCH_ROTATE_ACTION):
		rotate_requested = false
		selector.rotate_y(deg_to_rad(90))
		
		Audio.play("sounds/rotate.ogg", -30)

# Toggle between structures to build

func action_structure_toggle():
	if Input.is_action_just_pressed("structure_next"):
		index = wrap(index + 1, 0, structures.size())
		Audio.play("sounds/toggle.ogg", -30)
	
	if Input.is_action_just_pressed("structure_previous"):
		index = wrap(index - 1, 0, structures.size())
		Audio.play("sounds/toggle.ogg", -30)

	update_structure()

# Update the structure visual in the 'cursor'

func update_structure():
	# Clear previous structure preview in selector
	for n in selector_container.get_children():
		selector_container.remove_child(n)
		n.queue_free()
		
	# Create new structure preview in selector
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.position.y += 0.25
	
func update_cash():
	cash_display.text = "$" + str(map.cash)

# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		print("Saving map...")
		
		map.structures.clear()
		for cell in gridmap.get_used_cells():
			
			var data_structure:DataStructure = DataStructure.new()
			
			data_structure.position = Vector2i(cell.x, cell.z)
			data_structure.orientation = gridmap.get_cell_item_orientation(cell)
			data_structure.structure = gridmap.get_cell_item(cell)
			
			map.structures.append(data_structure)
			
		ResourceSaver.save(map, "user://map.res")
	
func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map...")
		
		gridmap.clear()
		
		map = ResourceLoader.load("user://map.res")
		if not map:
			map = DataMap.new()
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()

func action_load_resources():
	if Input.is_action_just_pressed("load_resources"):
		print("Loading map...")
		
		gridmap.clear()
		
		map = ResourceLoader.load("res://sample map/map.res")
		if not map:
			map = DataMap.new()
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()
