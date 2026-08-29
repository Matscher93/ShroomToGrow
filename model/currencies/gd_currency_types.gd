class_name CurrencyTypes
extends RefCounted

## Append only: the ordinal is the icon_id shader parameter on the resource pill
## and the value serialised into every authored .tres that names a currency.
##
## Fertilizer sat outside this for a long time, on the grounds that
## UpgradeSystem.buy() spends a PlayerData field rather than a currency and that
## nothing produces fertilizer or shows it in the resource bar - both still true.
## What it also had was a colour and an icon of its own that no def carried, so
## every screen painting it hardcoded the same green. It is a currency in every
## way that shows on screen, so it is one here.
enum Types {NUTRIENTS, WATER, BIOMASS, CRYSTALS, RELICS, ICHOR, GLYPHS, FERTILIZER}

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
		Types.FERTILIZER:
			return &"fertilizer"
		_:
			return &"nutrients"

## A currency as the word a sentence uses - "5 relics", "20 ichor". Lowercase,
## because every caller drops it into a phrase rather than starting one with it.
##
## Here rather than read off CurrencyDef.currency_name because the places that
## need it hold the ordinal and not the def: a mission payout is serialised as
## {currency, m, e}, which is what round-trips through JSON. Two screens were
## about to carry the same seven-arm match.
static func display_name_for(currency: Types) -> String:
	match currency:
		Types.WATER:
			return "water"
		Types.BIOMASS:
			return "biomass"
		Types.CRYSTALS:
			return "crystals"
		Types.RELICS:
			return "relics"
		Types.ICHOR:
			return "ichor"
		Types.GLYPHS:
			return "glyphs"
		Types.FERTILIZER:
			return "fertilizer"
		_:
			return "nutrients"

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
	Types.FERTILIZER: &"lifetime_fertilizer",
}

static func lifetime_field_for(currency: Types) -> StringName:
	return LIFETIME_FIELDS.get(currency, &"")
