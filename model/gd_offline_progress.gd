class_name OfflineProgress
extends RefCounted
## MODEL: the offline-gap arithmetic, split out of SaveManager so the boundary
## behaviour is testable without a wall clock, a scene tree or a live App.
##
## Pure functions only. SaveManager owns the timestamps and the timesliced loop
## that drives these numbers.

const MIN_SECONDS := 60.0
const MAX_SECONDS := 86400.0  # 24h cap on offline income collection

## Whether a gap is long enough to simulate and show a popup for. Every caller
## must use this rather than comparing against MIN_SECONDS itself: arming and
## polling used to test the same boundary with different operators, so a gap of
## exactly MIN_SECONDS was armed and then never consumed.
static func is_gap_worth_showing(elapsed: float) -> bool:
	return elapsed > MIN_SECONDS

## Clamps a gap to the collection cap.
static func capped(elapsed: float) -> float:
	return minf(elapsed, MAX_SECONDS)

## Ticks a gap is worth at the current tick duration. One full interval has to
## elapse before the first offline tick lands - matching the live timer, where
## reopening the app exactly one interval later is worth zero - so the count is
## one short of the intervals the gap spans. This is the count the catch-up loop
## runs *and* the total the progress bar counts towards, so the two cannot drift
## apart.
static func simulated_ticks(elapsed: float, tick_duration: float) -> int:
	if tick_duration <= 0.0:
		return 0
	return maxi(0, int(ceil(elapsed / tick_duration)) - 1)
