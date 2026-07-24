class_name BiomeCalculator
## MODEL — pure calculation: biome XP and leveling. Reads live counters off
## App (node counts, upgrade levels, prestige count) but performs no writes.

## Sums manual_nodes only (not the auto-generated BigNumber tiers) so this
## always fits a plain int — "nodes grown" tracks purchases, not throughput.
static func xp_for(def: BiomeDef) -> int:
	match def.xp_source:
		BiomeDef.XpSource.TOTAL_NODES:
			var total := 0
			for node in App.nodes.mycelium_nodes:
				total += node.manual_nodes
			return total
		BiomeDef.XpSource.SYMBIOSIS_LEVELS:
			return App.upgrade_system.total_levels()
		BiomeDef.XpSource.PRESTIGE_COUNT:
			return App.player_data.prestige_count * 10
		_:
			return 0

## Level 1 starts at xp=0; each level needs floor(prev_need*1.55) more XP.
## Bounded by log growth, so this loop stays short even at very high xp.
static func level_for(xp: int) -> Dictionary:
	var lvl := 1
	var need := 6
	var acc := 0
	while xp >= acc + need:
		acc += need
		lvl += 1
		need = int(round(need * 1.55))
	return {"level": lvl, "into": xp - acc, "need": need}
