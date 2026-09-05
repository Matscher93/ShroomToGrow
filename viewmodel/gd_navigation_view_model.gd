class_name NavigationViewModel
extends ViewModel
## VIEWMODEL: the nav menu and the menu disc that opens it.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## Composes what three other places already know - which screens are unlocked
## (ScreensViewModel's rule), which sub-views the Caves screen is showing
## (CrystalCavesViewModel), and what is affordable right now (the boost and
## automation card VMs) - into one flat list of rows. The menu binds this and
## nothing else, so a row never has to reach past its ViewModel to paint itself.
##
## Built once and owned by App: the disc is on screen at all times and the menu
## is spawned and freed on every open, so neither can own the lifetime.

## The list of rows changed, or the row marked current moved. The menu rebuilds.
const PROP_DESTINATIONS_CHANGED := &"destinations_changed"
## Only the badge counts moved. Split from the above so a crystal tick repaints
## the numbers on an open menu instead of rebuilding every row under the
## player's finger.
const PROP_BADGES_CHANGED := &"badges_changed"

# --- View -> ViewModel ---

## One nav tap. sub_index is a SubScreenDefinition.tab_index, or -1 for a
## top-level row, which leaves the target screen on whatever sub-view it
## remembers.
func go_to(screen_type: ScreenTypes.Types, sub_index: int = -1) -> void:
	App.screens_data.select(screen_type, sub_index)

# --- Read-only display properties bound by the View ---

## What the disc prints. The current screen's name, which is the whole reason the
## disc can double as an orientation cue instead of being a bare hamburger.
var current_label: String:
	get:
		var definition := _definition(App.screens_data.current_screen)
		return definition.screen_name.to_upper() if definition else ""

## What the disc paints, and the accent of the row marked current.
var current_accent: Color:
	get:
		var definition := _definition(App.screens_data.current_screen)
		return definition.accent_color if definition else Color.WHITE

## Every destination the player can reach right now, in NAV_ORDER.
##
## Locked screens are left out rather than shown greyed: they unlock from the
## biome cards, so a dead row here would point at nothing the player can act on.
## The two reasons a screen can be absent are folded together the same way
## ScreensViewModel.visible_screens folds them.
var destinations: Array[NavDestination]:
	get:
		var rows: Array[NavDestination] = []
		for type in ScreenTypes.NAV_ORDER:
			if not App.is_screen_unlocked(type):
				continue
			var definition := _definition(type)
			if definition == null:
				continue
			var is_current := App.screens_data.current_screen == type
			var row := NavDestination.new()
			row.screen_type = type
			row.label = definition.screen_name
			row.subtitle = definition.subtitle
			row.accent = definition.accent_color
			row.icon_shader = definition.icon_shader
			row.is_current = is_current
			row.subs = _sub_rows(type, definition, is_current)
			row.badge_count = screen_badge_count(type)
			rows.append(row)
		return rows

## True when a screen the player is *not* on has something waiting. What the menu
## disc shows, and the only cue in the game that reaches across screens.
##
## The current screen is left out on purpose: its own cards carry their dots, and
## a disc that lit for the screen under it would be lit for most of the session
## rather than meaning "there is somewhere else to be".
##
## Walks NAV_ORDER rather than destinations: the disc polls this once a second
## (see NavDisc), and building a row object per screen to throw them all away is
## work this can early-return out of instead.
var any_attention: bool:
	get:
		var current := App.screens_data.current_screen
		for type in ScreenTypes.NAV_ORDER:
			if type == current or not App.is_screen_unlocked(type):
				continue
			if screen_badge_count(type) > 0:
				return true
		return false

## The sub-views of the screen that is up, for the chip bar beside the disc.
##
## The same rows the menu builds under the current destination, handed out on
## their own so they can be reached without opening the menu at all: switching
## tab is the one nav move a player makes constantly, and it is a full open,
## scroll and tap away otherwise. Empty for a screen with no sub-views, which is
## what hides the bar.
var current_subs: Array[NavSubDestination]:
	get:
		var type := App.screens_data.current_screen
		var definition := _definition(type)
		if definition == null:
			return []
		return _sub_rows(type, definition, true)

## The live count a sub-row's badge shows. Public so the menu can refresh badges
## on an already-built row without rebuilding the list.
func badge_count(source: BadgeSource.Source) -> int:
	match source:
		BadgeSource.Source.AFFORDABLE_BOOSTS:
			return _affordable(App.boost_vms)
		BadgeSource.Source.AFFORDABLE_AUTOMATIONS:
			return _affordable(App.automation_vms)
		BadgeSource.Source.COLLECTABLE_MISSIONS:
			# Missions finish on the wall clock, so this number moves with no
			# model signal behind it. The disc polls once a second to cover that
			# (see NavDisc); the menu is short-lived enough to not need its own
			# timer, and the count is right every time it is opened.
			return App.collectable_mission_count()
		BadgeSource.Source.AFFORDABLE_MISSION_BOOSTS:
			return _affordable(App.mission_boost_vms)
		BadgeSource.Source.BIOME_ATTENTION:
			return _with_attention(App.biome_vms.values())
		BadgeSource.Source.NEW_NODE_TIER:
			return _with_attention(App.mycelium_node_vms)
	return 0

