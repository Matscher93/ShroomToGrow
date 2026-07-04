class_name MyceliumNodesViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_GOLD_TEXT := &"gold_text"
const PROP_UPGRADE_TEXT := &"upgrade_button_text"
const PROP_CAN_BUY := &"can_buy_upgrade"

var _model: PlayerData
var node_level: int = 0

# --- Read-only display properties the View binds to ---

var gold_text: String:
	get:
		return "%s" % _format_number(_model.nutrients)

var upgrade_button_text: String:
	get:
		return "Upgrade (Lv %d) — %s" % [_model.nodes[node_level].manual_nodes, _format_number(_model.upgrade_cost(node_level))]

var can_buy_upgrade: bool:
	get:
		return _model.can_afford_upgrade(node_level)

# --- Lifecycle ---

func _init(model: PlayerData) -> void:
	_model = model
	_model.nutrients_changed.connect(_on_nutrients_changed)


func dispose() -> void:
	_model.nutrients_changed.disconnect(_on_nutrients_changed)

# --- Commands (called by the View on user input) ---

func buy_upgrade() -> void:
	_model.buy_upgrade(node_level)
	# Model signals will trigger the notifications below.

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_GOLD_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_UPGRADE_TEXT)  # cost affordability display may change

func _on_upgrade_changed(_level: int) -> void:
	_notify(PROP_UPGRADE_TEXT)
	_notify(PROP_CAN_BUY)

# --- Formatting (replace with your BigNumber formatter) ---

func _format_number(value: BigNumber) -> String:
	return value._to_string()
