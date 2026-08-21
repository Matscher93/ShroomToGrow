class_name ScreenDefinition
extends Resource

@export var screen_name: String
@export var screen_scene: PackedScene

## Currencies the resource bar shows while this screen is up, in display order.
## The bar is contextual: only what this screen earns or spends belongs here,
## not every currency the player owns.
@export var currencies: Array[CurrencyDef] = []

## One-line qualifier under the name in the nav menu ("mycelium colony"). The
## name alone says where a row goes, this says what is there when you arrive.
@export var subtitle: String

## The row's accent, and the menu disc's fill while this screen is up. Authored
## to match the owning biome's biome_color so a screen reads as the same identity
## in the nav as it does on its biome card.
@export var accent_color: Color

## Set on the nav row icon's material. Reuses the per-biome icon shaders under
## shaders/icons/biomes/ rather than minting a second set of glyphs.
@export var icon_shader: Shader

## Sub-views promoted into the nav menu as indented rows under this screen.
## Empty for every screen that has no tabs of its own.
@export var sub_screens: Array[SubScreenDefinition] = []
