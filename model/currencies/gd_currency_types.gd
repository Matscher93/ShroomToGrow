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
