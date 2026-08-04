class_name BiomeSequenceViewModel
extends ViewModel
## VIEWMODEL: one biome's recorded upgrade sequence, as shown in its section of
## the Crystal Caves Upgrades tab. Owns formatting and derived state.
## References the model, never a Node.
##
## One instance per biome, built once in App._ready() and owned for the app's
## lifetime, mirroring App.biome_vms: every section needs live state at once.

const PROP_SEQUENCE_CHANGED := &"sequence_changed"
const PROP_SUMMARY_TEXT := &"summary_text"
const PROP_STEP_AMOUNT := &"step_amount_text"
const PROP_AUTO_UNLOCK := &"auto_unlock_text"

## How many steps one slot press records. 0 is "Max", meaning fill the upgrade's
## remaining cap. Cycled rather than typed, so a single tap changes it on touch.
const STEP_AMOUNTS: Array[int] = [1, 5, 10, 0]

## Steps shown at once. A finished sequence runs to dozens of entries, and one
## unbroken list buries the slot grid and the next biome's section under it.
const PAGE_SIZE := 10

var _key: StringName
var _def: BiomeDef
## Kept on the VM rather than the section, because App owns VMs for the app's
## lifetime while the screen is respawned on every tab switch. Not saved: they
## are view state, not progress.
var _amount_index := 0
var _page := 0

# --- Static display properties (fixed for this biome's lifetime) ---
var biome_key: StringName:
	get: return _key

var display_name: String:
	get: return _def.display_name

var biome_color: Color:
	get: return _def.biome_color

# --- Read-only display properties bound by the View ---
var is_unlocked: bool:
	get: return App.biomes_data.is_unlocked(_key)

var step_count: int:
	get: return App.automation_data.sequence_for(_key, _def.upgrade_ids).size()

var points_available: int:
	get: return App.biome_available_points(_key)

var summary_text: String:
	get:
		var steps := step_count
		if steps == 0:
			return "No sequence yet - %d pts waiting" % [points_available]
		return "%d step%s - %d pts available" % [steps, "" if steps == 1 else "s",
			points_available]

## True once the automation that replays sequences is owned and switched on.
## Until then a sequence is authored but dormant, which the section says out loud
## rather than leaving the player waiting on nothing.
var is_replaying: bool:
	get: return App.is_automation_active(_replay_automation_id())

var status_text: String:
	get:
		if step_count == 0:
			return ""
		if not App.is_automation_owned(_replay_automation_id()):
			return "Buy Cavern Steward to replay this"
		if not is_replaying:
			return "Cavern Steward is switched off"
		return "Replaying"

## One row per step, in replay order: {index, id, name, done, reachable}.
##
## `done` marks the steps the biome has already bought, which is what the
## automation skips over when it picks up a sequence again after a prestige.
##
## `reachable` is false when the step sits earlier than its own point gate. New
## steps can never be appended in that state, but removing or reordering existing
## ones can push a later step above its gate, and the automation would then skip
## it forever without saying so. The row says so instead.
func sequence_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen := {}
	var index := 0
	for id: StringName in App.automation_data.sequence_for(_key, _def.upgrade_ids):
		var count: int = seen.get(id, 0) + 1
		seen[id] = count
		var upgrade_def := App.biome_upgrade_system.def(id)
		rows.append({
			"index": index,
			"id": id,
			"name": upgrade_def.display_name if upgrade_def != null else String(id),
			"done": count <= App.biome_upgrade_system.level(id),
			"reachable": _gate_for(id) <= index,
		})
		index += 1
	return rows

## The biome's ten upgrade ids in grid order, so the section's slots line up
## one-for-one with the same biome's card on the Biomes screen.
func upgrade_ids() -> Array[StringName]:
	return _def.upgrade_ids

func upgrade_name(id: StringName) -> String:
	var upgrade_def := App.biome_upgrade_system.def(id)
	return upgrade_def.display_name if upgrade_def != null else String(id)

## How many levels of this upgrade the sequence currently asks for, i.e. how many
## times it has been tapped in.
func recorded_count(id: StringName) -> int:
	var count := 0
	for step: StringName in App.automation_data.sequence_for(_key, _def.upgrade_ids):
		if step == id:
			count += 1
	return count

## Recorded levels over the upgrade's cap.
##
## Deliberately *not* the level the biome has actually bought, which is what the
## same slot shows on the Biomes screen. These sections are about the sequence
## being written, so their numbers have to move when the player edits it, not
## when a run happens to buy something. Reading purchases here made the two
## screens look like one control with two contradictory readings.
func upgrade_slot_text(id: StringName) -> String:
	var upgrade_def := App.biome_upgrade_system.def(id)
	var count := recorded_count(id)
	if upgrade_def == null or upgrade_def.max_level <= 0:   # 0 = infinite
		return "%d" % count
	return "%d/%d" % [count, upgrade_def.max_level]

