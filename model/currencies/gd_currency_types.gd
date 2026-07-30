class_name CurrencyTypes
extends RefCounted

enum Types {NUTRIENTS, WATER, BIOMASS}

## The PlayerData field backing a currency, for get()/set() reflection.
static func field_for(currency: Types) -> StringName:
	match currency:
		Types.WATER:
			return &"water"
		Types.BIOMASS:
			return &"biomass"
		_:
			return &"nutrients"
