@tool
extends PanelContainer
## VIEW — the biome hub: spawns one BiomePanel (sc_biome_panel.tscn) per
## BiomeDef. Each panel binds itself to App's biome state; this container
## only owns the list.

@export var vbox_items: VBoxContainer
@export var biome_scene: PackedScene

func _ready() -> void:
	for child in vbox_items.get_children():
		vbox_items.remove_child(child)
		child.queue_free()

	for def in App.biomes.biomes:
		var panel := biome_scene.instantiate()
		panel.biome_key = def.key
		vbox_items.add_child(panel)
