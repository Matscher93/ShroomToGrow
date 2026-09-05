/* Crystals screen: the closed loop nothing else shows both ends of.
 *
 * Crystals are minted in exactly one place - claiming an achievement tier - and
 * spent in three: boosts, automations, and a biome's auto-unlock. Every other
 * reference to player_data.crystals in model/ subtracts.
 *
 * The two ends live apart in the game. Crystal Caves is a screen with Boosts,
 * Automations and Sequences tabs; achievements are an overlay reached from the
 * top bar. But an achievement's goal curve sets the crystal supply *and* the
 * Crystal Caves biome's level - XpSource.ACHIEVEMENT_TIERS, unweighted, counting
 * claimed tiers across all nine - so tuning one moves both, and there was no
 * view that put them together.
 *
 * Achievement curves are the least visible numbers in the game: nine defs, four
 * growth knobs each, charted nowhere. Two things make them harder than they
 * look, and both are why the engine's own samples lead here rather than merely
 * checking the mirror:
 *
 *   - the goal curve is base * growth^(n ^ exponent), not the
 *     base * growth^(n * exponent^n) every other curve in the game uses
 *   - for a counted stat the goal is max(ceil(raw), ceil(base) + n), and on a
 *     shallow curve that floor term *is* the early ladder - Cartographer's first
 *     four goals are 1, 2, 3, 4, nothing to do with its 1.5 growth
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    log10Of, formatBig, growthCurve, powerCurve, chartBlock, engineSeries, engineCurve,
    xpLadder, rowsOf, cell, numberCell, field, fieldGroup, bigField, scopeTargetFields,
  } = window.GameKit;

  const TIERS = 50;              // matches BalanceData.CURVE_OPEN_ENDED_LEVELS
  const AUTOMATION_LEVELS = 50;

  /* Only these two AchievementDef.Stat values are continuous; every other one
   * counts whole things, and their goals get rounded up and floor-separated.
   * Mirrors AchievementDef.is_counted(), which defaults to counted so a stat
   * added later behaves without anyone remembering the list. */
  const CONTINUOUS_STATS = ["Lifetime Nutrients", "Lifetime Crystals"];

  const screen = { label: "Crystals" };

  const list = (value) => (value || "").split("|").filter(Boolean);

  const hint = (text) => {
    const p = document.createElement("p");
    p.className = "hint";
    p.textContent = text;
    return p;
  };

  function shortPath(path) {
    const parts = (path || "").split("::")[0].replace(/^res:\/\/data\//, "").split("/");
    return parts.slice(-2).join("/");
  }

  const isCounted = (entry) => !CONTINUOUS_STATS.includes(cell(entry, "stat"));

  /* ------------------------------------------------------------------- order */

  /** Rows in the order their list resource holds them, which is the order the
   * game shows them in. Falls back to the table's own order when the list is
   * missing, so a screen degrades rather than empties. */
  function orderedBy(listTable, listColumn, rowTable) {
    const listRows = rowsOf(listTable);
    const paths = listRows.length ? list(cell(listRows[0], listColumn)) : [];
    const rows = rowsOf(rowTable);
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    return paths.map((path) => byPath.get(path)).filter(Boolean);
  }

  const achievementEntries = () =>
    orderedBy("AchievementList", "achievements", "AchievementDef");
  const boostEntries = () => orderedBy("BoostList", "boosts", "BoostDef");
  const automationEntries = () =>
    orderedBy("AutomationList", "automations", "AutomationDef");

  /* ------------------------------------------------------------ ladder shape */

  /* BoostTiers.LEVELS_PER_TIER, authored on BoostList and read into BoostTiers at
   * boot. Read through a function rather than captured once: editing the field
   * must redraw every boost's charts in place, and a const would go stale the
   * moment the box is typed in.
   *
   * The default matches BoostTiers', so an unloaded table degrades to the shipped
   * ladder rather than throwing - cell() already answers "" for a null entry. */
  const ladderRow = () => rowsOf("BoostList")[0];
  const levelsPerTier = () =>
    Math.max(1, Math.round(numberCell(ladderRow(), "levels_per_tier", 100)));

  /* A window on the ladder, not a limit on it: a boost tiers up every
   * levels_per_tier levels for as long as its ceiling is raised, so there is no
   * last tier to chart to. Matches BalanceData.CURVE_BOOST_TIERS, which is what
   * the engine samples, so the mirrored line and the engine's dots cover the same
   * span. Each chart's own range control reaches past it. */
  const CHARTED_TIERS = 5;
  const boostLevels = () => CHARTED_TIERS * levelsPerTier();

  /* ------------------------------------------------------------------ curves */

  /** AchievementSystem.goal_for(), including the whole-number handling the
   * authored fields alone do not describe.
   *
   * For a counted stat the goal is the rounded-up curve held at least one above
   * where tier 0 sat plus one per tier since. Rounding alone would let a shallow
   * curve give two tiers the same bar, and a tier whose goal matches the one
   * before it completes the instant that one does - a free tier. */
  function goalCurve(entry, from, to) {
    const base = log10Of(numberCell(entry, "_goal_base_mantissa", 1),
      numberCell(entry, "_goal_base_exponent", 0));
    const raw = powerCurve(base,
      numberCell(entry, "goal_growth", 2),
      numberCell(entry, "goal_growth_exponent", 1), from, to);
    if (!isCounted(entry)) return raw;

    const baseValue = numberCell(entry, "_goal_base_mantissa", 1)
      * 10 ** numberCell(entry, "_goal_base_exponent", 0);
    const floorAt = Math.ceil(baseValue);
    const growth = numberCell(entry, "goal_growth", 2);
    const exponent = numberCell(entry, "goal_growth_exponent", 1);

    return raw.map((value, index) => {
      if (value === null || !Number.isFinite(value)) return value;
      const tier = from + index;
      // Past 1e15 a float has no fractional part left to round away, and the
      // engine leaves those alone rather than losing precision on the trip.
      if (value > 15) return value;
      // Recomputed in linear space rather than rounded as 10 ** value: the log
      // round trip lands a goal_base of 5 on 5.000000000000001, and ceil turns
      // that drift into a whole extra unit - an off-by-one on the very first
      // tier of every counted achievement whose base is a round number.
      const linear = baseValue * growth ** (tier ** exponent);
      if (!Number.isFinite(linear)) return value;
      return Math.log10(Math.max(Math.ceil(linear), floorAt + tier));
    });
  }

  /** AchievementSystem.reward_for(), in crystals. Same power shape as the goal,
   * and no rounding: crystals are a BigNumber all the way down. */
  function rewardCurve(entry, from, to) {
    return powerCurve(
      log10Of(numberCell(entry, "_reward_base_mantissa", 1),
        numberCell(entry, "_reward_base_exponent", 0)),
      numberCell(entry, "reward_growth", 1.5),
      numberCell(entry, "reward_growth_exponent", 1), from, to);
  }

  /** BoostDef.per_level(tier) - the rate one level of this tier is bought at. */
  const perLevelAt = (entry, tier) =>
    numberCell(entry, "base_per_level", 0.01)
      * numberCell(entry, "per_level_growth", 5) ** (tier - 1);

  const tierOf = (level) =>
    Math.max(Math.floor(Math.max(level, 0) / levelsPerTier()) + 1, 1);

  /** BoostDef.cost_at(level), in log10 - what the next level costs at this point
   * on the whole ladder.
   *
   * Log space is not a nicety here: cost_growth_exponent raises the level through
   * itself before it becomes an exponent, so any value above 1.0 puts the top of
   * a five-hundred level ladder far past what a double holds. The engine carries
   * it as a BigNumber for the same reason.
   *
   * Priced off the total level, so the levels of every tier below count. A tier
   * therefore opens one step above where the one under it closed, and
   * tier_cost_growth is a step on top of that rather than the whole boundary. */
  function costAtLog(entry, level) {
    const base = numberCell(entry, "base_cost", 1);
    const growth = numberCell(entry, "cost_growth", 1.05);
    if (base <= 0 || growth <= 0) return null;
    const steps = level * numberCell(entry, "cost_growth_exponent", 1) ** level;
    const value = Math.log10(base)
      + steps * Math.log10(growth)
      + (tierOf(level) - 1) * Math.log10(numberCell(entry, "tier_cost_growth", 1));
    return Number.isFinite(value) ? value : null;
  }

  /** Crystals for the next level, across the whole authored ladder.
   *
   * One curve, not a staircase: tier_cost_growth of 1.0 draws an unbroken line
   * and anything above it kinks the line upwards at each boundary. It used to
   * restart per tier, which made every boundary a discount - the levels below
   * were dropped out of the exponent, and tier_cost_growth had to make all of
   * that back on its own.
   *
   * On a log axis a cost_growth_exponent of 1.0 is a straight line, and anything
   * above it bows upwards - which is the only honest way to read that field,
   * since the numbers at the top of the ladder stop meaning much very quickly. */
  function boostCostCurve(entry, from, to) {
    const out = [];
    for (let level = from; level <= to; level += 1) out.push(costAtLog(entry, level));
    return out;
  }

  /** The total multiplier at each level: every tier's rate compounded over the
   * levels bought in it. Level 0 is x1, and the level being priced above is the
   * one whose gain lands on the next sample. */
  function boostMultiplierCurve(entry, from, to) {
    const out = [];
    let total = 0;   // log10 of the running product
    for (let level = 0; level <= to; level += 1) {
      if (level >= from) out.push(total);
      total += Math.log10(1 + perLevelAt(entry, tierOf(level)));
    }
    return out;
  }

  /** AutomationSystem.runs_per_tick_at(): linear in level, and nothing below
   * level 1, since an automation that has never been bought never runs. */
  function runsCurve(entry, from, to) {
    const base = numberCell(entry, "base_runs_per_tick", 0.25);
    const per = numberCell(entry, "runs_per_level", 0.25);
    const out = [];
    for (let level = from; level <= to; level += 1) {
      out.push(level <= 0 ? 0 : Math.max(0, base + per * (level - 1)));
    }
    return out;
  }

  /* -------------------------------------------------------------- 1. the loop */

  function loopSection() {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "The crystal loop";
    wrap.append(heading);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Minted in one place only \u2014 claiming an achievement tier. Spent on "
      + "boosts, automations and a biome's auto-unlock. Crystals survive prestige, which is "
      + "what makes them the meta-currency.";
    wrap.append(note);

    const flat = document.createElement("p");
    flat.className = "hint";
    flat.textContent = "Nothing raises a crystal payout. There is no crystal stat for an "
      + "upgrade, boost, project or perk to name, so a tier pays exactly what the curve below "
      + "says and the numbers on this page are the numbers the player is paid.";
    wrap.append(flat);
    return wrap;
  }

  /* --------------------------------------------------- 2. achievement cards */

  function achievementCard(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card crystal-card";
    wrap.append(cardHead(entry, `${index + 1} / ${total} · ${cell(entry, "stat")}`
      + (isCounted(entry) ? " · counted" : " · continuous")));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry,
      ["id", "display_name", "description", "sort_order", "stat", "max_tier"]));

    // Goal
    const goal = document.createElement("div");
    goal.className = "game-group game-split";
    const goalHead = document.createElement("h4");
    goalHead.textContent = "Goal per tier";
    goal.append(goalHead);
    const goalFields = document.createElement("div");
    goalFields.className = "game-fields";
    goalFields.append(bigField(entry, "first goal", "_goal_base"));
    for (const column of ["goal_growth", "goal_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) goalFields.append(editor);
    }
    const goalNote = document.createElement("p");
    goalNote.className = "hint";
    goalNote.textContent = "goal_base × goal_growth^(tier ^ goal_growth_exponent). Note the "
      + "exponent applies to the tier itself, unlike every other curve in the game."
      + (isCounted(entry)
        ? " This stat counts whole things, so each goal is rounded up and held at least one "
          + "above the tier before it — on a shallow curve that floor is the early ladder, "
          + "not the growth."
        : " This stat is continuous, so goals keep their fractions.");
    goalFields.append(goalNote);
    goal.append(goalFields, chartBlock("Goal at tier",
      (from, to) => withEngine(entry, "goal", goalCurve(entry, from, to), from, to,
        "goal", ([m, e]) => log10Of(m, e)),
      { log: true, xLabel: "tier",
        range: { key: "achievement-goal", from: 0, to: TIERS, label: "tier" } }));
    body.append(goal);

    // Reward
    const reward = document.createElement("div");
    reward.className = "game-group game-split";
    const rewardHead = document.createElement("h4");
    rewardHead.textContent = "Reward per tier";
    reward.append(rewardHead);
    const rewardFields = document.createElement("div");
    rewardFields.className = "game-fields";
    rewardFields.append(bigField(entry, "first reward (crystals)", "_reward_base"));
    for (const column of ["reward_growth", "reward_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) rewardFields.append(editor);
    }
    const rewardNote = document.createElement("p");
    rewardNote.className = "hint";
    rewardNote.textContent = "Crystals paid when the tier is claimed. Nothing in the game "
      + "modifies it, so this is what the player actually collects \u2014 set reward_growth to "
      + "1.0 for a ladder that pays the same at every tier.";
    rewardFields.append(rewardNote);
    reward.append(rewardFields, chartBlock("Reward at tier",
      (from, to) => withEngine(entry, "reward", rewardCurve(entry, from, to), from, to,
        "reward", ([m, e]) => log10Of(m, e)),
      { log: true, xLabel: "tier",
        range: { key: "achievement-reward", from: 0, to: TIERS, label: "tier" } }));
    body.append(reward);
    return wrap;
  }

  /** A mirrored line with the engine's own samples behind it, read out of
   * whichever array of the report carries this curve kind. */
  function withEngine(entry, label, points, from, to, sampleKey, decode) {
    const series = [{ label, points, color: "var(--accent)" }];
    const sampled = engineCurve(entry.path);
    const dots = engineSeries(entry, sampled && sampled[sampleKey], from, to, decode);
    if (dots) series.push(dots);
    return series;
  }

  /* -------------------------------------------------- 3. tiers -> caves level */

  function tierLadderSection(entries) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Claimed tiers → Crystal Caves level";
    wrap.append(heading);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = `Crystal Caves takes its XP from the total tiers claimed across all `
      + `${entries.length} achievements, unweighted — one tier, one XP. Levels need 6 XP and `
      + "then 1.55× the last, so this is the curve that turns a shallower goal anywhere into "
      + "a faster biome here. Only claimed tiers count, not completed-but-unclaimed ones.";
    wrap.append(note);

    // Log, because the ladder reaches six figures of tiers by level 25 and a
    // linear axis flattens the first ten levels - the ones anybody will actually
    // play - into the floor. The table beside it carries the exact counts.
    const build = (from, to) => [
      { label: "tiers to reach the level", color: "var(--accent)",
        points: xpLadder(from, to).map((xp) => (xp > 0 ? Math.log10(xp) : null)) },
    ];
    const chart = chartBlock("Tiers needed per biome level", build,
      { log: true, xLabel: "level",
        range: { key: "caves-level", from: 1, to: 25, label: "level" } });

    const table = document.createElement("table");
    table.className = "web-table game-gate-table";
    const head = table.insertRow();
    for (const column of ["level", "tiers claimed", "per achievement"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }
    const ladder = xpLadder(1, 26);
    for (const level of [2, 5, 10, 15, 20, 25]) {
      if (level > ladder.length) continue;
      const tiers = ladder[level - 1];
      const row = table.insertRow();
      row.insertCell().textContent = `Lv ${level}`;
      row.insertCell().textContent = tiers.toLocaleString();
      row.insertCell().textContent = entries.length
        ? (tiers / entries.length).toFixed(1) : "-";
    }

    const split = document.createElement("div");
    split.className = "game-split";
    const left = document.createElement("div");
    left.className = "game-fields";
    left.append(table);
    split.append(left, chart);
    wrap.append(split);
    return wrap;
  }

  /* ------------------------------------------------------------- 4. boosts */

  const tiers = () => Array.from({ length: CHARTED_TIERS }, (_, index) => index + 1);

  /** The ladder every boost shares, edited once rather than per card.
   *
   * On BoostList rather than on each BoostDef because BoostTiers is what reads
   * it, and BoostTiers is one table for the whole game - BoostDef already owns
   * the two curves that differ per boost. Levels bought under an old shape are
   * not redistributed, so shrinking either number retires whatever sat above the
   * new ceiling. */
  function ladderShapeSection() {
    const row = ladderRow();
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Ladder shape";
    wrap.append(heading);
    if (!row) {
      wrap.append(hint("BoostList is not loaded. Press \"Reload from .tres\" and try again."));
      return wrap;
    }
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["levels_per_tier"]) {
      const editor = field(row, column);
      if (editor) fields.append(editor);
    }
    fields.append(hint(`Applies to every boost: one tier every ${levelsPerTier()} levels, with `
      + "no last tier — a boost keeps tiering up for as long as its cap perk and the Well's "
      + `projects raise its ceiling. The charts below show the first ${CHARTED_TIERS} tiers; `
      + "the range control under each one goes further. Read into BoostTiers at boot, so "
      + "moving it moves where every boundary falls."));
    wrap.append(fields);
    return wrap;
  }

  /** A magnitude the ladder reaches, as the game would print it. The prices pass
   * 1e8 by the top tier, so they are carried in log space and only turned into a
   * mantissa/exponent pair here. */
  function formatLog(value) {
    if (!Number.isFinite(value)) return "-";
    const exponent = Math.floor(value);
    return formatBig(10 ** (value - exponent), exponent);
  }

  /** Every tier of one boost on one line: what a level of it is worth, what it
   * opens and closes at, and how the opening compares to the close below it.
   *
   * That last column is the whole point. A boundary is the one place the two
   * curves move at once - the payout jumps by per_level_growth and the price
   * restarts - and a step under 1.0 there means the player is paid to cross into
   * a tier that is worth more, which is what the staircase pricing used to do at
   * every boundary. */
  function tierTable(entry) {
    const perTier = levelsPerTier();
    const table = document.createElement("table");
    table.className = "web-table game-gate-table boost-tiers";
    const head = table.insertRow();
    for (const column of ["tier", "per level", "opens at", "closes at", "step"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }

    let previousClose = null;
    for (const tier of tiers()) {
      // Both read off the ladder itself rather than derived from a per-tier
      // base, so cost_growth_exponent bends these the way it bends the chart.
      const first = (tier - 1) * perTier;
      const open = costAtLog(entry, first);
      // The last level of the tier, i.e. one short of where the next one opens.
      const close = costAtLog(entry, first + perTier - 1);
      const row = table.insertRow();
      row.insertCell().textContent = `T${tier}`;
      const rate = row.insertCell();
      rate.className = "num";
      rate.textContent = `×${(1 + perLevelAt(entry, tier)).toFixed(2)}`;
      for (const value of [open, close]) {
        const price = row.insertCell();
        price.className = "num";
        price.textContent = formatLog(value);
      }
      const step = row.insertCell();
      step.className = "num";
      if (previousClose === null || !Number.isFinite(open) || !Number.isFinite(previousClose)) {
        step.textContent = "-";
      } else {
        const factor = 10 ** (open - previousClose);
        step.textContent = `×${factor < 10 ? factor.toFixed(2) : formatLog(open - previousClose)}`;
        if (factor < 1) step.classList.add("boost-dip");
      }
      previousClose = close;
    }
    return table;
  }

  function boostCard(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card crystal-card";
    wrap.append(cardHead(entry, `${index + 1} / ${total} · ${cell(entry, "stat")}`));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["id", "display_name", "description"]));
    const effect = fieldGroup("Effect", entry, ["stat"]);
    // Paired, and under TAG the group's tiers are picked here - see
    // GameKit.scopeTargetFields.
    effect.querySelector(".game-fields").append(scopeTargetFields(entry));
    body.append(effect);
    body.append(fieldGroup("Gates", entry,
      ["unlock_perk_id", "base_max_level", "max_level_perk_id", "max_level_per_perk_level"]));

    const gateNote = document.createElement("p");
    gateNote.className = "hint";
    gateNote.textContent = `Both charts run the first ${CHARTED_TIERS} tiers — `
      + `${boostLevels()} levels at ${levelsPerTier()} per tier, set under Ladder shape above. `
      + "The ladder itself has no end: in game the boost opens at base_max_level and its cap "
      + "perk lifts it from there, tiering up every "
      + `${levelsPerTier()} levels however far that goes.`;
    body.append(gateNote);

    // Cost
    const cost = document.createElement("div");
    cost.className = "game-group game-split";
    const costHead = document.createElement("h4");
    costHead.textContent = "Crystal price";
    cost.append(costHead);
    const costFields = document.createElement("div");
    costFields.className = "game-fields";
    for (const column of
      ["base_cost", "cost_growth", "cost_growth_exponent", "tier_cost_growth"]) {
      const editor = field(entry, column);
      if (editor) costFields.append(editor);
    }
    const costNote = document.createElement("p");
    costNote.className = "hint";
    costNote.textContent = "One curve across the whole ladder: every level climbs by "
      + "cost_growth, and the levels of the tiers below count towards the exponent, so a tier "
      + "opens one step above where the last one closed. tier_cost_growth is an extra step on "
      + "top of that — 1.0 is smooth, not free. Below 1.0 a boundary becomes a discount, which "
      + "is exactly when the payout jumps. cost_growth_exponent bows the whole line upwards "
      + `and bites hard over ${boostLevels()} levels — the third decimal is the useful range, `
      + "and the chart is the only honest read of it.";
    costFields.append(costNote, tierTable(entry));
    cost.append(costFields, chartBlock("Crystals for the next level",
      (from, to) => withEngine(entry, "next level", boostCostCurve(entry, from, to),
        from, to, "cost", ([m, e]) => log10Of(m, e)),
      { log: true, xLabel: "level",
        range: { key: "boost-cost", from: 0, to: boostLevels(), label: "level" } }));
    body.append(cost);

    // Multiplier
    const rate = document.createElement("div");
    rate.className = "game-group game-split";
    const rateHead = document.createElement("h4");
    rateHead.textContent = "Multiplier";
    rate.append(rateHead);
    const rateFields = document.createElement("div");
    rateFields.className = "game-fields";
    for (const column of ["base_per_level", "per_level_growth"]) {
      const editor = field(entry, column);
      if (editor) rateFields.append(editor);
    }
    const rates = document.createElement("p");
    rates.className = "hint";
    rates.textContent = "Per level by tier: "
      + tiers().map((tier) => `T${tier} ×${(1 + perLevelAt(entry, tier)).toFixed(2)}`)
        .join(" · ")
      + ". A level multiplies rather than adds, so the tiers compound on each other.";
    rateFields.append(rates);
    rate.append(rateFields, chartBlock("Total multiplier at level",
      (from, to) => withEngine(entry, "multiplier", boostMultiplierCurve(entry, from, to),
        from, to, "multiplier", ([m, e]) => log10Of(m, e)),
      { log: true, xLabel: "level",
        range: { key: "boost-mult", from: 0, to: boostLevels(), label: "level" } }));
    body.append(rate);
    return wrap;
  }

  /* --------------------------------------------------------- 5. automations */

  function automationCard(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card crystal-card";
    wrap.append(cardHead(entry, `${index + 1} / ${total} · ${cell(entry, "kind")}`));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry,
      ["id", "display_name", "description", "sort_order", "kind"]));
    body.append(fieldGroup("Gates", entry,
      ["max_level", "unlock_perk_id", "max_level_perk_id", "max_level_per_perk_level"]));

    const maxLevel = Math.round(numberCell(entry, "max_level", 0));
    const levels = maxLevel > 0 ? maxLevel : AUTOMATION_LEVELS;

    const cost = document.createElement("div");
    cost.className = "game-group game-split";
    const costHead = document.createElement("h4");
    costHead.textContent = "Crystal price";
    cost.append(costHead);
    const costFields = document.createElement("div");
    costFields.className = "game-fields";
    costFields.append(bigField(entry, "first level costs (crystals)", "_base_cost"));
    for (const column of ["cost_growth", "cost_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) costFields.append(editor);
    }
    cost.append(costFields, chartBlock("Crystals for the next level",
      (from, to) => withEngine(entry, "next level",
        growthCurve(log10Of(numberCell(entry, "_base_cost_mantissa", 1),
          numberCell(entry, "_base_cost_exponent", 0)),
          numberCell(entry, "cost_growth", 1.15),
          numberCell(entry, "cost_growth_exponent", 1), from, to),
        from, to, "cost", ([m, e]) => log10Of(m, e)),
      { log: true, xLabel: "level",
        range: { key: "automation-cost", from: 0, to: levels, label: "level" } }));
    body.append(cost);

    const rate = document.createElement("div");
    rate.className = "game-group game-split";
    const rateHead = document.createElement("h4");
    rateHead.textContent = "Rate";
    rate.append(rateHead);
    const rateFields = document.createElement("div");
    rateFields.className = "game-fields";
    for (const column of ["base_runs_per_tick", "runs_per_level"]) {
      const editor = field(entry, column);
      if (editor) rateFields.append(editor);
    }
    const rateNote = document.createElement("p");
    rateNote.className = "hint";
    rateNote.textContent = "base_runs_per_tick + runs_per_level × (level − 1), and nothing at "
      + "all below level 1. Under one run a tick the card shows ticks-per-run instead, so the "
      + "crossing at 1.0 is where the automation starts firing every tick.";
    rateFields.append(rateNote);
    rate.append(rateFields, chartBlock("Runs per tick", (from, to) => [
      { label: "runs / tick", points: runsCurve(entry, from, to), color: "var(--accent)" },
      { label: "one per tick", color: "var(--muted)", dashed: true,
        points: runsCurve(entry, from, to).map(() => 1) },
    ], { zeroBased: true, xLabel: "level",
      range: { key: "automation-rate", from: 0, to: levels, label: "level" } }));
    body.append(rate);
    return wrap;
  }

  /* -------------------------------------------------------------- card head */

  function cardHead(entry, badgeText) {
    const row = document.createElement("header");
    row.className = "game-card-head";

    const icon = document.createElement("span");
    icon.className = "game-card-icon";
    row.append(icon);

    const names = document.createElement("div");
    names.className = "game-card-names";
    const name = document.createElement("strong");
    name.textContent = cell(entry, "display_name") || "(unnamed)";
    const description = document.createElement("span");
    description.textContent = cell(entry, "description");
    names.append(name, description);
    row.append(names);

    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    badge.textContent = badgeText;
    row.append(badge);

    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.title = "Open this in the dependency graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    row.append(open);
    return row;
  }

  function sectionHeading(text, hint) {
    const wrap = document.createElement("div");
    // game-section marks a heading that governs the cards *after* it rather than
    // the ones inside it, which is what lets the fold reach them.
    wrap.className = "game-group game-section";
    const heading = document.createElement("h4");
    heading.textContent = text;
    wrap.append(heading);
    if (hint) {
      const note = document.createElement("p");
      note.className = "hint";
      note.textContent = hint;
      wrap.append(note);
    }
    return wrap;
  }

  /* ------------------------------------------------------------------ render */

  screen.render = (body) => {
    const achievements = achievementEntries();
    const boosts = boostEntries();
    const automations = automationEntries();

    body.append(loopSection());

    body.append(sectionHeading(`Achievements (${achievements.length}) — the mint`,
      "Every crystal in the game comes from claiming one of these tiers. An achievement never "
      + "finishes unless max_tier says so: tier 0 is the first goal, and completing it raises "
      + "both the bar and the payout by the authored growth."));
    body.append(tierLadderSection(achievements));
    achievements.forEach((entry, index) =>
      body.append(achievementCard(entry, index, achievements.length)));

    body.append(sectionHeading(`Boosts (${boosts.length}) — the sink`,
      `Bought with crystals, tiering up every ${levelsPerTier()} levels with no last tier. A `
      + "level multiplies rather than adds, and each tier is worth more per level than the one "
      + "below it, so how far a boost's ceiling is raised is how far the rate keeps climbing."));
    body.append(ladderShapeSection());
    boosts.forEach((entry, index) => body.append(boostCard(entry, index, boosts.length)));

    body.append(sectionHeading(`Automations (${automations.length}) — the other sink`,
      "Also bought with crystals. These buy things on the player's behalf, so their rate is "
      + "measured in runs per tick rather than in a multiplier."));
    automations.forEach((entry, index) =>
      body.append(automationCard(entry, index, automations.length)));

    setStatus(`${achievements.length} achievements · ${boosts.length} boosts · `
      + `${automations.length} automations · payouts unmodified`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.crystals = screen;
})();
