class_name MyceliumNodeViewModel
extends ViewModel
## VIEWMODEL: adapts PlayerData for display and exposes commands.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.

const PROP_BUY_TEXT := &"buy_button_text"
const PROP_MANUAL_NODE_TEXT := &"manual_node_text"
const PROP_OWNED_NODE_TEXT := &"owned_node_text"
const PROP_CAN_BUY := &"can_buy_upgrade"
const PROP_PRODUCTION_TEXT := &"production_text"
const PROP_SYMBIOSIS_YIELD_TEXT := &"symbiosis_yield_text"
const PROP_TOTAL_YIELD_TEXT := &"total_yield_text"
const PROP_POTENCY_LEVEL_TEXT := &"potency_level_text"
const PROP_POTENCY_HEADER_TEXT := &"potency_header_text"
const PROP_POTENCY_ACCUMULATED_TEXT := &"potency_accumulated_text"
const PROP_POTENCY_COST_TEXT := &"potency_cost_text"
const PROP_POTENCY_CAN_BUY := &"potency_can_buy"
const PROP_SYNERGY_LEVEL_TEXT := &"synergy_level_text"
const PROP_SYNERGY_HEADER_TEXT := &"synergy_header_text"
const PROP_SYNERGY_ACCUMULATED_TEXT := &"synergy_accumulated_text"
const PROP_SYNERGY_COST_TEXT := &"synergy_cost_text"
const PROP_SYNERGY_CAN_BUY := &"synergy_can_buy"

## Whether this tier has been reached at all. The nodes panel shows a tier once
## it or the tier below it has any nodes, and that read used to happen in the view
## against MyceliumNode directly.
const PROP_HAS_NODES := &"has_nodes"

## The card's notification dot, and what the Nodes nav row badges.
const PROP_HAS_ATTENTION := &"has_attention"

# --- View state ---
## Whether the card's buy body is open. Parked here for the same reason as
## BiomeViewModel.expanded: App owns this VM for the app's lifetime, the Nodes
## screen is freed on every nav switch, and a flag on the card would collapse
## every tier again on every visit. Defaults open: the buy body is the card's
## whole point, and a screen of shut cards hides every cost on first open.
## Not saved.
var expanded := true

var _player_data: PlayerData
var _mycelium_data: MyceliumNodeData
var _potency_id: StringName
var _synergy_id: StringName
## The last value the cue was notified at - see _notify_attention().
var _attention := false

# --- Read-only display properties bound by the View ---
var buy_button_text: String:
	get:
		if not _mycelium_data.is_unlocked():
			return "Needs %s" % [_unlock_perk_name()]
		return "%s" % [_format_number(_mycelium_data.upgrade_cost())]

## True once this tier holds anything, bought or grown. Drives whether the nodes
## panel shows the row at all.
var has_nodes: bool:
	get: return _mycelium_data.node.has_nodes()

var manual_node_text: String:
	get:
		return "%d" % [_mycelium_data.node.manual_nodes]

var owned_node_text: String:
	get:
		return "%s" % [_mycelium_data.node.auto_nodes
						.add(BigNumber.from_value(_mycelium_data.node.manual_nodes))
						.to_display()]

var production_text: String:
	get:
		var production := _scaled_production()
		return "+%s / tick" % [_unit_text(production)]

var production_per_node_text: String:
	get:
		return _mycelium_data.node.desc % [_unit_text(_bonus_production())]

var production_text_short: String:
	get:
		return "+%s/tick" % [_scaled_production().to_display()]

var can_buy_upgrade: bool:
	get:
		return _mycelium_data.can_buy_upgrade()

## False while this tier waits on its unlock perk. The panel stays visible,
## but nothing on it can be bought.
var is_unlocked: bool:
	get:
		return _mycelium_data.is_unlocked()

## A tier the player has reached but never bought, affordable now.
##
## Not can_buy_upgrade on its own, which is what a cue here would obviously be:
## nutrients climb on their own, so an owned tier is affordable nearly all the
## time and a dot on that would be lit nearly all the time - which teaches the
## player to stop reading every other dot in the game too. Gated on has_nodes it
## fires once per tier, at the only moment the Nodes screen has news: the next
## link in the chain just became reachable. Buying it puts the cue out for good.
##
## Naturally 0-or-1 across the whole screen, since NodesPanel only ever shows one
## tier the player does not already own.
var has_attention: bool:
	get: return is_unlocked and not has_nodes and can_buy_upgrade

