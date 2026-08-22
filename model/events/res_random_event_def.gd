class_name RandomEventDef
extends Resource
## MODEL: static definition of one random event - what it offers, what it asks
## for, and what it pays.
##
## Amounts are authored as a rule rather than a number: an event rolled an hour
## ago and collected now is worth what the rule says of the *current* balance, so
## a queued offer never goes stale. That is also what keeps a saved event two ints
## wide - see EventsData.

## BOON pays a resource out for one tap. SPEND asks for a resource and pays
## fertilizer back. PROGRESS asks for nothing and pays out on its own once enough
## ticks have passed.
enum Kind { BOON, SPEND, PROGRESS }

@export var id: StringName

@export var title: String
@export_multiline var description: String

## Tints the card's rail, dot and action button.
@export var accent_color: Color = Color.WHITE

@export var kind: Kind = Kind.BOON

## The resource a BOON pays or a SPEND asks for. Null on a PROGRESS event, and on
## the BOON that pays fertilizer - fertilizer is deliberately not a CurrencyDef,
## since it is never produced and never shown in the resource bar.
@export var currency: CurrencyDef

## amount = max(min_amount, floor(pct_of_balance * balance + flat_amount)).
## Scaling off the live balance is what keeps an event meaningful at every point
## on the curve; the floor is what keeps it meaningful at the start of one.
@export var pct_of_balance: float = 0.0
@export var flat_amount: float = 0.0
@export var min_amount: float = 0.0

## Fertilizer this pays. Rolled uniformly in [min, max] at collect time for a
## BOON, and paid flat for a SPEND or PROGRESS reward (author both equal).
@export var fertilizer_min: float = 0.0
@export var fertilizer_max: float = 0.0

## PROGRESS only: live ticks the event must survive before it pays out.
@export var goal_ticks: int = 0

## Biome key that must be unlocked for this event to enter the pool. Empty = always
## eligible. Read off the run's own unlocked set, not ever_unlocked, matching
## WaterSystem.is_pumping(): an event about crystals has nothing to offer a run
## that has not bought the caves back.
@export var requires_biome: StringName = &""

## True when this event pays fertilizer rather than one of the four currencies.
func pays_fertilizer() -> bool:
	return currency == null and fertilizer_max > 0.0