## Everything waiting on one screen: its own count plus the rows underneath it.
##
## A screen names at most one of the two - a screen with sub-views speaks through
## their badges and leaves its own source NONE - so nothing here is counted twice.
## Hidden sub-rows are skipped for the same reason the menu skips them: a count
## behind a row that is not on screen points the player at nothing.
func screen_badge_count(type: ScreenTypes.Types) -> int:
	var definition := _definition(type)
	if definition == null:
		return 0
	var count := badge_count(definition.badge_source)
	for sub in definition.sub_screens:
		if _is_sub_visible(sub):
			count += badge_count(sub.badge_source)
	return count

# --- Lifecycle ---

func _init() -> void:
	App.screens_data.screen_changed.connect(_on_destinations_changed.unbind(1))
	# A tab tap on the screen already up moves no screen, so screen_changed stays
	# silent - and the chip bar's highlight would sit on the tab the player just
	# left. This is the only signal that fires for that move.
	App.screens_data.sub_screen_requested.connect(_on_destinations_changed.unbind(2))
	# Reaching a biome reveals its screen, which is the only thing that changes
	# the row list after startup.
	App.biomes_data.biome_unlocked.connect(_on_destinations_changed.unbind(1))
	# ...and the first time, it also walks the player there. Deferred on purpose:
	# the unlock arrives from a press handler on a button that lives inside the
	# screen GameScreens is about to free, and swapping screens inside that
	# button's own emission tears the node down mid-signal.
	App.biomes_data.biome_first_unlocked.connect(_on_biome_first_unlocked, CONNECT_DEFERRED)
	# A perk purchase is what brings the Boosts sub-row in, and the perk web is a
	# screen away rather than behind this menu.
	App.prestige_upgrade_system.upgrades_changed.connect(_on_destinations_changed)
	App.player_data.crystals_changed.connect(_on_badges_changed.unbind(1))
	App.boost_upgrade_system.upgrades_changed.connect(_on_badges_changed)
	App.automation_data.levels_changed.connect(_on_badges_changed)
	# The three mission currencies, which is what makes a Ruins boost affordable.
	App.player_data.relics_changed.connect(_on_badges_changed.unbind(1))
	App.player_data.ichor_changed.connect(_on_badges_changed.unbind(1))
	App.player_data.glyphs_changed.connect(_on_badges_changed.unbind(1))
	App.mission_upgrade_system.upgrades_changed.connect(_on_badges_changed)
	# Sending and collecting move the collectable count directly. A mission
	# *finishing* fires nothing - see badge_count().
	App.ruins_data.active_changed.connect(_on_badges_changed)
	# Reaching the first hero brings the Heroes row in, which is a row
	# change rather than a badge one.
	App.ruins_data.missions_completed_changed.connect(_on_destinations_changed.unbind(1))
	# The Biomes and Nodes counts come off the card ViewModels rather than from
	# the model signals underneath them. BiomeViewModel alone fans in four
	# currencies, six XP sources and every node's manual count to work out whether
	# it is waiting on the player; repeating that list here would be a second copy
	# of the rule to keep in step. App owns both sets for the app's lifetime and
	# builds them before this, so the connections outlive every screen.
	for vm: BiomeViewModel in App.biome_vms.values():
		vm.property_changed.connect(_on_card_property_changed)
	for vm: MyceliumNodeViewModel in App.mycelium_node_vms:
		vm.property_changed.connect(_on_card_property_changed)

func dispose() -> void:
	App.screens_data.screen_changed.disconnect(_on_destinations_changed.unbind(1))
	App.screens_data.sub_screen_requested.disconnect(_on_destinations_changed.unbind(2))
	App.biomes_data.biome_unlocked.disconnect(_on_destinations_changed.unbind(1))
	App.biomes_data.biome_first_unlocked.disconnect(_on_biome_first_unlocked)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_destinations_changed)
	App.player_data.crystals_changed.disconnect(_on_badges_changed.unbind(1))
	App.boost_upgrade_system.upgrades_changed.disconnect(_on_badges_changed)
	App.automation_data.levels_changed.disconnect(_on_badges_changed)
	App.player_data.relics_changed.disconnect(_on_badges_changed.unbind(1))
	App.player_data.ichor_changed.disconnect(_on_badges_changed.unbind(1))
	App.player_data.glyphs_changed.disconnect(_on_badges_changed.unbind(1))
	App.mission_upgrade_system.upgrades_changed.disconnect(_on_badges_changed)
	App.ruins_data.active_changed.disconnect(_on_badges_changed)
	App.ruins_data.missions_completed_changed.disconnect(_on_destinations_changed.unbind(1))
	for vm: BiomeViewModel in App.biome_vms.values():
		vm.property_changed.disconnect(_on_card_property_changed)
	for vm: MyceliumNodeViewModel in App.mycelium_node_vms:
		vm.property_changed.disconnect(_on_card_property_changed)

