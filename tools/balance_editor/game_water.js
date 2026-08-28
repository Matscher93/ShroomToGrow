/* Water screen: the well, and everything that feeds or drains it.
 *
 * view/well/sc_well.tscn is a pump status line over a flat vertical list of
 * project cards - not a tree. This screen is that, with the authored numbers
 * where the played ones would be, and three sections above the list that the
 * game has no room for.
 *
 * Water is the tightest loop in the game: one source and one sink.
 *
 *   source  the pump. yield = stack("water_production", 1.0), drawn every
 *           interval = max(1, round(clamp(1.0, stack("water_rate", 10.0)))) ticks
 *   sink    well projects, priced in water directly - WellSystem.invest() pays
 *           with the &"water" literal, there is no exchange step
 *
 * About thirty-five authored effects push on those two stats, scattered across
 * biome upgrades, perk branches, boosts, the fertilizer track and the boons
 * themselves. Tuning water meant grepping for them; the cross-reference here is
 * the one thing no other view can give, and it is nearly free because every
 * table is already in memory by the time a screen renders.
 *
 * Three tables meet on a card. ProjectDef holds the price and the gate; its
 * `boons` cell is a list of sub-resource paths into ProjectBoonDef; each of
 * those points at an UpgradeEffectDef, also a sub-resource. Ladder order comes
 * from the `boons` cell, never from the boon table, which the snapshot sorts by
 * path.
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    log10Of, formatBig, growthCurve, effectCurve, enumIs, chartBlock,
    engineSeries, engineCurve, rowsOf, cell, numberCell,
    field, fieldGroup, bigField,
  } = window.GameKit;

  /* WaterSystem's own constants. GDScript `const`s, not .tres - this editor
   * cannot write them, and leaving them out would imply the pump has no
   * baseline. */
  const PUMP = { yield: 1.0, interval: 10.0, minInterval: 1.0 };

  const WATER_STATS = ["water_production", "water_rate"];
  const FALLBACK_LEVELS = 50;    // matches BalanceData.CURVE_OPEN_ENDED_LEVELS

  const screen = {
    label: "Water",
    selected: new Map(),   // project res_path -> boon index, so a redraw keeps the pick
  };

  const list = (value) => (value || "").split("|").filter(Boolean);
  const cellIs = (entry, column, name) => enumIs(cell(entry, column), name);
  /** Enough of a path to place a row without the column running off the card:
   * the folder it sits in and the file itself. */
  function shortPath(path) {
    const parts = (path || "").split("::")[0].replace(/^res:\/\/data\//, "").split("/");
    return parts.slice(-2).join("/");
  }

  /* ----------------------------------------------------------- project order */

  /** The projects in the order ProjectList holds them, which is the order the
   * game stacks the cards in and the order the gates are asserted to climb in.
   * Falls back to the table's own order if the list is missing, so the screen
   * degrades rather than empties. */
  function projectEntries() {
    const listRows = rowsOf("ProjectList");
    const paths = listRows.length ? list(cell(listRows[0], "projects")) : [];
    const rows = rowsOf("ProjectDef");
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    return paths.map((path) => byPath.get(path)).filter(Boolean);
  }

  const projectListRow = () => rowsOf("ProjectList")[0] || null;

  /** A project's boons in ladder order, each with the effect it carries. */
  function boonsOf(entry) {
    return list(cell(entry, "boons")).map((path, index) => {
      const boon = rowIndexOf(path);
      const effectPath = boon ? cell(boon, "effect") : "";
      return {
        index, path, boon,
        effect: effectPath ? rowIndexOf(effectPath) : null,
      };
    });
  }

  /* ------------------------------------------------------------------ curves */

  /** UpgradeSystem.cost() over a project's own fields - the water price of the
   * next funding. */
  function costCurve(entry, from, to) {
    return growthCurve(
      log10Of(numberCell(entry, "_base_cost_mantissa", 1),
        numberCell(entry, "_base_cost_exponent", 1)),
      numberCell(entry, "cost_growth", 1.35),
      numberCell(entry, "cost_growth_exponent", 1),
      from, to);
  }

  /** Total water spent reaching each level, as log10 of the running sum.
   *
   * Summed in linear space through the mantissa, which is safe here and nowhere
   * else on this screen: a project's whole ladder tops out around 1e30, well
   * inside a double. The per-level line is the one that has to stay in log
   * space, and it does. */
  function cumulativeCurve(entry, from, to) {
    const per = costCurve(entry, 0, to);
    if (!per.length) return [];
    const out = [];
    let total = 0;
    for (let level = 0; level <= to; level += 1) {
      const value = per[level];
      if (value !== null && Number.isFinite(value) && value < 300) total += 10 ** value;
      if (level >= from) out.push(total > 0 ? Math.log10(total) : null);
    }
    return out;
  }

  /** A boon's magnitude at each level of the project carrying it.
   *
   * The project's level is the x axis, not the boon's own: a boon's level is
   * (project level - unlock_at_level + 1), and nothing computes that - it falls
   * out of WellSystem.invest() only levelling the boons already open. So the
   * curve sits at zero until the threshold and climbs from there. */
  function boonCurve(slot, from, to) {
    const unlockAt = Math.round(numberCell(slot.boon, "unlock_at_level", 1));
    const shape = {
      perLevel: numberCell(slot.effect, "per_level", 0),
      compound: cellIs(slot.effect, "level_scaling", "COMPOUND"),
      cap: numberCell(slot.effect, "max_magnitude", 0),
      factor: null,
    };
    const out = [];
    for (let projectLevel = from; projectLevel <= to; projectLevel += 1) {
      const own = Math.max(0, projectLevel - unlockAt + 1);
      out.push(effectCurve(shape, own, own).raw[0]);
    }
    return out;
  }

  /* -------------------------------------------------------------- 1. the pump */

  function pumpSection() {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "The pump";
    wrap.append(heading);

    const stats = document.createElement("div");
    stats.className = "water-consts";
    for (const [label, value, note] of [
      ["BASE_YIELD", PUMP.yield, "water one pump draws, before water_production"],
      ["BASE_INTERVAL", PUMP.interval, "ticks between pumps, before water_rate"],
      ["MIN_INTERVAL", PUMP.minInterval, "floor on that gap, so a stack can never pump for free"],
    ]) {
      const row = document.createElement("div");
      row.innerHTML = `<b>${label}</b> <span class="num">${value}</span>`;
      const hint = document.createElement("i");
      hint.textContent = note;
      row.append(hint);
      stats.append(row);
    }
    wrap.append(stats);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "These three are GDScript consts in model/water/gd_water_system.gd, "
      + "not authored resources, so they are shown here but cannot be edited from this "
      + "editor. Water per tick is yield / interval, paid in lumps of yield every "
      + "interval ticks. The pump only runs while Underground Lake is unlocked in the "
      + "current run, and a sporation drains the balance but never the projects.";
    wrap.append(note);
    return wrap;
  }

  /* ------------------------------------------------------------- 2. the input */

  /** The water GrowthProducerDef - the one authored lever on the income side.
   * Its two generated upgrade ids exist only at runtime through
   * GrowthTree.build(), so they appear in no table and are named here instead. */
  function producerSection() {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Water income";
    wrap.append(heading);

    const producer = rowsOf("GrowthProducerDef")
      .find((entry) => cell(entry, "stat") === "water_production");
    if (!producer) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = "No GrowthProducerDef writes water_production.";
      wrap.append(missing);
      return wrap;
    }

    wrap.append(fieldGroup("", producer,
      ["currency", "stat", "scope", "target", "lp_per_level", "daily_per_level"]));

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Level Points and daily claims both stack additively on this producer "
      + "(n levels resolve as 1 + per_level x n), and the shared lp_global_double "
      + "multiplies every producer by 2 for each 10 LP invested. The three upgrade ids "
      + "this generates - lp_water, daily_water, lp_global_double - are built at runtime "
      + "by GrowthTree, so they appear in no table here. The other three producers "
      + "belong to a Growth screen rather than this one.";
    wrap.append(note);
    return wrap;
  }

  /* ------------------------------------------------- 3. everything else water */

  /** Every authored row that pushes on a water stat, wherever it lives.
   *
   * Scanned rather than listed: effects reach their systems by plain StringName,
   * so the only way to know what touches water is to look at every row that
   * names a stat. Boons reach theirs through an `effect` one hop away, which is
   * why the boon's own row is reported as the owner. */
  function waterWriters() {
    const out = [];
    const boonByEffect = new Map();
    for (const boon of rowsOf("ProjectBoonDef")) {
      const effect = cell(boon, "effect");
      if (effect) boonByEffect.set(effect, boon);
    }

    for (const file of state.files) {
      if (!state.loaded.has(file)) continue;
      const data = dataOf(file);
      if (!data.header.includes("stat")) continue;
      for (const entry of rowsOf(file)) {
        const stat = cell(entry, "stat");
        if (!WATER_STATS.includes(stat)) continue;
        const owner = boonByEffect.get(entry.path);
        out.push({
          entry,
          stat,
          file,
          label: owner ? `${cell(owner, "display_name")} (boon)` : labelOf(entry),
          where: shortPath(entry.path),
          // A BoostDef names its rate base_per_level and a producer lp_per_level;
          // neither carries an op, because the tree that expands them fixes it.
          op: cell(entry, "op") || "-",
          perLevel: cell(entry, "per_level") || cell(entry, "base_per_level")
            || cell(entry, "lp_per_level") || "-",
          scaling: cell(entry, "level_scaling") || "-",
        });
      }
    }
    return out.sort((a, b) =>
      a.stat.localeCompare(b.stat) || a.where.localeCompare(b.where));
  }

  function writersSection() {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const rows = waterWriters();

    const heading = document.createElement("h4");
    heading.textContent = `Everything that touches water (${rows.length})`;
    wrap.append(heading);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "water_production multiplies what one pump draws; water_rate is added "
      + "to the tick gap, so its effects are authored negative. Both are found by scanning "
      + "every table with a stat column, which is the only way to know: effects reach their "
      + "systems by plain StringName and nothing links them back.";
    wrap.append(note);

    const table = document.createElement("table");
    table.className = "web-table water-writers";
    const head = table.insertRow();
    for (const column of ["stat", "what", "op", "per level", "scaling", "file"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }

    let lastStat = null;
    for (const row of rows) {
      const tr = table.insertRow();
      if (row.stat !== lastStat) tr.className = "branch";
      lastStat = row.stat;
      tr.insertCell().textContent = row.stat;

      const name = tr.insertCell();
      name.textContent = row.label;
      name.className = "link";
      name.title = "Open this in the graph";
      name.onclick = () => { setFocus(row.entry.path); setView("graph"); };

      tr.insertCell().textContent = row.op;
      tr.insertCell().textContent = row.perLevel;
      tr.insertCell().textContent = row.scaling;
      tr.insertCell().textContent = row.where;
    }
    wrap.append(table);
    return wrap;
  }

  /* --------------------------------------------------------- 4. the ladder */

  /** The gate and the entry price across the whole ladder. Both are asserted to
   * climb with display order by the authored-data tests, so drawing them is what
   * shows a break before the test does. */
  function ladderChart(entries) {
    const gates = entries.map((entry) => numberCell(entry, "min_project_levels", 0));
    const capacity = entries.reduce(
      (total, entry) => total + Math.round(numberCell(entry, "max_level", 0)), 0);

    const block = chartBlock("Entry price along the ladder", [{
      label: "first funding costs",
      points: entries.map((entry) =>
        log10Of(numberCell(entry, "_base_cost_mantissa", 1),
          numberCell(entry, "_base_cost_exponent", 1))),
    }], { log: true, width: 900, height: 200, xLabel: "project" });

    const gateBlock = chartBlock("Well levels needed to open each project", [{
      label: "min_project_levels", points: gates, color: "var(--dirty)",
    }], { zeroBased: true, width: 900, height: 160, xLabel: "project" });

    const capacityNote = document.createElement("p");
    capacityNote.className = "hint";
    const lastGate = gates.length ? gates[gates.length - 1] : 0;
    capacityNote.textContent = `The ladder holds ${capacity} levels in total and the last `
      + `gate opens at ${lastGate}, leaving ${capacity - lastGate} spare - before the depth `
      + "perk, which raises every ceiling further.";

    const wrap = document.createElement("div");
    wrap.className = "game-group";
    wrap.append(block, gateBlock, capacityNote);
    return wrap;
  }

  /* ------------------------------------------------------------- 5. the card */

  function card(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card water-card";
    wrap.append(head(entry, index, total));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["id", "display_name", "description"]));
    body.append(fundingBlock(entry));
    body.append(boonTrack(entry));
    return wrap;
  }

  function head(entry, index, total) {
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

    const gate = Math.round(numberCell(entry, "min_project_levels", 0));
    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    badge.textContent = `${index + 1} / ${total} · `
      + (gate > 0 ? `opens at ${gate} well levels` : "open from the start");
    row.append(badge);

    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.title = "Open this project in the dependency graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    row.append(open);
    return row;
  }

  /* ---------------------------------------------------------------- funding */

  function fundingBlock(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Funding";
    wrap.append(heading);

    const left = document.createElement("div");
    left.className = "game-fields";
    for (const column of ["max_level", "min_project_levels"]) {
      const editor = field(entry, column);
      if (editor) left.append(editor);
    }
    left.append(bigField(entry, "first funding costs (water)", "_base_cost"));
    for (const column of ["cost_growth", "cost_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) left.append(editor);
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "base_cost x cost_growth^(level x cost_growth_exponent^level), paid in "
      + "water. min_project_levels counts fundings across every project, not this one - the "
      + "Well is a self-contained ladder, so a gate only blocks further funding and levels "
      + "bought before a rebalance keep paying out.";
    left.append(note);

    const maxLevel = Math.round(numberCell(entry, "max_level", 0));
    const levels = maxLevel > 0 ? maxLevel : FALLBACK_LEVELS;
    const build = (from, to) => {
      const series = [
        { label: "next funding", points: costCurve(entry, from, to), color: "var(--accent)" },
        { label: "spent in total", points: cumulativeCurve(entry, from, to),
          color: "var(--dirty)", dashed: true },
      ];
      const sampled = engineCurve(entry.path);
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => log10Of(mantissa, exponent));
      if (dots) series.push(dots);
      return series;
    };
    wrap.append(left, chartBlock("Water per funding", build,
      { log: true, xLabel: "level",
        range: { key: "project-cost", from: 0, to: levels, label: "level" } }));
    return wrap;
  }

  /* ------------------------------------------------------------------ boons */

  function boonTrack(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const slots = boonsOf(entry);

    const heading = document.createElement("h4");
    heading.textContent = `Boons (${slots.length})`;
    wrap.append(heading);

    if (!slots.length) {
      const empty = document.createElement("p");
      empty.className = "hint warn";
      empty.textContent = "This project has no boons, so funding it buys nothing.";
      wrap.append(empty);
      return wrap;
    }

    let picked = screen.selected.get(entry.path) ?? 0;
    if (picked >= slots.length) picked = 0;

    const rows = document.createElement("div");
    rows.className = "boon-rows";
    slots.forEach((slot, index) => {
      const button = document.createElement("button");
      button.className = "boon-row";
      button.classList.toggle("selected", index === picked);
      button.classList.toggle("missing", !slot.boon);

      const rung = document.createElement("b");
      rung.textContent = String(index + 1);
      const name = document.createElement("span");
      name.textContent = slot.boon
        ? (cell(slot.boon, "display_name") || "(unnamed)")
        : `${shortPath(slot.path)} — missing`;
      const at = document.createElement("i");
      const unlockAt = Math.round(numberCell(slot.boon, "unlock_at_level", 1));
      at.textContent = `opens Lv ${unlockAt}`;
      const stat = document.createElement("em");
      stat.textContent = slot.effect ? cell(slot.effect, "stat") : "no effect";
      button.append(rung, name, at, stat);

      button.onclick = () => {
        screen.selected.set(entry.path, index);
        renderActiveView();
      };
      rows.append(button);
    });
    wrap.append(rows);

    // One detail block below the rows, rebound to the pick - the game rebinds a
    // single card the same way rather than building one per boon.
    wrap.append(boonDetail(slots[picked], entry));
    return wrap;
  }

  function boonDetail(slot, project) {
    const wrap = document.createElement("div");
    wrap.className = "slot-detail";

    const heading = document.createElement("div");
    heading.className = "web-editor-head";
    const title = document.createElement("h3");
    title.textContent = `Boon ${slot.index + 1} · ${slot.boon
      ? (cell(slot.boon, "display_name") || "(unnamed)") : "missing"}`;
    heading.append(title);
    if (slot.boon) {
      const open = document.createElement("button");
      open.textContent = "Graph";
      open.title = "Open this boon in the dependency graph";
      open.onclick = () => { setFocus(slot.path); setView("graph"); };
      heading.append(open);
    }
    wrap.append(heading);

    if (!slot.boon) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = `${shortPath(project.path)} lists ${slot.path}, but no boon `
        + "answers to it. The rung is dead until one does.";
      wrap.append(missing);
      return wrap;
    }

    wrap.append(fieldGroup("", slot.boon,
      ["display_name", "description", "unlock_at_level"]));

    if (slot.index === 0) {
      const first = document.createElement("p");
      first.className = "hint";
      first.textContent = "This is boon 0: it carries the project's own level and its water "
        + "price, so its unlock_at_level must stay 1. A project whose first rung opens later "
        + "can never be funded at all.";
      wrap.append(first);
    }

    if (!slot.effect) {
      const empty = document.createElement("p");
      empty.className = "hint warn";
      empty.textContent = "This boon has no effect resource, so reaching it does nothing.";
      wrap.append(empty);
      return wrap;
    }
    wrap.append(effectBlock(slot, project));
    return wrap;
  }

  function effectBlock(slot, project) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Effect";
    wrap.append(heading);

    const left = document.createElement("div");
    left.className = "game-fields";
    for (const column of ["stat", "op", "scope", "target", "per_level", "level_scaling",
                          "max_magnitude"]) {
      const editor = field(slot.effect, column);
      if (editor) left.append(editor);
    }

    // water_rate is added to the tick gap, so a helpful boon is authored
    // negative. A positive one slows the pump down, which is almost never meant.
    if (cell(slot.effect, "stat") === "water_rate"
        && numberCell(slot.effect, "per_level", 0) > 0) {
      const wrong = document.createElement("p");
      wrong.className = "hint warn";
      wrong.textContent = "per_level is positive on water_rate, which lengthens the gap "
        + "between pumps. Discounts here are authored negative.";
      left.append(wrong);
    }

    const maxLevel = Math.round(numberCell(project, "max_level", 0));
    const levels = maxLevel > 0 ? maxLevel : FALLBACK_LEVELS;
    const build = (from, to) => {
      const series = [{
        label: `${cell(slot.effect, "stat")} magnitude`,
        points: boonCurve(slot, from, to),
        color: "var(--accent)",
      }];
      const sampled = engineCurve(slot.path);
      const dots = engineSeries(slot.effect, sampled && sampled.effect, from, to,
        ([mantissa, exponent]) => mantissa * 10 ** exponent);
      if (dots) series.push(dots);
      return series;
    };
    wrap.append(left, chartBlock("Magnitude at project level", build,
      { zeroBased: true, xLabel: "project level",
        range: { key: "project-boon", from: 0, to: levels, label: "level" } }));
    return wrap;
  }

  /* ------------------------------------------------------------------ render */

  screen.render = (body) => {
    const entries = projectEntries();
    body.append(pumpSection());
    body.append(producerSection());
    body.append(writersSection());

    if (!entries.length) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No well projects loaded. Press \"Reload from .tres\" and try again.";
      body.append(empty);
      return;
    }

    const listRow = projectListRow();
    if (listRow) {
      const depth = document.createElement("div");
      depth.className = "game-group";
      const heading = document.createElement("h4");
      heading.textContent = "Ladder";
      depth.append(heading, fieldGroup("", listRow,
        ["max_level_perk_id", "max_level_per_perk_level"]));
      const note = document.createElement("p");
      note.className = "hint";
      note.textContent = "Authored on the list rather than per project, because it lifts every "
        + "ceiling at once. A typo in the perk id leaves the whole ladder pinned at its "
        + "authored max_level, with nothing reported at load.";
      depth.append(note);
      body.append(depth);
    }

    body.append(ladderChart(entries));
    entries.forEach((entry, index) => body.append(card(entry, index, entries.length)));

    const boonCount = entries.reduce(
      (total, entry) => total + list(cell(entry, "boons")).length, 0);
    setStatus(`${entries.length} well projects · ${boonCount} boons · `
      + `${waterWriters().length} effects touching water`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.water = screen;
})();