## Pluralised against the amount actually shown, not the production multiplier:
## 500 nutrients at a 1.0x bonus would otherwise render "500 nutrient".
func _unit_text(amount: BigNumber) -> String:
	var plural := amount.gt(BigNumber.from_value(1.0))
	if _mycelium_data.node.node_id == 0:
		return ("%s nutrients" if plural else "%s nutrient") % [amount.to_display()]
	var level_text := "LV%d" % [_mycelium_data.node.node_id]
	return ("%s %s nodes" if plural else "%s %s node") % [amount.to_display(), level_text]

## Potency times synergy only, so the player can tell their own symbiosis levels
## apart from the biome and perk multipliers folded into the total below.
var symbiosis_yield_text: String:
	get:
		var symbiosis := App.node_symbiosis_bonus(_node_id_key()).sub(BigNumber.from_value(1.0))
		return "+%s%%" % [symbiosis.scale(100.0).to_display()]

var total_yield_text: String:
	get:
		var total := App.node_production_bonus(_node_id_key()).sub(BigNumber.from_value(1.0))
		return "+%s%%" % [total.scale(100.0).to_display()]

var synergy_track_unlocked: bool:
	get: return App.biomes_data.is_unlocked(&"forest")

var node_name: String:
	get: return _mycelium_data.node.name

var node_color: Color:
	get: return _mycelium_data.node.color

var node_level_font_color: Color:
	get: return _mycelium_data.node.level_font_color

# --- Potency track ---
var potency_level_text: String:
	get: return "Lv %d" % App.upgrade_system.level(_potency_id)

var potency_header_text: String:
	get:
		var mult := App.node_potency_external_multiplier(_node_id_key())
		var delta := App.upgrade_system.next_level_delta(_potency_id, App.resolve_context)
		return "+%s%% / level:" % [delta.mul(mult).scale(100.0).to_display()]

var potency_accumulated_text: String:
	get:
		var bonus := App.node_potency_bonus(_node_id_key())
		return "now +%s%%" % [bonus.sub(BigNumber.from_value(1.0)).scale(100.0).to_display()]

var potency_cost_text: String:
	get: return App.upgrade_system.cost(_potency_id).to_display() if App.upgrade_system.has_def(_potency_id) else "--"

var potency_can_buy: bool:
	get: return is_unlocked and App.upgrade_system.can_buy(_potency_id, _player_data.nutrients)

# --- Synergy track ---
var synergy_level_text: String:
	get: return "Lv %d" % App.upgrade_system.level(_synergy_id)

var synergy_header_text: String:
	get:
		var mult := App.node_synergy_external_multiplier(_node_id_key())
		var delta := App.upgrade_system.next_level_delta(_synergy_id, App.resolve_context)
		return "+%s%% / level:" % [delta.mul(mult).scale(100.0).to_display()]

var synergy_accumulated_text: String:
	get:
		var bonus := App.node_synergy_bonus(_node_id_key())
		return "now +%s%%" % [bonus.sub(BigNumber.from_value(1.0)).scale(100.0).to_display()]

var synergy_cost_text: String:
	get: return App.upgrade_system.cost(_synergy_id).to_display() if App.upgrade_system.has_def(_synergy_id) else "--"

var synergy_can_buy: bool:
	get: return is_unlocked and App.upgrade_system.can_buy(_synergy_id, _player_data.nutrients)

# --- Lifecycle ---

func _init(player_data: PlayerData, mycelium_data: MyceliumNodeData) -> void:
	_player_data = player_data
	_player_data.nutrients_changed.connect(_on_nutrients_changed)
	_mycelium_data = mycelium_data
	_potency_id = StringName("NodePotency%d" % _mycelium_data.node.node_id)
	_synergy_id = StringName("NodeSynergy%d" % _mycelium_data.node.node_id)
	_mycelium_data.node.auto_nodes_changed.connect(_on_auto_nodes_changed)
	_mycelium_data.node.manual_nodes_changed.connect(_on_manual_nodes_changed)
	App.upgrade_system.upgrades_changed.connect(_on_upgrades_changed)
	App.biome_upgrade_system.upgrades_changed.connect(_on_upgrades_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_upgrades_changed)
	# Seeded rather than left false: _notify_attention() only fires on a crossing,
	# so a cue that is already on at construction has to be known about here or its
	# first turn *off* would look like no change at all.
	_attention = has_attention


