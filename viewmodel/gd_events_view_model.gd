class_name EventsViewModel
extends ViewModel
## VIEWMODEL: the events sheet and the top bar's bell chip - what is on offer and
## whether answering it is affordable.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One VM behind both surfaces on purpose, the same call GrowthViewModel makes:
## the badge is exactly "the sheet has something in it", and computing that in two
## places is how the two drift.
##
## Built once and owned by App: the chip is on screen at all times, so this always
## needs live state.

const PROP_EVENTS_CHANGED := &"events_changed"

# --- View -> ViewModel ---

func collect(instance_id: int) -> void:
	App.collect_event(instance_id)

func fulfil(instance_id: int) -> void:
	App.fulfil_event(instance_id)

func skip(instance_id: int) -> void:
	App.skip_event(instance_id)

# --- Read-only display properties bound by the View ---

var has_events: bool:
	get: return not App.events().is_empty()

## Drives the sheet's "All caught up" placeholder.
var is_empty: bool:
	get: return App.events().is_empty()

var badge_text: String:
	get: return "%d" % App.events().size()

var rows: Array[EventRow]:
	get:
		var out: Array[EventRow] = []
		for event in App.events():
			var row := _row(event)
			if row != null:
				out.append(row)
		return out

# --- Lifecycle ---

## The four currency signals are here as well as the queue's own: a Fulfil
## button's affordability flips with the balance, not only with what is on the
## board, and production moves the balance every tick.
func _init() -> void:
	App.events_data.events_changed.connect(_on_events_changed)
	App.player_data.nutrients_changed.connect(_on_events_changed.unbind(1))
	App.player_data.water_changed.connect(_on_events_changed.unbind(1))
	App.player_data.biomass_changed.connect(_on_events_changed.unbind(1))
	App.player_data.crystals_changed.connect(_on_events_changed.unbind(1))

func dispose() -> void:
	App.events_data.events_changed.disconnect(_on_events_changed)
	App.player_data.nutrients_changed.disconnect(_on_events_changed.unbind(1))
	App.player_data.water_changed.disconnect(_on_events_changed.unbind(1))
	App.player_data.biomass_changed.disconnect(_on_events_changed.unbind(1))
	App.player_data.crystals_changed.disconnect(_on_events_changed.unbind(1))

# --- Model -> notification plumbing ---

func _on_events_changed() -> void:
	_notify(PROP_EVENTS_CHANGED)

# --- Row building ---

## Null for an instance whose def no longer exists - a save can carry one past a
## rename, and a card with no rule behind it must not reach the sheet.
func _row(event: Dictionary) -> EventRow:
	var def := App.event_def(event["def_id"])
	if def == null:
		return null
	var row := EventRow.new()
	row.instance_id = int(event["instance_id"])
	row.title = def.title
	row.description = def.description
	row.accent = def.accent_color
	row.kind = def.kind
	row.enabled = true
	match def.kind:
		RandomEventDef.Kind.BOON:
			_fill_boon(row, def, event)
		RandomEventDef.Kind.SPEND:
			_fill_spend(row, def, event)
		RandomEventDef.Kind.PROGRESS:
			_fill_progress(row, def, event)
	return row

func _fill_boon(row: EventRow, def: RandomEventDef, event: Dictionary) -> void:
	if def.pays_fertilizer():
		row.action_text = "Collect +%s fertilizer" % App.event_reward(event).to_display(0)
		return
	row.action_text = "Collect +%s %s" % [App.event_amount(def).to_display(),
		def.currency.currency_name.to_lower()]

func _fill_spend(row: EventRow, def: RandomEventDef, event: Dictionary) -> void:
	row.action_text = "Spend %s %s" % [App.event_amount(def).to_display(),
		def.currency.currency_name.to_lower()]
	row.reward_text = "+%s fertilizer" % App.event_reward(event).to_display(0)
	row.enabled = App.can_fulfil_event(event)

func _fill_progress(row: EventRow, def: RandomEventDef, event: Dictionary) -> void:
	var progress := int(event["progress"])
	row.reward_text = "+%s fertilizer" % App.event_reward(event).to_display(0)
	row.progress_text = "%d / %d ticks" % [progress, def.goal_ticks]
	row.progress_pct = 0.0 if def.goal_ticks <= 0 else clampf(
		float(progress) / float(def.goal_ticks), 0.0, 1.0)
