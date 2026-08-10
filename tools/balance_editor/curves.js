/* Curves view: what a cost or an effect actually does over its levels.
 *
 * Every priced row - anything with a base_cost and a cost_growth, so UpgradeDefs
 * and PerkNodeDefs alike - can be plotted, several at once, on a log scale.
 *
 * The maths here mirrors UpgradeSystem.cost() and UpgradeEffectDef.magnitude()
 * rather than calling them, because a Godot round trip per keystroke would make
 * tuning unusable. To keep that mirror honest, the samples the engine itself
 * produced (GET /api/curves) are drawn as dots behind every unedited line: if
 * this file ever drifts from the game, the dots leave the curve.
 *
 * Registered on window.BalanceViews, which index.html turns into a view button.
 */
(() => {
  const MANTISSA = "_base_cost_mantissa";
  const EXPONENT = "_base_cost_exponent";
  const OPEN_ENDED_LEVELS = 50;   // matches BalanceData.CURVE_OPEN_ENDED_LEVELS

  const MODES = {
    cost: { label: "Cost", axis: "cost of the next level" },
    effect: { label: "Effect", axis: "total effect at level" },
    roi: { label: "Effect per cost", axis: "effect gained per unit spent" },
  };

  const view = {
    label: "Curves",
    title: "Cost, effect and effect-per-cost over levels",
    mode: "cost",
    selected: new Set(),   // res_path
    reference: {},         // res_path -> the engine's own samples
    filter: "",
    defs: [],              // every priced row as definitionOf() reduced it
    dom: {},               // the panel parts refresh() updates in place
  };

  /* ------------------------------------------------------------- reading rows */

  /** Every row the cost formula applies to, in file order. */
  function pricedRows() {
    const out = [];
    for (const file of state.files) {
      if (!state.loaded.has(file)) continue;
      const data = dataOf(file);
      if (!data.header.includes(MANTISSA) || !data.header.includes("cost_growth")) continue;
      data.rows.forEach((row, rowIndex) =>
        out.push({ file, rowIndex, header: data.header, row, path: row[0] }));
    }
    return out;
  }

  const cell = (entry, column) => {
    const index = entry.header.indexOf(column);
    return index === -1 ? "" : entry.row[index];
  };

  const number = (entry, column, fallback) => {
    const value = parseFloat(cell(entry, column));
    return Number.isFinite(value) ? value : fallback;
  };

  /** The effects a row resolves to, following the same fallback PerkBranchDef
   * does: a perk with no effects of its own inherits its branch's. The branch is
   * found by walking the children/roots edges back up, since that is the only
   * link between the two rows. */
  function effectPaths(entry) {
    const own = cell(entry, "effects").split("|").filter(Boolean);
    if (own.length || !entry.header.includes("children")) return own;

    const seen = new Set([entry.path]);
    let current = entry.path;
    while (current) {
      const up = state.edges.find((edge) =>
        edge.to === current && (edge.column === "children" || edge.column === "roots"));
      if (!up || seen.has(up.from)) break;
      seen.add(up.from);
      current = up.from;
      const parent = rowIndexOf(current);
      if (!parent) break;
      const defaults = parent.header.indexOf("default_effects");
      if (defaults !== -1) return parent.row[defaults].split("|").filter(Boolean);
    }
    return [];
  }

  /** One row reduced to the handful of numbers both curves need. */
  function definitionOf(entry) {
    const maxLevel = Math.max(0, Math.round(number(entry, "max_level", 0)));
    const effectPath = effectPaths(entry)[0];
    const effectRow = effectPath ? rowIndexOf(effectPath) : null;
    // Enum cells carry Godot's own capitalisation ("Compound", "Add"), while the
    // engine's curve report carries the script's ("COMPOUND", "ADD"). Upper-case
    // both so a comparison here does not depend on which side it came from.
    const enumCell = (column) =>
      (effectRow.row[effectRow.header.indexOf(column)] || "").toUpperCase();
    const effect = effectRow ? {
      perLevel: parseFloat(effectRow.row[effectRow.header.indexOf("per_level")]) || 0,
      compound: enumCell("level_scaling") === "COMPOUND",
      stat: effectRow.row[effectRow.header.indexOf("stat")] || "",
      op: enumCell("op"),
      inherited: !cell(entry, "effects"),
    } : null;

    return {
      path: entry.path,
      label: labelOf(entry),
      file: entry.file,
      maxLevel,
      samples: maxLevel > 0 ? maxLevel : OPEN_ENDED_LEVELS,
      baseLog10: Math.log10(Math.abs(number(entry, MANTISSA, 1)) || 1)
        + number(entry, EXPONENT, 0),
      growth: number(entry, "cost_growth", 1),
      growthExponent: number(entry, "cost_growth_exponent", 1),
      effect,
      edited: fileHasChanges(entry.file),
    };
  }

  /* ----------------------------------------------------------------- formulas */

  /** Ceiling BigNumber.pow_float() saturates at (BigNumber.MAX_EXPONENT). A
   * steep growth_exponent runs past it within fifty levels, and a line drawn
   * beyond the point the game stops counting is a line about nothing. */
  const MAX_LOG10 = 1e9;

  /** log10 of what the next level costs while sitting at `level`.
   * Mirrors UpgradeSystem.cost(): base * growth^(level * growth_exponent^level).
   *
   * The clamp sits on the power alone, not on the product, because that is where
   * the engine's sits: pow_float() saturates and cost() then multiplies the base
   * into the saturated value, landing a base-exponent above the ceiling. */
  const costLog10 = (def, level) => def.baseLog10 + Math.min(MAX_LOG10,
    level * Math.pow(def.growthExponent, level) * Math.log10(Math.max(def.growth, 1e-12)));

  /** Total effect magnitude at `level`. Mirrors UpgradeEffectDef.magnitude();
   * signed, because a tick_rate effect is authored negative. */
  function magnitude(def, level) {
    if (!def.effect) return 0;
    if (def.effect.compound) return Math.pow(1 + def.effect.perLevel, level) - 1;
    return def.effect.perLevel * level;
  }

  /** The series for the current mode, as {level, log10, sign} points. Anything
   * that has no meaningful value at a level (zero effect, no effect at all) is
   * simply left out rather than plotted at some invented floor. */
  function series(def) {
    const points = [];
    for (let level = 0; level <= def.samples; level++) {
      let value = null;
      if (view.mode === "cost") {
        points.push({ level, log10: costLog10(def, level), sign: 1 });
        continue;
      }
      if (!def.effect) return [];
      if (view.mode === "effect") {
        value = magnitude(def, level);
      } else {
        const delta = magnitude(def, level + 1) - magnitude(def, level);
        if (delta !== 0) {
          points.push({ level, log10: Math.log10(Math.abs(delta)) - costLog10(def, level),
            sign: Math.sign(delta) });
        }
        continue;
      }
      if (value !== 0) {
        points.push({ level, log10: Math.log10(Math.abs(value)), sign: Math.sign(value) });
      }
    }
    return points;
  }

  /** The engine's own samples for the same series, or [] when there are none to
   * compare against - an edited file no longer matches what Godot measured. */
  function referenceSeries(def) {
    const raw = view.reference[def.path];
    if (!raw || def.edited) return [];
    const pair = ([mantissa, exponent]) =>
      mantissa === 0 ? null
        : { log10: Math.log10(Math.abs(mantissa)) + exponent, sign: Math.sign(mantissa) };

    const points = [];
    for (let level = 0; level < raw.cost.length; level++) {
      const cost = pair(raw.cost[level]);
      const effect = pair(raw.effect[level]);
      if (view.mode === "cost" && cost) points.push({ level, ...cost });
      if (view.mode === "effect" && effect) points.push({ level, ...effect });
      if (view.mode === "roi" && cost && effect && raw.effect[level + 1]) {
        // The engine reports totals; the marginal step is the difference of two.
        const next = raw.effect[level + 1];
        const delta = next[0] * Math.pow(10, next[1]) - raw.effect[level][0] * Math.pow(10, raw.effect[level][1]);
        if (delta !== 0) {
          points.push({ level, log10: Math.log10(Math.abs(delta)) - cost.log10, sign: Math.sign(delta) });
        }
      }
    }
    return points;
  }

  /* ------------------------------------------------------------------ drawing */

  const CHART = { width: 900, height: 520, left: 62, right: 26, top: 20, bottom: 40 };

  const hueOf = (index) => (index * 47) % 360;

  function drawChart(defs) {
    const svg = svgEl("svg", { id: "curve-chart", viewBox: `0 0 ${CHART.width} ${CHART.height}` });
    const plotted = defs.map((def) => ({ def, points: series(def),
      reference: referenceSeries(def) }))
      .filter((entry) => entry.points.length);

    if (!plotted.length) {
      const empty = svgEl("text", { x: CHART.width / 2, y: CHART.height / 2, class: "empty" });
      empty.textContent = defs.length
        ? "nothing to plot for these rows in this mode"
        : "pick a row on the right";
      empty.setAttribute("text-anchor", "middle");
      svg.append(empty);
      return svg;
    }

    let minY = Infinity;
    let maxY = -Infinity;
    let maxX = 1;
    for (const entry of plotted) {
      for (const point of entry.points.concat(entry.reference)) {
        minY = Math.min(minY, point.log10);
        maxY = Math.max(maxY, point.log10);
        maxX = Math.max(maxX, point.level);
      }
    }
    if (maxY - minY < 1) { minY -= 0.5; maxY += 0.5; }

    const plotWidth = CHART.width - CHART.left - CHART.right;
    const plotHeight = CHART.height - CHART.top - CHART.bottom;
    const x = (level) => CHART.left + (level / maxX) * plotWidth;
    const y = (log10) => CHART.top + (1 - (log10 - minY) / (maxY - minY)) * plotHeight;

    // One gridline per decade, thinned out so a 20-decade span stays readable.
    const step = Math.max(1, Math.ceil((maxY - minY) / 10));
    for (let decade = Math.ceil(minY); decade <= Math.floor(maxY); decade += step) {
      svg.append(svgEl("line", { class: "grid", x1: CHART.left, x2: CHART.width - CHART.right,
        y1: y(decade), y2: y(decade) }));
      const label = svgEl("text", { class: "axis", x: CHART.left - 8, y: y(decade) + 4 });
      label.setAttribute("text-anchor", "end");
      label.textContent = decade === 0 ? "1" : `1e${decade}`;
      svg.append(label);
    }

    const xStep = Math.max(1, Math.ceil(maxX / 12));
    for (let level = 0; level <= maxX; level += xStep) {
      const label = svgEl("text", { class: "axis", x: x(level), y: CHART.height - 14 });
      label.setAttribute("text-anchor", "middle");
      label.textContent = String(level);
      svg.append(label);
    }
    const axis = svgEl("text", { class: "axis-title", x: CHART.left + plotWidth / 2,
      y: CHART.height - 2 });
    axis.setAttribute("text-anchor", "middle");
    axis.textContent = `level · y: ${MODES[view.mode].axis} (log)`;
    svg.append(axis);

    plotted.forEach((entry, index) => {
      const color = `hsl(${hueOf(index)} 65% 50%)`;
      const line = entry.points.map((point, i) =>
        `${i ? "L" : "M"}${x(point.level).toFixed(1)} ${y(point.log10).toFixed(1)}`).join(" ");
      svg.append(svgEl("path", { class: "curve", d: line, stroke: color }));

      const engineAt = new Map(entry.reference.map((point) => [point.level, point]));
      for (const point of entry.reference) {
        svg.append(svgEl("circle", { class: "engine", cx: x(point.level), cy: y(point.log10),
          r: 2.6, fill: color }));
      }

      // A hit target per level, on top of both the line and the dot. Reading a
      // value off a log axis by eye is guesswork, and the question at a dot is
      // always the same: which level is this, and what does it cost there.
      for (const point of entry.points) {
        const hit = svgEl("circle", { class: "hit", cx: x(point.level), cy: y(point.log10),
          r: 7, stroke: color });
        attachTip(hit, pointTip(entry.def, point, engineAt.get(point.level)));
        svg.append(hit);
      }
      // A negative series (a tick_rate discount) is drawn on the magnitude scale
      // like any other, so say so rather than let it read as a gain.
      if (entry.points.some((point) => point.sign < 0)) {
        const mark = svgEl("text", { class: "axis", x: x(entry.points.at(-1).level) - 4,
          y: y(entry.points.at(-1).log10) - 6, fill: color });
        mark.setAttribute("text-anchor", "end");
        mark.textContent = "negative";
        svg.append(mark);
      }
    });

    return svg;
  }

  /** What one level of one def is worth, as tooltip text.
   *
   * All three numbers show whatever the current mode is plotting, because the
   * question "is this cost worth that effect" is never answered by one of them
   * alone. `engine` is the sample Godot produced at this level, present only
   * while the file is unedited, and it is spelled out so a disagreement between
   * the drawn line and the dot can be read rather than guessed at. */
  function pointTip(def, point, engine) {
    const level = point.level;
    const lines = [`${def.label} · level ${level}`];
    lines.push(`next level costs ${exp10(costLog10(def, level))}`);
    if (def.effect) {
      lines.push(`${def.effect.stat} at this level: ${formatEffect(def, level)}`);
      const delta = magnitude(def, level + 1) - magnitude(def, level);
      if (delta !== 0) {
        lines.push(`one more level adds ${formatMagnitude(def, delta)}, `
          + `${exp10(Math.log10(Math.abs(delta)) - costLog10(def, level))} per unit spent`);
      }
    } else {
      lines.push("no effect on this def");
    }
    if (def.maxLevel > 0 && level >= def.maxLevel) lines.push("(its last level)");
    if (engine) {
      lines.push(Math.abs(point.log10 - engine.log10) < 1e-6
        ? "engine sample agrees"
        : `engine sample sits at ${exp10(engine.log10)} - the drawn line is wrong`);
    }
    return lines.join("\n");
  }


  /* -------------------------------------------------------------------- panel */

  /** The panel is built once per full render and then left alone. Ticking a row
   * is not a reason to rebuild the list it lives in: the list is the scrolling
   * element, and rebuilding it sends the reader back to the top of 109 rows
   * every time they add a curve. Selecting only redraws the chart and the
   * legend, through refresh() below. */
  function renderPanel(panel) {
    panel.replaceChildren();

    const modes = document.createElement("div");
    modes.className = "curve-modes";
    view.dom.modes = new Map();
    for (const [key, mode] of Object.entries(MODES)) {
      const button = document.createElement("button");
      button.textContent = mode.label;
      button.className = key === view.mode ? "active" : "";
      button.onclick = () => { view.mode = key; refresh(); };
      view.dom.modes.set(key, button);
      modes.append(button);
    }
    panel.append(modes);

    const search = document.createElement("input");
    search.type = "search";
    search.placeholder = "filter rows…";
    search.value = view.filter;
    // Only the rows are refilled, never the panel: rebuilding it would replace
    // this very input mid-keystroke and take the caret with it.
    search.oninput = () => { view.filter = search.value; fillList(); refresh(); };
    view.dom.search = search;
    panel.append(search);

    const actions = document.createElement("div");
    actions.className = "curve-actions";
    const clear = document.createElement("button");
    clear.textContent = "Clear selection";
    clear.onclick = () => { view.selected.clear(); syncBoxes(); refresh(); };
    const all = document.createElement("button");
    all.textContent = "Select shown";
    all.onclick = () => {
      visible(view.defs).forEach((def) => view.selected.add(def.path));
      syncBoxes();
      refresh();
    };
    actions.append(all, clear);
    panel.append(actions);

    view.dom.list = document.createElement("div");
    view.dom.list.className = "curve-list";
    fillList();
    panel.append(view.dom.list);

    // Below the list, and scrolling on its own. A legend above it re-flows the
    // list every time a curve is added or dropped, which drags the rows out from
    // under the pointer; below, the list keeps both its height and its place.
    view.dom.legend = document.createElement("div");
    view.dom.legend.className = "curve-legend-slot";
    panel.append(view.dom.legend);
  }


  /** The rows the filter currently lets through, written into the existing list
   * element. Called on its own when only the filter moved, so the list is the
   * only thing that changes and the search box keeps the caret. */
  function fillList() {
    const rows = [];
    view.dom.boxes = new Map();
    let lastFile = null;
    for (const def of visible(view.defs)) {
      if (def.file !== lastFile) {
        lastFile = def.file;
        const heading = document.createElement("div");
        heading.className = "curve-file";
        heading.textContent = def.file;
        rows.push(heading);
      }
      const row = document.createElement("label");
      row.className = "curve-row";
      const box = document.createElement("input");
      box.type = "checkbox";
      box.checked = view.selected.has(def.path);
      box.onchange = () => {
        box.checked ? view.selected.add(def.path) : view.selected.delete(def.path);
        refresh();
      };
      view.dom.boxes.set(def.path, box);
      const name = document.createElement("span");
      name.textContent = def.label;
      name.title = def.path;
      const note = document.createElement("span");
      note.className = "curve-note";
      note.textContent = def.effect
        ? `${def.effect.stat}${def.effect.inherited ? " (branch)" : ""}`
        : "no effect";
      row.append(box, name, note);
      rows.push(row);
    }
    view.dom.list.replaceChildren(...rows);
  }


  /** Everything a selection or mode change touches, and nothing else - the row
   * list keeps its DOM, and with it the scroll position. */
  function refresh() {
    const defs = view.defs;
    for (const [key, button] of view.dom.modes) {
      button.className = key === view.mode ? "active" : "";
    }
    const selected = defs.filter((def) => view.selected.has(def.path));
    view.element.querySelector(".curve-canvas").replaceChildren(drawChart(selected));
    // The legend changing size can still make the browser clamp the list's
    // scroll when the list grows back, so it is put back where it was.
    const scrolled = view.dom.list.scrollTop;
    view.dom.legend.replaceChildren(...(selected.length ? [legend(selected)] : []));
    view.dom.list.scrollTop = scrolled;
    reportStatus(selected, defs);
  }


  /** Points the checkboxes at what is actually selected, for the two buttons
   * that change the selection without the user clicking a box. */
  function syncBoxes() {
    for (const [path, box] of view.dom.boxes) box.checked = view.selected.has(path);
  }


  function reportStatus(selected, defs) {
    const drift = selected.filter((def) => def.edited).length;
    setStatus(`curves - ${selected.length} of ${defs.length} rows`
      + (drift ? ` · ${drift} edited, engine samples hidden for those` : ""));
  }

  function visible(defs) {
    const needle = view.filter.trim().toLowerCase();
    if (!needle) return defs;
    return defs.filter((def) =>
      def.label.toLowerCase().includes(needle) || def.path.toLowerCase().includes(needle));
  }

  /** The legend's columns and the width each starts at. Names are long and
   * numbers are short, so the split is fixed rather than left to the browser -
   * and any of them can be dragged wider, see legendResizer(). */
  const LEGEND_COLUMNS = [
    { label: "", width: 24 },
    { label: "row", width: 130 },
    { label: "max", width: 46 },
    { label: "cost to max", width: 90 },
    { label: "effect at max", width: 96 },
  ];

  const LEGEND_WIDTHS_KEY = "balance-editor-legend-widths";
  const MIN_LEGEND_WIDTH = 24;

  let legendWidths = {};
  try {
    legendWidths = JSON.parse(localStorage.getItem(LEGEND_WIDTHS_KEY) || "{}");
  } catch (error) { /* private mode - the defaults apply */ }

  const legendWidthOf = (column) => legendWidths[column.label] || column.width;

  function saveLegendWidths() {
    try {
      localStorage.setItem(LEGEND_WIDTHS_KEY, JSON.stringify(legendWidths));
    } catch (error) { /* private mode - widths just won't survive the reload */ }
  }

  /** Drag handle on a legend header cell. The table is laid out fixed and as
   * wide as its columns add up to, so a widened column pushes the table past the
   * panel and the legend scrolls sideways rather than squeezing its neighbours. */
  function legendResizer(table, th, column) {
    const handle = document.createElement("div");
    handle.className = "legend-resizer";
    handle.title = "drag to resize · double-click to reset";
    handle.onpointerdown = (event) => {
      event.preventDefault();
      handle.setPointerCapture(event.pointerId);
      handle.classList.add("dragging");
      const startX = event.clientX;
      const startWidth = th.getBoundingClientRect().width;
      const onMove = (moveEvent) => {
        legendWidths[column.label] =
          Math.max(MIN_LEGEND_WIDTH, Math.round(startWidth + moveEvent.clientX - startX));
        applyLegendWidths(table);
      };
      const onUp = () => {
        handle.classList.remove("dragging");
        handle.removeEventListener("pointermove", onMove);
        handle.removeEventListener("pointerup", onUp);
        saveLegendWidths();
      };
      handle.addEventListener("pointermove", onMove);
      handle.addEventListener("pointerup", onUp);
    };
    handle.ondblclick = (event) => {
      event.preventDefault();
      delete legendWidths[column.label];
      saveLegendWidths();
      applyLegendWidths(table);
    };
    return handle;
  }

  function applyLegendWidths(table) {
    const cells = table.rows[0].cells;
    let total = 0;
    LEGEND_COLUMNS.forEach((column, index) => {
      const width = legendWidthOf(column);
      total += width;
      if (cells[index]) cells[index].style.width = `${width}px`;
    });
    table.style.width = `${total}px`;
  }

  /** Name, colour and the two numbers worth reading off directly: what maxing
   * costs and what it buys. */
  function legend(defs) {
    const table = document.createElement("table");
    table.className = "curve-legend";
    const head = table.insertRow();
    for (const column of LEGEND_COLUMNS) {
      const th = document.createElement("th");
      th.textContent = column.label;
      th.append(legendResizer(table, th, column));
      head.append(th);
    }
    defs.forEach((def, index) => {
      const row = table.insertRow();
      const swatch = row.insertCell();
      swatch.className = "swatch";
      swatch.innerHTML = `<i style="background:hsl(${hueOf(index)} 65% 50%)"></i>`;
      const name = row.insertCell();
      name.textContent = def.label;
      name.className = "link";
      // The graph view's side panel, where the row's fields can be changed -
      // clicking a plotted curve's name is always about retuning it.
      name.onclick = () => { setFocus(def.path); setView("graph"); };
      row.insertCell().textContent = def.maxLevel > 0 ? String(def.maxLevel) : "∞";
      row.insertCell().textContent = def.maxLevel > 0 ? exp10(costToMaxLog10(def)) : "-";
      row.insertCell().textContent = def.effect
        ? formatEffect(def, def.maxLevel > 0 ? def.maxLevel : def.samples) : "-";
      for (const cell of row.cells) cell.title = cell.textContent;   // narrowed to an ellipsis
    });
    applyLegendWidths(table);
    return table;
  }

  /** Total spend to buy every level, summed in linear space per level and kept
   * in log10 so a 1e30 total still prints. */
  function costToMaxLog10(def) {
    let total = 0;
    let scale = null;
    for (let level = 0; level < def.maxLevel; level++) {
      const log10 = costLog10(def, level);
      if (scale === null) scale = log10;
      total += Math.pow(10, log10 - scale);
    }
    return scale === null ? 0 : scale + Math.log10(total);
  }

  const exp10 = (log10) => {
    const exponent = Math.floor(log10);
    const mantissa = Math.pow(10, log10 - exponent);
    return exponent < 4 && exponent > -3
      ? (mantissa * Math.pow(10, exponent)).toPrecision(3)
      : `${mantissa.toFixed(2)}e${exponent}`;
  };

  const formatEffect = (def, level) => formatMagnitude(def, magnitude(def, level));


  /** A flat op reads as a number, everything else as the percentage it is. */
  function formatMagnitude(def, value) {
    if (def.effect.op === "ADD") return value.toPrecision(3);
    return `${(value * 100).toFixed(1)}%`;
  }

  /* ------------------------------------------------------------------- wiring */

  /** Re-reads the engine's own samples. Cheap unless something was written: the
   * server caches this report and only drops it when the data changes. */
  view.invalidate = async () => {
    view.reference = (await api("/api/curves")).curves || {};
  };

  view.open = async () => {
    await loadAllFiles();
    buildEdges();
    // Every time, not just the first: costs saved since the last visit would
    // otherwise leave the dots sitting on the old curve.
    await view.invalidate();
    if (!view.selected.size && state.focus) view.selected.add(state.focus);
  };

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "curves-view";
    wrap.innerHTML = `<div class="curve-canvas"></div><aside class="curve-panel"></aside>`;
    return wrap;
  };

  /** Full rebuild: the rows themselves may have changed (a saved edit, a filter,
   * a different file). The list's scroll position is carried across, since the
   * reader was looking at something when whatever caused this happened. */
  view.render = () => {
    const scrolled = view.dom.list ? view.dom.list.scrollTop : 0;
    // A rebuild triggered from outside (a saved edit, a focus change) must not
    // pull the caret out of the filter box mid-word.
    const typing = view.dom.search && document.activeElement === view.dom.search;
    const caret = typing ? view.dom.search.selectionStart : 0;
    view.defs = pricedRows().map(definitionOf);
    renderPanel(view.element.querySelector(".curve-panel"));
    if (scrolled) view.dom.list.scrollTop = scrolled;
    if (typing) {
      view.dom.search.focus();
      view.dom.search.setSelectionRange(caret, caret);
    }
    refresh();
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.curves = view;
})();
