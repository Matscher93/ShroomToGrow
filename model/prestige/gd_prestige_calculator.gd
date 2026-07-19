class_name PrestigeCalculator
## MODEL — pure calculation, no state. Formula is a placeholder; will be tuned.

static func calculate_biomass_gain(tick_count: int, nutrients: BigNumber) -> BigNumber:
	var magnitude := float(nutrients.exponent)
	var gain : float = floor(magnitude * 1.0 + sqrt(float(tick_count)) * 0.1)
	return BigNumber.from_value(max(gain, 0.0))
