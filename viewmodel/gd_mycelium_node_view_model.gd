class_name MyceliumNodeViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_BUY_TEXT := &"buy_button_text"
const PROP_MANUAL_NODE_TEXT := &"manual_node_text"
const PROP_OWNED_NODE_TEXT := &"owned_node_text"
const PROP_CAN_BUY := &"can_buy_upgrade"
const PROP_PRODUCTION_TEXT := &"production_text"
const PROP_PRODUCTION_PER_NODE_TEXT := &"production_per_node_text"
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

var _player_data: PlayerData
var _mycelium_data: MyceliumNodeData
var _potency_id: StringName
var _synergy_id: StringName

# --- Read-only display properties the View binds to ---
var buy_button_text: String:
	get:
		return "%s" % [_format_number(_mycelium_data.upgrade_cost())]

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
		if production.equals(BigNumber.from_value(0.0)):
			return ""
		return "+%s / tick" % [_unit_text(production)]

var production_per_node_text: String:
	get:
		return _mycelium_data.node.desc % [_unit_text(_bonus_production())]

var production_text_short: String:
	get:
		return "+%s/tick" % [_scaled_production().to_display()]

var can_buy_upgrade: bool:
	get:
		return _mycelium_data.can_afford_upgrade()

## Pluralised against the number actually being shown. This used to be a
## parameterless `is_multiple` reading the production *multiplier* rather than
## the amount next to the noun, so a node producing 500 with a 1.0x bonus
## rendered "500 nutrient".
func _unit_text(amount: BigNumber) -> String:
	var plural := amount.gt(BigNumber.from_value(1.0))
	if _mycelium_data.node.node_id == 0:
		return ("%s nutrients" if plural else "%s nutrient") % [amount.to_display()]
	var level_text := "LV%d" % [_mycelium_data.node.node_id]
	return ("%s %s nodes" if plural else "%s %s node") % [amount.to_display(), level_text]

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
		return "+%s%% / level:" % [App.upgrade_system.next_level_delta(_potency_id).mul(mult).scale(100.0).to_display()]

var potency_accumulated_text: String:
	get:
		var bonus := App.node_potency_bonus(_node_id_key())
		return "now +%s%%" % [bonus.sub(BigNumber.from_value(1.0)).scale(100.0).to_display()]

var potency_cost_text: String:
	get: return App.upgrade_system.cost(_potency_id).to_display() if App.upgrade_system.has_def(_potency_id) else "--"

var potency_can_buy: bool:
	get: return App.upgrade_system.can_buy(_potency_id, _player_data.nutrients)

# --- Synergy track ---
var synergy_level_text: String:
	get: return "Lv %d" % App.upgrade_system.level(_synergy_id)

var synergy_header_text: String:
	get:
		var mult := App.node_synergy_external_multiplier(_node_id_key())
		return "+%s%% / manual node:" % [App.upgrade_system.next_level_delta(_synergy_id).mul(mult).scale(100.0).to_display()]

var synergy_accumulated_text: String:
	get:
		var bonus := App.node_synergy_bonus(_node_id_key())
		return "now +%s%%" % [bonus.sub(BigNumber.from_value(1.0)).scale(100.0).to_display()]

var synergy_cost_text: String:
	get: return App.upgrade_system.cost(_synergy_id).to_display() if App.upgrade_system.has_def(_synergy_id) else "--"

var synergy_can_buy: bool:
	get: return App.upgrade_system.can_buy(_synergy_id, _player_data.nutrients)

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


func dispose() -> void:
	_player_data.nutrients_changed.disconnect(_on_nutrients_changed)
	_mycelium_data.node.auto_nodes_changed.disconnect(_on_auto_nodes_changed)
	_mycelium_data.node.manual_nodes_changed.disconnect(_on_manual_nodes_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)

# --- Commands (called by the View on user input) ---

func buy_upgrade() -> void:
	_mycelium_data.buy_upgrade()
	# Model signals will trigger the notifications below.

func buy_potency() -> bool:
	return App.upgrade_system.buy(_potency_id, _player_data)

func buy_synergy() -> bool:
	return App.upgrade_system.buy(_synergy_id, _player_data)

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_BUY)
	_notify(PROP_BUY_TEXT)  # cost affordability display may change
	_notify(PROP_POTENCY_CAN_BUY)
	_notify(PROP_SYNERGY_CAN_BUY)

func _on_auto_nodes_changed(_auto_nodes: BigNumber) -> void:
	_notify(PROP_OWNED_NODE_TEXT)
	_notify(PROP_PRODUCTION_TEXT)

func _on_manual_nodes_changed(_manual_nodes: int) -> void:
	_notify(PROP_MANUAL_NODE_TEXT)
	_notify(PROP_OWNED_NODE_TEXT)
	_notify(PROP_PRODUCTION_TEXT)
	_notify(PROP_BUY_TEXT)
	_notify(PROP_CAN_BUY)

func _on_upgrades_changed() -> void:
	_notify(PROP_PRODUCTION_TEXT)
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

# --- Formatting ---

func _format_number(value: BigNumber) -> String:
	return value.to_display()

func _node_id_key() -> StringName:
	return StringName(str(_mycelium_data.node.node_id))

func _scaled_production() -> BigNumber:
	var raw := _mycelium_data.node.auto_nodes.add(BigNumber.from_value(_mycelium_data.node.manual_nodes))
	return raw.mul(_bonus_production())

func _bonus_production() -> BigNumber:
	return App.node_production_bonus(StringName(str(_mycelium_data.node.node_id)))
