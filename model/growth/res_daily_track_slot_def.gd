class_name DailyTrackSlotDef
extends Resource
## MODEL: one day of the daily-reward track - what it pays and how much.
##
## The amount is authored as a rule rather than a number, the same rule
## RandomEventDef uses: amount = max(min_amount, pct_of_balance * balance +
## flat_amount). Scaling off the live balance is what keeps a reward meaningful
## at every point on the curve, and the floor is what keeps it meaningful at the
## start of one. A flat number would be a fortune on day one and a rounding error
## a week later.

## The resource this day pays. A slot whose currency the player has no screen for
## yet pays the deepest one they do - see DailyTrackSystem.currency_for().
@export var currency: CurrencyDef

## amount = max(min_amount, pct_of_balance * balance + flat_amount).
@export var pct_of_balance: float = 0.0
@export var flat_amount: float = 0.0
@export var min_amount: float = 0.0
