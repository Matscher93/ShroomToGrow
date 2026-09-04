class_name ProjectViewModel
extends ViewModel
## VIEWMODEL: one well project's card - how often it has been funded, what the
## next funding costs in water, and which of its boons that funding has opened.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.
##
## One per authored project, built once and owned by App: every card repaints on
## any water change, so they all need live state at the same time.

const PROP_PROJECT_CHANGED := &"project_changed"

var _id: StringName
var _def: ProjectDef

# --- View -> ViewModel ---

func invest() -> void:
	App.invest_project(_id)

# --- Read-only display properties bound by the View ---

var display_name: String:
	get: return _def.display_name

## Expanded against the project's own boons, indexed - a project has no effect of
## its own, and the line under its name is a summary of the rungs beneath it, so
## {value:3} is how it quotes the deepest one without typing the number twice.
var description: String:
	get: return EffectLabel.expand(_def.description, _boon_effects(), _def.max_level)

## Against the ceiling the depth perk has opened so far, not the authored one: a
## project the perk has widened would otherwise read as maxed while it is still
## buyable.
var level_text: String:
	get:
		var ceiling := App.project_max_level(_id)
		if ceiling <= 0:
			return "Funded %d times" % App.project_level(_id)
		return "Lv %d / %d" % [App.project_level(_id), ceiling]

## A locked project reads as progress towards its gate rather than as a bare
## requirement, the same way a locked biome upgrade does: the number it is
## waiting on is one the player moves by funding anything at all.
var cost_text: String:
	get:
		if not is_unlocked:
			return "Locked - %d / %d well levels" % [App.well_total_levels(),
				App.project_min_levels(_id)]
		if is_maxed:
			return "-"
		return "%s water" % App.project_cost(_id).to_display()

## How many of the ladder's boons are paying out, which is the number the player
## is actually funding towards.
var boons_text: String:
	get:
		var open := 0
		for i in _def.boons.size():
			if App.is_project_boon_unlocked(_id, i):
				open += 1
		return "%d / %d boons" % [open, _def.boons.size()]

var is_maxed: bool:
	get: return App.is_project_maxed(_id)

## False until the well has been funded far enough overall. The card stays
## visible: a hidden one gives the player nothing to work towards.
var is_unlocked: bool:
	get: return App.is_project_unlocked(_id)

var can_invest: bool:
	get: return App.can_invest_project(_id)

## One row per boon, in ladder order. A locked row says what it is waiting for
## rather than being left out - the ladder is the reason to keep funding, so
## hiding its rungs hides the point of the project.
##
## An open rung shows what it is worth and what one more funding adds, not the
## level it sits at: the level is a means, and the project's own level is already
## on the card. What the player is choosing between is the bonus.
##
## The row carries the stat name rather than an icon id: which picture stands for
## an area is the View's call, and a ViewModel that knew about icon ordinals
## would be holding a piece of the shader.
##
## Keys: name, description, detail, rate, stat, unlocked.
func boon_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in _def.boons.size():
		var boon := _def.boons[i]
		var unlocked := App.is_project_boon_unlocked(_id, i)
		var detail := ""
		var rate := ""
		if unlocked:
			detail = _amount_text(boon.effect, App.project_boon_amount(_id, i))
			rate = _rate_text(boon, i)
		else:
			detail = "Opens at Lv %d" % boon.unlock_at_level
		rows.append({
			"name": boon.display_name,
			# A boon carries one effect and its own ceiling is the project's, so the
			# rung's levels are what {total} would be measured against - not a number
			# the boon knows. max_level is left at 0 rather than guessed at.
			"description": EffectLabel.expand(boon.description, [boon.effect]),
			"detail": detail,
			"rate": rate,
			"stat": boon.effect.stat if boon.effect != null else &"",
			"unlocked": unlocked,
		})
	return rows

# --- Lifecycle ---