func dispose() -> void:
	_player_data.nutrients_changed.disconnect(_on_nutrients_changed)
	_mycelium_data.node.auto_nodes_changed.disconnect(_on_auto_nodes_changed)
	_mycelium_data.node.manual_nodes_changed.disconnect(_on_manual_nodes_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)

# --- Commands (called by the View on input) ---

func buy_upgrade() -> void:
	_mycelium_data.buy_upgrade()
	# Model signals trigger the notifications below.

func buy_potency() -> bool:
	if not is_unlocked:
		return false
	return App.upgrade_system.buy(_potency_id, _player_data)

func buy_synergy() -> bool:
	if not is_unlocked:
		return false
	return App.upgrade_system.buy(_synergy_id, _player_data)

# --- Model to notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_BUY)
	_notify(PROP_BUY_TEXT)  # affordability display may change
	_notify(PROP_POTENCY_CAN_BUY)
	_notify(PROP_SYNERGY_CAN_BUY)
	_notify_attention()

func _on_auto_nodes_changed(_auto_nodes: BigNumber) -> void:
	_notify(PROP_OWNED_NODE_TEXT)
	_notify(PROP_PRODUCTION_TEXT)
	_notify(PROP_HAS_NODES)
	_notify_attention()

func _on_manual_nodes_changed(_manual_nodes: int) -> void:
	_notify(PROP_MANUAL_NODE_TEXT)
	_notify(PROP_OWNED_NODE_TEXT)
	_notify(PROP_PRODUCTION_TEXT)
	_notify(PROP_BUY_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_HAS_NODES)
	_notify_attention()

func _on_upgrades_changed() -> void:
	# Buying the unlock perk lands here too, so the buy panel re-reads both its
	# label and its enabled state.
	_notify(PROP_BUY_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_PRODUCTION_TEXT)
	_notify(PROP_SYMBIOSIS_YIELD_TEXT)
	_notify(PROP_TOTAL_YIELD_TEXT)
	_notify(PROP_POTENCY_LEVEL_TEXT)
	_notify(PROP_POTENCY_HEADER_TEXT)
	_notify(PROP_POTENCY_ACCUMULATED_TEXT)
	_notify(PROP_POTENCY_COST_TEXT)
	_notify(PROP_POTENCY_CAN_BUY)
	_notify(PROP_SYNERGY_LEVEL_TEXT)
	_notify(PROP_SYNERGY_HEADER_TEXT)
	_notify(PROP_SYNERGY_ACCUMULATED_TEXT)
	_notify(PROP_SYNERGY_COST_TEXT)
	_notify(PROP_SYNERGY_CAN_BUY)
	_notify_attention()

## Emits only when the cue actually turns on or off.
##
## has_attention is re-read from a nutrient change, which lands every game tick
## for the whole session, and every notify reaches the nav badges and the menu
## disc through NavigationViewModel. A dot has two states; only the crossings
## between them are news. Mirrors BiomeViewModel._notify_attention().
func _notify_attention() -> void:
	var attention := has_attention
	if attention == _attention:
		return
	_attention = attention
	_notify(PROP_HAS_ATTENTION)

# --- Formatting ---

func _format_number(value: BigNumber) -> String:
	return value.to_display()

func _unlock_perk_name() -> String:
	var def := App.perk_def(_mycelium_data.node.unlock_perk_id)
	return def.display_name if def != null else "a prestige perk"

func _node_id_key() -> StringName:
	return _mycelium_data.node.id_key

func _scaled_production() -> BigNumber:
	var raw := _mycelium_data.node.auto_nodes.add(BigNumber.from_value(_mycelium_data.node.manual_nodes))
	return raw.mul(_bonus_production())

func _bonus_production() -> BigNumber:
	return App.node_production_bonus(_node_id_key())
