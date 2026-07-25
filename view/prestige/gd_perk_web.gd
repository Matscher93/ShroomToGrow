class_name PerkWeb
extends Control
## VIEW — pannable/zoomable canvas for the mycelial web. Spawns one plain
## Button per PerkDef at its precomputed world position, drags/zooms the
## whole "world" node, and repaints PerkLines underneath on any change.
## No shader/theme work — flat StyleBoxFlat colored by branch hue, functional
## scaffold matching the rest of the current-gen UI.

signal perk_selected(id: StringName)

@export var world: Node2D
@export var lines: PerkLines

const NODE_SIZE := 40.0
const MIN_SCALE := 0.35
const MAX_SCALE := 2.5
const ZOOM_STEP := 1.15

var _buttons: Dictionary = {}  # StringName -> Button
var _dragging := false
var _drag_last := Vector2.ZERO
var _touches: Dictionary = {}  # int finger index -> Vector2 last local position
var _pinch_prev_dist := -1.0

func _ready() -> void:
	# Android/iOS synthesize InputEventMouseMotion from touch by default, which
	# would double-drive world.position alongside our own ScreenDrag handling
	# below (that's what the earlier 2x pan bug actually was).
	Input.set_emulate_mouse_from_touch(false)
	clip_contents = true
	for id in App.perk_defs:
		_spawn_button(App.perk_defs[id])
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)
	App.player_data.biomass_changed.connect(_on_changed)
	resized.connect(_center_on_core)
	call_deferred("_center_on_core")
	_refresh_all()

func _exit_tree() -> void:
	if App.prestige_upgrade_system.upgrades_changed.is_connected(_on_changed):
		App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)
	if App.player_data.biomass_changed.is_connected(_on_changed):
		App.player_data.biomass_changed.disconnect(_on_changed)

func _on_changed(_arg = null) -> void:
	_refresh_all()

func _center_on_core() -> void:
	var core := App.perk_def(&"core")
	if core == null or world == null:
		return
	world.position = size / 2.0 - Vector2(core.world_x, core.world_y) * world.scale.x

# --- building ---

func _spawn_button(def: PerkDef) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.position = Vector2(def.world_x, def.world_y) - Vector2(NODE_SIZE, NODE_SIZE) / 2.0
	btn.text = "✦" if def.branch_key == &"" else String(def.id).trim_prefix(String(def.branch_key))
	btn.tooltip_text = def.display_name
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: perk_selected.emit(def.id))
	world.add_child(btn)
	_buttons[def.id] = btn

func _branch_for(key: StringName) -> PerkBranchDef:
	for b in App.perk_branches.branches:
		if b.key == key:
			return b
	return null

# --- refresh ---

func _refresh_all() -> void:
	for id in _buttons:
		_refresh_button(id)
	if lines:
		lines.refresh()

func _refresh_button(id: StringName) -> void:
	var btn: Button = _buttons[id]
	var def: PerkDef = App.perk_defs[id]
	var status := App.perk_status(id)
	var hue := 0.75
	if def.branch_key != &"":
		var branch := _branch_for(def.branch_key)
		if branch:
			hue = branch.hue / 360.0

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(999)
	match status:
		"owned":
			sb.bg_color = Color.from_hsv(hue, 0.6, 0.9)
			sb.set_border_width_all(2)
			sb.border_color = Color.from_hsv(hue, 0.35, 1.0)
		"available":
			sb.bg_color = Color.from_hsv(hue, 0.45, 0.55)
		_:
			sb.bg_color = Color(0.16, 0.15, 0.19)
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(style_name, sb)

	btn.tooltip_text = "%s — Lv %d/%d" % [def.display_name, App.prestige_upgrade_system.level(id), def.max_level]

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
		# Position-delta, not sd.relative — matches the mouse-drag path above.
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
