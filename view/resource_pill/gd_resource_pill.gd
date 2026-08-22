@tool
extends MarginContainer
## VIEW: one currency chip in the top resource bar - icon, amount, and the rate
## line underneath the amount's baseline. The bar spawns these contextually, so a
## chip only ever exists while the current screen actually earns or spends its
## currency.

@export var currency_def: CurrencyDef:
	set(value):
		if currency_def:
			currency_def.changed.disconnect(_update_visuals)
		currency_def = value
		if currency_def:
			currency_def.changed.connect(_update_visuals)
		_update_visuals()

@export var image_background: ColorRect
@export var image_header: ColorRect
@export var label_amount: Label
@export var label_change_per_tick: Label

var _vm: PlayerViewModel
var _vm_change: MyceliumNodeViewModel
var _vm_prestige: PrestigeViewModel

func _ready() -> void:
	_update_colors()

	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	if App.player_vm:
		bind(App.player_vm)
		if App.mycelium_node_vms.size() > 0:
			bind_change(App.mycelium_node_vms[0])
		if App.prestige_vm:
			bind_prestige(App.prestige_vm)
		_refresh_all()

func _update_visuals() -> void:
	_update_colors()
	if is_instance_valid(image_header):
		image_header.material.set_shader_parameter("icon_id", currency_def.currency_type)

func _update_colors() -> void:
	var child := get_node_or_null("ColorRect")
	if is_instance_valid(child):
		image_background.set_shader_color(currency_def.main_color)
		image_header.set_shader_color(currency_def.main_color)
		label_amount.label_settings.font_color = currency_def.currency_color
		label_change_per_tick.label_settings.font_color = currency_def.label_color

func bind(vm: PlayerViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)


func bind_change(vm: MyceliumNodeViewModel) -> void:
	if _vm_change:
		_vm_change.property_changed.disconnect(_on_property_changed)
	_vm_change = vm
	_vm_change.property_changed.connect(_on_property_changed)


func bind_prestige(vm: PrestigeViewModel) -> void:
	if _vm_prestige:
		_vm_prestige.property_changed.disconnect(_on_property_changed)
	_vm_prestige = vm
	_vm_prestige.property_changed.connect(_on_property_changed)


func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if _vm_change:
		_vm_change.property_changed.disconnect(_on_property_changed)
		_vm_change = null
	if _vm_prestige:
		_vm_prestige.property_changed.disconnect(_on_property_changed)
		_vm_prestige = null

# --- VM -> View ---
func _on_property_changed(property: StringName) -> void:
	match property:
		PlayerViewModel.PROP_NUTRIENT_TEXT, PlayerViewModel.PROP_BIOMASS_TEXT, \
		PlayerViewModel.PROP_WATER_TEXT, PlayerViewModel.PROP_CRYSTALS_TEXT, \
		PlayerViewModel.PROP_RELICS_TEXT, PlayerViewModel.PROP_ICHOR_TEXT, \
		PlayerViewModel.PROP_GLYPHS_TEXT:
			# One arm for every balance rather than one per currency: the pill only
			# ever shows its own, and currency_text() already picks the right field.
			# A notification for a currency this pill does not show costs one
			# formatted string that nothing reads, which is cheaper than the seven
			# match arms it replaces.
			label_amount.text = _vm.currency_text(currency_def.currency_type)
		MyceliumNodeViewModel.PROP_PRODUCTION_TEXT:
			if currency_def.currency_type == CurrencyTypes.Types.NUTRIENTS:
				label_change_per_tick.text = _vm_change.production_text_short
		PrestigeViewModel.PROP_PENDING_CHANGED:
			if currency_def.currency_type == CurrencyTypes.Types.BIOMASS:
				label_change_per_tick.text = _vm_prestige.pending_biomass_text

func _refresh_all() -> void:
	label_amount.text = _vm.currency_text(currency_def.currency_type)
	# Only two currencies have a second line: nutrients show what a tick pays, and
	# biomass shows what a sporation would. Every other pill leaves it blank.
	if currency_def.currency_type == CurrencyTypes.Types.NUTRIENTS:
		label_change_per_tick.text = _vm_change.production_text_short if _vm_change else ""
	elif currency_def.currency_type == CurrencyTypes.Types.BIOMASS:
		label_change_per_tick.text = _vm_prestige.pending_biomass_text if _vm_prestige else ""
	else:
		label_change_per_tick.text = ""
