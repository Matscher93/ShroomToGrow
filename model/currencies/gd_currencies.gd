class_name Currencies
extends Resource
## MODEL: every authored CurrencyDef, by type.
##
## There was no registry before this: a def was only reachable through whichever
## ScreenDefinition listed it in `currencies`, which worked only because the six
## screens happened to name all seven between them. Fertilizer is the one that
## broke it - it is never shown in the resource bar, so no screen lists it, and a
## def nothing can look up is a def that may as well not exist.
##
## Mirrors Screens: a Dictionary keyed by the same enum the ordinal is
## serialised as.
@export var currencies: Dictionary[CurrencyTypes.Types, CurrencyDef]
