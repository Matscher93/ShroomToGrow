class_name GrowthRow
extends RefCounted
## VIEWMODEL: one producer's row in the growth sheet, already resolved for
## display. Used for both an LP investment row and a daily-reward chip - they
## carry the same four pieces of information in a different shape.
##
## A value object rather than a live binding, for the same reason NavDestination
## is one: the sheet is spawned on open and freed on close, so a row never
## outlives the snapshot it was built from.

## What the row acts on. The view hands it straight back to invest() / claim().
var currency: CurrencyTypes.Types
var label: String
var accent: Color
var text_color: Color

## The headline number - "x1.35" for an investment, "+8%" for a daily stack.
var value_text: String

## The count behind it, e.g. "4 LP". Empty when the value speaks for itself.
var detail_text: String

## Whether the row's button does anything right now: a point to spend, or a claim
## still unspent today. A disabled row stays visible - hiding it gives the player
## nothing to work towards.
var enabled: bool
