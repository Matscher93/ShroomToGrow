/* Growth screen: the account-wide ladder and the two dailies that ride on it.
 *
 * view/growth/sc_growth_panel.tscn is one sheet with four things stacked in it -
 * the player level and its Level Point budget, the LP investment rows, the daily
 * producer chips, and the fourteen-day reward track. Three tables and a GDScript
 * constant meet there, and none of them sit next to each other anywhere else:
 *
 *   PlayerLevelCurve     what a level costs in lifetime nutrients
 *   GrowthProducerDef    lp_per_level and daily_per_level, one row per producer
 *   DailyTrackSlotDef    the fourteen slots, in DailyTrackList order
 *
 * The one number here that is *not* authored is PlayerLevelSystem.LP_PER_DOUBLE,
 * the ten invested points that double every producer. It is a GDScript const, so
 * it is shown and used in the charts below but cannot be edited from here - the
 * same treatment game_water.js gives the pump's constants.
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    log10Of, formatBig, fromLog10, chartBlock,
    rowsOf, cell, numberCell, field, fieldGroup,
  } = window.GameKit;

  /* PlayerLevelSystem's own constant. Ten invested Level Points, wherever they
   * were spent, buy one more doubling of every producer. */
  const LP_PER_DOUBLE = 10;

  /* How far out the default windows look. Forty levels is well past where the
   * authored curve leaves float range, which is the point: the chart is drawn in
   * log10 so the late game is legible at all. */
  const LADDER_LEVELS = 40;
  const LP_POINTS = 40;
  const DAILY_DAYS = 60;

  const screen = {
    label: "Growth",
  };

  const list = (value) => (value || "").split("|").filter(Boolean);

  /* ------------------------------------------------------------------ tables */

  const curveRow = () => rowsOf("PlayerLevelCurve")[0] || null;

  /** The producers in the order GrowthProducerList holds them, which is the order
   * the sheet stacks the rows in. The table itself is sorted by path, so
   * nutrients would otherwise come after biomass. */
  function producerEntries() {
    const listRows = rowsOf("GrowthProducerList");
    const paths = listRows.length ? list(cell(listRows[0], "producers")) : [];
    const rows = rowsOf("GrowthProducerDef");
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    const ordered = paths.map((path) => byPath.get(path)).filter(Boolean);
    // Anything the list forgot still gets shown, rather than silently vanishing
    // from the only screen that would have caught the omission.
    for (const entry of rows) if (!paths.includes(entry.path)) ordered.push(entry);
    return ordered;
  }

  /** The fourteen slots in DailyTrackList order - which is the day order, and the
   * only place it exists. The slot rows are sub-resources sorted by path. */
  function trackEntries() {
    const listRows = rowsOf("DailyTrackList");
    const paths = listRows.length ? list(cell(listRows[0], "slots")) : [];
    const rows = rowsOf("DailyTrackSlotDef");
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    return paths.map((path) => byPath.get(path)).filter(Boolean);
  }

  /** A currency def path as the word the game shows. The defs are one table over
   * and carry the display name, but the file name is enough to label a row and
   * needs no second lookup to stay right. */
  function currencyName(path) {
    const match = /res_(\w+?)_def\.tres/.exec(path || "");
    if (!match) return "?";
    return match[1].replace(/^\w/, (c) => c.toUpperCase());
  }

  /* ------------------------------------------------------------- 1. the ladder */

  const curveBase = () => numberCell(curveRow(), "base", 0);
  const curveGrowth = () => numberCell(curveRow(), "growth", 0);
  /* PlayerLevelCalculator._exponent_of() reads a non-positive exponent as 1.0
   * rather than as authored, so the chart has to do the same or it would draw a
   * ladder the game never walks. */
  const curveExponent = () => {
    const value = numberCell(curveRow(), "growth_exponent", 1);
    return value > 0 ? value : 1;
  };

  /** log10 of the lifetime nutrients level n costs, which is what
   * PlayerLevelCalculator.requirement() computes:
   * base * growth^((n - 1)^growth_exponent).
   *
   * Level 0 is free by definition and is left off the line rather than plotted
   * at zero, where a log axis has no place to put it. */
  function ladderCurve(from, to) {
    const base = curveBase();
    const growth = curveGrowth();
    const exponent = curveExponent();
    if (base <= 0 || growth <= 0) return [];
    const out = [];
    for (let level = from; level <= to; level += 1) {
      out.push(level <= 0
        ? null
        : Math.log10(base) + Math.pow(level - 1, exponent) * Math.log10(growth));
    }
    return out;
  }

  /** The straight-ratio ladder the exponent bends away from, so the chart shows
   * what the knob is actually doing rather than one unplaceable line. Drawn
   * only when the exponent is off 1.0, where the two lines coincide. */
  function flatLadderCurve(from, to) {
    const base = curveBase();
    const growth = curveGrowth();
    if (base <= 0 || growth <= 0) return [];
    const out = [];
    for (let level = from; level <= to; level += 1) {
      out.push(level <= 0 ? null : Math.log10(base) + (level - 1) * Math.log10(growth));
    }
    return out;
  }

  /** How much dearer level 30 gets at a modest exponent, as a plain ratio - the
   * one number that makes the knob's reach obvious before it is turned. Read off
   * the authored base and growth so it stays true after a retune. */
  function exponentBiteText() {
    const growth = curveGrowth();
    if (growth <= 1) return "far more";
    const extra = (Math.pow(29, 1.2) - 29) * Math.log10(growth);
    return `10^${extra.toFixed(0)} times as much as at 1.0`;
  }

  function ladderSection() {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "The level ladder";
    wrap.append(heading);

    const entry = curveRow();
    if (!entry) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = "No PlayerLevelCurve loaded. Press \"Reload from .tres\" and try again.";
      wrap.append(missing);
      return wrap;
    }

    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["base", "growth", "growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Levels off lifetime nutrients, which no sporation resets - this is the "
      + "one ladder that measures the account rather than the run. Level n costs "
      + "base x growth^((n-1)^growth_exponent), and the level IS the Level Point budget: one "
      + "point per level, so this curve alone decides how fast the Growth sheet fills up. "
      + "growth_exponent 1.0 is the flat-ratio ladder - every level costs exactly `growth` "
      + "times the one before. Above 1.0 that ratio itself climbs, stretching the late levels "
      + "without touching the first few; below 1.0 the ladder flattens out. It bites hard: at "
      + "1.2 level 30 already costs about " + exponentBiteText() + ". growth at or below 1.0 "
      + "is degenerate and PlayerLevelCalculator reads the whole ladder as level 0; a "
      + "growth_exponent at or below 0.0 is read as 1.0.";
    fields.append(note);

    const table = document.createElement("div");
    table.className = "growth-ladder";
    for (const level of [1, 5, 10, 20, 30]) {
      const log = ladderCurve(level, level)[0];
      const row = document.createElement("div");
      const value = log === null || !Number.isFinite(log)
        ? "-" : formatBig(...fromLog10(log));
      row.innerHTML = `<b>Lv ${level}</b> <span class="num">${value}</span>`;
      const hint = document.createElement("i");
      hint.textContent = "lifetime nutrients";
      row.append(hint);
      table.append(row);
    }
    fields.append(table);
    wrap.append(fields);

    wrap.append(chartBlock("Lifetime nutrients to reach a level",
      (from, to) => {
        const lines = [{ label: "requirement", points: ladderCurve(from, to) }];
        // At an exponent of 1.0 the two are the same line, and a second one
        // drawn over it reads as a bug rather than as a comparison.
        if (curveExponent() !== 1) {
          lines.push({ label: "exponent 1.0", points: flatLadderCurve(from, to) });
        }
        return lines;
      },
      { log: true, xLabel: "level",
        range: { key: "growth-ladder", from: 1, to: LADDER_LEVELS, label: "level" } }));
    return wrap;
  }

  /* ---------------------------------------------------------- 2. the LP boosts */

  /** What one producer is multiplied by with n Level Points in it.
   *
   * Two factors, the same two GrowthViewModel splices together: the producer's
   * own additive stacks (1 + lp_per_level x n) and the doubling every producer
   * shares (2 ^ floor(total / 10)). The chart puts every point into the one
   * producer, so its own count IS the total - which is the fastest a single row
   * can be driven, and the honest ceiling to tune against. */
  function lpCurve(entry, from, to) {
    const perLevel = numberCell(entry, "lp_per_level", 0);
    const out = [];
    for (let points = from; points <= to; points += 1) {
      const additive = 1 + perLevel * points;
      const doublings = Math.floor(points / LP_PER_DOUBLE);
      out.push(Math.log10(additive) + doublings * Math.log10(2));
    }
    return out;
  }

  function lpSection(entries) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Level Point boosts";
    wrap.append(heading);

    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const entry of entries) {
      const group = fieldGroup(currencyName(cell(entry, "currency")), entry, ["lp_per_level"]);
      if (group) fields.append(group);
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = `Stacks additively: n points resolve as 1 + lp_per_level x n on that `
      + `producer's stat. On top of it every ${LP_PER_DOUBLE} points invested - across all `
      + `producers, not per row - double every producer at once. That doubling is `
      + `PlayerLevelSystem.LP_PER_DOUBLE, a GDScript const, so it cannot be edited here; it is `
      + `what the sheet's "+N" button tops up to. The upgrade ids these generate (lp_nutrients, `
      + `lp_water, lp_biomass, lp_global_double) are built at runtime by GrowthTree and appear `
      + `in no table.`;
    fields.append(note);
    wrap.append(fields);

    wrap.append(chartBlock("Producer multiplier, every point into one row",
      (from, to) => entries.map((entry) => ({
        label: currencyName(cell(entry, "currency")),
        points: lpCurve(entry, from, to),
      })),
      { log: true, xLabel: "Level Points invested",
        range: { key: "growth-lp", from: 0, to: LP_POINTS, label: "points" } }));
    return wrap;
  }

  /* ------------------------------------------------------- 3. the daily boosts */

  /** A producer's multiplier after n daily claims: 1 + daily_per_level x n.
   *
   * Linear, and deliberately drawn on a linear axis - a daily stack is meant to
   * be read as "a month of turning up is worth this much", which a log axis
   * hides. */
  function dailyCurve(entry, from, to) {
    const perLevel = numberCell(entry, "daily_per_level", 0);
    const out = [];
    for (let days = from; days <= to; days += 1) out.push(1 + perLevel * days);
    return out;
  }

  function dailySection(entries) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Daily producer boosts";
    wrap.append(heading);

    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const entry of entries) {
      const group = fieldGroup(currencyName(cell(entry, "currency")), entry, ["daily_per_level"]);
      if (group) fields.append(group);
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Every producer is claimable once per local calendar day, and each claim "
      + "is a permanent stack that survives prestige - so this number is priced per day of the "
      + "game's whole life, not per run. The chips are shown as a percentage (+8% after four "
      + "claims), which is 1 + daily_per_level x claims resolved additively, exactly like a "
      + "Level Point. Days to double a producer: "
      + entries.map((entry) => {
        const perLevel = numberCell(entry, "daily_per_level", 0);
        const days = perLevel > 0 ? Math.ceil(1 / perLevel) : null;
        return `${currencyName(cell(entry, "currency"))} ${days === null ? "never" : days}`;
      }).join(" · ") + ".";
    fields.append(note);
    wrap.append(fields);

    wrap.append(chartBlock("Producer multiplier after n daily claims",
      (from, to) => entries.map((entry) => ({
        label: currencyName(cell(entry, "currency")),
        points: dailyCurve(entry, from, to),
      })),
      { xLabel: "daily claims",
        range: { key: "growth-daily", from: 0, to: DAILY_DAYS, label: "claims" } }));
    return wrap;
  }

  /* -------------------------------------------------------- 4. the reward track */

  function trackSection(entries) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Daily reward track";
    wrap.append(heading);

    if (!entries.length) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = "No DailyTrackSlotDef rows loaded.";
      wrap.append(missing);
      return wrap;
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "One slot per day, claimed on its own press and reset by a missed day. "
      + "A slot pays max(min_amount, pct_of_balance x balance + flat_amount) of its currency - "
      + "the same rule RandomEventDef uses, so a payout stays meaningful at every point on the "
      + "curve and the floor carries the start of one. A slot whose currency the player has no "
      + "screen for yet pays the deepest one they have reached, so the later days can name late "
      + "resources safely. Both columns are asserted to climb every day by "
      + "authored_data_test.gd.";
    wrap.append(note);

    const grid = document.createElement("div");
    grid.className = "growth-track";
    entries.forEach((entry, index) => {
      const cellWrap = document.createElement("div");
      cellWrap.className = "growth-track-slot";
      const title = document.createElement("h5");
      title.textContent = `Day ${index + 1} · ${currencyName(cell(entry, "currency"))}`;
      cellWrap.append(title);
      const fields = document.createElement("div");
      fields.className = "game-fields";
      for (const column of ["pct_of_balance", "flat_amount", "min_amount"]) {
        const editor = field(entry, column);
        if (editor) fields.append(editor);
      }
      cellWrap.append(fields);
      grid.append(cellWrap);
    });
    wrap.append(grid);

    wrap.append(chartBlock("Floor paid on each day",
      (from, to) => [{
        label: "min_amount",
        points: entries.slice(from, to + 1).map(
          (entry) => log10Of(numberCell(entry, "min_amount", 0), 0)),
      }],
      { log: true, xLabel: "day",
        range: { key: "growth-track", from: 0, to: entries.length - 1, label: "day" } }));
    return wrap;
  }

  /* ------------------------------------------------------------------ render */

  screen.render = (body) => {
    const producers = producerEntries();
    const track = trackEntries();

    body.append(ladderSection());

    if (!producers.length) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No growth producers loaded. Press \"Reload from .tres\" and try again.";
      body.append(empty);
    } else {
      body.append(lpSection(producers));
      body.append(dailySection(producers));
    }
    body.append(trackSection(track));

    const base = curveBase();
    const growth = curveGrowth();
    const exponent = curveExponent();
    // Bracketed once bent: "3^(n-1)^1.35" reads as the wrong association.
    const step = exponent === 1 ? "(n-1)" : `((n-1)^${exponent})`;
    setStatus(`level ${base || "?"} x ${growth || "?"}^${step} · ${producers.length} producers · `
      + `${track.length}-day reward track`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.growth = screen;
})();
