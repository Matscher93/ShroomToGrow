extends PanelContainer
## VIEW: the row of overlay entry points above the currency pills. Five of them:
## the player level chip, the events bell, the fertilizer sack, the statistics
## sheet and the achievement archive.
##
## Four of them carry the same notification cue a biome card uses for unspent
## points - a dot on three, a count on the bell, since "how many offers" is worth
## more than "some". Every overlay is off screen by default, so that cue is the
## only thing telling the player something is waiting: a claimable tier, an
## unspent Level Point, today's daily reward, an affordable fertilizer upgrade,
## or an event about to be missed.
##
## Statistics has no cue and wants none: nothing there is waiting to be
## collected, and a dot that never means "act on this" teaches the player to
## ignore the other three.

signal achievements_pressed
signal growth_pressed
signal events_pressed
signal fertilizer_pressed
signal statistics_pressed

@export var btn_achievements: Button
## The whole chip, not just its Button: the icon and the notification dot are
## siblings of the button inside it, so hiding the button alone would leave a
## dead chip behind.
@export var panel_achievements: PanelContainer
@export var image_achievements_notification: ColorRect
@export var btn_growth: Button
@export var lbl_growth_level: Label
@export var image_growth_notification: ColorRect
@export var btn_events: Button
@export var lbl_events_badge: Label
@export var panel_events_badge: PanelContainer
@export var btn_fertilizer: Button
## The chip's glyph comes from sh_stat_icon.gdshader with icon_id 12, which is
## StatIcons.Icon.FERTILIZER - the sack already existed as a .gdshaderinc that
## dispatcher includes, and a wrapper shader would compile the same shape twice.
@export var image_fertilizer_notification: ColorRect
@export var btn_statistics: Button

var _vm: AchievementsViewModel
var _growth_vm: GrowthViewModel
var _events_vm: EventsViewModel
var _fertilizer_vm: FertilizerViewModel

func _ready() -> void:
	btn_achievements.pressed.connect(_on_achievements_pressed)
	btn_growth.pressed.connect(_on_growth_pressed)
	btn_events.pressed.connect(_on_events_pressed)
	btn_fertilizer.pressed.connect(_on_fertilizer_pressed)
	btn_statistics.pressed.connect(_on_statistics_pressed)
	if App.achievements_vm:
		bind(App.achievements_vm)
	if App.growth_vm:
		bind_growth(App.growth_vm)
	if App.events_vm:
		bind_events(App.events_vm)
	if App.fertilizer_vm:
		bind_fertilizer(App.fertilizer_vm)

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

func bind_fertilizer(vm: FertilizerViewModel) -> void:
	if _fertilizer_vm:
		_fertilizer_vm.property_changed.disconnect(_on_fertilizer_property_changed)
	_fertilizer_vm = vm
	_fertilizer_vm.property_changed.connect(_on_fertilizer_property_changed)
	_refresh_fertilizer()

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
	if _fertilizer_vm:
		_fertilizer_vm.property_changed.disconnect(_on_fertilizer_property_changed)
		_fertilizer_vm = null

func _on_property_changed(property: StringName) -> void:
	if property == AchievementsViewModel.PROP_HAS_CLAIMS \
			or property == AchievementsViewModel.PROP_VISIBLE:
		_refresh()

## Every notification repaints the chip: the level number and the dot come from
## different sources - lifetime nutrients for one, unspent points and the day's
## claim for the other - and there is no property that moves only one of them.
func _on_growth_property_changed(_property: StringName) -> void:
	_refresh_growth()

func _on_events_property_changed(property: StringName) -> void:
	if property == EventsViewModel.PROP_QUEUE_CHANGED:
		_refresh_events()

## The VM has one notification and it moves the only thing the chip shows, so
## there is nothing to match on.
func _on_fertilizer_property_changed(_property: StringName) -> void:
	_refresh_fertilizer()

## Hidden outright before the Crystal Caves rather than left dead: the archive
## pays crystals, and until that screen exists there is nowhere to spend them.
## The row is an HBox, so the other three simply repack.
func _refresh() -> void:
	panel_achievements.visible = _vm.is_visible
	image_achievements_notification.visible = _vm.has_claims

func _refresh_growth() -> void:
	lbl_growth_level.text = "Lv %s" % _growth_vm.level_number
	image_growth_notification.visible = _growth_vm.has_alert

## A dot rather than the stock as a number: fertilizer arrives in threes and
## fours against prices that start at three, so "you have some" would be lit
## almost always. The dot means an upgrade is affordable right now, which is the
## same "there is a decision waiting" the other two dots mean.
func _refresh_fertilizer() -> void:
	image_fertilizer_notification.visible = _fertilizer_vm.has_alert

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

func _on_fertilizer_pressed() -> void:
	fertilizer_pressed.emit()

func _on_statistics_pressed() -> void:
	statistics_pressed.emit()
