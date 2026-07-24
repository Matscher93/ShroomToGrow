class_name PerkLines
extends Node2D
## VIEW — draws the parent->child edges of the mycelial web beneath the
## perk buttons. Redrawn on demand by PerkWeb (see refresh()).

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	for id in App.perk_defs:
		var def: PerkDef = App.perk_defs[id]
		if def.parent_id == &"":
			continue
		var parent: PerkDef = App.perk_defs.get(def.parent_id)
		if parent == null:
			continue
		var owned := App.prestige_upgrade_system.level(id) > 0
		var color := Color(0.7, 0.55, 0.95, 0.85) if owned else Color(0.32, 0.28, 0.38, 0.5)
		var width := 3.0 if owned else 1.5
		draw_line(Vector2(parent.world_x, parent.world_y), Vector2(def.world_x, def.world_y), color, width)
