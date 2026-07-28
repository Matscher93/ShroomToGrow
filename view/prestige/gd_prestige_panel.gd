extends PanelContainer
## VIEW — prestige screen: biomass + sporate bar on top, the pannable perk
## web in the middle, a floating detail/buy panel on the bottom for
## whichever perk is currently selected. Sporate section binds to
## App.prestige_vm; the detail panel rebinds to the selected perk's
## persistent PerkViewModel (App.perk_vms — one per perk, owned by App,
## never disposed here — only the view's own listener is swapped).

@export var biomass_label: Label
@export var sporate_button: Button
@export var perk_web: PerkWeb
@export var detail_name: Label
@export var detail_effect: Label
@export var detail_cost: Label
@export var buy_button: Button

var _vm: PrestigeViewModel
var _detail_vm: PerkViewModel
var _selected_id: StringName = &"core"

func _ready() -> void:
	sporate_button.pressed.connect(_on_sporate_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	perk_web.perk_selected.connect(_on_perk_selected)
	bind(App.prestige_vm)
	_select_perk(_selected_id)

func bind(vm: PrestigeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_sporate()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if _detail_vm:
		_detail_vm.property_changed.disconnect(_on_detail_property_changed)
		_detail_vm = null

func _on_property_changed(_property: StringName) -> void:
	_refresh_sporate()

func _on_detail_property_changed(_property: StringName) -> void:
	_refresh_detail()

func _on_perk_selected(id: StringName) -> void:
	_select_perk(id)

func _select_perk(id: StringName) -> void:
	_selected_id = id
	if _detail_vm:
		_detail_vm.property_changed.disconnect(_on_detail_property_changed)
	_detail_vm = App.perk_vms.get(id)
	if _detail_vm:
		_detail_vm.property_changed.connect(_on_detail_property_changed)
	_refresh_detail()

func _on_sporate_pressed() -> void:
	_vm.sporate()

func _on_buy_pressed() -> void:
	_detail_vm.buy()

func _refresh_sporate() -> void:
	biomass_label.text = App.player_vm.biomass_text
	sporate_button.text = _vm.sporate_text
	sporate_button.disabled = not _vm.sporate_enabled

func _refresh_detail() -> void:
	if _detail_vm == null:
		return
	detail_name.text = _detail_vm.tooltip_text
	detail_effect.text = _detail_vm.detail_effect_text
	detail_cost.text = _detail_vm.detail_cost_text
	buy_button.text = _detail_vm.detail_buy_text
	buy_button.disabled = not _detail_vm.can_buy
