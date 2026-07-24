class_name BiomeList
extends Resource
## MODEL — ordered registry of every BiomeDef, loaded once by App. Mirrors
## MyceliumNodes / Screens (a thin @export Array wrapper the editor can author).

@export var biomes: Array[BiomeDef]
