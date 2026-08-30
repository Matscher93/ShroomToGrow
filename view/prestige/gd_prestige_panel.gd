extends PanelContainer
## VIEW: prestige screen. Biomass and sporate bar on top, pannable perk web in
## the middle, floating detail/buy panel at the bottom for the selected perk.
## Sporate section binds to App.prestige_vm. The detail panel rebinds to the
## selected perk's PerkViewModel (App.perk_vms, one per perk, owned by App).
## Those are never disposed here, only the view's own listener is swapped.

@export var sporate_button: PanelContainer
@export var perk_web: PerkWeb
@export var detail_name: Label
@export var detail_description: Label
@export var detail_level: Label
@export var buy_button: PanelContainer
@export var storage_toggle: Button
@export var storage_box: Control
@export var nutrient_storage_label: Label
@export var nutrient_storage_bar: ProgressBar
@export var tick_storage_label: Label
@export var tick_storage_bar: ProgressBar
@export var gate_label: Label

var _vm: PrestigeViewModel
var _detail_vm: PerkViewModel
var _selected_id: StringName = &"core"
## Folded away by default: the sporate button and two labelled bars do not both
## fit across the top bar, and the button is what the screen is for.
var _storage_open := false

func _ready() -> void:
	sporate_button.pressed.connect(_on_sporate_pressed)
	storage_toggle.pressed.connect(_on_storage_toggled)
	_apply_storage_visibility()
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

## PrestigeViewModel notifies both of its properties per model change, so
## ignoring which one arrived ran this twice for every change. The button is the
## pending half; the perk web repaints off its own per-perk VMs.
func _on_property_changed(property: StringName) -> void:
	if property == PrestigeViewModel.PROP_PENDING_CHANGED:
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

func _on_storage_toggled() -> void:
	_storage_open = not _storage_open
	_apply_storage_visibility()
	if _storage_open:
		_refresh_sporate()

func _apply_storage_visibility() -> void:
	storage_box.visible = _storage_open
	storage_toggle.text = "Storage ▴" if _storage_open else "Storage ▾"

func _on_buy_pressed() -> void:
	_detail_vm.buy()

func _refresh_sporate() -> void:
	sporate_button.set_button_text(_vm.sporate_text)
	sporate_button.set_disabled(not _vm.sporate_enabled)
	# The bars read the model on every access, and the panel refreshes on every
	# tick: skipped entirely while nobody is looking at them.
	if not _storage_open:
		return
	nutrient_storage_label.text = _vm.nutrient_storage_text
	nutrient_storage_bar.value = _vm.nutrient_storage_fill
	tick_storage_label.text = _vm.tick_storage_text
	tick_storage_bar.value = _vm.tick_storage_fill
	# Empty while a sporate is available: an inert "why not" line under an
	# enabled button reads as a warning about the button.
	gate_label.text = _vm.gate_text
	gate_label.visible = not gate_label.text.is_empty()

func _refresh_detail() -> void:
	if _detail_vm == null:
		return
	detail_name.text = _detail_vm.display_name
	# A perk with neither a description nor an effect to describe leaves this
	# empty, and an empty label would still take its separation from the name
	# above it, so it goes away entirely.
	detail_description.text = _detail_vm.description
	detail_description.visible = not detail_description.text.is_empty()
	detail_level.text = _detail_vm.level_text
	buy_button.set_button_text(_detail_vm.detail_buy_text)
	buy_button.set_disabled(not _detail_vm.can_buy)
