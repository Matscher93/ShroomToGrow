class_name PerkWeb
extends Control
## VIEW: pannable, zoomable canvas for the mycelial web. Spawns one PerkNode per
## PerkDef at its precomputed world position, drags and zooms the whole "world"
## node, and refreshes PerkLines underneath on any change. Node shape and style
## live in sc_perk_node.tscn (see gd_perk_node.gd), this class only positions
## nodes and tints them by branch hue.

signal perk_selected(id: StringName)

@export var world: Node2D
@export var lines: PerkLines
@export var node_scene: PackedScene
## Width of the alpha falloff at the clip edges, in pixels. sh_web_fade.gdshader
## on "world" wants it in screen UV, so it is converted per axis on update.
@export var edge_fade_pixels: float = 48.0

const NODE_SIZE := 40.0
const MIN_SCALE := 0.35
const MAX_SCALE := 2.5
const ZOOM_STEP := 1.15
const TAP_CANCEL_DISTANCE := 10.0  # px, beyond this a press is a pan, not a tap

var _vm: PrestigeViewModel
var _buttons: Dictionary = {}  # StringName -> PerkNode
var _selected_id: StringName = &"core"
var _dragging := false
var _drag_last := Vector2.ZERO
var _touches: Dictionary = {}  # int finger index -> Vector2 last local position
var _pinch_prev_dist := -1.0
var _press_start := Vector2.ZERO
var _gesture_moved := false

func _ready() -> void:
	clip_contents = true
	# App.perk_defs is a static registry: the ids and their world positions are
	# fixed for the app's lifetime, so spawning off it directly is the documented
	# exception. Everything that *changes* comes through the VM below.
	for id in App.perk_defs:
		_spawn_button(App.perk_defs[id])
	bind(App.prestige_vm)
	resized.connect(_center_on_core)
	item_rect_changed.connect(_update_edge_fade)
	_center_on_core.call_deferred()
	_update_edge_fade.call_deferred()
	_update_touch_emulation()

func bind(vm: PrestigeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_all()

func _on_property_changed(property: StringName) -> void:
	if property == PrestigeViewModel.PROP_PERKS_CHANGED:
		_refresh_all()

func _exit_tree() -> void:
	Input.set_emulate_mouse_from_touch(true)
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_touch_emulation()
		_update_edge_fade()

## The fade lives in screen UV (see sh_web_fade.gdshader), so it has to be
## recomputed whenever this control's place on screen changes, including the
## first layout after this screen is spawned.
func _update_edge_fade() -> void:
	if world == null or not (world.material is ShaderMaterial):
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var rect := get_global_rect()
	var material: ShaderMaterial = world.material
	material.set_shader_parameter("rect_min", rect.position / viewport_size)
	material.set_shader_parameter("rect_max", rect.end / viewport_size)
	material.set_shader_parameter("fade_size", Vector2(edge_fade_pixels, edge_fade_pixels) / viewport_size)

## Android/iOS synthesize InputEventMouseMotion from touch by default, which
## would double-drive world.position alongside the ScreenDrag handling below and
## pan at 2x. Keyed off on-screen visibility rather than _ready/_exit_tree alone,
## so an ancestor hiding us (a popup layer, a parent toggled off) restores the
## default just as leaving the screen does.
func _update_touch_emulation() -> void:
	Input.set_emulate_mouse_from_touch(not is_visible_in_tree())

func _center_on_core() -> void:
	var core := App.perk_def(&"core")
	if core == null or world == null:
		return
	world.position = size / 2.0 - Vector2(core.world_x, core.world_y) * world.scale.x

# --- building ---

func _spawn_button(def: PerkDef) -> void:
	var btn: PerkNode = node_scene.instantiate()
	btn.position = Vector2(def.world_x, def.world_y) - Vector2(NODE_SIZE, NODE_SIZE) / 2.0
	btn.bind(def)
	btn.pressed.connect(func() -> void: _on_node_pressed(def.id))
	world.add_child(btn)
	_buttons[def.id] = btn

# --- selection ---

## The nodes' Buttons pass their input through so a press that starts on a node
## still pans the web. They emit pressed on release regardless, and Godot routes
## that release to the Button before it bubbles here, so the pan/zoom flag has to
## be raised while the gesture is still moving and only cleared on the next
## press. Same tap-vs-drag rule as gd_biome_panel.gd.
func _on_node_pressed(id: StringName) -> void:
	if _gesture_moved:
		return
	_select(id)
	perk_selected.emit(id)

func _select(id: StringName) -> void:
	if _selected_id == id:
		return
	var previous := _selected_id
	_selected_id = id
	if _buttons.has(previous):
		_refresh_button(previous)
	if _buttons.has(id):
		_refresh_button(id)

# --- refresh ---

func _refresh_all() -> void:
	for id in _buttons:
		_refresh_button(id)
	if lines:
		lines.refresh(world.scale.x)

func _refresh_button(id: StringName) -> void:
	var btn: PerkNode = _buttons.get(id)
	var def: PerkDef = App.perk_defs.get(id)
	var vm: PerkViewModel = App.perk_vms.get(id)
	if btn == null or def == null or vm == null:
		return
	btn.refresh(vm, id == _selected_id)
	btn.set_zoom(world.scale.x)

	if vm.status == "locked":
		btn.set_color(Color.WHITE)
		return
	var hue := App.perk_branches.hue_for(def.branch_key) / 360.0
	var color := Color.from_hsv(hue, 0.6, 0.9) if vm.status == "owned" else Color.from_hsv(hue, 0.45, 0.55)
	btn.set_color(color)

# --- pan / zoom ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
			if mb.pressed:
				_press_start = mb.position
				_gesture_moved = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / ZOOM_STEP, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		world.position += mm.position - _drag_last
		_drag_last = mm.position
		if mm.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_gesture_moved = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _touches.is_empty():
				_press_start = st.position
				_gesture_moved = false
			else:
				# Second finger down means a pinch, never a tap.
				_gesture_moved = true
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() < 2:
			_pinch_prev_dist = -1.0
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		# Position delta, not sd.relative, to match the mouse-drag path above.
		var prev: Vector2 = _touches.get(sd.index, sd.position)
		_touches[sd.index] = sd.position
		if sd.position.distance_to(_press_start) > TAP_CANCEL_DISTANCE:
			_gesture_moved = true
		if _touches.size() >= 2:
			_update_pinch()
		else:
			world.position += sd.position - prev
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_by(mg.factor, size / 2.0)

func _update_pinch() -> void:
	var points := _touches.values()
	var p0: Vector2 = points[0]
	var p1: Vector2 = points[1]
	var dist := p0.distance_to(p1)
	if _pinch_prev_dist > 0.0:
		_zoom_by(dist / _pinch_prev_dist, (p0 + p1) / 2.0)
	_pinch_prev_dist = dist

func _zoom_by(factor: float, anchor: Vector2) -> void:
	_gesture_moved = true
	var new_scale := clampf(world.scale.x * factor, MIN_SCALE, MAX_SCALE)
	var actual_factor := new_scale / world.scale.x
	world.position = anchor - (anchor - world.position) * actual_factor
	world.scale = Vector2(new_scale, new_scale)
	for id in _buttons:
		_buttons[id].set_zoom(new_scale)
	if lines:
		lines.refresh(world.scale.x)
