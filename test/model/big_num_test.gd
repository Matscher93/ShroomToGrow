extends GdUnitTestSuite
## Unit tests for BigNumber (model/gd_big_num.gd).
##
## This is the highest bug-density file in the project: normalisation, gt() and
## equals() each shipped a real defect. Every test below that names a "used to"
## behaviour is a regression guard for one of them.

const EPS := 0.000001

# ─── Normalisation ───────────────────────────────────────────────────────────

func test_normalises_mantissa_into_one_to_ten() -> void:
	# Canonical form is the invariant gt() and equals() both rely on.
	for value: float in [1.0, 9.99, 10.0, 999.0, 1000.0, 123456.0, 0.5, 0.0001]:
		var n := BigNumber.from_value(value)
		assert_float(absf(n.mantissa)).is_greater_equal(1.0)
		assert_float(absf(n.mantissa)).is_less(10.0)

func test_zero_normalises_exponent_to_zero() -> void:
	var zero := BigNumber.new(0.0, 42)
	assert_float(zero.mantissa).is_zero()
	assert_int(zero.exponent).is_zero()

func test_one_thousand_has_a_single_representation() -> void:
	# Used to allow both (1.0, 3) and (100.0, 1) for the same value.
	var direct := BigNumber.new(1000.0, 0)
	assert_float(direct.mantissa).is_equal_approx(1.0, EPS)
	assert_int(direct.exponent).is_equal(3)

func test_multiplication_result_is_canonical() -> void:
	# mul() was the main producer of non-canonical mantissas.
	var product := BigNumber.new(5.0, 1).mul(BigNumber.new(4.0, 1))
	assert_float(product.mantissa).is_greater_equal(1.0)
	assert_float(product.mantissa).is_less(10.0)
	assert_float(product.to_float()).is_equal_approx(2000.0, EPS)

func test_negative_values_keep_their_sign() -> void:
	var n := BigNumber.from_value(-1500.0)
	assert_float(n.mantissa).is_negative()
	assert_float(n.to_float()).is_equal_approx(-1500.0, EPS)

# ─── Arithmetic ──────────────────────────────────────────────────────────────

func test_add_and_sub() -> void:
	var a := BigNumber.from_value(1000.0)
	var b := BigNumber.from_value(250.0)
	assert_float(a.add(b).to_float()).is_equal_approx(1250.0, EPS)
	assert_float(a.sub(b).to_float()).is_equal_approx(750.0, EPS)

func test_add_with_zero_is_identity() -> void:
	var a := BigNumber.from_value(42.0)
	var zero := BigNumber.from_value(0.0)
	assert_float(a.add(zero).to_float()).is_equal_approx(42.0, EPS)
	assert_float(zero.add(a).to_float()).is_equal_approx(42.0, EPS)

func test_add_drops_operands_lost_in_float_noise() -> void:
	# 17+ exponents apart, the smaller value cannot affect the mantissa.
	var huge := BigNumber.new(1.0, 40)
	var tiny := BigNumber.new(1.0, 1)
	assert_float(huge.add(tiny).to_float()).is_equal_approx(huge.to_float(), EPS)

func test_mul_and_div() -> void:
	var a := BigNumber.from_value(2000.0)
	var b := BigNumber.from_value(4.0)
	assert_float(a.mul(b).to_float()).is_equal_approx(8000.0, EPS)
	assert_float(a.div(b).to_float()).is_equal_approx(500.0, EPS)

func test_div_by_zero_is_reported_and_yields_zero() -> void:
	# assert_error, not a bare call: an unexpected push_error under the test
	# runner's attached debugger aborts the whole run.
	var out: Array[BigNumber] = []
	assert_error(func() -> void:
		out.append(BigNumber.from_value(10.0).div(BigNumber.from_value(0.0)))
	).is_push_error("BigNumber: division by zero")
	assert_float(out[0].to_float()).is_zero()

func test_scale_by_plain_float() -> void:
	assert_float(BigNumber.from_value(50.0).scale(3.0).to_float()).is_equal_approx(150.0, EPS)

func test_pow_int() -> void:
	assert_float(BigNumber.from_value(2.0).pow_int(10).to_float()).is_equal_approx(1024.0, EPS)
	assert_float(BigNumber.from_value(7.0).pow_int(0).to_float()).is_equal_approx(1.0, EPS)
	assert_float(BigNumber.from_value(7.0).pow_int(1).to_float()).is_equal_approx(7.0, EPS)

func test_pow_float_handles_huge_exponents() -> void:
	# Used for cost curves; must not overflow the way pow_int would.
	# log10(1.15) * 500 = 30.3499..., so 1.15^500 is 2.238e30.
	var result := BigNumber.from_value(1.15).pow_float(500.0)
	assert_int(result.exponent).is_equal(30)
	assert_float(result.mantissa).is_equal_approx(2.238, 0.01)

# ─── Comparison ──────────────────────────────────────────────────────────────

