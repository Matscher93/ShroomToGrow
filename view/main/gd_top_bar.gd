extends PanelContainer
## VIEW: the row of overlay entry points above the currency pills. Four of them:
## the player level chip, the events bell, the statistics sheet and the
## achievement archive.
##
## Three of them carry the same notification cue a biome card uses for unspent
## points - a dot on two, a count on the bell, since "how many offers" is worth
## more than "some". Every overlay is off screen by default, so that cue is the
## only thing telling the player something is waiting: a claimable tier, an
## unspent Level Point, today's daily reward, or an event about to be missed.
##
## Statistics has no cue and wants none: nothing there is waiting to be
## collected, and a dot that never means "act on this" teaches the player to
## ignore the other three.

signal achievements_pressed
signal growth_pressed
signal events_pressed
signal statistics_pressed

@export var btn_achievements: Button
@export var image_achievements_notification: ColorRect
@export var btn_growth: Button
@export var lbl_growth_level: Label
@export var image_growth_notification: ColorRect
@export var btn_events: Button
@export var lbl_events_badge: Label
@export var panel_events_badge: PanelContainer
@export var btn_statistics: Button

var _vm: AchievementsViewModel
var _growth_vm: GrowthViewModel
var _events_vm: EventsViewModel

func _ready() -> void:
	btn_achievements.pressed.connect(_on_achievements_pressed)
	btn_growth.pressed.connect(_on_growth_pressed)
	btn_events.pressed.connect(_on_events_pressed)
	btn_statistics.pressed.connect(_on_statistics_pressed)
	if App.achievements_vm:
		bind(App.achievements_vm)
	if App.growth_vm:
		bind_growth(App.growth_vm)
	if App.events_vm:
		bind_events(App.events_vm)

func bind(vm: AchievementsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh()

func bind_growth(vm: GrowthViewModel) -> void:
	if _growth_vm:
		_growth_vm.property_changed.disconnect(_on_growth_property_changed)
	_growth_vm = vm
	_growth_vm.property_changed.connect(_on_growth_property_changed)
	_refresh_growth()

func bind_events(vm: EventsViewModel) -> void:
	if _events_vm:
		_events_vm.property_changed.disconnect(_on_events_property_changed)
	_events_vm = vm
	_events_vm.property_changed.connect(_on_events_property_changed)
	_refresh_events()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if _growth_vm:
		_growth_vm.property_changed.disconnect(_on_growth_property_changed)
		_growth_vm = null
	if _events_vm:
		_events_vm.property_changed.disconnect(_on_events_property_changed)
		_events_vm = null

func _on_property_changed(property: StringName) -> void:
	if property == AchievementsViewModel.PROP_HAS_CLAIMS:
		_refresh()

## Every notification repaints the chip: the level number and the dot come from
## different sources - lifetime nutrients for one, unspent points and the day's
## claim for the other - and there is no property that moves only one of them.
func _on_growth_property_changed(_property: StringName) -> void:
	_refresh_growth()

func _on_events_property_changed(property: StringName) -> void:
	if property == EventsViewModel.PROP_QUEUE_CHANGED:
		_refresh_events()

func _refresh() -> void:
	image_achievements_notification.visible = _vm.has_claims

func _refresh_growth() -> void:
	lbl_growth_level.text = "Lv %s" % _growth_vm.level_number
	image_growth_notification.visible = _growth_vm.has_alert

## The badge carries the count rather than a bare dot: an empty queue hides it
## outright, so the number is only ever shown when there is something to answer.
func _refresh_events() -> void:
	panel_events_badge.visible = _events_vm.has_events
	lbl_events_badge.text = _events_vm.badge_text

func _on_achievements_pressed() -> void:
	achievements_pressed.emit()

func _on_growth_pressed() -> void:
	growth_pressed.emit()

func _on_events_pressed() -> void:
	events_pressed.emit()

func _on_statistics_pressed() -> void:
	statistics_pressed.emit()