## True once the sequence asks for this upgrade at all. Drives the dimming, so a
## glance at the grid shows which upgrades the recording covers.
func is_recorded(id: StringName) -> bool:
	return recorded_count(id) > 0

## Points the biome must already have spent before this upgrade unlocks.
func _gate_for(id: StringName) -> int:
	var upgrade_def := App.biome_upgrade_system.def(id)
	return upgrade_def.min_biome_points_spent if upgrade_def != null else 0

## Whether the sequence can take this upgrade as its next step.
##
## Gating is simulated off the sequence itself rather than off the run: every
## step spends exactly one point, so by the time the automation reaches step
## n it has spent n points, and a step whose gate is above that could never be
## bought when its turn came. Checking the *current* run instead would let the
## player record a step that works today and silently dies after a prestige.
func can_record(id: StringName) -> bool:
	return record_blocked_reason(id).is_empty()

## Why this upgrade cannot be appended right now, or empty when it can. Doubles
## as the slot's tooltip, so a disabled slot says what it is waiting for.
func record_blocked_reason(id: StringName) -> String:
	var upgrade_def := App.biome_upgrade_system.def(id)
	if upgrade_def != null and upgrade_def.max_level > 0 \
			and recorded_count(id) >= upgrade_def.max_level:
		return "Already at its cap of %d" % [upgrade_def.max_level]
	var gate := _gate_for(id)
	var recorded := step_count
	if gate > recorded:
		return "Unlocks after %d more step%s" % [gate - recorded,
			"" if gate - recorded == 1 else "s"]
	return ""

# --- Auto-unlock ---

## A starter biome never relocks, so there is nothing here to sell it.
var offers_auto_unlock: bool:
	get: return not _def.always_unlocked

var has_auto_unlock: bool:
	get: return App.has_biome_auto_unlock(_key)

var can_buy_auto_unlock: bool:
	get: return App.can_buy_biome_auto_unlock(_key)

var auto_unlock_text: String:
	get:
		if not offers_auto_unlock:
			return "Never relocks"
		if has_auto_unlock:
			return "Reopens itself every run"
		return "Reopen after sporation"

var auto_unlock_cost_text: String:
	get: return App.biome_auto_unlock_cost(_key).to_display()

# --- Pagination ---

var page_count: int:
	get: return maxi(1, ceili(float(step_count) / float(PAGE_SIZE)))

var page: int:
	get: return clampi(_page, 0, page_count - 1)

var page_text: String:
	get: return "%d / %d" % [page + 1, page_count]

## Hidden entirely for a sequence that fits on one page, so a short recording
## carries no controls it does not need.
var has_pages: bool:
	get: return page_count > 1

var can_page_back: bool:
	get: return page > 0

var can_page_forward: bool:
	get: return page < page_count - 1

## The steps on the current page. Each row keeps its absolute index, so reorder
## and remove still address the sequence rather than the page.
func page_rows() -> Array[Dictionary]:
	var all := sequence_rows()
	var rows: Array[Dictionary] = []
	var start := page * PAGE_SIZE
	for i in range(start, mini(start + PAGE_SIZE, all.size())):
		rows.append(all[i])
	return rows

func page_back() -> void:
	_show_page(page - 1)

func page_forward() -> void:
	_show_page(page + 1)

func _show_page(target: int) -> void:
	var clamped := clampi(target, 0, page_count - 1)
	if clamped == _page:
		return
	_page = clamped
	_notify(PROP_SEQUENCE_CHANGED)

## Brings the page holding `index` into view, so an edit is never invisible.
func _reveal_index(index: int) -> void:
	@warning_ignore("integer_division")
	_show_page(index / PAGE_SIZE)

# --- Step amount ---

var step_amount: int:
	get: return STEP_AMOUNTS[_amount_index]

var step_amount_text: String:
	get: return "Max" if step_amount <= 0 else "x%d" % [step_amount]

## Levels of this upgrade the sequence could still take, or -1 when the upgrade
## has no cap at all.
func _remaining_capacity(id: StringName) -> int:
	var upgrade_def := App.biome_upgrade_system.def(id)
	if upgrade_def == null or upgrade_def.max_level <= 0:
		return -1
	return maxi(0, upgrade_def.max_level - recorded_count(id))