func test_gt_past_float_range() -> void:
	# Both operands used to be scaled into a shared exponent, overflowing to INF.
	# INF > INF is false, so this returned false for a genuinely greater value —
	# silently inverting affordability checks late in a run.
	var huge := BigNumber.new(1.0, 400)
	var big := BigNumber.new(1.0, 390)
	assert_bool(huge.gt(big)).is_true()
	assert_bool(big.gt(huge)).is_false()
	assert_bool(huge.gte(big)).is_true()
	assert_bool(big.lt(huge)).is_true()

func test_gt_same_exponent_uses_mantissa() -> void:
	assert_bool(BigNumber.new(9.0, 5).gt(BigNumber.new(1.0, 5))).is_true()
	assert_bool(BigNumber.new(1.0, 5).gt(BigNumber.new(9.0, 5))).is_false()

func test_gt_equal_values() -> void:
	var a := BigNumber.from_value(500.0)
	var b := BigNumber.from_value(500.0)
	assert_bool(a.gt(b)).is_false()
	assert_bool(a.gte(b)).is_true()
	assert_bool(a.lte(b)).is_true()

func test_gt_sign_matrix() -> void:
	var neg_small := BigNumber.from_value(-1.0)
	var neg_large := BigNumber.from_value(-1000.0)
	var zero := BigNumber.from_value(0.0)
	var pos := BigNumber.from_value(1.0)

	assert_bool(neg_small.gt(neg_large)).is_true()      # -1 > -1000
	assert_bool(neg_large.gt(neg_small)).is_false()
	assert_bool(zero.gt(neg_small)).is_true()           #  0 > -1
	assert_bool(neg_small.gt(zero)).is_false()
	assert_bool(pos.gt(zero)).is_true()                 #  1 >  0
	assert_bool(zero.gt(pos)).is_false()
	assert_bool(pos.gt(neg_small)).is_true()            #  1 > -1
	assert_bool(zero.gt(BigNumber.from_value(0.0))).is_false()

func test_affordability_at_high_exponents() -> void:
	# The shape this actually guards in-game.
	var funds := BigNumber.new(5.0, 350)
	var cost := BigNumber.new(2.0, 349)
	assert_bool(funds.gte(cost)).is_true()
	assert_bool(cost.gte(funds)).is_false()

func test_equals_across_construction_paths() -> void:
	# mul() and from_value() used to disagree on the fields for the same value.
	var via_mul := BigNumber.new(10.0, 1).mul(BigNumber.new(10.0, 1))
	var via_value := BigNumber.from_value(10000.0)
	assert_bool(via_mul.equals(via_value)).is_true()

func test_same_value_is_exact_not_approximate() -> void:
	# same_value backs the "did this change?" guards in the property setters, so
	# it must never call two distinct values equal — a real gain would be lost.
	var a := BigNumber.from_value(100.0)
	assert_bool(a.same_value(BigNumber.from_value(100.0))).is_true()
	assert_bool(a.same_value(BigNumber.from_value(100.001))).is_false()
	assert_bool(a.same_value(null)).is_false()

# ─── Display ─────────────────────────────────────────────────────────────────

func test_to_display_suffixes() -> void:
	assert_str(BigNumber.from_value(0.0).to_display()).is_equal("0")
	assert_str(BigNumber.from_value(42.0).to_display()).is_equal("42.0")
	assert_str(BigNumber.from_value(1500.0).to_display()).is_equal("1.5K")
	assert_str(BigNumber.from_value(999_900_000.0).to_display()).is_equal("999.9M")

func test_to_display_honours_decimals() -> void:
	# The no-suffix branch used to hardcode "%.1f" and ignore the argument.
	assert_str(BigNumber.from_value(42.0).to_display(0)).is_equal("42")
	assert_str(BigNumber.from_value(42.0).to_display(3)).is_equal("42.000")
	assert_str(BigNumber.from_value(1500.0).to_display(2)).is_equal("1.50K")

func test_plain_numbering_runs_through_decillion() -> void:
	# Deliberate cutoff: suffixed numbers up to Dc, scientific only past it.
	assert_str(BigNumber.new(1.0, 33).to_display()).is_equal("1.0Dc")
	assert_str(BigNumber.new(1.0, 35).to_display()).is_equal("100.0Dc")
	assert_str(BigNumber.new(1.0, 36).to_display()).is_equal("1.00e36")

func test_to_scientific() -> void:
	assert_str(BigNumber.new(1.234, 99).to_scientific()).is_equal("1.23e99")

# ─── Persistence ─────────────────────────────────────────────────────────────

func test_save_round_trip() -> void:
	var original := BigNumber.from_value(123456.789)
	var restored := BigNumber.from_save(original.to_save())
	assert_bool(restored.same_value(original)).is_true()

func test_from_save_tolerates_missing_keys() -> void:
	# The corrupt/missing-data path: must yield zero, not crash.
	var restored := BigNumber.from_save({})
	assert_float(restored.to_float()).is_zero()
