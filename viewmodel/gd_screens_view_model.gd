class_name ScreensViewModel
extends ViewModel
## VIEWMODEL: adapts PlayerData for display and exposes commands.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.

const PROP_SCREEN_CHANGED_TEXT := &"screen_changed"
## The set of nav tabs changed, i.e. a biome unlock revealed one. Separate from
## PROP_SCREEN_CHANGED_TEXT so the view can rebuild the buttons without tearing
## down and respawning the screen that is up.
const PROP_NAV_CHANGED := &"nav_changed"

var _model: ScreensData

# --- View -> ViewModel ---
func set_current_screen(type: ScreenTypes.Types) -> void:
	_model.current_screen = type

# --- Read-only display properties bound by the View ---

var current_screen: ScreenTypes.Types:
	get: return _model.current_screen

## Currencies the resource bar should show for the screen that is up right now.
var current_currencies: Array[CurrencyDef]:
	get:
		var definition := get_screen_data(_model.current_screen)
		if definition == null:
			return []
		return definition.currencies

func get_screen_data(type: ScreenTypes.Types) -> ScreenDefinition:
	return _model.screen_data.get(type)

## The nav tabs to show right now, in bottom-bar order, already filtered to the
## ones the player has reached and the ones with a definition authored.
##
## The unlocked check is dynamic - a biome unlock reveals a tab mid-session - so
## it belongs here rather than being asked of App from the view, and the two
## reasons a tab can be absent are folded together so the view has one list to
## walk rather than two conditions to remember.
var visible_screens: Array[ScreenTypes.Types]:
	get:
		var visible: Array[ScreenTypes.Types] = []
		for type in ScreenTypes.NAV_ORDER:
			if not App.is_screen_unlocked(type):
				continue
			if _model.screen_data.get(type) == null:
				continue
			visible.append(type)
		return visible

# --- Lifecycle ---

func _init(model: ScreensData) -> void:
	_model = model
	_model.screen_changed.connect(_on_screen_changed)
	# Unlocking a biome can reveal a nav tab, which is the only thing that
	# changes visible_screens after startup.
	App.biomes_data.biome_unlocked.connect(_on_biome_unlocked)

func dispose() -> void:
	_model.screen_changed.disconnect(_on_screen_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_biome_unlocked)

# --- Model -> notification plumbing ---

func _on_screen_changed(_type: ScreenTypes.Types) -> void:
	_notify(PROP_SCREEN_CHANGED_TEXT)

func _on_biome_unlocked(_key: StringName) -> void:
	_notify(PROP_NAV_CHANGED)
