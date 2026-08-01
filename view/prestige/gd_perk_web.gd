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

const NODE_SIZE := 40.0
const MIN_SCALE := 0.35
const MAX_SCALE := 2.5
const ZOOM_STEP := 1.15

var _buttons: Dictionary = {}  # StringName -> PerkNode
var _selected_id: StringName = &"core"
var _dragging := false
var _drag_last := Vector2.ZERO
var _touches: Dictionary = {}  # int finger index -> Vector2 last local position
var _pinch_prev_dist := -1.0

func _ready() -> void:
	clip_contents = true
	for id in App.perk_defs:
		_spawn_button(App.perk_defs[id])
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	# unbind(1) drops biomass_changed's BigNumber, so the handler stays
	# parameterless.
	App.player_data.biomass_changed.connect(_on_changed.unbind(1))
	resized.connect(_center_on_core)
	call_deferred("_center_on_core")
	_refresh_all()
	_update_touch_emulation()

func _exit_tree() -> void:
	Input.set_emulate_mouse_from_touch(true)
	if App.prestige_upgrade_system.upgrades_changed.is_connected(_on_changed):
		App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	if App.player_data.biomass_changed.is_connected(_on_changed.unbind(1)):
		App.player_data.biomass_changed.disconnect(_on_changed.unbind(1))

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_touch_emulation()

## Android/iOS synthesize InputEventMouseMotion from touch by default, which
## would double-drive world.position alongside the ScreenDrag handling below and
## pan at 2x. Screens are cached rather than freed on switch (see
## gd_game_screens.gd), so this can't key off _ready/_exit_tree alone. It has to
## track on-screen visibility, since an ancestor is what shows and hides us.
func _update_touch_emulation() -> void:
	Input.set_emulate_mouse_from_touch(not is_visible_in_tree())

func _on_changed() -> void:
	_refresh_all()

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
	btn.pressed.connect(func() -> void: _select(def.id); perk_selected.emit(def.id))
	world.add_child(btn)
	_buttons[def.id] = btn

# --- selection ---

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
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / ZOOM_STEP, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		world.position += mm.position - _drag_last
		_drag_last = mm.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
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
	var new_scale := clampf(world.scale.x * factor, MIN_SCALE, MAX_SCALE)
	var actual_factor := new_scale / world.scale.x
	world.position = anchor - (anchor - world.position) * actual_factor
	world.scale = Vector2(new_scale, new_scale)
	for id in _buttons:
		_buttons[id].set_zoom(new_scale)
	if lines:
		lines.refresh(world.scale.x)
