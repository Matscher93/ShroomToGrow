/* Nodes screen: every mycelium tier as the card the game draws for it.
 *
 * view/mycelium_node/sc_nodes_panel.tscn is a vertical stack of tier cards, and
 * each card is a header, a buy button, and the potency and synergy tracks under
 * it. This screen is that, with the authored numbers where the played ones would
 * be, and every card open at once so two tiers can be compared by scrolling.
 *
 * Three curves meet on a card, and none of them can be read off the fields:
 *
 *   buy      MyceliumNodeData.upgrade_cost() - what the next node of this tier
 *            costs by hand, which is the whole early game
 *   potency  the tier's NodePotency<n> upgrade, compounding
 *   synergy  its NodeSynergy<n>, scaled by the symbiosis biome's size
 *
 * The buy price and the two tracks live in different files - a MyceliumNode
 * under data/mycelium_nodes, its upgrades under data/upgrades/symbiosis/node<n>
 * - and the tier is the only thing that connects them.
 *
 * The maths is mirrored from the game rather than called, so the charts move on
 * every keystroke; the engine's own samples ride behind as dots, so a mirror
 * that drifts shows it.
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    log10Of, growthCurve, effectCurve, enumIs, chartBlock, engineSeries, engineCurve,
    rowsOf, findRow, cell, numberCell, field, fieldGroup, bigField,
  } = window.GameKit;

  const BUY_LEVELS = 50;         // matches BalanceData.CURVE_OPEN_ENDED_LEVELS
  const TRACK_LEVELS = 50;       // both tracks are max_level 0, i.e. open ended
  const DEPENDENCY_SIZE = 10;    // the biome size the scaled synergy line is drawn at

  const screen = { label: "Nodes" };

  const list = (value) => (value || "").split("|").filter(Boolean);
  const cellIs = (entry, column, name) => enumIs(cell(entry, column), name);

  /* -------------------------------------------------------------- tier order */

  /** The tiers in the order MyceliumNodes holds them, which is the order the
   * game stacks the cards in and the order each tier unlocks the next. Falls
   * back to the table's own order if the list is missing, so the screen degrades
   * rather than empties. */
  function nodeEntries() {
    const listRows = rowsOf("MyceliumNodes");
    const paths = listRows.length ? list(cell(listRows[0], "mycelium_nodes")) : [];
    const rows = rowsOf("MyceliumNode");
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    return paths.map((path) => byPath.get(path)).filter(Boolean);
  }

  /* ------------------------------------------------------------------ tracks */

  /** A tier's two symbiosis upgrades. They are keyed by id - NodePotency3,
   * NodeSynergy3 - with nothing but the tier number linking them to the node,
   * so a renumbered tier silently loses its tracks and this says so rather than
   * drawing a card that looks complete. */
  function trackOf(kind, nodeId) {
    const id = `Node${kind}${nodeId}`;
    const def = findRow("UpgradeDef", "id", id);
    if (!def) return { kind, id, def: null, effect: null };
    const effectPath = list(cell(def, "effects"))[0];
    return { kind, id, def, effect: effectPath ? rowIndexOf(effectPath) : null };
  }

  /* ------------------------------------------------------------------ curves */

  /** MyceliumNodeData.upgrade_cost(). Its fields are named for nodes rather than
   * for upgrades, but the curve underneath is the one in GameKit. */
  function buyCurve(entry, from, to) {
    return growthCurve(
      log10Of(numberCell(entry, "_initial_cost_mantissa", 1),
        numberCell(entry, "_initial_cost_exponent", 1)),
      numberCell(entry, "cost_increase_per_level", 1.5),
      numberCell(entry, "cost_growth_exponent", 1.2),
      from, to);
  }

  /** UpgradeSystem.cost() over a track's own fields. */
  function trackCostCurve(def, from, to) {
    return growthCurve(
      log10Of(numberCell(def, "_base_cost_mantissa", 1),
        numberCell(def, "_base_cost_exponent", 0)),
      numberCell(def, "cost_growth", 1.15),
      numberCell(def, "cost_growth_exponent", 1),
      from, to);
  }

  function trackEffectCurve(effect, from, to) {
    const dependency = cell(effect, "dependency")
      ? rowIndexOf(cell(effect, "dependency")) : null;
    return effectCurve({
      perLevel: numberCell(effect, "per_level", 0),
      compound: cellIs(effect, "level_scaling", "COMPOUND"),
      cap: numberCell(effect, "max_magnitude", 0),
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

  /* -------------------------------------------------------------- the ladder */

  /** What each tier costs to start on, across the whole chain. A tier's first
   * node is the price of entry to it, and how those step up is the shape of the
   * whole early game.
   *
   * Only the first node, deliberately. A tier's fiftieth costs upwards of 1e29000
   * with the exponents as authored, and putting that on the same axis flattens
   * the entry prices - which span a mere eighteen decades - into one straight
   * line at the floor. How far a single tier runs away is what its own card
   * shows. */
  function ladderChart(entries) {
    const series = [{
      label: "price of the first node",
      points: entries.map((entry) =>
        log10Of(numberCell(entry, "_initial_cost_mantissa", 1),
          numberCell(entry, "_initial_cost_exponent", 1))),
    }];

    const block = chartBlock("Entry price along the tier chain", series,
      { log: true, width: 900, height: 210, xLabel: "tier" });

    const names = document.createElement("div");
    names.className = "game-ladder-names";
    entries.forEach((entry) => {
      const name = document.createElement("span");
      name.textContent = cell(entry, "name") || `tier ${cell(entry, "node_id")}`;
      name.style.setProperty("--tint", cell(entry, "color") || "#888");
      names.append(name);
    });
    block.append(names);
    return block;
  }

  /* ---------------------------------------------------------------- the card */

  function card(entry, index, total) {
    const wrap = document.createElement("section");
    wrap.className = "game-card";
    wrap.style.setProperty("--tint", cell(entry, "color") || "#888");
    wrap.append(head(entry, index, total));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["name", "desc"]));
    body.append(fieldGroup("Wiring", entry,
      ["node_id", "color", "level_font_color", "unlock_perk_id"]));
    body.append(buyBlock(entry));
    body.append(trackBlock(trackOf("Potency", cell(entry, "node_id")), entry));
    body.append(trackBlock(trackOf("Synergy", cell(entry, "node_id")), entry));
    body.append(startingState(entry));
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
    name.textContent = cell(entry, "name") || "(unnamed)";
    const description = document.createElement("span");
    description.textContent = cell(entry, "desc");
    names.append(name, description);
    row.append(names);

    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    const perk = cell(entry, "unlock_perk_id");
    badge.textContent = `tier ${cell(entry, "node_id")} · ${index + 1} / ${total}`
      + (perk ? ` · needs ${perk}` : " · open from the start");
    row.append(badge);

    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.title = "Open this tier in the dependency graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    row.append(open);
    return row;
  }

  /* ---------------------------------------------------------------- buy cost */

  function buyBlock(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-split";
    const heading = document.createElement("h4");
    heading.textContent = "Manual buy price";
    wrap.append(heading);

    const left = document.createElement("div");
    left.className = "game-fields";
    left.append(bigField(entry, "first node costs (nutrients)", "_initial_cost"));
    for (const column of ["cost_increase_per_level", "cost_growth_exponent"]) {
      const editor = field(entry, column);
      if (editor) left.append(editor);
    }
    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "initial_cost × cost_increase_per_level^(bought × cost_growth_exponent^bought). "
      + "The exponent is the one that bites: above 1 the price stops being a "
      + "geometric climb and starts running away.";
    left.append(note);

    const build = (from, to) => {
      const series = [
        { label: "cost of the next node", points: buyCurve(entry, from, to),
          color: "var(--accent)" },
      ];
      const sampled = engineCurve(entry.path);
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => log10Of(mantissa, exponent));
      if (dots) series.push(dots);
      return series;
    };
    wrap.append(left, chartBlock("Price of the next node", build,
      { log: true, xLabel: "nodes owned",
        range: { key: "node-buy", from: 0, to: BUY_LEVELS, label: "node" } }));
    return wrap;
  }

  /* ------------------------------------------------------------------ tracks */

  function trackBlock(track, node) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = `${track.kind} track`;
    wrap.append(heading);

    if (!track.def) {
      const missing = document.createElement("p");
      missing.className = "hint warn";
      missing.textContent = `No UpgradeDef carries the id "${track.id}". `
        + "The tracks are found by tier number, so this tier has no "
        + `${track.kind.toLowerCase()} upgrade until one does.`;
      wrap.append(missing);
      return wrap;
    }

    const split = document.createElement("div");
    split.className = "game-split";
    wrap.append(split);

    const left = document.createElement("div");
    left.className = "game-fields";
    for (const column of ["display_name", "description", "max_level"]) {
      const editor = field(track.def, column);
      if (editor) left.append(editor);
    }
    left.append(bigField(track.def, "base cost", "_base_cost"));
    for (const column of ["cost_growth", "cost_growth_exponent"]) {
      const editor = field(track.def, column);
      if (editor) left.append(editor);
    }
    split.append(left);

    const maxLevel = Math.round(numberCell(track.def, "max_level", 0));
    const levels = maxLevel > 0 ? maxLevel : TRACK_LEVELS;
    const costBuild = (from, to) => {
      const series = [
        { label: "cost of the next level", points: trackCostCurve(track.def, from, to),
          color: "var(--accent)" },
      ];
      const sampled = engineCurve(track.def.path);
      const dots = engineSeries(track.def, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => log10Of(mantissa, exponent));
      if (dots) series.push(dots);
      return series;
    };
    split.append(chartBlock(`${track.kind} price per level`, costBuild,
      { log: true, xLabel: "level",
        range: { key: "node-track-cost", from: 0, to: levels, label: "level" } }));

    if (!track.effect) {
      const empty = document.createElement("p");
      empty.className = "hint warn";
      empty.textContent = "This upgrade has no effect resource, so buying it does nothing.";
      wrap.append(empty);
      return wrap;
    }

    const effectSplit = document.createElement("div");
    effectSplit.className = "game-split";
    wrap.append(effectSplit);

    const effectFields = document.createElement("div");
    effectFields.className = "game-fields";
    for (const column of ["stat", "op", "scope", "target", "per_level", "level_scaling",
                          "max_magnitude"]) {
      const editor = field(track.effect, column);
      if (editor) effectFields.append(editor);
    }
    effectFields.append(dependencyChip(track.effect));
    // scope NODE with target "<tier>" is what keeps a node_production bonus to
    // this tier alone; a target that has drifted off the tier is silent.
    const target = cell(track.effect, "target");
    const nodeId = cell(node, "node_id");
    if (cellIs(track.effect, "scope", "NODE") && target !== nodeId) {
      const wrong = document.createElement("p");
      wrong.className = "hint warn";
      wrong.textContent = `Scoped to node "${target}" but this is tier ${nodeId} — `
        + "the effect lands on a different tier, or on none.";
      effectFields.append(wrong);
    }
    effectSplit.append(effectFields);

    let capped = false;
    const effectBuild = (from, to) => {
      const curves = trackEffectCurve(track.effect, from, to);
      capped = curves.capped;
      const series = [{ label: "magnitude", points: curves.raw, color: "var(--accent)" }];
      if (curves.scaled) {
        series.push({ label: `× biome size ${DEPENDENCY_SIZE}`, points: curves.scaled,
          color: "var(--accent)", dashed: true });
      }
      // Keyed on the effect row, not the def: per_level lives on the effect,
      // and that is the field that moves this curve.
      const sampled = engineCurve(track.def.path);
      const dots = engineSeries(track.effect, sampled && sampled.effect, from, to,
        ([mantissa, exponent]) => mantissa * 10 ** exponent);
      if (dots) series.push(dots);
      return series;
    };
    const effectChart = chartBlock(`${track.kind} magnitude at level`, effectBuild,
      { zeroBased: true, xLabel: "level",
        range: { key: "node-track-effect", from: 0, to: levels, label: "level" } });
    if (capped) {
      const note = document.createElement("p");
      note.className = "hint";
      note.textContent = "max_magnitude clamps this curve — the flat top is the cap, not the maths.";
      effectFields.append(note);
    }
    effectSplit.append(effectChart);
    return wrap;
  }

  function dependencyChip(effect) {
    const wrap = document.createElement("div");
    wrap.className = "field";
    const label = document.createElement("label");
    label.textContent = "dependency";
    wrap.append(label);

    const path = cell(effect, "dependency");
    const dependency = path ? rowIndexOf(path) : null;
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
      + `${transform && !enumIs(transform, "NONE") ? ` · ${transform}` : ""}`;
    chip.title = "Open this scaling source in the dependency graph";
    chip.onclick = () => { setFocus(dependency.row[0]); setView("graph"); };
    wrap.append(chip);
    return wrap;
  }

  /* ---------------------------------------------------------- starting state */

  /** manual_nodes and auto_nodes are exported, so the reflection offers them
   * like any other field - but they are a running save's counters that happen to
   * be authored with a starting value, not balance. Folded away so they are
   * reachable without sitting among the numbers being tuned. */
  function startingState(entry) {
    const details = document.createElement("details");
    details.className = "game-unused";
    const summary = document.createElement("summary");
    summary.textContent = "Starting state (live counters, not balance)";
    details.append(summary);
    const editor = field(entry, "manual_nodes");
    if (editor) details.append(editor);
    details.append(bigField(entry, "auto nodes", "_auto_nodes"));
    return details;
  }

  /* ------------------------------------------------------------------ render */

  screen.render = (body) => {
    const entries = nodeEntries();
    if (!entries.length) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No mycelium nodes loaded. Press \"Reload from .tres\" and try again.";
      body.append(empty);
      return;
    }
    body.append(ladderChart(entries));
    entries.forEach((entry, index) => body.append(card(entry, index, entries.length)));

    const missing = entries.filter((entry) =>
      !trackOf("Potency", cell(entry, "node_id")).def
      || !trackOf("Synergy", cell(entry, "node_id")).def).length;
    setStatus(`${entries.length} node tiers`
      + (missing ? ` · ${missing} missing a track` : " · every tier has both tracks"));
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.nodes = screen;
})();
