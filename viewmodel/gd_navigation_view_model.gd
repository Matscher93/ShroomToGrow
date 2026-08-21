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
			rows.append(row)
		return rows

## The live count a sub-row's badge shows. Public so the menu can refresh badges
## on an already-built row without rebuilding the list.
func badge_count(source: SubScreenDefinition.BadgeSource) -> int:
	match source:
		SubScreenDefinition.BadgeSource.AFFORDABLE_BOOSTS:
			return _affordable(App.boost_vms)
		SubScreenDefinition.BadgeSource.AFFORDABLE_AUTOMATIONS:
			return _affordable(App.automation_vms)
	return 0

# --- Lifecycle ---

func _init() -> void:
	App.screens_data.screen_changed.connect(_on_destinations_changed.unbind(1))
	# Reaching a biome reveals its screen, which is the only thing that changes
	# the row list after startup.
	App.biomes_data.biome_unlocked.connect(_on_destinations_changed.unbind(1))
	# A perk purchase is what brings the Boosts sub-row in, and the perk web is a
	# screen away rather than behind this menu.
	App.prestige_upgrade_system.upgrades_changed.connect(_on_destinations_changed)
	App.player_data.crystals_changed.connect(_on_badges_changed.unbind(1))
	App.boost_upgrade_system.upgrades_changed.connect(_on_badges_changed)
	App.automation_data.levels_changed.connect(_on_badges_changed)

func dispose() -> void:
	App.screens_data.screen_changed.disconnect(_on_destinations_changed.unbind(1))
	App.biomes_data.biome_unlocked.disconnect(_on_destinations_changed.unbind(1))
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_destinations_changed)
	App.player_data.crystals_changed.disconnect(_on_badges_changed.unbind(1))
	App.boost_upgrade_system.upgrades_changed.disconnect(_on_badges_changed)
	App.automation_data.levels_changed.disconnect(_on_badges_changed)

# --- Model -> notification plumbing ---

func _on_destinations_changed() -> void:
	_notify(PROP_DESTINATIONS_CHANGED)

func _on_badges_changed() -> void:
	_notify(PROP_BADGES_CHANGED)

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
## CrystalCavesPanel._refresh_boosts_tab(). Before the first boost perk the
## Boosts tab is a page of locked cards and is hidden there, so a row leading to
## it would lead somewhere that is not on screen.
func _is_sub_visible(sub: SubScreenDefinition) -> bool:
	match sub.visible_when:
		SubScreenDefinition.VisibleWhen.BOOSTS_UNLOCKED:
			return App.crystal_caves_vm.boosts_visible
	return true

## Which sub-view the given screen is showing, or -1 for a screen that has none.
## The one place the nav names a specific screen's ViewModel: sub-views are the
## Caves screen's alone today, and a registry of one is more indirection than the
## coupling it would hide.
func _current_sub_index(type: ScreenTypes.Types) -> int:
	if type == ScreenTypes.Types.CRYSTAL_CAVES:
		return App.crystal_caves_vm.current_tab
	return -1

## Both card VMs already expose can_buy against live currency, so the count is a
## read rather than a second affordability rule to keep in step with the cards.
func _affordable(vms: Dictionary) -> int:
	var count := 0
	for vm: Variant in vms.values():
		if vm.is_unlocked and vm.can_buy:
			count += 1
	return count
