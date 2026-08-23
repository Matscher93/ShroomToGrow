@tool
extends PanelContainer
## VIEW: the Crystal Caves screen. Three tabs: the crystal-bought boosts, the
## crystal-bought automations, and the per-biome sequences the point-spending
## automation replays.
##
## The tab bar is hidden - the nav menu lists these three as sub-rows under
## Crystals, reachable in one tap from any screen, and a second row of tabs at
## the bottom of the screen was competing with the menu disc for the same thumb.
## The TabContainer still owns the pages, the hidden-tab rule and the per-tab
## scroll offsets; only its bar is off. The chip above it is what now says which
## tab is up.
##
## The crystal balance is not repeated here. The screen definition lists crystals
## as its currency, so the top bar already shows it labelled above every tab; a
## second bare number under it was one readout too many.
##
## The Boosts tab is a self-contained scene (see view/boosts/) that binds the
## same CrystalCavesViewModel for its card list, so it needs no wiring here
## beyond sitting in the TabContainer.
##
## Sequences sit last because they are set up once and then left alone, and the
## rows are long enough that they crowded the upgrade list they used to share.
## Each biome's auto-buy-after-sporation lives in that biome's section rather
## than under the automation cards: it is per-biome the way the cards are not.
##
## The achievement archive that mints those crystals used to lead here as a third
## tab. It moved to the top-bar overlay, which is reachable from every screen -
## claims pile up between visits, and having to walk to this screen to collect
## them was the only thing keeping it here.
##
## The Crystal Caves *biome* card (level, XP, points, size, its 10 upgrades)
## lives on the Biomes screen like every other biome. This screen is the hub the
## biome unlocks, not a second copy of that card.

@export var tab_container: FullWidthTabContainer
@export var boosts_tab: Control
@export var automations_tab: ScrollContainer
@export var sequences_tab: ScrollContainer
@export var vbox_automations: VBoxContainer
@export var vbox_sequences: VBoxContainer
@export var lbl_current_tab: Label
@export var automation_card_scene: PackedScene
@export var biome_sequence_scene: PackedScene

var _vm: CrystalCavesViewModel

## Holds structural refreshes back while the player has the pointer down, so a
## tick landing mid-press cannot free or reflow the button under their finger.
var _guard := PressGuard.new()

func _ready() -> void:
	# Parented before the editor-hint bail below: an unparented guard is an orphan
	# Node this panel would leak on every rebuild.
	add_child(_guard)
	# Autoloads aren't instantiated for @tool scripts in the editor, so the
	# ViewModels only exist at runtime.
	if Engine.is_editor_hint():
		return

	bind(App.crystal_caves_vm)
	_build_automations()
	_build_sequences()
	_refresh_boosts_tab()
	await _restore_view_state()

func bind(vm: CrystalCavesViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	match property:
		CrystalCavesViewModel.PROP_BOOSTS_VISIBLE:
			_guard.run_when_free(&"boosts_tab", _refresh_boosts_tab)
		CrystalCavesViewModel.PROP_SECTIONS_CHANGED:
			_guard.run_when_free(&"sequences", _build_sequences)
		CrystalCavesViewModel.PROP_TAB_REQUESTED:
			_apply_requested_tab()

## Boosts leads the tabs, so it is also the one the screen opens on. Hiding the
## current tab leaves TabContainer pointing at a tab that is no longer there, so
## the selection is moved to the first one still showing.
func _refresh_boosts_tab() -> void:
	var index := boosts_tab.get_index()
	tab_container.set_tab_hidden(index, not _vm.boosts_visible)
	_refresh_tab_chip()
	# One fewer tab to share the bar, so what is left has to be repadded.
	tab_container.spread_tabs()
	if _vm.boosts_visible or tab_container.current_tab != index:
		return
	for i in range(tab_container.get_tab_count()):
		if not tab_container.is_tab_hidden(i):
			tab_container.current_tab = i
			return

## The nav menu asked for one of these tabs while the screen was already up.
## Arriving from another screen respawns the screen instead, and _ready() reads
## the same remembered tab on its own.
##
## A hidden tab is ignored rather than forced: the menu does not offer a row for
## one, so a request for it is stale state, not a destination.
func _apply_requested_tab() -> void:
	if tab_container.is_tab_hidden(_vm.current_tab):
		return
	tab_container.current_tab = _vm.current_tab
	_refresh_tab_chip()

func _refresh_tab_chip() -> void:
	lbl_current_tab.text = _vm.tab_label(tab_container.current_tab)

# --- View state ---

## Puts the screen back where the player left it. Screens are freed on every nav
## switch (see GameScreens), so without this a glance at another screen costs the
## player their tab, their place in the list and every section they had opened -
## which on a long sequence is a dozen taps to get back to.
##
## Scroll is restored a frame late on purpose: a ScrollContainer has no content
## height until it has been laid out once, and setting an offset before then is
## clamped to zero.
func _restore_view_state() -> void:
	if not tab_container.is_tab_hidden(_vm.current_tab):
		tab_container.current_tab = _vm.current_tab
	tab_container.tab_changed.connect(_on_tab_changed)
	_refresh_tab_chip()
	for tab in _scrolling_tabs():
		tab.get_v_scroll_bar().value_changed.connect(_on_scrolled.bind(tab))
	await get_tree().process_frame
	# The player can leave the screen inside that frame, which frees this node.
	if not is_inside_tree() or _vm == null:
		return
	for tab in _scrolling_tabs():
		tab.scroll_vertical = int(_vm.scroll_offsets.get(tab.get_index(), 0))

func _scrolling_tabs() -> Array[ScrollContainer]:
	return [automations_tab, sequences_tab]

func _on_tab_changed(tab: int) -> void:
	_vm.current_tab = tab
	_refresh_tab_chip()

func _on_scrolled(value: float, tab: ScrollContainer) -> void:
	_vm.scroll_offsets[tab.get_index()] = int(value)

# --- Building ---

func _build_automations() -> void:
	_clear(vbox_automations)
	for vm in _vm.automation_vms_ordered:
		var card := automation_card_scene.instantiate()
		vbox_automations.add_child(card)
		card.bind(vm)

## One section per biome the save has ever reached, each owning the sequence the
## point-spending automation replays for it and that biome's auto-buy purchase.
##
## Rebuilt whenever the set of biomes changes rather than only at _ready: the
## screen keeps its state across nav switches now, so it no longer gets a free
## rebuild every time the player comes back. Expansion and page live on the
## persistent per-biome ViewModels, so a rebuild does not disturb them.
func _build_sequences() -> void:
	_clear(vbox_sequences)
	for vm in _vm.sequence_vms():
		var section := biome_sequence_scene.instantiate()
		vbox_sequences.add_child(section)
		section.bind(vm)

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
