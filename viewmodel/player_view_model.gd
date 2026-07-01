class_name PlayerViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_GOLD_TEXT := &"gold_text"
const PROP_UPGRADE_TEXT := &"upgrade_button_text"
const PROP_CAN_BUY := &"can_buy_upgrade"

var _model: PlayerData

# --- Read-only display properties the View binds to ---

var gold_text: String:
	get:
		return "Gold: %s" % _format_number(_model.gold)

var upgrade_button_text: String:
	get:
		return "Upgrade (Lv %d) — %s" % [_model.upgrade_level, _format_number(_model.upgrade_cost())]

var can_buy_upgrade: bool:
	get:
		return _model.can_afford_upgrade()

# --- Lifecycle ---

func _init(model: PlayerData) -> void:
	_model = model
	_model.gold_changed.connect(_on_gold_changed)
	_model.upgrade_level_changed.connect(_on_upgrade_changed)

func dispose() -> void:
	_model.gold_changed.disconnect(_on_gold_changed)
	_model.upgrade_level_changed.disconnect(_on_upgrade_changed)

# --- Commands (called by the View on user input) ---

func buy_upgrade() -> void:
	_model.buy_upgrade()
	# Model signals will trigger the notifications below.

# --- Model -> notification plumbing ---

func _on_gold_changed(_value: float) -> void:
	_notify(PROP_GOLD_TEXT)
	_notify(PROP_CAN_BUY)
	_notify(PROP_UPGRADE_TEXT)  # cost affordability display may change

func _on_upgrade_changed(_level: int) -> void:
	_notify(PROP_UPGRADE_TEXT)
	_notify(PROP_CAN_BUY)

# --- Formatting (replace with your BigNumber formatter) ---

func _format_number(value: float) -> String:
	if value >= 1_000_000.0:
		return "%.2fM" % (value / 1_000_000.0)
	if value >= 1_000.0:
		return "%.2fK" % (value / 1_000.0)
	return "%.0f" % value
