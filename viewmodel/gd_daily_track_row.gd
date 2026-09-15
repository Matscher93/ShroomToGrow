class_name DailyTrackRow
extends RefCounted
## VIEWMODEL: one day of the daily-reward track, already resolved for display.
##
## A value object rather than a live binding, like GrowthRow beside it: the sheet
## is spawned on open and freed on close, so a row never outlives the snapshot it
## was built from.

## Where this day sits relative to the pass the player is on. CLAIMED days are
## behind them, TODAY is the one this evening's claim pays, and LOCKED days are
## the ones still ahead - which is also what every day reads as once a missed day
## has broken the pass and there is no claim left today.
enum State {CLAIMED, TODAY, LOCKED}

## 1-based, and shown as written: the track is "day 7", not "index 6".
var day: int

## The resource this day actually pays, after the unlock substitution - so the
## icon and the colour are of the thing the player receives, not of the thing the
## slot was authored for.
var currency: CurrencyTypes.Types
var accent: Color

## What the day is worth at this moment, e.g. "+1.2K". Recomputed on every
## refresh rather than frozen at build: the amount scales off a live balance.
var amount_text: String

var state: State
