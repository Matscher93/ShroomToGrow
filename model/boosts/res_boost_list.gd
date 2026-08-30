class_name BoostList
extends Resource
## MODEL: every authored boost, in display order. Parallel to BiomeList /
## PerkBranchList / AchievementList.

@export var boosts: Array[BoostDef] = []

## How tall one tier is. Shared by every boost, which is why it lives on the list
## rather than on each def - BoostDef already owns the two curves that differ per
## boost, and this is what the whole ladder shares.
##
## There is no companion tier count. The ladder tiers up every this many levels
## for as long as a boost's ceiling allows, so how many tiers a boost has is a
## consequence of its perks rather than an authored number.
##
## Read into BoostTiers at boot and nowhere after; see BoostTiers.configure().
## The default must match the one there, or a list that never authored it would
## move the ladder just by existing.
@export_range(1, 500) var levels_per_tier: int = 100
