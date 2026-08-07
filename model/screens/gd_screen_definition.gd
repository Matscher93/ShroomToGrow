class_name ScreenDefinition
extends Resource

@export var screen_name: String
@export var screen_scene: PackedScene

## Currencies the resource bar shows while this screen is up, in display order.
## The bar is contextual: only what this screen earns or spends belongs here,
## not every currency the player owns.
@export var currencies: Array[CurrencyDef] = []
