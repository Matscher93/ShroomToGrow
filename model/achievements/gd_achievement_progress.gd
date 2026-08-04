class_name AchievementProgress
extends RefCounted
## MODEL: pure state. How many tiers of each achievement have been claimed, and
## how many are sitting completed waiting to be. Knows nothing about goals,
## rewards or UI.
##
## Completing and claiming are separate on purpose: an idle game is played in
## bursts, so tiers keep banking up while the player is away and none of that
## progress is lost by not watching. Only claiming pays out.
##
## Deliberately has no reset(): both counts are permanent and survive prestige,
## which is what makes crystals a meta-currency rather than a run currency.

var tiers: Dictionary = {}      # StringName -> int, claimed
var unclaimed: Dictionary = {}  # StringName -> int, completed and waiting

## Tiers already claimed. This is the permanent record, and what Crystal Caves
## levels off.
func tier(id: StringName) -> int:
	return tiers.get(id, 0)

func unclaimed_count(id: StringName) -> int:
	return unclaimed.get(id, 0)

## Bars crossed in total, claimed or not. This is the index of the goal the
## player is currently working towards.
func completed(id: StringName) -> int:
	return tier(id) + unclaimed_count(id)

func mark_completed(id: StringName) -> void:
	unclaimed[id] = unclaimed_count(id) + 1

## Moves one waiting tier into the claimed count. False when there was nothing
## to claim, so the caller knows not to pay out.
func claim(id: StringName) -> bool:
	if unclaimed_count(id) <= 0:
		return false
	unclaimed[id] = unclaimed_count(id) - 1
	tiers[id] = tier(id) + 1
	return true

## Sum of every achievement's claimed tiers. Feeds PlayerData.achievement_tiers.
func total_tiers() -> int:
	var total := 0
	for id in tiers:
		total += tiers[id]
	return total

func total_unclaimed() -> int:
	var total := 0
	for id in unclaimed:
		total += unclaimed[id]
	return total

func to_save() -> Dictionary:
	var tiers_out := {}
	for id in tiers:
		if tiers[id] > 0:
			tiers_out[String(id)] = tiers[id]
	var unclaimed_out := {}
	for id in unclaimed:
		if unclaimed[id] > 0:
			unclaimed_out[String(id)] = unclaimed[id]
	return {"tiers": tiers_out, "unclaimed": unclaimed_out}

## Applies a save dict onto this instance in place, so AchievementSystem's
## reference stays valid. Same reason PlayerData.load_from_save exists.
func load_from_save(d: Dictionary) -> void:
	tiers.clear()
	unclaimed.clear()
	# Saves written before claiming existed stored a flat id -> tier map, with
	# every tier already paid out. Read those as fully claimed rather than
	# dropping them, and rather than handing the player a second payout.
	if not d.is_empty() and not d.has("tiers") and not d.has("unclaimed"):
		for key in d:
			tiers[StringName(key)] = int(d[key])
		return
	var tiers_in: Dictionary = d.get("tiers", {})
	for key in tiers_in:
		tiers[StringName(key)] = int(tiers_in[key])
	var unclaimed_in: Dictionary = d.get("unclaimed", {})
	for key in unclaimed_in:
		unclaimed[StringName(key)] = int(unclaimed_in[key])

static func from_save(d: Dictionary) -> AchievementProgress:
	var progress := AchievementProgress.new()
	progress.load_from_save(d)
	return progress
