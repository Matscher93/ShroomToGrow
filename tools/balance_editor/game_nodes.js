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
    log10Of, formatBig, growthCurve, effectCurve, enumIs, chartBlock, engineSeries, engineCurve,
    rowsOf, findRow, cell, numberCell, field, fieldGroup, bigField, scopeTargetFields,
    declaredGroups, tagsOfNode, dependencyField, dependencyFactor, dependencyAxis,
  } = window.GameKit;

  const BUY_LEVELS = 50;         // matches BalanceData.CURVE_OPEN_ENDED_LEVELS
  const TRACK_LEVELS = 50;       // both tracks are max_level 0, i.e. open ended
  const DEPENDENCY_AT = 10;      // the dependency level the scaled line starts at

  /** The three stats that land on a tier's own output. potency and synergy
   * multiply into the symbiosis bonus, node_production multiplies over both -
   * ProductionSystem.node_production_bonus() folds them in that order. */
  const NODE_STATS = ["potency_production", "synergy_production", "node_production"];

  // Groups are read through GameKit so the screen and the scope/target control
  // cannot disagree about who is in one.
  const tagsOf = tagsOfNode;
  const declaredTags = declaredGroups;

  /** What the comparison chart plots, and how. Every metric is a curve one card
   * already draws for a single tier; the point of the section is seeing where
   * two tiers cross, which no per-card chart can show. */
  const COMPARE = {
    buy: {
      label: "Buy cost", log: true, xLabel: "nodes owned", to: BUY_LEVELS, unit: "nodes",
      points: (entry, from, to) => buyCurve(entry, from, to),
    },
    potency_cost: {
      // Opens narrower than the rest. The symbiosis tracks carry a
      // cost_growth_exponent of 1.5, which puts level 50 past 1e1000000000 - a
      // real number the engine agrees with, and a useless window to land on.
      label: "Potency cost", log: true, xLabel: "level", to: 25, unit: "potency levels",
      points: (entry, from, to) => trackPoints(entry, "Potency", "cost", from, to),
    },
    potency_effect: {
      label: "Potency magnitude", zeroBased: true, xLabel: "level", to: TRACK_LEVELS,
      points: (entry, from, to) => trackPoints(entry, "Potency", "effect", from, to),
    },
    synergy_cost: {
      label: "Synergy cost", log: true, xLabel: "level", to: 25, unit: "synergy levels",
      points: (entry, from, to) => trackPoints(entry, "Synergy", "cost", from, to),
    },
    synergy_effect: {
      label: "Synergy magnitude", zeroBased: true, xLabel: "level", to: TRACK_LEVELS,
      points: (entry, from, to) => trackPoints(entry, "Synergy", "effect", from, to),
    },
  };

  const screen = {
    label: "Nodes",
    metric: "buy",
    // Which tiers are on the comparison. Null until the first render fills it
    // with every tier, since the list is not known until the data is loaded.
    tiers: null,
  };

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

  /** The track's magnitude at each level, and the same scaled by its
   * ScalingSourceDef at the dependency level `at` - the biome size or node count
   * the track is being previewed at, which the chart's own box sets. */
  function trackEffectCurve(effect, from, to, at) {
    return effectCurve({
      perLevel: numberCell(effect, "per_level", 0),
      compound: cellIs(effect, "level_scaling", "COMPOUND"),
      cap: numberCell(effect, "max_magnitude", 0),
      factor: dependencyFactor(dependencyOf(effect), at ?? DEPENDENCY_AT),
    }, from, to);
  }

  const dependencyOf = (effect) => {
    const path = cell(effect, "dependency");
    return path ? rowIndexOf(path) : null;
  };

  /** One tier's track curve, or an empty series when that tier has no such
   * track - a renumbered tier loses its upgrades silently, and a comparison
   * that quietly dropped it would hide exactly that. */
  function trackPoints(entry, kind, which, from, to) {
    const track = trackOf(kind, cell(entry, "node_id"));
    if (!track.def) return [];
    if (which === "cost") return trackCostCurve(track.def, from, to);
    if (!track.effect) return [];
    return trackEffectCurve(track.effect, from, to).raw;
  }

  /* -------------------------------------------------------- what a price buys */

  /** Levels looked at when counting what a budget buys. Well past anything the
   * cumulative cost can stay finite over, so the count is never cut short by the
   * window rather than by the money. */
  const AFFORD_CAP = 400;

  /** log10(10^a + 10^b).
   *
   * The only safe way to add two of these: a late node on tier 9 costs more than
   * a double can hold, so a running total kept in linear space would be Infinity
   * long before the count meant anything. A term eighteen decades under the
   * larger one cannot move it, so it is dropped rather than underflowed. */
  function logAdd(a, b) {
    const hi = Math.max(a, b);
    const lo = Math.min(a, b);
    return lo - hi < -18 ? hi : hi + Math.log10(1 + 10 ** (lo - hi));
  }

  /** Running total of a price curve: entry n is what levels 0..n cost together. */
  function cumulative(points) {
    const out = [];
    let total = null;
    for (const value of points) {
      if (value === null || !Number.isFinite(value)) break;
      total = total === null ? value : logAdd(total, value);
      out.push(total);
    }
    return out;
  }

  /** How much a budget buys on one ladder, counting from nothing.
   *
   * Cumulative rather than marginal: the question a price on the chart raises is
   * what that much money would actually get you, and the nth level costs
   * everything before it too. Hovering a tier's own curve at level n therefore
   * lands near n on that tier, which is the readout checking itself. */
  function countFor(totals, budget) {
    let n = 0;
    while (n < totals.length && totals[n] <= budget) n += 1;
    return n;
  }

  /** The hover readout: at the price under the pointer, what every tier on the
   * comparison would buy. Only for the cost metrics - a magnitude is not a
   * budget, and node buying and both symbiosis tracks all spend nutrients, so
   * the comparison is between like and like. */
  function affordabilityTip(entries, metric) {
    if (!metric.unit) return null;
    const ladders = entries
      .map((entry) => ({
        name: cell(entry, "name") || `tier ${cell(entry, "node_id")}`,
        totals: cumulative(metric.points(entry, 0, AFFORD_CAP)),
      }))
      .filter((ladder) => ladder.totals.length);
    if (!ladders.length) return null;

    const width = Math.max(...ladders.map((ladder) => ladder.name.length));
    return (series, level, value) => {
      const exponent = Math.floor(value);
      const budget = formatBig(10 ** (value - exponent), exponent);
      const lines = ladders.map((ladder) => {
        const count = countFor(ladder.totals, value);
        // A count that used up the whole window is a floor, not an answer.
        const shown = count >= ladder.totals.length ? `${count}+` : `${count}`;
        return `  ${ladder.name.padEnd(width)}  ${shown}`;
      });
      return `${budget} nutrients buys, from nothing:\n${lines.join("\n")}`;
    };
  }

  /* ----------------------------------------------------------- the comparison */

  /** Every tier's curve for one metric, on one chart.
   *
   * The per-card charts answer "what does this tier do"; only this one answers
   * "which tier is dearer, and from where" - the question behind every decision
   * about the chain. Tiers keep their authored colour rather than taking a
   * generated hue, so a line is matched to a card by eye.
   *
   * No engine dots here: ten mirrored lines with ten sets of samples behind them
   * is unreadable, and the drift check belongs on the per-card charts, which
   * carry it already. */
  function compareSection(entries) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const heading = document.createElement("h4");
    heading.textContent = "Compare tiers";
    wrap.append(heading);

    if (screen.tiers === null) {
      screen.tiers = new Set(entries.map((entry) => cell(entry, "node_id")));
    }
    const metric = COMPARE[screen.metric] || COMPARE.buy;

    const metrics = document.createElement("div");
    metrics.className = "web-modes";
    for (const [key, spec] of Object.entries(COMPARE)) {
      const button = document.createElement("button");
      button.textContent = spec.label;
      button.className = key === screen.metric ? "active" : "";
      button.onclick = () => {
        screen.metric = key;
        renderActiveView();
      };
      metrics.append(button);
    }
    wrap.append(metrics);

    const chips = document.createElement("div");
    chips.className = "node-chips";
    for (const entry of entries) {
      const id = cell(entry, "node_id");
      const chip = document.createElement("button");
      chip.className = screen.tiers.has(id) ? "node-chip on" : "node-chip";
      chip.style.setProperty("--tint", cell(entry, "color") || "#888");
      chip.textContent = cell(entry, "name") || `tier ${id}`;
      chip.onclick = () => {
        if (screen.tiers.has(id)) screen.tiers.delete(id);
        else screen.tiers.add(id);
        renderActiveView();
      };
      chips.append(chip);
    }
    const all = document.createElement("button");
    all.className = "node-chip all";
    const everyOn = entries.every((entry) => screen.tiers.has(cell(entry, "node_id")));
    all.textContent = everyOn ? "none" : "all";
    all.title = everyOn ? "Clear the comparison" : "Put every tier on the comparison";
    all.onclick = () => {
      screen.tiers = everyOn
        ? new Set() : new Set(entries.map((entry) => cell(entry, "node_id")));
      renderActiveView();
    };
    chips.append(all);
    wrap.append(chips);

    const build = (from, to) => entries
      .filter((entry) => screen.tiers.has(cell(entry, "node_id")))
      .map((entry) => ({
        label: cell(entry, "name") || `tier ${cell(entry, "node_id")}`,
        color: cell(entry, "color") || undefined,
        points: metric.points(entry, from, to),
      }));

    wrap.append(chartBlock(metric.label, build, {
      log: metric.log, zeroBased: metric.zeroBased, xLabel: metric.xLabel,
      width: 900, height: 300,
      tipExtra: affordabilityTip(
        entries.filter((entry) => screen.tiers.has(cell(entry, "node_id"))), metric),
      // One range per metric. A buy curve is worth reading over fifty nodes and
      // a symbiosis cost over fifteen levels, so a shared window would open one
      // of them wrong every time the metric changed.
      range: { key: `node-compare-${screen.metric}`, from: 0, to: metric.to,
        label: "level" },
    }));
    return wrap;
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
    body.append(wiringBlock(entry));
    body.append(buyBlock(entry));
    body.append(trackBlock(trackOf("Potency", cell(entry, "node_id")), entry));
    body.append(trackBlock(trackOf("Synergy", cell(entry, "node_id")), entry));
    body.append(reachSection(entry));
    body.append(startingState(entry));
    return wrap;
  }

  /** Wiring, plus the groups this tier belongs to. A group is free text because
   * this is where one is born - there is nowhere else to declare it - so the
   * hint below names who else carries each, and a group of one shows as such.
   */
  function wiringBlock(entry) {
    const wrap = fieldGroup("Wiring", entry,
      ["node_id", "color", "level_font_color", "unlock_perk_id", "tags"]);
    const tags = tagsOf(entry);
    if (!tags.length) return wrap;

    const counts = declaredTags();
    const parts = tags.map((tag) => {
      const others = nodeEntries()
        .filter((other) => other !== entry && tagsOf(other).includes(tag))
        .map((other) => `tier ${cell(other, "node_id")}`);
      return others.length
        ? `${tag}: with ${others.join(", ")}`
        : `${tag}: this tier alone - a group of one is a node-scoped effect ` +
          "written the long way, or a typo";
    });
    const hint = document.createElement("p");
    hint.className = counts.size && parts.some((part) => part.includes("alone"))
      ? "hint warn" : "hint";
    hint.textContent = parts.join(" · ");
    wrap.append(hint);
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
    for (const column of ["stat", "op"]) {
      const editor = field(track.effect, column);
      if (editor) effectFields.append(editor);
    }
    // Paired, because the scope decides what the target may say — see
    // GameKit.scopeTargetFields, which also owns the warning below so a scope
    // changed in place cannot leave the previous scope's complaint standing.
    //
    // scope NODE with target "<tier>" is what keeps a node_production bonus to
    // this tier alone; a target that has drifted off the tier is silent. A group
    // this tier does not carry is the same mistake spelled differently.
    effectFields.append(scopeTargetFields(track.effect, (effect) => {
      const target = cell(effect, "target");
      const nodeId = cell(node, "node_id");
      const wrong = document.createElement("p");
      wrong.className = "hint warn";
      if (cellIs(effect, "scope", "NODE") && target !== nodeId) {
        wrong.textContent = `Scoped to node "${target}" but this is tier ${nodeId} — `
          + "the effect lands on a different tier, or on none.";
        return wrong;
      }
      if (cellIs(effect, "scope", "TAG") && !tagsOf(node).includes(target)) {
        wrong.textContent = `Scoped to group "${target}", which tier ${nodeId} does not carry — `
          + "this tier's own track does not reach it.";
        return wrong;
      }
      return null;
    }));
    for (const column of ["per_level", "level_scaling", "max_magnitude"]) {
      const editor = field(track.effect, column);
      if (editor) effectFields.append(editor);
    }
    const dependency = dependencyField(track.effect);
    if (dependency) effectFields.append(dependency);
    effectSplit.append(effectFields);

    const axis = dependencyAxis(dependencyOf(track.effect));
    let capped = false;
    const effectBuild = (from, to, at) => {
      const level = at ?? DEPENDENCY_AT;
      const curves = trackEffectCurve(track.effect, from, to, level);
      capped = curves.capped;
      const series = [{ label: "magnitude", points: curves.raw, color: "var(--accent)" }];
      if (curves.scaled) {
        series.push({ label: `× ${axis.short} ${level}`, points: curves.scaled,
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
        range: { key: "node-track-effect", from: 0, to: levels, label: "level",
          at: axis ? DEPENDENCY_AT : null,
          atLabel: axis ? axis.short : null, atTitle: axis ? axis.long : null } });
    if (capped) {
      const note = document.createElement("p");
      note.className = "hint";
      note.textContent = "max_magnitude clamps this curve — the flat top is the cap, not the maths.";
      effectFields.append(note);
    }
    effectSplit.append(effectChart);
    return wrap;
  }

  /* ---------------------------------------------------------- starting state */

  /** manual_nodes and auto_nodes are exported, so the reflection offers them
   * like any other field - but they are a running save's counters that happen to
   * be authored with a starting value, not balance. Folded away so they are
   * reachable without sitting among the numbers being tuned. */
  /* ----------------------------------------------------------------- reach */

  /** Enough of a path to place a row without the column running off the card. */
  function shortPath(path) {
    const parts = (path || "").split("::")[0].replace(/^res:\/\/data\//, "").split("/");
    return parts.slice(-2).join("/");
  }

  /** Everything authored anywhere that lands on this tier's own output, and how
   * far each one reaches.
   *
   * Scanned rather than listed: effects reach their systems by plain StringName,
   * so the only way to know what boosts a tier is to look at every row naming a
   * stat. A FertilizerUpgradeDef takes its scope and target from the producer it
   * expands, so it is reported through that producer's row rather than twice. */
  function nodeWriters(entry) {
    const nodeId = cell(entry, "node_id");
    const tags = tagsOf(entry);
    const out = [];

    for (const file of state.files) {
      if (!state.loaded.has(file)) continue;
      const data = dataOf(file);
      if (!data.header.includes("stat")) continue;
      for (const row of rowsOf(file)) {
        const stat = cell(row, "stat");
        if (!NODE_STATS.includes(stat)) continue;

        const target = cell(row, "target");
        let reach = null;
        if (!cell(row, "scope") || cellIs(row, "scope", "GLOBAL")) reach = "every tier";
        else if (cellIs(row, "scope", "NODE") && target === nodeId) reach = "this tier";
        else if (cellIs(row, "scope", "TAG") && tags.includes(target)) reach = `group ${target}`;
        if (!reach) continue;

        out.push({
          entry: row,
          reach,
          stat,
          label: labelOf(row),
          where: shortPath(row.path),
          // A BoostDef names its rate base_per_level and a producer lp_per_level;
          // neither carries an op, because the tree that expands them fixes it.
          op: cell(row, "op") || "—",
          perLevel: cell(row, "per_level") || cell(row, "base_per_level")
            || cell(row, "lp_per_level") || "—",
          scaling: cell(row, "level_scaling") || "—",
        });
      }
    }
    // Widest reach first: what every tier gets is the backdrop the tier's own
    // effects are read against.
    const order = { "every tier": 0, "this tier": 2 };
    const rank = (row) => (row.reach in order ? order[row.reach] : 1);
    return out.sort((a, b) =>
      rank(a) - rank(b) || a.reach.localeCompare(b.reach)
      || a.stat.localeCompare(b.stat) || a.where.localeCompare(b.where));
  }

  function reachSection(entry) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    const rows = nodeWriters(entry);

    const heading = document.createElement("h4");
    heading.textContent = `Everything that boosts tier ${cell(entry, "node_id")} (${rows.length})`;
    wrap.append(heading);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "potency and synergy multiply into this tier's symbiosis bonus and "
      + "node_production multiplies over both. Found by scanning every table with a stat "
      + "column, which is the only way to know: effects reach their systems by plain "
      + "StringName and nothing links them back. A fertilizer upgrade takes its scope from "
      + "the producer it expands, so it is listed as that producer.";
    wrap.append(note);

    const table = document.createElement("table");
    table.className = "web-table water-writers";
    const head = table.insertRow();
    for (const column of ["reach", "stat", "what", "op", "per level", "scaling", "file"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }

    let lastReach = null;
    for (const row of rows) {
      const tr = table.insertRow();
      if (row.reach !== lastReach) tr.className = "branch";
      lastReach = row.reach;
      tr.insertCell().textContent = row.reach;
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

    const cascade = cascadeWarning(entry, rows);
    if (cascade) wrap.append(cascade);
    return wrap;
  }

  /** node_production is applied once per link of the tier cascade, so a bonus
   * reaching K tiers is worth its multiplier to the power K at the nutrient
   * output. That is why the boosts and the growth producers pin themselves to
   * tier 0 — spelled out here, at the point where someone widens one. */
  function cascadeWarning(entry, rows) {
    const tiers = nodeEntries().length;
    const counts = declaredTags();
    const spans = new Map();
    for (const row of rows) {
      if (row.stat !== "node_production") continue;
      if (row.reach === "every tier") spans.set("every tier", tiers);
      else if (row.reach.startsWith("group ")) {
        const size = counts.get(row.reach.slice(6)) || 1;
        if (size > 1) spans.set(row.reach, size);
      }
    }
    if (!spans.size) return null;

    const parts = [...spans].map(([reach, size]) =>
      `${reach} (${size} tiers, so x1.5 there lands as x1.5^${size} in nutrients)`);
    const warn = document.createElement("p");
    warn.className = "hint warn";
    warn.textContent = `node_production above reaches more than this tier: ${parts.join(", ")}. `
      + "The cascade applies it once per link.";
    return warn;
  }

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
    body.append(compareSection(entries));
    entries.forEach((entry, index) => body.append(card(entry, index, entries.length)));

    const missing = entries.filter((entry) =>
      !trackOf("Potency", cell(entry, "node_id")).def
      || !trackOf("Synergy", cell(entry, "node_id")).def).length;
    const groups = declaredTags().size;
    setStatus(`${entries.length} node tiers`
      + (missing ? ` · ${missing} missing a track` : " · every tier has both tracks")
      + ` · ${groups} group${groups === 1 ? "" : "s"}`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.nodes = screen;
})();
