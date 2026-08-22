class_name FertilizerRow
extends RefCounted
## VIEWMODEL: one fertilizer upgrade's row in the growth sheet, already resolved
## for display.
##
## A value object rather than a live binding, for the same reason GrowthRow is
## one: the sheet is spawned on open and freed on close, so a row never outlives
## the snapshot it was built from.
##
## Keyed on the upgrade id rather than GrowthRow's currency - a fertilizer upgrade
## raises several producers at once, so no single currency identifies it.

## What the row acts on. The view hands it straight back to buy().
var id: StringName

var label: String
var description: String

## "Lv 3", shown in the pill next to the name.
var level_text: String

## The fertilizer the next level costs, on the buy button.
var cost_text: String

## Whether the balance covers that cost right now. A disabled row stays visible -
## hiding it gives the player nothing to work towards.
var enabled: bool
