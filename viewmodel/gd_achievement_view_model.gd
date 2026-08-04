class_name AchievementViewModel
extends ViewModel
## VIEWMODEL: adapts one AchievementDef plus its live tier and progress for the
## Crystal Caves archive. Owns formatting and derived state.
## References the model, never a Node.
##
## One instance per achievement, built once in App._ready() and owned for the
## app's lifetime, mirroring App.perk_vms: every row needs live state at once, so
## per-selection VMs would not help.

const PROP_TIER_TEXT := &"tier_text"
const PROP_PROGRESS_TEXT := &"progress_text"
const PROP_PROGRESS_RATIO := &"progress_ratio"
const PROP_REWARD_TEXT := &"reward_text"
const PROP_IS_MAXED := &"is_maxed"
const PROP_CAN_CLAIM := &"can_claim"
const PROP_CLAIM_TEXT := &"claim_text"

var _def: AchievementDef

# --- Static display properties (fixed for this achievement's lifetime) ---
var id: StringName:
	get: return _def.id

var display_name: String:
	get: return _def.display_name

var description: String:
	get: return _def.description

var sort_order: int:
	get: return _def.sort_order

# --- Read-only display properties bound by the View ---
var tier: int:
	get: return App.achievement_tier(_def.id)

var unclaimed: int:
	get: return App.achievement_unclaimed(_def.id)

## The tier being worked towards, counting from 1, so the label matches what the
## progress bar underneath it is filling.
var tier_text: String:
	get:
		if is_maxed:
			return "MAX"
		return "Tier %d" % [tier + unclaimed + 1]

var is_maxed: bool:
	get: return App.is_achievement_maxed(_def)

var progress_text: String:
	get:
		if is_maxed:
			return "Completed %d times" % [tier + unclaimed]
		return "%s / %s" % [_format_measure(App.achievement_value(_def)),
			_format_measure(App.achievement_goal(_def))]

var progress_ratio: float:
	get: return App.achievement_progress_ratio(_def)

## What the goal currently being filled will pay, once it is claimed.
var reward_text: String:
	get:
		if is_maxed:
			return "--"
		return "+%s" % [App.achievement_reward(_def).to_display()]

var can_claim: bool:
	get: return unclaimed > 0

## Rewards are collected, never handed over automatically, so a tier completed
## while the player was away is still theirs to take.
var claim_text: String:
	get:
		if unclaimed <= 0:
			return "Claim"
		if unclaimed > 1:
			return "Claim +%s (%d)" % [App.achievement_claim_reward(_def).to_display(), unclaimed]
		return "Claim +%s" % [App.achievement_claim_reward(_def).to_display()]

# --- Lifecycle ---

func _init(def: AchievementDef) -> void:
	_def = def
	App.achievement_system.progress_changed.connect(_on_progress_changed)

func dispose() -> void:
	App.achievement_system.progress_changed.disconnect(_on_progress_changed)

# --- Commands (called by the View on input) ---

func claim() -> bool:
	return App.claim_achievement(_def.id)

# --- Formatting ---

## A counted stat below a thousand reads as "12 / 25", not "12.0 / 25.0":
## to_display()'s default decimal is noise on something that is only ever whole.
## Past a thousand the suffix earns its decimal back, since "1.5K" carries more
## than "2K".
func _format_measure(value: BigNumber) -> String:
	if AchievementDef.is_counted(_def.stat) and value.exponent < 3:
		return value.to_display(0)
	return value.to_display()

# --- Model -> notification plumbing ---

## AchievementSystem emits once per evaluate(), which App only runs when
## something an achievement measures actually moved.
func _on_progress_changed() -> void:
	_notify(PROP_TIER_TEXT)
	_notify(PROP_PROGRESS_TEXT)
	_notify(PROP_PROGRESS_RATIO)
	_notify(PROP_REWARD_TEXT)
	_notify(PROP_IS_MAXED)
	_notify(PROP_CAN_CLAIM)
	_notify(PROP_CLAIM_TEXT)
