class_name MyceliumNodeViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_UPGRADE_TEXT := &"upgrade_button_text"
const PROP_MANUAL_NODE_TEXT := &"manual_node_text"
const PROP_AUTO_NODE_TEXT := &"auto_node_text"
const PROP_CAN_BUY := &"can_buy_upgrade"

var _player_data: PlayerData
var _mycelium_data: MyceliumData

# --- Read-only display properties the View binds to ---
var upgrade_button_text: String:
	get:
		return "Buy %s - %s" % [_mycelium_data._node.name, _format_number(_mycelium_data.upgrade_cost())]

var manual_node_text: String:
	get:
		return "Manual: %d" % [_mycelium_data._node.manual_nodes]

var auto_node_text: String:
	get:
		return "Auto: %s" % [_mycelium_data._node.auto_nodes._to_string()]

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
	

func dispose() -> void:
	_player_data.nutrients_changed.disconnect(_on_nutrients_changed)
	_mycelium_data._node.auto_nodes_changed.disconnect(_on_auto_nodes_changed)
	_mycelium_data._node.manual_nodes_changed.disconnect(_on_manual_nodes_changed)

# --- Commands (called by the View on user input) ---

func buy_upgrade() -> void:
	_mycelium_data.buy_upgrade()
	# Model signals will trigger the notifications below.

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_CAN_BUY)
	_notify(PROP_UPGRADE_TEXT)  # cost affordability display may change

func _on_auto_nodes_changed(_auto_nodes: BigNumber) -> void:
	_notify(PROP_UPGRADE_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_AUTO_NODE_TEXT)
	
func _on_manual_nodes_changed(_manual_nodes: int) -> void:
	_notify(PROP_UPGRADE_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_MANUAL_NODE_TEXT)

# --- Formatting (replace with your BigNumber formatter) ---

func _format_number(value: BigNumber) -> String:
	return value._to_string()
