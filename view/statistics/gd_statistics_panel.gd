extends PanelContainer
## VIEW: the statistics sheet, shown as a full-screen overlay over whatever screen
## the player is on. Opened from the top bar and built exactly like the
## achievement archive next to it: the root is the dimmed backdrop and tapping it
## closes, the sheet inside swallows its own presses.
##
## Four tabs over one content box rather than four scrolling lists side by side.
## Three of them are cheap, and the fourth - the bonus breakdown - walks every
## levelled upgrade in all eight tracks, so it is built when it is opened and not
## before. See StatisticsViewModel.refresh_bonuses().

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

enum Tab { RECORDS, TIMELINE, RUNS, BONUSES }

@export var btn_close: Button
@export var btn_records: Button
@export var btn_timeline: Button
@export var btn_runs: Button
@export var btn_bonuses: Button
@export var lbl_empty: Label
@export var scroll: ScrollContainer
@export var vbox_content: VBoxContainer
@export var stat_row_scene: PackedScene
@export var stat_card_scene: PackedScene
@export var stat_group_scene: PackedScene
@export var style_tab_on: StyleBox
@export var style_tab_off: StyleBox

var _vm: StatisticsViewModel
var _tab: Tab = Tab.RECORDS
var _guard := PressGuard.new()

func _ready() -> void:
	add_child(_guard)
	btn_close.pressed.connect(_on_dismiss_pressed)
	btn_records.pressed.connect(_on_tab_pressed.bind(Tab.RECORDS))
	btn_timeline.pressed.connect(_on_tab_pressed.bind(Tab.TIMELINE))
	btn_runs.pressed.connect(_on_tab_pressed.bind(Tab.RUNS))
	btn_bonuses.pressed.connect(_on_tab_pressed.bind(Tab.BONUSES))
	bind(App.statistics_vm)