## How many steps the next press on this slot would actually record. Below the
## chosen amount when the upgrade's cap is closer than that, and zero when the
## slot is blocked outright.
func steps_to_append(id: StringName) -> int:
	if not can_record(id):
		return 0
	var remaining := _remaining_capacity(id)
	if step_amount <= 0:
		# "Max" fills the cap. An uncapped upgrade has no cap to fill, so it
		# takes a single step, the same as x1.
		return remaining if remaining > 0 else 1
	return step_amount if remaining < 0 else mini(step_amount, remaining)

# --- Commands (called by the View on input) ---

func cycle_step_amount() -> void:
	_amount_index = (_amount_index + 1) % STEP_AMOUNTS.size()
	_notify(PROP_STEP_AMOUNT)
	# The slot captions advertise how many a press would add, so they move too.
	_notify(PROP_SEQUENCE_CHANGED)

## Records as many steps as the current amount allows. Returns how many landed.
func append_step(id: StringName) -> int:
	var count := steps_to_append(id)
	if count <= 0:
		return 0
	App.automation_data.append_to_sequence(_key, id, count)
	# New steps land at the end, so follow them there rather than leaving the
	# player on an earlier page wondering whether the tap registered.
	_reveal_index(step_count - 1)
	return count

func remove_step(index: int) -> bool:
	return App.automation_data.remove_from_sequence(_key, index)

## Nudging a step across a page boundary follows it, so it can be nudged again
## without hunting for the page it landed on.
func move_step_up(index: int) -> bool:
	if not App.automation_data.move_sequence_entry(_key, index, index - 1):
		return false
	_reveal_index(index - 1)
	return true

func move_step_down(index: int) -> bool:
	if not App.automation_data.move_sequence_entry(_key, index, index + 1):
		return false
	_reveal_index(index + 1)
	return true

func clear() -> void:
	App.automation_data.clear_sequence(_key)

func buy_auto_unlock() -> bool:
	return App.buy_biome_auto_unlock(_key)

# --- Lifecycle ---

func _init(key: StringName, def: BiomeDef) -> void:
	_key = key
	_def = def
	App.automation_data.sequence_changed.connect(_on_sequence_changed)
	App.player_data.crystals_changed.connect(_on_crystals_changed)
	App.biomes_data.auto_unlock_changed.connect(_on_auto_unlock_changed)
	App.biomes_data.biome_unlocked.connect(_on_replay_state_changed.unbind(1))
	App.automation_data.levels_changed.connect(_on_replay_state_changed)
	App.automation_data.enabled_changed.connect(_on_replay_state_changed.unbind(1))
	# A purchase moves both the done marks and the points left to spend.
	App.biome_upgrade_system.upgrades_changed.connect(_on_replay_state_changed)
	App.prestige_upgrade_system.upgrades_changed.connect(_on_replay_state_changed)

func dispose() -> void:
	App.automation_data.sequence_changed.disconnect(_on_sequence_changed)
	App.player_data.crystals_changed.disconnect(_on_crystals_changed)
	App.biomes_data.auto_unlock_changed.disconnect(_on_auto_unlock_changed)
	App.biomes_data.biome_unlocked.disconnect(_on_replay_state_changed.unbind(1))
	App.automation_data.levels_changed.disconnect(_on_replay_state_changed)
	App.automation_data.enabled_changed.disconnect(_on_replay_state_changed.unbind(1))
	App.biome_upgrade_system.upgrades_changed.disconnect(_on_replay_state_changed)
	App.prestige_upgrade_system.upgrades_changed.disconnect(_on_replay_state_changed)

# --- Model -> notification plumbing ---

func _replay_automation_id() -> StringName:
	return AutomationSystem.SEQUENCE_AUTOMATION_ID

func _on_sequence_changed(key: StringName) -> void:
	if key != _key:
		return
	# Removing or clearing can drop the page count below where the player was
	# standing, which would otherwise leave them on an empty page past the end.
	_page = page
	_notify(PROP_SEQUENCE_CHANGED)
	_notify(PROP_SUMMARY_TEXT)

func _on_replay_state_changed() -> void:
	_notify(PROP_SEQUENCE_CHANGED)
	_notify(PROP_SUMMARY_TEXT)
	_notify(PROP_AUTO_UNLOCK)

## Affordability of the auto-unlock moves with the crystal balance. Note this is
## only about affordability: the purchase itself announces through
## auto_unlock_changed, because a big balance can swallow the cost without the
## currency ever reporting a change.
func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_AUTO_UNLOCK)

func _on_auto_unlock_changed(key: StringName) -> void:
	if key != _key:
		return
	_notify(PROP_AUTO_UNLOCK)
