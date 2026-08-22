class_name EventRow
extends RefCounted
## VIEWMODEL: one event card, already resolved for display.
##
## A value object rather than a live binding, for the same reason GrowthRow is
## one: the sheet is spawned on open and freed on close, and the queue is rebuilt
## whole whenever it changes, so a row never outlives the snapshot it was built
## from.

## What the row acts on. The view hands it straight back to collect() / fulfil() /
## skip().
var instance_id: int

var title: String
var description: String
var accent: Color

## Which body the card shows. The three are mutually exclusive.
var kind: RandomEventDef.Kind

## The action button's label: "Collect +820 nutrients" on a boon, "Spend 240
## water" on a quest. Empty on a progress event, which has no button.
var action_text: String

## "+3 fertilizer" - what answering pays. Empty when the event pays a resource
## rather than fertilizer, since action_text already names it.
var reward_text: String

## Whether the Fulfil button does anything right now. Always true on a boon, which
## asks for nothing.
var enabled: bool

## "2 / 4 ticks" and the bar's fill, on a progress event only.
var progress_text: String
var progress_pct: float
