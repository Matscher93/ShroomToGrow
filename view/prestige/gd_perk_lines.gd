class_name PerkLines
extends Node2D
## VIEW — spawns/repositions one PerkConnector per parent->child edge of the
## mycelial web, beneath the perk buttons. Connector color/width per owned
## state lives in sc_perk_connector.tscn (see gd_perk_connector.gd).

@export var connector_scene: PackedScene
## Saturation/value the branch hue is expanded to; the per-status color and
## alpha authored on PerkConnector still modulate this.
@export var branch_saturation: float = 0.6
@export var branch_value: float = 0.9

var _connectors: Dictionary = {}  # StringName (child id) -> PerkConnector

func refresh(zoom: float) -> void:
	for id in App.perk_defs:
		var def: PerkDef = App.perk_defs[id]
		if def.parent_id == &"":
			continue
		var parent: PerkDef = App.perk_defs.get(def.parent_id)
		if parent == null:
			continue
		var connector: PerkConnector = _connectors.get(id)
		if connector == null:
			connector = connector_scene.instantiate()
			add_child(connector)
			_connectors[id] = connector
		var status: String = App.perk_vms[id].status
		# The edge belongs to the child, so it takes the child's branch hue —
		# that keeps the four arms distinct right down from the core.
		var hue := App.perk_branches.hue_for(def.branch_key) / 360.0
		var branch_color := Color.from_hsv(hue, branch_saturation, branch_value)
		connector.bind(Vector2(parent.world_x, parent.world_y), Vector2(def.world_x, def.world_y), status, zoom, branch_color)
