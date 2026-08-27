/* Biomes screen: every biome as the card the game draws for it.
 *
 * view/biomes/sc_biomes.tscn is a vertical list of biome cards, and each card is
 * a header, a price, a Biome Size row and a 5x2 grid of upgrade slots over one
 * detail panel that rebinds to whichever slot is picked. This screen is that,
 * with the authored numbers where the played ones would be, and every card open
 * at once so two biomes can be compared by scrolling rather than by clicking.
 *
 * Four tables meet here. BiomeList holds the order; a BiomeDef holds the meta
 * and the three prices; upgrade_ids point at UpgradeDefs by id (not by path);
 * each of those points at an UpgradeEffectDef, which points at a
 * ScalingSourceDef. The player never sees that fan-out and neither should whoever
 * is tuning it.
 *
 * The charts mirror the game's formulas rather than calling them, so they move
 * on every keystroke. To keep the mirrors honest the engine's own samples from
 * GET /api/curves are drawn as dots behind them: if a formula here drifts from
 * the one in model/, the dots leave the line.
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    log10Of, growthCurve, effectCurve, enumIs, chartBlock, engineSeries,
    rowsOf, findRow, cell, numberCell,
    field, fieldGroup, bigField, engineCurve,
  } = window.GameKit;

  const SIZE_LEVELS = 50;        // matches BalanceData.CURVE_OPEN_ENDED_LEVELS
  const XP_LEVELS = 40;          // past this the XP needed is beyond any real run
  const SLOT_COLUMNS = 5;        // UpgradeSlotGrid.COLUMNS
  const DEPENDENCY_SIZE = 10;    // the size the "scaled" effect line is drawn at

  const screen = {
    label: "Biomes",
    selected: new Map(),   // biome res_path -> slot index, so a redraw keeps the pick
  };

  const list = (value) => (value || "").split("|").filter(Boolean);

  const cellIs = (entry, column, name) => enumIs(cell(entry, column), name);

  /* ------------------------------------------------------------- biome order */

  /** The biomes in the order BiomeList holds them, which is the order the game
   * stacks the cards in and the order the unlock prices are asserted to rise in.
   * Falls back to the BiomeDef table's own order if the list is missing, so the
   * screen degrades rather than empties. */
  function biomeEntries() {
    const listRows = rowsOf("BiomeList");
    const paths = listRows.length ? list(cell(listRows[0], "biomes")) : [];
    if (!paths.length) return rowsOf("BiomeDef");
    const byPath = new Map(rowsOf("BiomeDef").map((entry) => [entry.path, entry]));
    return paths.map((path) => byPath.get(path)).filter(Boolean);
  }

  /* ------------------------------------------------------------------- curves */

  /** BiomeSystem.size_cost(). Its fields differ from an upgrade's, but the curve
   * underneath is the same one, so the maths lives in GameKit and this only says
   * which columns feed it. */
  function sizeCostCurve(entry, from, to) {
    return growthCurve(
      log10Of(numberCell(entry, "_size_base_cost_mantissa", 0),
        numberCell(entry, "_size_base_cost_exponent", 0)),
      numberCell(entry, "size_cost_growth", 1.15),
      numberCell(entry, "size_cost_growth_exponent", 1),
      from, to);
  }


  /** BiomeCalculator.level_for(), read forwards: the total XP standing at the
   * door of each level. Level 1 is free, level 2 needs 6, and each step after
   * needs round(previous * 1.55). */
  function xpLadder(from, to) {
    const out = [];
    let need = 6;
    let total = 0;
    for (let level = 1; level <= to; level += 1) {
      if (level >= from) out.push(total);
      total += need;
      need = Math.round(need * 1.55);
    }
    return out;
  }

  /** UpgradeEffectDef.magnitude() at each level, and the same scaled by the
   * effect's ScalingSourceDef at a representative biome size. */
  function effectCurves(effectEntry, from, to) {
    const dependency = dependencyOf(effectEntry);
    return effectCurve({
      perLevel: numberCell(effectEntry, "per_level", 0),
      compound: cellIs(effectEntry, "level_scaling", "COMPOUND"),
      cap: numberCell(effectEntry, "max_magnitude", 0),
      factor: dependency ? dependencyFactor(dependency, DEPENDENCY_SIZE) : null,
    }, from, to);
  }

  /** ScalingSourceDef.evaluate() for a BIOME_SIZE source, where the context
   * resolves a biome's size as purchased + 1 - so an unbought biome multiplies
   * by one rather than by zero. */
  function dependencyFactor(dependency, size) {
    if (!cellIs(dependency, "kind", "BIOMESIZE")) return null;
    const value = size + 1;
    if (cellIs(dependency, "transform", "SQRT")) return Math.sqrt(value);
    if (cellIs(dependency, "transform", "LOG10")) return Math.log10(Math.max(1, value));
    return value;
  }

  const dependencyOf = (effectEntry) => {
    const path = cell(effectEntry, "dependency");
    return path ? rowIndexOf(path) : null;
  };

  /* ------------------------------------------------------------ upgrade lookup */

  /** The UpgradeDef, its first effect and that effect's dependency for one slot.
   * upgrade_ids hold ids while the tables are keyed by res_path, so the def is
   * found by its id column - and a slot naming an id nothing answers to is a
   * real authoring error, reported rather than skipped. */
  function slotOf(id) {
    const def = findRow("UpgradeDef", "id", id);
    if (!def) return { id, def: null, effect: null, dependency: null };
    const effectPath = list(cell(def, "effects"))[0];
    const effect = effectPath ? rowIndexOf(effectPath) : null;
    return { id, def, effect, dependency: effect ? dependencyOf(effect) : null };
  }

  const slotsOf = (entry) => list(cell(entry, "upgrade_ids")).map(slotOf);

  /* -------------------------------------------------------------- the ladder */

  /** The three prices across the whole biome order. The authored-data tests
   * assert every one of these rises along the list, so drawing them together is
   * what shows a break before the test does. */
  function ladderChart(entries) {
    const series = [
      { key: "_unlock_cost", label: "unlock" },
      { key: "_size_base_cost", label: "size base" },
      { key: "_auto_unlock_cost", label: "auto-unlock" },
    ].map(({ key, label }) => ({
      label,
      points: entries.map((entry) =>
        log10Of(numberCell(entry, `${key}_mantissa`, 0), numberCell(entry, `${key}_exponent`, 0))),
    }));

    const block = chartBlock("Prices along the biome order", series,
      { log: true, width: 900, height: 210, xLabel: "biome" });

    const names = document.createElement("div");
    names.className = "game-ladder-names";
    entries.forEach((entry) => {
      const name = document.createElement("span");
      name.textContent = cell(entry, "display_name") || cell(entry, "key");
      name.style.setProperty("--tint", cell(entry, "biome_color") || "#888");
      names.append(name);
    });
    block.append(names);
    return block;
  }

  /* ---------------------------------------------------------------- the card */

  function card(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card";
    wrap.style.setProperty("--tint", cell(entry, "biome_color") || "#888");
    wrap.append(head(entry, index, total));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry,
      ["key", "display_name", "description", "xp_label"]));
    body.append(fieldGroup("Wiring", entry,
      ["screen_type", "xp_source", "biome_color", "biome_shader", "always_unlocked"]));
    body.append(costs(entry));
    body.append(progression(entry));
    body.append(track(entry));
    return wrap;
  }

  function head(entry, index, total) {
    const row = document.createElement("header");
    row.className = "game-card-head";

    // The game paints a shader on a ColorRect here; a swatch is as close as a
    // browser gets, and the colour is the part being authored anyway.
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
    badge.textContent = `${index + 1} / ${total} · ${cell(entry, "key")}`;
    row.append(badge);

    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.title = "Open this biome in the dependency graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    row.append(open);
    return row;
  }

  /* ------------------------------------------------------------------- costs */

  function costs(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Costs";
    wrap.append(heading);

    const left = document.createElement("div");
    left.className = "game-fields";
    const currency = field(entry, "unlock_currency");
    if (currency) left.append(currency);
    left.append(bigField(entry, "unlock cost", "_unlock_cost"));
    left.append(bigField(entry, "auto-unlock cost (crystals)", "_auto_unlock_cost"));
    left.append(bigField(entry, "size base cost (nutrients)", "_size_base_cost"));
    for (const column of ["size_cost_growth", "size_cost_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) left.append(editor);
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Biome Size is always paid in nutrients, whatever unlock_currency says. "
      + "Its price is size_base_cost × size_cost_growth^(size × size_cost_growth_exponent^size).";
    left.append(note);

    wrap.append(left, sizeChart(entry));
    return wrap;
  }

  function sizeChart(entry) {
    const build = (from, to) => {
      const series = [
        { label: "size cost", points: sizeCostCurve(entry, from, to), color: "var(--accent)" },
      ];
      const sampled = engineCurve(entry.path);
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => log10Of(mantissa, exponent));
      if (dots) series.push(dots);
      return series;
    };
    return chartBlock("Biome Size price per level", build,
      { log: true, xLabel: "size",
        range: { key: "biome-size", from: 0, to: SIZE_LEVELS, label: "size" } });
  }

  /* -------------------------------------------------------------- progression */

  function progression(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Progression";
    wrap.append(heading);

    const left = document.createElement("div");
    left.className = "game-fields";

    const label = cell(entry, "xp_label") || "xp";
    const source = cell(entry, "xp_source");
    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = `Levels come from ${source || "the XP source"} (“${label}”). `
      + "A level is worth one upgrade point, so the point budget is level − 1 — the "
      + "markers are the biome levels each min_biome_points_spent gate opens at.";
    left.append(note);

    const gates = [...new Set(slotsOf(entry)
      .map((slot) => Math.round(numberCell(slot.def, "min_biome_points_spent", 0)))
      .filter((points) => points > 0))].sort((a, b) => a - b);

    const table = document.createElement("table");
    table.className = "web-table game-gate-table";
    // The gate table lists every gate whatever the chart happens to be showing,
    // so it reads the ladder from the first level rather than from the window.
    const ladder = xpLadder(1, XP_LEVELS);
    const head = table.insertRow();
    for (const column of ["gate", "needs level", "total xp"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }
    for (const points of gates) {
      const level = points + 1;
      const row = table.insertRow();
      row.insertCell().textContent = `${points} pts`;
      row.insertCell().textContent = `Lv ${level}`;
      row.insertCell().textContent = level <= ladder.length
        ? ladder[level - 1].toLocaleString()
        : "beyond the chart";
    }
    if (!gates.length) {
      const row = table.insertRow();
      const only = row.insertCell();
      only.colSpan = 3;
      only.textContent = "no slot is gated — every upgrade is buyable from the first point";
    }
    left.append(table);

    // The gate markers are placed in the chart's own x space, which starts at
    // whatever level the range starts at - a gate before the window is off-chart.
    const build = (from, to) => [
      { label: "total xp to reach",
        points: xpLadder(from, to).map((xp) => (xp > 0 ? Math.log10(xp) : null)) },
    ];
    const chart = chartBlock("XP needed per biome level", build,
      { log: true, xLabel: "level",
        range: { key: "biome-xp", from: 1, to: XP_LEVELS, label: "level" },
        markers: gates.map((points) => ({ at: points + 1, label: `${points}pt` })) });

    wrap.append(left, chart);
    return wrap;
  }

  /* ------------------------------------------------------------ upgrade track */

  function track(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Upgrade track";
    wrap.append(heading);

    const slots = slotsOf(entry);
    if (!slots.length) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "This biome has no upgrade_ids yet. Add them from the graph.";
      wrap.append(empty);
      return wrap;
    }

    let picked = screen.selected.get(entry.path) ?? 0;
    if (picked >= slots.length) picked = 0;

    const grid = document.createElement("div");
    grid.className = "slot-grid";
    grid.style.setProperty("--slot-columns", SLOT_COLUMNS);
    slots.forEach((slot, index) => {
      const button = document.createElement("button");
      button.className = "slot";
      button.classList.toggle("selected", index === picked);
      button.classList.toggle("missing", !slot.def);
      const gate = Math.round(numberCell(slot.def, "min_biome_points_spent", 0));
      button.classList.toggle("gated", gate > 0);

      const number = document.createElement("b");
      number.textContent = String(index + 1);
      const name = document.createElement("span");
      name.textContent = slot.def
        ? (cell(slot.def, "display_name") || slot.id)
        : `${slot.id} — missing`;
      const level = document.createElement("i");
      const max = Math.round(numberCell(slot.def, "max_level", 0));
      level.textContent = `${max > 0 ? `${max} lv` : "∞"}${gate > 0 ? ` · ${gate}pt` : ""}`;
      button.append(number, name, level);

      button.onclick = () => {
        screen.selected.set(entry.path, index);
        renderActiveView();
      };
      grid.append(button);
    });
    wrap.append(grid);

    // One detail block below the grid, rebound to the pick - the same shape the
    // game uses, where a single sc_biome_upgrade_card is rebound rather than ten
    // being built.
    wrap.append(detail(slots[picked], picked, entry));
    return wrap;
  }

  function detail(slot, index, biome) {
    const wrap = document.createElement("div");
    wrap.className = "slot-detail";

    const heading = document.createElement("div");
    heading.className = "web-editor-head";
    const title = document.createElement("h3");
    title.textContent = `Slot ${index + 1} · ${slot.def
      ? (cell(slot.def, "display_name") || slot.id) : slot.id}`;
    heading.append(title);
    if (slot.def) {
      const open = document.createElement("button");
      open.textContent = "Graph";
      open.title = "Open this upgrade in the dependency graph, to rewire or replace it";
      open.onclick = () => { setFocus(slot.def.path); setView("graph"); };
      heading.append(open);
    }
    wrap.append(heading);

    if (!slot.def) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = `${biome.row[0]} lists "${slot.id}", but no UpgradeDef `
        + "carries that id. The slot is dead until one does.";
      wrap.append(missing);
      return wrap;
    }

    wrap.append(fieldGroup("", slot.def,
      ["display_name", "description", "max_level", "min_biome_points_spent"]));

    // base_cost and cost_growth are real columns that this upgrade never uses:
    // a biome upgrade is bought with one biome point per level, full stop. Left
    // visible but folded, because hiding them makes them look absent instead of
    // inert.
    const unused = document.createElement("details");
    unused.className = "game-unused";
    const summary = document.createElement("summary");
    summary.textContent = "Currency cost fields (unused — biome upgrades cost 1 point a level)";
    unused.append(summary);
    unused.append(bigField(slot.def, "base cost", "_base_cost"));
    const growth = fieldGroup("", slot.def, ["cost_growth", "cost_growth_exponent"]);
    unused.append(growth);
    wrap.append(unused);

    wrap.append(effectBlock(slot));
    return wrap;
  }

  function effectBlock(slot) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Effect";
    wrap.append(heading);

    if (!slot.effect) {
      const empty = document.createElement("p");
      empty.className = "hint warn";
      empty.textContent = "This upgrade has no effect resource, so buying it does nothing.";
      wrap.append(empty);
      return wrap;
    }

    const left = document.createElement("div");
    left.className = "game-fields";
    for (const column of ["stat", "op", "scope", "target", "per_level", "level_scaling",
                          "max_magnitude"]) {
      const editor = field(slot.effect, column);
      if (editor) left.append(editor);
    }
    left.append(dependencyChip(slot.dependency));

    const maxLevel = Math.round(numberCell(slot.def, "max_level", 0));
    let capped = false;
    const build = (from, to) => {
      const curves = effectCurves(slot.effect, from, to);
      capped = curves.capped;
      const series = [{ label: "magnitude", points: curves.raw, color: "var(--accent)" }];
      if (curves.scaled) {
        series.push({ label: `× size ${DEPENDENCY_SIZE}`, points: curves.scaled,
          color: "var(--accent)", dashed: true });
      }
      // Keyed on the effect row: per_level is what moves this curve.
      const sampled = engineCurve(slot.def.path);
      const dots = engineSeries(slot.effect, sampled && sampled.effect, from, to,
        ([mantissa, exponent]) => mantissa * 10 ** exponent);
      if (dots) series.push(dots);
      return series;
    };

    // An upgrade's natural end is its own max_level, so the default differs per
    // slot; the range still shares one key, so a window set on one upgrade holds
    // while clicking along the track.
    const block = chartBlock("Total magnitude at level", build,
      { zeroBased: true, xLabel: "level",
        range: { key: "biome-effect", from: 0, to: maxLevel > 0 ? maxLevel : SIZE_LEVELS,
          label: "level" } });

    if (capped) {
      const note = document.createElement("p");
      note.className = "hint";
      note.textContent = "max_magnitude clamps this curve — the flat top is the cap, not the maths.";
      left.append(note);
    }

    wrap.append(left, block);
    return wrap;
  }

  function dependencyChip(dependency) {
    const wrap = document.createElement("div");
    wrap.className = "field";
    const label = document.createElement("label");
    label.textContent = "dependency";
    wrap.append(label);

    if (!dependency) {
      const none = document.createElement("span");
      none.className = "game-chip muted";
      none.textContent = "none — this effect does not scale with anything";
      wrap.append(none);
      return wrap;
    }
    const chip = document.createElement("button");
    chip.className = "game-chip";
    const kind = cell(dependency, "kind") || "?";
    const key = cell(dependency, "key");
    const transform = cell(dependency, "transform");
    chip.textContent = `${kind}${key ? ` · ${key}` : ""}`
      + `${transform && transform.toUpperCase() !== "NONE" ? ` · ${transform}` : ""}`;
    chip.title = "Open this scaling source in the dependency graph";
    chip.onclick = () => { setFocus(dependency.row[0]); setView("graph"); };
    wrap.append(chip);
    return wrap;
  }

  /* ------------------------------------------------------------------ render */

  screen.render = (body) => {
    const entries = biomeEntries();
    if (!entries.length) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No biomes loaded. Press \"Reload from .tres\" and try again.";
      body.append(empty);
      return;
    }
    body.append(ladderChart(entries));
    entries.forEach((entry, index) => body.append(card(entry, index, entries.length)));
    setStatus(`${entries.length} biomes · ${entries.reduce(
      (total, entry) => total + list(cell(entry, "upgrade_ids")).length, 0)} upgrade slots`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.biomes = screen;
})();
