extends PanelContainer
## VIEW: one project in the Well. Bound to a persistent ProjectViewModel owned by
## App.

## Drawn per boon row so the number is attached to the area it moves. Each row
## gets its own ShaderMaterial: one shared instance would leave every row showing
## whichever icon_id was written last. Built once per row - see _build_boons().
const STAT_ICON_SHADER: Shader = preload("res://view/icons/sh_stat_icon.gdshader")
const STAT_ICON_SIZE := Vector2(18.0, 18.0)

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_boons: Label
@export var lbl_level: Label
@export var lbl_cost: Label
@export var btn_invest: Button
@export var vbox_boons: VBoxContainer

var _vm: ProjectViewModel
## One entry per boon, in ladder order, built once by _build_boons(). Keys:
## name, rate, detail, icon.
var _boon_rows: Array[Dictionary] = []

func _ready() -> void:
	btn_invest.pressed.connect(_on_invest_pressed)

func bind(vm: ProjectViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	_build_boons()
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_level.text = _vm.level_text
	lbl_boons.text = _vm.boons_text
	lbl_cost.text = _vm.cost_text
	btn_invest.disabled = not _vm.can_invest
	btn_invest.text = "Done" if _vm.is_maxed else "Fund"
	_update_boons()

## Built once per card rather than on every repaint. A boon's name, its icon and
## the ladder's length are all fixed for the project's lifetime; only the two
## numbers and the dimming move.
##
## The rows used to be rebuilt on every refresh(), which was defensible at three
## projects. At twenty-six it is four labels, an icon and a ShaderMaterial
## discarded and remade over a hundred times - and refresh() runs on every water
## change, which is every pump.
func _build_boons() -> void:
	for child in vbox_boons.get_children():
		vbox_boons.remove_child(child)
		child.queue_free()
	_boon_rows.clear()

	for row: Dictionary in _vm.boon_rows():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)

		# Ahead of the name, and drawn for locked rungs too: what a rung will
		# raise is exactly what the player is deciding whether to fund towards.
		var icon := ColorRect.new()
		icon.custom_minimum_size = STAT_ICON_SIZE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader_material := ShaderMaterial.new()
		shader_material.shader = STAT_ICON_SHADER
		shader_material.set_shader_parameter("icon_id", StatIcons.for_stat(row["stat"]))
		icon.material = shader_material

		var name_label := Label.new()
		name_label.text = row["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# What the next funding adds, then what the rung is worth now. The total
		# goes last so it lands in the same trailing column on every row, since it
		# is the number read down the list; the rate is dimmed against it because
		# it only explains why that number will move.
		var rate_label := Label.new()
		var detail_label := Label.new()

		line.add_child(icon)
		line.add_child(name_label)
		line.add_child(rate_label)
		line.add_child(detail_label)
		vbox_boons.add_child(line)
		_boon_rows.append({"name": name_label, "rate": rate_label,
			"detail": detail_label, "icon": icon})

## Only what a funding can actually change. Dimming rides on modulate rather than
## on the icon's shader parameter, so a repaint never touches the material.
func _update_boons() -> void:
	var rows := _vm.boon_rows()
	for i in mini(rows.size(), _boon_rows.size()):
		var row: Dictionary = rows[i]
		var nodes: Dictionary = _boon_rows[i]
		# A locked rung is dimmed rather than hidden: it is the reason to keep
		# funding, so the player has to be able to see what is coming.
		var alpha := 1.0 if row["unlocked"] else 0.4
		var name_label: Label = nodes["name"]
		var rate_label: Label = nodes["rate"]
		var detail_label: Label = nodes["detail"]
		var icon: ColorRect = nodes["icon"]
		rate_label.text = row["rate"]
		detail_label.text = row["detail"]
		name_label.modulate = Color(1.0, 1.0, 1.0, alpha)
		detail_label.modulate = Color(0.76, 0.95, 0.98, alpha)
		rate_label.modulate = Color(1.0, 1.0, 1.0, alpha * 0.55)
		icon.modulate = Color(1.0, 1.0, 1.0, alpha)

func _on_invest_pressed() -> void:
	_vm.invest()