# --- Model -> notification plumbing ---

func _on_destinations_changed() -> void:
	_notify(PROP_DESTINATIONS_CHANGED)

func _on_badges_changed() -> void:
	_notify(PROP_BADGES_CHANGED)

## Both card ViewModels notify on a great deal more than their cue - every label,
## cost and progress bar on the card - and all of it arrives here. Only the one
## property is a badge move, so the rest is dropped rather than repainting the nav
## on every nutrient tick.
##
## One name covers both, since BiomeViewModel and MyceliumNodeViewModel spell
## their cue the same: they are two answers to the same question.
func _on_card_property_changed(property: StringName) -> void:
	if property == BiomeViewModel.PROP_HAS_ATTENTION:
		_on_badges_changed()

## A biome opened for the very first time takes the player to the screen it
## brings with it - or, where it brings none, to the screen its purchase is spent
## on (BiomeDef.reveal_screen). The row it adds to the menu is otherwise the only
## announcement a whole new screen ever gets, and that is behind the disc.
##
## A biome that names neither reaches nothing here, and neither does one whose
## screen is already up.
func _on_biome_first_unlocked(key: StringName) -> void:
	var definition := App.biome_def(key)
	if definition == null:
		return
	var target := definition.reveal_screen
	if target == ScreenTypes.Types.BIOMES:
		target = definition.screen_type
	if target == ScreenTypes.Types.BIOMES or App.screens_data.current_screen == target:
		return
	go_to(target)

# --- Building ---

func _definition(type: ScreenTypes.Types) -> ScreenDefinition:
	return App.screens_data.screen_data.get(type)

## A sub-row is only marked current while its parent screen is the one up: the
## Caves screen remembers a tab whether or not the player is looking at it, and
## highlighting that tab from another screen would claim the player is somewhere
## they are not. The badges stay live either way - surfacing claimable work from
## across the game is the point of them.
func _sub_rows(type: ScreenTypes.Types, definition: ScreenDefinition,
		parent_is_current: bool) -> Array[NavSubDestination]:
	var rows: Array[NavSubDestination] = []
	for sub in definition.sub_screens:
		if not _is_sub_visible(sub):
			continue
		var row := NavSubDestination.new()
		row.screen_type = type
		row.label = sub.display_name
		row.tab_index = sub.tab_index
		row.accent = definition.accent_color
		row.is_current = parent_is_current and _current_sub_index(type) == sub.tab_index
		row.badge_source = sub.badge_source
		row.badge_count = badge_count(sub.badge_source)
		rows.append(row)
	return rows

## The same gate the screen puts on the tab itself - see
## CrystalCavesPanel._refresh_optional_tabs(). Before the first boost perk the
## Boosts tab is a page of locked cards and is hidden there, and the Sequences
## tab is a point plan nothing replays until the steward is bought, so a row
## leading to either would lead somewhere that is not on screen.
func _is_sub_visible(sub: SubScreenDefinition) -> bool:
	match sub.visible_when:
		SubScreenDefinition.VisibleWhen.BOOSTS_UNLOCKED:
			return App.crystal_caves_vm.boosts_visible
		SubScreenDefinition.VisibleWhen.HEROES_UNLOCKED:
			return App.ruins_vm.heroes_visible
		SubScreenDefinition.VisibleWhen.SEQUENCES_UNLOCKED:
			return App.crystal_caves_vm.sequences_visible
	return true

## Which sub-view the given screen is showing, or -1 for a screen that has none.
## The one place the nav names a specific screen's ViewModel: sub-views are the
## Caves screen's alone today, and a registry of one is more indirection than the
## coupling it would hide.
func _current_sub_index(type: ScreenTypes.Types) -> int:
	if type == ScreenTypes.Types.CRYSTAL_CAVES:
		return App.crystal_caves_vm.current_tab
	if type == ScreenTypes.Types.RUINS:
		return App.ruins_vm.current_tab
	return -1

## Both card VMs already expose can_buy against live currency, so the count is a
## read rather than a second affordability rule to keep in step with the cards.
func _affordable(vms: Dictionary) -> int:
	var count := 0
	for vm: Variant in vms.values():
		if vm.is_unlocked and vm.can_buy:
			count += 1
	return count

## How many cards on a screen are waiting on the player. Each card VM already
## owns what counts as waiting on it - which is deliberately narrower than "can
## be bought" for both biomes and nodes - so this only adds them up.
func _with_attention(vms: Array) -> int:
	var count := 0
	for vm: Variant in vms:
		if vm.has_attention:
			count += 1
	return count
