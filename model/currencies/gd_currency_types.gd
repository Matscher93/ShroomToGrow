class_name CurrencyTypes
extends RefCounted

## Append only: the ordinal is the icon_id shader parameter on the resource pill
## and the value serialised into every authored .tres that names a currency.
enum Types {NUTRIENTS, WATER, BIOMASS, CRYSTALS, RELICS, ICHOR, GLYPHS}

## The PlayerData field backing a currency, for get()/set() reflection.
static func field_for(currency: Types) -> StringName:
	match currency:
		Types.WATER:
			return &"water"
		Types.BIOMASS:
			return &"biomass"
		Types.CRYSTALS:
			return &"crystals"
		Types.RELICS:
			return &"relics"
		Types.ICHOR:
			return &"ichor"
		Types.GLYPHS:
			return &"glyphs"
		_:
			return &"nutrients"

## The PlayerData lifetime counter a currency feeds, or &"" where it has none.
##
## Water and biomass are deliberately absent: nothing measures either across
## runs, so there is no counter to move. Every payout path reads this rather than
## matching on the type itself - a two-arm match is how EventSystem._pay() came
## to move a relic balance without moving lifetime_relics, which is the stat the
## achievement ladder actually reads.
const LIFETIME_FIELDS := {
	Types.NUTRIENTS: &"lifetime_nutrients",
	Types.CRYSTALS: &"lifetime_crystals",
	Types.RELICS: &"lifetime_relics",
	Types.ICHOR: &"lifetime_ichor",
	Types.GLYPHS: &"lifetime_glyphs",
}

static func lifetime_field_for(currency: Types) -> StringName:
	return LIFETIME_FIELDS.get(currency, &"")
