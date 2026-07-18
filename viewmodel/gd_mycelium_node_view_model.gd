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

var _player_data: PlayerData
var _mycelium_data: MyceliumData

# --- Read-only display properties the View binds to ---
var buy_button_text: String:
	get:
		return "%s" % [_format_number(_mycelium_data.upgrade_cost())]

var manual_node_text: String:
	get:
		return "%d" % [_mycelium_data._node.manual_nodes]

var owned_node_text: String:
	get:
		return "%s" % [_mycelium_data._node.auto_nodes
						.add(BigNumber.from_value(_mycelium_data._node.manual_nodes))
						._to_string()]
		
var production_text: String:
	get:
		return "+%s / tick" % [_scaled_production()._to_string()]

var production_text_short: String:
	get:
		return "+%s/t" % [_scaled_production()._to_string()]

var can_buy_upgrade: bool:
	get:
		return _mycelium_data.can_afford_upgrade()

# --- Lifecycle ---

func _init(player_data: PlayerData, mycelium_data: MyceliumData) -> void:
	_player_data = player_data
	_player_data.nutrients_changed.connect(_on_nutrients_changed)
	_mycelium_data = mycelium_data
	_mycelium_data._node.auto_nodes_changed.connect(_on_auto_nodes_changed)
	_mycelium_data._node.manual_nodes_changed.connect(_on_manual_nodes_changed)
	App.upgrade_system.upgrades_changed.connect(_on_upgrades_changed)


func dispose() -> void:
	_player_data.nutrients_changed.disconnect(_on_nutrients_changed)
	_mycelium_data._node.auto_nodes_changed.disconnect(_on_auto_nodes_changed)
	_mycelium_data._node.manual_nodes_changed.disconnect(_on_manual_nodes_changed)
	App.upgrade_system.upgrades_changed.disconnect(_on_upgrades_changed)

# --- Commands (called by the View on user input) ---

func buy_upgrade() -> void:
	_mycelium_data.buy_upgrade()
	# Model signals will trigger the notifications below.

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_BUY)
	_notify(PROP_BUY_TEXT)  # cost affordability display may change

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

# --- Formatting ---

func _format_number(value: BigNumber) -> String:
	return value._to_string()

func _scaled_production() -> BigNumber:
	var raw := _mycelium_data._node.auto_nodes.add(BigNumber.from_value(_mycelium_data._node.manual_nodes))
	var bonus := App.upgrade_system.modify(&"node_production", BigNumber.from_value(1.0),
		App.resolve_context, [], StringName(str(_mycelium_data._node.node_id)))
	return raw.mul(bonus)