func bind(vm: StatisticsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_select_tab(_tab)

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

## Every rebuild here is structural, so all of them go through the guard: a
## sporation resolving under a held finger would otherwise free the row the press
## landed on. See PressGuard.
func _on_property_changed(property: StringName) -> void:
	match property:
		StatisticsViewModel.PROP_RECORDS, StatisticsViewModel.PROP_MILESTONES, \
		StatisticsViewModel.PROP_RUNS, StatisticsViewModel.PROP_BONUSES:
			_guard.run_when_free(&"content", _rebuild)

## Deferred, and for the reason the guard's own `defer` flag exists: this arrives
## from inside a tab button's `pressed` emission, and _rebuild() frees the
## content under it - not the button itself, but close enough to it that running
## inline is not worth the distinction.
func _on_tab_pressed(tab: Tab) -> void:
	_guard.run_when_free(&"content", _select_tab.bind(tab), true)

func _select_tab(tab: Tab) -> void:
	_tab = tab
	_paint_tabs()
	# Only now, so a player who never opens the tab never pays for the walk over
	# every track. Reopening it re-reads, since levels move while it is closed.
	if tab == Tab.BONUSES:
		_vm.refresh_bonuses()
	_rebuild()
	scroll.scroll_vertical = 0

func _paint_tabs() -> void:
	var buttons := [btn_records, btn_timeline, btn_runs, btn_bonuses]
	for i in buttons.size():
		var style: StyleBox = style_tab_on if i == int(_tab) else style_tab_off
		(buttons[i] as Button).add_theme_stylebox_override(&"normal", style)
		(buttons[i] as Button).add_theme_stylebox_override(&"hover", style)
		(buttons[i] as Button).add_theme_stylebox_override(&"pressed", style)

func _rebuild() -> void:
	for child in vbox_content.get_children():
		vbox_content.remove_child(child)
		child.queue_free()
	match _tab:
		Tab.RECORDS:
			_build_records()
		Tab.TIMELINE:
			_build_timeline()
		Tab.RUNS:
			_build_runs()
		Tab.BONUSES:
			_build_bonuses()
	lbl_empty.visible = vbox_content.get_child_count() == 0
	lbl_empty.text = _empty_text()

## What an empty tab says. Three of the four can legitimately be empty on a fresh
## save, and each is empty for its own reason - "nothing here" would leave a
## player wondering whether it is broken.
func _empty_text() -> String:
	match _tab:
		Tab.TIMELINE:
			return "No milestones yet. Unlocking a biome, growing a new node or sporating puts one here."
		Tab.RUNS:
			return "No finished runs yet. The first one lands here when you sporate."
		Tab.BONUSES:
			return "Nothing levelled yet. Bonuses show up here as you buy upgrades."
		_:
			return "No records yet."

func _build_records() -> void:
	for row: Dictionary in _vm.records_rows:
		_add_row(vbox_content, row["label"], row["value"], row["key"])

func _build_timeline() -> void:
	for row: Dictionary in _vm.milestone_rows:
		var card := _add_card(row["title"], row["when"], row["detail"])
		card.rows.visible = false
		_paint_milestone_icon(card, row["kind"], row["key"])

func _build_runs() -> void:
	for row: Dictionary in _vm.run_rows:
		var card := _add_card(row["title"], row["when"], "")
		# The run in progress is measured in time still running; a finished one is
		# the sporation that ended it.
		if row["in_progress"]:
			card.set_icon(StatIcons.Icon.TIME)
		else:
			# The same colour "Sporations" wears on the records tab, so the two
			# places a finished run is counted agree on what it looks like.
			card.set_icon(StatIcons.Icon.SPORE, _color_for(&"prestige_count"))
		for field: Dictionary in row["fields"]:
			var line := _add_row(card.rows, field["label"], field["value"], field["key"])
			# The one field naming a place rather than counting something, so it
			# takes that place's own colour - the same tint the timeline's tile
			# for that biome carries, on the row that says how far a run got.
			var biome: String = field.get("biome", "")
			if not biome.is_empty():
				line.set_icon(StatIcons.Icon.BIOME, _biome_color(biome))

## Two levels of folding, and a closed level spawns nothing under it.
##
## That is the whole point of the feature rather than an optimisation: this tab
## walks every levelled upgrade in all eight tracks, and a mid-game save is
## several hundred rows of scroll if every resource stays open. Hiding them with
## `visible = false` would still build them all.
func _build_bonuses() -> void:
	for group: Dictionary in _vm.bonus_groups:
		var resource: String = group["resource"]
		var card := _add_card(resource, group["total"], group["count"])
		card.set_collapsible(true)
		card.set_expanded(_vm.is_resource_open(resource))
		card.toggled.connect(_on_resource_toggled.bind(resource))
		if not _vm.is_resource_open(resource):
			continue
		for source: Dictionary in group["sources"]:
			var track: String = source["track"]
			var stat_group := stat_group_scene.instantiate()
			card.rows.add_child(stat_group)
			stat_group.set_group(track, source["multiplier"])
			stat_group.set_expanded(_vm.is_track_open(resource, track))
			stat_group.toggled.connect(_on_track_toggled.bind(resource, track))
			if not _vm.is_track_open(resource, track):
				continue
			for upgrade: Dictionary in source["upgrades"]:
				# One line each. The effect lines that used to sit under these
				# said the magnitude and the op - "x1.61 MORE Potency
				# Production" - beside a name that already reads "Mycelium
				# Potency" and a value column that already reads x1.61.
				_add_row(stat_group.rows, upgrade["name"], upgrade["multiplier"]).set_compact()

## A biome milestone draws that biome's own authored tile, so the timeline says
## which place was reached without the reader parsing the title.
##
## The BiomeDef is read straight off the registry: a shader and a colour are
## fixed for the resource's lifetime, which is exactly the enumeration case the
## ViewModel rule carves out. Nothing dynamic is read here.
func _paint_milestone_icon(card: Node, kind: String, key: String) -> void:
	match kind:
		StatsSystem.MILESTONE_BIOME:
			for def: BiomeDef in App.biomes.biomes:
				if String(def.key) == key:
					card.set_biome_icon(def.biome_shader, def.biome_color)
					return
			card.set_icon(StatIcons.Icon.BIOME)
		StatsSystem.MILESTONE_NODE:
			card.set_icon(StatIcons.Icon.NODE)
		StatsSystem.MILESTONE_PRESTIGE:
			card.set_icon(StatIcons.Icon.SPORE)
		_:
			card.clear_icon()

## A biome's authored colour, or the overlay's own accent for a key nothing in
## the registry answers to - a run recorded under a name that has since been
## changed, which StatisticsViewModel._biome_key() leaves empty.
func _biome_color(key: String) -> Color:
	for def: BiomeDef in App.biomes.biomes:
		if String(def.key) == key:
			return def.biome_color
	return StatIcons.ROW_COLOR

## Deferred for the same reason _on_tab_pressed() is: this arrives from inside
## the header button's own `pressed` emission, and _rebuild() frees that button.
func _on_resource_toggled(resource: String) -> void:
	_vm.toggle_resource(resource)
	_guard.run_when_free(&"content", _rebuild, true)

func _on_track_toggled(resource: String, track: String) -> void:
	_vm.toggle_track(resource, track)
	_guard.run_when_free(&"content", _rebuild, true)

## Which screen - and so which biome - a statistics row belongs to, or -1 for the
## rows that belong to no place.
##
## Every economy in the game is somebody's: nutrients are what the Nodes screen
## produces, crystals are the Caves, relics and ichor and glyphs are all three of
## the Ruins' currencies. Each of those screens carries the biome_color of the
## biome that owns it, which is what makes this a colour lookup at all - see
## _color_for().
##
## Nutrients are the one currency two screens list. Nodes wins it over Biomes:
## nodes are what make nutrients, and the Biomes screen only spends them.
##
## The -1 rows are not oversights. Time played, the daily streak, events resolved,
## the player level and fertilizer all sit in sheets that open over any biome
## rather than in one, so they keep the overlay's own accent - and the accent then
## means something, rather than being what a row gets when nobody thought about
## it.
static func _screen_for(key: StringName) -> int:
	match key:
		&"nutrients", &"lifetime_nutrients", &"production", &"tick_count", \
		&"lifetime_ticks", &"manual_nodes", &"lifetime_manual_nodes", \
		&"symbiosis_levels":
			return ScreenTypes.Types.NODES
		&"biomes_unlocked", &"biome_size", &"lifetime_biome_size":
			return ScreenTypes.Types.BIOMES
		&"water":
			return ScreenTypes.Types.WELL
		&"biomass", &"perk_levels", &"prestige_count":
			return ScreenTypes.Types.PRESTIGE
		&"crystals", &"lifetime_crystals":
			return ScreenTypes.Types.CRYSTAL_CAVES
		&"relics", &"ichor", &"glyphs":
			return ScreenTypes.Types.RUINS
		_:
			return -1

## Which currency a statistics row counts, or -1 where it counts something that
## is not one - nodes grown, biomes open, a streak.
static func _currency_for(key: StringName) -> int:
	match key:
		&"nutrients", &"lifetime_nutrients", &"production":
			return CurrencyTypes.Types.NUTRIENTS
		&"water":
			return CurrencyTypes.Types.WATER
		&"biomass":
			return CurrencyTypes.Types.BIOMASS
		&"crystals", &"lifetime_crystals":
			return CurrencyTypes.Types.CRYSTALS
		&"relics":
			return CurrencyTypes.Types.RELICS
		&"ichor":
			return CurrencyTypes.Types.ICHOR
		&"glyphs":
			return CurrencyTypes.Types.GLYPHS
		&"fertilizer":
			return CurrencyTypes.Types.FERTILIZER
		_:
			return -1

## The colour a row's icon paints, in the order of how much the row is *about*
## that colour.
##
## A currency's own main_color first: it is the more vibrant of the two and it is
## already what the resource pill and the growth rows paint, so a nutrient count
## here matches the nutrient count in the bar above it. Where a row counts
## something that is no currency - nodes grown, biomes open, perk levels - there
## is no such colour, and it falls back to the accent of the screen that owns it,
## which ScreenDefinition authors to the owning biome's biome_color.
static func _color_for(key: StringName) -> Color:
	var currency := _currency_for(key)
	if currency >= 0:
		var def := _currency_def(currency)
		if def:
			return def.main_color
	var screen := _screen_for(key)
	if screen < 0:
		return StatIcons.ROW_COLOR
	var definition: ScreenDefinition = App.screens_data.screen_data.get(screen)
	return definition.accent_color if definition else StatIcons.ROW_COLOR

## Static registry read, which the ViewModel rule allows for exactly this: a
## currency's colour is fixed for the def's lifetime.
static func _currency_def(currency: int) -> CurrencyDef:
	return App.currencies.currencies.get(currency)

## Which icon stands for a statistics row.
##
## Records rows and run fields are keyed out of one space by the ViewModel, so
## one table covers both tabs. Falls back to nutrients, the resource every run
## has from its first tick, for the same reason StatIcons.for_stat() does: a row
## added without a key draws something rather than an empty column.
static func _icon_for(key: StringName) -> StatIcons.Icon:
	match key:
		&"water":
			return StatIcons.Icon.WATER
		&"biomass":
			return StatIcons.Icon.BIOMASS
		&"crystals", &"lifetime_crystals":
			return StatIcons.Icon.CRYSTALS
		&"fertilizer":
			return StatIcons.Icon.FERTILIZER
		&"relics":
			return StatIcons.Icon.RELICS
		&"ichor":
			return StatIcons.Icon.ICHOR
		&"glyphs":
			return StatIcons.Icon.GLYPHS
		&"production":
			return StatIcons.Icon.BOOST_POWER
		&"tick_count", &"lifetime_ticks":
			return StatIcons.Icon.TEMPO
		&"first_played", &"current_run":
			return StatIcons.Icon.TIME
		&"manual_nodes", &"lifetime_manual_nodes":
			return StatIcons.Icon.NODE
		&"biomes_unlocked", &"biome_size", &"lifetime_biome_size", &"deepest_biome":
			return StatIcons.Icon.BIOME
		&"player_level":
			return StatIcons.Icon.LEVEL
		&"symbiosis_levels":
			return StatIcons.Icon.SYMBIOSIS
		&"perk_levels":
			return StatIcons.Icon.PERK
		&"daily_streak":
			return StatIcons.Icon.STREAK
		&"events_resolved":
			return StatIcons.Icon.EVENT
		&"prestige_count":
			return StatIcons.Icon.SPORE
		_:
			return StatIcons.Icon.NUTRIENTS

## `key` empty means the row heads or explains other rows rather than being one -
## a bonus effect line, a track heading - and those keep the icon column's width
## without drawing in it. See StatRow.clear_icon().
func _add_row(parent: VBoxContainer, label: String, value: String,
		key: StringName = &"") -> Node:
	var row := stat_row_scene.instantiate()
	parent.add_child(row)
	row.set_row(label, value)
	if key.is_empty():
		row.clear_icon()
	else:
		row.set_icon(_icon_for(key), _color_for(key))
	return row

func _add_card(title: String, meta: String, caption: String) -> Node:
	var card := stat_card_scene.instantiate()
	vbox_content.add_child(card)
	card.set_card(title, meta, caption)
	card.clear_icon()
	return card

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