func _init(project_id: StringName, def: ProjectDef) -> void:
	_id = project_id
	_def = def
	App.player_data.water_changed.connect(_on_water_changed)
	# Funding anything moves every card: it is what pays for this project's next
	# level and what opens the ones still gated.
	App.project_upgrade_system.upgrades_changed.connect(_on_changed)
	# The depth perk raises every project's ceiling, so a card showing "Lv 60/60"
	# becomes buyable again the moment it is bought - a screen away.
	App.prestige_upgrade_system.upgrades_changed.connect(_on_changed)

func dispose() -> void:
	App.player_data.water_changed.disconnect(_on_water_changed)
	App.project_upgrade_system.upgrades_changed.disconnect(_on_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_changed)

# --- Model -> notification plumbing ---

func _on_water_changed(_value: BigNumber) -> void:
	_notify(PROP_PROJECT_CHANGED)

func _on_changed() -> void:
	_notify(PROP_PROJECT_CHANGED)

# --- Formatting ---

## The boons' effects in authored order, so a {value:N} in a description names
## the same rung the card lists Nth.
func _boon_effects() -> Array:
	var effects: Array = []
	for boon in _def.boons:
		effects.append(boon.effect)
	return effects


## A boon's magnitude in the shape its op actually applies in. Unlike the biome
## upgrade card, which can hardcode "+x%" because every biome upgrade is
## INCREASED, a project's rungs span all three ops - printing a MORE boon as a
## percentage would show "+8%" for what is really a x1.08, and an ADD boon on
## tick_rate as "+-0.6%" for what is really six tenths of a second.
##
## Units are deliberately absent: the boon's own description carries them, and
## nothing here can know that water_rate is ticks while tick_rate is seconds.
func _amount_text(effect: UpgradeEffectDef, amount: BigNumber) -> String:
	if effect == null:
		return ""
	match effect.op:
		UpgradeEffectDef.Op.MORE:
			return "x%s" % BigNumber.from_value(1.0).add(amount).to_display(2)
		UpgradeEffectDef.Op.ADD:
			return _signed(amount.to_display(2))
		_:
			return "%s%%" % _signed(amount.scale(100.0).to_display())

## What one more funding is worth on this rung, or "max" once the rung's
## max_magnitude ceiling means it is worth nothing.
##
## A MORE boon reads its authored rate rather than the level-to-level difference:
## its levels compound, so the difference grows with the level while the factor
## each one multiplies by stays put. Reporting the difference would advertise a
## rate that climbs on its own, which is not what the next funding buys. Same
## call BoostViewModel.next_level_text makes.
func _rate_text(boon: ProjectBoonDef, index: int) -> String:
	if boon.effect == null:
		return ""
	var delta := App.project_boon_next_level_delta(_id, index)
	# Checked before the op branch, and off the delta rather than off the level:
	# a boon on its max_magnitude ceiling gains nothing from the next funding, and
	# a MORE boon reading its authored rate would go on claiming its factor
	# forever without this.
	if delta.mantissa == 0.0:
		return "max"
	if boon.effect.op == UpgradeEffectDef.Op.MORE:
		# The authored rate, worded the same way the boon's own description words
		# it - the two sit on one card and a x1.045 in the sentence beside a
		# "x1.04/lvl" underneath would read as two different rungs.
		return "%s/lvl" % EffectLabel.value_of(boon.effect)
	return "%s/lvl" % _amount_text(boon.effect, delta)

## to_display() carries a minus of its own but never a plus, and a bare "8%" next
## to a "-0.05" reads as though only one of them has a direction.
func _signed(text: String) -> String:
	return text if text.begins_with("-") else "+%s" % text

## Three decimals with the trailing zeros dropped, so the shallow rungs read
## "x1.025" instead of collapsing to "x1.02" while the round ones stay "x1.03".
## Two decimals was enough while every compounding rate was a clean hundredth;
## the additive rungs converted into halves of one.
func _trimmed(value: float) -> String:
	var text := "%.3f" % value
	if not text.contains("."):
		return text
	return text.rstrip("0").rstrip(".")
