/* Game view: the balance data laid out the way the game lays it out.
 *
 * The table view is one spreadsheet per resource class, which is the shape the
 * data is stored in and not the shape it is authored in. One biome's truth is
 * spread over four of those tables - the BiomeDef, its ten UpgradeDefs, their
 * UpgradeEffectDefs and a ScalingSourceDef - and tuning it means holding all
 * four in your head at once. The screens here put them back together in the
 * arrangement the player meets them in, so a number is edited next to the thing
 * it does.
 *
 * This file is only the shell: a tab strip over the screens registered on
 * window.BalanceScreens, plus the helpers they share (window.GameKit). One
 * screen per file - game_biomes.js is the first - so adding Boosts later is a
 * file and a <script> tag.
 *
 * Editing goes through fieldEditor() from index.html, the same control the
 * graph's side panel and the perk web use. That means writeCell(), which means
 * Save, Save all, the per-field revert and the changed-cell highlight all work
 * here without this file knowing they exist.
 *
 * Registered on window.BalanceViews, which index.html turns into a view button.
 */
(() => {
  const view = {
    label: "Game",
    title: "Biomes, laid out the way the game lays them out",
    screen: null,      // which of window.BalanceScreens is showing
    curves: null,      // GET /api/curves - the engine's own samples
    dom: {},
  };

  const screens = () => window.BalanceScreens || {};

  /* ------------------------------------------------------------------ numbers */

  const SUFFIXES = ["", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"];

  /** A mantissa/exponent pair as the game would show it. BigNumber.to_display()
   * is the thing being echoed, so a magnitude past the suffix table reads as
   * "1.0e42" rather than silently losing its scale. */
  function formatBig(mantissa, exponent) {
    const m = Number(mantissa);
    const e = Math.round(Number(exponent));
    if (!Number.isFinite(m) || !Number.isFinite(e) || m === 0) return "0";
    const group = Math.floor(e / 3);
    if (group < 0) return (m * 10 ** e).toPrecision(3);
    if (group >= SUFFIXES.length) return `${m.toFixed(1)}e${e}`;
    const scaled = m * 10 ** (e - group * 3);
    return `${scaled.toFixed(scaled < 10 ? 2 : 1)}${SUFFIXES[group]}`;
  }

  /** log10 of a mantissa/exponent pair, which is the only space these costs can
   * be drawn in: a late biome's size price passes 1e300 inside fifty levels. */
  const log10Of = (mantissa, exponent) => {
    const m = Number(mantissa);
    if (!Number.isFinite(m) || m <= 0) return null;
    return Math.log10(m) + Number(exponent);
  };

  /* ------------------------------------------------------------------ curves */

  /** The one growth curve the game prices everything with, in log10.
   *
   * UpgradeSystem.cost() and BiomeSystem.size_cost() are the same expression
   * over different fields - `base * growth^(level * growth_exponent^level)` -
   * so they are mirrored once here rather than once per screen. `base` arrives
   * already in log10, because a late level's price passes what a double holds
   * long before the chart runs out of room.
   *
   * Computed over the window asked for rather than over a fixed span and
   * cropped, so pushing a range out samples the formula further.
   */
  function growthCurve(base, growth, growthExponent, from, to) {
    if (base === null || !Number.isFinite(base) || growth <= 0) return [];
    const out = [];
    for (let level = from; level <= to; level += 1) {
      const scaled = level * growthExponent ** level;
      const value = base + scaled * Math.log10(growth);
      out.push(Number.isFinite(value) ? value : null);
    }
    return out;
  }

  /** UpgradeEffectDef.magnitude() over a window, and the same scaled by whatever
   * the effect depends on.
   *
   * A level either adds its rate (LINEAR) or compounds it (COMPOUND), and
   * max_magnitude clamps the result. `factor` is what a ScalingSourceDef
   * evaluates to, or null when the effect scales with nothing. */
  function effectCurve({ perLevel, compound, cap, factor }, from, to) {
    const raw = [];
    for (let level = from; level <= to; level += 1) {
      raw.push(compound ? (1 + perLevel) ** level - 1 : perLevel * level);
    }
    const clamp = (value) => (cap > 0 ? Math.max(-cap, Math.min(cap, value)) : value);
    return {
      raw: raw.map(clamp),
      scaled: factor === null || factor === undefined
        ? null : raw.map((value) => clamp(value * factor)),
      capped: cap > 0 && raw.some((value) => Math.abs(value) > cap),
    };
  }

  /** Godot writes an enum cell with its own capitalisation ("Compound", "Biome
   * Size") while the engine's curve report writes the script's ("COMPOUND").
   * Fold both so a comparison never depends on which side it came from. */
  const enumIs = (value, name) =>
    String(value || "").toUpperCase().replace(/[\s_]/g, "") === name;

  /** The achievement curve: base * growth^(n ^ exponent), in log10.
   *
   * Deliberately not growthCurve(), which is base * growth^(n * exponent^n).
   * The two agree only at exponent 1.0 - which is what all nine achievements
   * are authored at, so the engine's own samples would not catch the difference
   * on today's data. They diverge the moment anyone turns the knob this screen
   * exists to expose, which is exactly when a wrong mirror would mislead.
   */
  function powerCurve(base, growth, exponent, from, to) {
    if (base === null || !Number.isFinite(base) || growth <= 0) return [];
    const out = [];
    for (let tier = from; tier <= to; tier += 1) {
      const value = base + (tier ** exponent) * Math.log10(growth);
      out.push(Number.isFinite(value) ? value : null);
    }
    return out;
  }

  /** BiomeCalculator.level_for(), read forwards: the total XP standing at the
   * door of each level. Level 1 is free, level 2 needs 6, and each step after
   * needs round(previous * 1.55).
   *
   * Shared, because two screens read the same ladder from different ends - the
   * biome card asks what a level costs, the crystals screen asks what a pile of
   * achievement tiers buys. */
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

  /** The level a given XP total reaches, the inverse of the ladder above. */
  function levelForXp(xp) {
    let level = 1;
    let need = 6;
    let acc = 0;
    while (xp >= acc + need) {
      acc += need;
      level += 1;
      need = Math.round(need * 1.55);
    }
    return level;
  }

  /* ------------------------------------------------------------------- charts */

  const CHART = { width: 460, height: 190, left: 46, right: 12, top: 12, bottom: 26 };

  const hueOf = (index) => `hsl(${(index * 47) % 360} 65% 55%)`;

  /** A line chart over a shared integer x axis.
   *
   * `series` is [{ label, points: [y|null], color?, dots?, dashed? }] - one y per
   * x, and null for "this series has nothing here", so a curve that runs out
   * before the axis does simply stops. `dots` draws markers instead of a line,
   * which is how the engine's own samples are overplotted behind a mirrored
   * curve: if the mirror drifts, the dots leave the line.
   *
   * `options.log` says the y values are already log10 and should be labelled as
   * powers of ten; without it they are labelled as themselves.
   */
  function chart(series, options = {}) {
    const width = options.width || CHART.width;
    const height = options.height || CHART.height;
    const plotWidth = width - CHART.left - CHART.right;
    const plotHeight = height - CHART.top - CHART.bottom;

    const svg = svgEl("svg", {
      class: "game-chart", viewBox: `0 0 ${width} ${height}`,
      width, height, preserveAspectRatio: "xMidYMid meet",
    });

    const finite = (y) => y !== null && Number.isFinite(y);
    const flat = series.flatMap((s) => s.points).filter(finite);
    const maxX = Math.max(1, ...series.map((s) => s.points.length - 1));
    if (!flat.length) {
      svg.append(svgEl("text", { x: width / 2, y: height / 2, "text-anchor": "middle",
        class: "game-chart-empty" }));
      svg.lastChild.textContent = "nothing to plot";
      return svg;
    }

    let minY = Math.min(...flat);
    let maxY = Math.max(...flat);
    if (options.zeroBased) minY = Math.min(0, minY);
    if (maxY - minY < 1e-9) { maxY = minY + 1; }   // a flat line still needs a band
    const pad = (maxY - minY) * 0.06;
    const floorY = minY;
    minY -= pad;
    maxY += pad;
    // In log space a price never goes below 1, so padding under a series that
    // starts there only buys an axis labelled 1e-30 for values that cannot exist.
    if (options.log && floorY >= 0) minY = Math.max(0, minY);

    const x = (index) => CHART.left + (index / maxX) * plotWidth;
    const y = (value) => CHART.top + (1 - (value - minY) / (maxY - minY)) * plotHeight;

    // Gridlines. In log space they are decades, thinned so a curve spanning
    // three hundred of them does not draw three hundred lines.
    const ticks = [];
    if (options.log) {
      const step = Math.max(1, Math.ceil((maxY - minY) / 8));
      for (let e = Math.ceil(minY); e <= Math.floor(maxY); e += step) ticks.push(e);
    } else {
      for (let i = 0; i <= 4; i += 1) ticks.push(minY + ((maxY - minY) * i) / 4);
    }
    for (const tick of ticks) {
      svg.append(svgEl("line", { class: "grid",
        x1: CHART.left, x2: width - CHART.right, y1: y(tick), y2: y(tick) }));
      const label = svgEl("text", { class: "axis", x: CHART.left - 6, y: y(tick) + 3,
        "text-anchor": "end" });
      label.textContent = options.log
        ? (tick === 0 ? "1" : `1e${Math.round(tick)}`)
        : formatAxis(tick);
      svg.append(label);
    }

    // x axis: first, middle and last, which is as much as a chart this wide reads.
    for (const index of [0, Math.round(maxX / 2), maxX]) {
      const label = svgEl("text", { class: "axis", x: x(index), y: height - 8,
        "text-anchor": "middle" });
      label.textContent = String((options.xOffset || 0) + index);
      svg.append(label);
    }
    series.forEach((entry, index) => {
      const color = entry.color || hueOf(index);
      if (entry.dots) {
        entry.points.forEach((value, i) => {
          if (!finite(value)) return;
          svg.append(svgEl("circle", { class: "engine", cx: x(i), cy: y(value), r: 2,
            fill: color }));
        });
        return;
      }
      // A gap starts a new subpath rather than being bridged: a price that has
      // no value at one biome (a starter biome unlocks for nothing) must leave a
      // hole, not a straight line drawn through where the point would have been.
      let path = "";
      let pen = "M";
      entry.points.forEach((value, i) => {
        if (!finite(value)) { pen = "M"; return; }
        path += `${pen}${x(i).toFixed(1)} ${y(value).toFixed(1)}`;
        pen = "L";
      });
      if (path) {
        svg.append(svgEl("path", { class: "curve", d: path, stroke: color,
          "stroke-dasharray": entry.dashed ? "4 3" : "" }));
      }
      // A hit target per point, so hovering says which level it is.
      //
      // `tipExtra` lets a screen answer a question the point alone cannot - what
      // a price on one curve would buy on all the others, say. Computed on hover
      // rather than up front: there are five hundred of these on a wide chart
      // and almost none of them are ever pointed at.
      entry.points.forEach((value, i) => {
        if (!finite(value)) return;
        const hit = svgEl("circle", { class: "hit", cx: x(i), cy: y(value), r: 6 });
        const level = (options.xOffset || 0) + i;
        const head = `${entry.label} · ${level}: `
          + `${options.log ? logDisplay(value) : formatAxis(value)}`;
        attachTip(hit, options.tipExtra ? () => {
          const extra = options.tipExtra(entry, level, value);
          return extra ? `${head}\n${extra}` : head;
        } : head);
        svg.append(hit);
      });
    });

    // A marker's `at` is a value on the x axis as the reader sees it, not an
    // index into the series - the window can start anywhere, so the two stopped
    // being the same thing once the range became adjustable. One outside the
    // window is dropped rather than clamped to an edge it is not at.
    for (const marker of options.markers || []) {
      const index = marker.at - (options.xOffset || 0);
      if (index < 0 || index > maxX) continue;
      svg.append(svgEl("line", { class: "game-marker",
        x1: x(index), x2: x(index), y1: CHART.top, y2: CHART.top + plotHeight }));
      const label = svgEl("text", { class: "axis", x: x(index) + 3, y: CHART.top + 9 });
      label.textContent = marker.label;
      svg.append(label);
    }

    return svg;
  }

  const logDisplay = (value) => {
    const exponent = Math.floor(value);
    return formatBig(10 ** (value - exponent), exponent);
  };

  function formatAxis(value) {
    if (Math.abs(value) >= 1000 || (value !== 0 && Math.abs(value) < 0.01)) {
      return value.toPrecision(3);
    }
    return String(Math.round(value * 100) / 100);
  }

  /* ------------------------------------------------------------- collapsing */

  const COLLAPSE_KEY = "balance-editor-collapsed";

  /** Which sub-sections are folded away, keyed by screen and heading rather than
   * by card.
   *
   * Per heading, so folding "Identity" folds it on all twenty-six project cards
   * at once - which is the only way it helps on a page that long. Reading one
   * number across every card is the thing these screens are for, and that means
   * hiding the other five sections everywhere, not card by card. Same reasoning
   * as the chart ranges, which are keyed by chart kind for the same reason.
   *
   * Survives the redraw every keystroke triggers, and the reload after that. */
  let collapsed = {};
  try {
    collapsed = JSON.parse(localStorage.getItem(COLLAPSE_KEY) || "{}");
  } catch (error) { /* private mode - everything just starts open */ }

  function saveCollapsed() {
    try {
      localStorage.setItem(COLLAPSE_KEY, JSON.stringify(collapsed));
    } catch (error) { /* private mode - the folds won't survive a reload */ }
  }

  /** A heading's identity, with any "(4)" count stripped: the boon section is
   * headed "Boons (4)" on one project and "Boons (3)" on the next, and those are
   * the same section. */
  const collapseKey = (screen, heading) =>
    `${screen}/${heading.replace(/\s*\(\d+\)/g, "").trim()}`;

  /** Turns every `.game-group` heading on a freshly rendered screen into a fold.
   *
   * Applied over the finished DOM rather than built into a helper, because the
   * screens raise their sections in half a dozen different ways - fieldGroup(),
   * hand-built blocks, split rows - and they all agree on `.game-group` with an
   * h4 on top. One pass here covers every screen written so far and every one
   * written later, with nothing to remember.
   *
   * The body is hidden in CSS rather than detached, so a folded chart keeps its
   * place in the shared-range redraw and comes back unchanged. */
  /** What a section band governs: every sibling after it, up to the next band.
   *
   * A band heads a run of cards rather than containing them - the heading and
   * its cards are siblings in the screen body - so folding one has to reach
   * forward. Folding only its own children hid the heading's hint line and left
   * all sixteen cards standing, which is not what a fold means. */
  function sectionRun(band) {
    const out = [];
    for (let node = band.nextElementSibling; node; node = node.nextElementSibling) {
      if (node.classList.contains("game-section")) break;
      out.push(node);
    }
    return out;
  }

  function applyCollapse(root, screen) {
    const groups = [...root.querySelectorAll(".game-group")]
      .filter((group) => {
        const heading = group.firstElementChild;
        return heading && heading.tagName === "H4";
      });

    const setFolded = (group, folded) => {
      group.classList.toggle("collapsed", folded);
      if (!group.classList.contains("game-section")) return;
      for (const node of sectionRun(group)) node.classList.toggle("folded-away", folded);
    };

    for (const group of groups) {
      const heading = group.firstElementChild;
      const key = collapseKey(screen, heading.textContent);
      const isBand = group.classList.contains("game-section");
      setFolded(group, collapsed[key] === true);
      heading.title = isBand
        ? "Fold this whole section away"
        : "Fold this section on every card";
      heading.onclick = () => {
        const folded = !collapsed[key];
        if (folded) collapsed[key] = true;
        else delete collapsed[key];
        saveCollapsed();
        // Every card carries a section under this heading, so they all move
        // together. Cheaper and steadier than a full re-render, which would
        // rebuild thirty charts to change a class.
        for (const other of groups) {
          if (collapseKey(screen, other.firstElementChild.textContent) !== key) continue;
          setFolded(other, folded);
        }
      };
    }
  }

  /* -------------------------------------------------------------- x ranges */

  const RANGE_KEY = "balance-editor-chart-ranges";

  /** How far each *kind* of chart is drawn, keyed by kind rather than by the
   * resource being drawn: setting the size chart to 0-200 on one biome sets it
   * on all six, which is the only way two of them can be read against each
   * other. Survives the redraw that every keystroke triggers, and the reload
   * after that, the way the column widths do. */
  let ranges = {};
  try {
    ranges = JSON.parse(localStorage.getItem(RANGE_KEY) || "{}");
  } catch (error) { /* private mode - the defaults apply */ }

  function saveRanges() {
    try {
      localStorage.setItem(RANGE_KEY, JSON.stringify(ranges));
    } catch (error) { /* private mode - the range just won't survive a reload */ }
  }

  const stored = (key, part) => {
    const entry = ranges[key];
    return entry && Number.isFinite(entry[part]) ? entry[part] : null;
  };

  /** The window in effect for one chart kind. `spec` carries the defaults the
   * screen would use on its own, so an unset `to` means "whatever this
   * particular chart's natural end is" - an upgrade's max_level, say, which
   * differs per upgrade and so cannot be a stored number. */
  function rangeOf(spec) {
    const from = stored(spec.key, "from") ?? spec.from;
    const to = stored(spec.key, "to") ?? spec.to;
    // A backwards or empty window would draw nothing and read as a broken chart.
    return { from, to: Math.max(from + 1, to) };
  }

  const isCustom = (key) => stored(key, "from") !== null || stored(key, "to") !== null;

  /** key -> the draw() of every chart currently showing that key, so moving one
   * range moves all the charts it governs. Rebuilt on each full render, since
   * the blocks from the previous one are detached by then. */
  const sharing = new Map();

  const redrawShared = (key) => {
    for (const draw of sharing.get(key) || []) draw();
  };

  /** from/to boxes for one chart kind, plus a reset back to the screen's own
   * defaults. Redraws the charts on this key and nothing else: the data fields
   * elsewhere on the page are mid-edit as often as not, and a full re-render
   * would take the caret with them. */
  function rangeControl(spec) {
    const wrap = document.createElement("span");
    wrap.className = "game-range";
    const current = rangeOf(spec);

    const box = (part, value) => {
      const input = document.createElement("input");
      input.type = "number";
      input.step = "1";
      input.value = String(value);
      input.title = `${part === "from" ? "First" : "Last"} ${spec.label || "level"} drawn`;
      input.addEventListener("change", () => {
        const parsed = Math.round(Number(input.value));
        // An empty or unparseable box would silently become 0 and move the chart
        // somewhere nobody asked for; put the value back instead.
        if (!Number.isFinite(parsed)) { input.value = String(value); return; }
        ranges[spec.key] = { ...(ranges[spec.key] || {}), [part]: parsed };
        saveRanges();
        redrawShared(spec.key);
      });
      return input;
    };

    wrap.append(box("from", current.from), document.createTextNode("–"), box("to", current.to));

    if (isCustom(spec.key)) {
      const reset = document.createElement("button");
      reset.className = "revert";
      reset.type = "button";
      reset.textContent = "↺";
      reset.title = "Back to the default range";
      reset.onclick = () => { delete ranges[spec.key]; saveRanges(); redrawShared(spec.key); };
      wrap.append(reset);
    }
    return wrap;
  }

  /** A chart under a caption, which is how every chart on a screen is placed.
   *
   * `seriesOrBuild` is either the series themselves or, when `options.range` is
   * given, a `build(from, to)` that produces them for a window - so moving the
   * range recomputes the curve over the levels asked for rather than cropping a
   * fixed one. */
  function chartBlock(title, seriesOrBuild, options = {}) {
    const wrap = document.createElement("div");
    wrap.className = "game-chart-block";
    const head = document.createElement("div");
    head.className = "game-chart-title";
    const body = document.createElement("div");
    wrap.append(head, body);

    const draw = () => {
      const window_ = options.range ? rangeOf(options.range) : null;
      const series = typeof seriesOrBuild === "function"
        ? seriesOrBuild(window_ ? window_.from : 0, window_ ? window_.to : 0)
        : seriesOrBuild;
      const drawOptions = window_ ? { ...options, xOffset: window_.from } : options;

      const caption = document.createElement("span");
      // The x axis is named in the caption rather than beside the axis, where it
      // sat on top of the last tick's number.
      caption.textContent = options.xLabel ? `${title}  ·  x: ${options.xLabel}` : title;
      head.replaceChildren(caption);
      if (options.range) head.append(rangeControl(options.range));

      body.replaceChildren(chart(series, drawOptions), legendOf(series));
    };

    if (options.range) {
      if (!sharing.has(options.range.key)) sharing.set(options.range.key, new Set());
      sharing.get(options.range.key).add(draw);
    }
    draw();
    return wrap;
  }

  function legendOf(series) {
    const legend = document.createElement("div");
    legend.className = "game-legend";
    series.forEach((entry, index) => {
      if (entry.hideFromLegend) return;
      const item = document.createElement("span");
      item.className = "game-legend-item";
      const swatch = document.createElement("i");
      swatch.style.background = entry.color || hueOf(index);
      item.append(swatch, document.createTextNode(entry.label));
      legend.append(item);
    });
    return legend;
  }

  /* -------------------------------------------------------------------- rows */

  /** Every row of one table, in file order. Screens read whole tables (all the
   * biomes, all the upgrades) far more often than they look one up. */
  function rowsOf(file) {
    if (!state.loaded.has(file)) return [];
    const data = dataOf(file);
    return data.rows.map((row, rowIndex) =>
      ({ file, rowIndex, header: data.header, row, path: row[0] }));
  }

  /** The first row of `file` whose `column` holds `value`, as a rowIndexOf-shaped
   * entry. This is how upgrade_ids (which hold ids) reach UpgradeDef rows (which
   * are keyed by res_path). */
  function findRow(file, column, value) {
    if (!state.loaded.has(file)) return null;
    const data = dataOf(file);
    const index = data.header.indexOf(column);
    if (index === -1) return null;
    const rowIndex = data.rows.findIndex((row) => row[index] === value);
    if (rowIndex === -1) return null;
    return { file, rowIndex, header: data.header, row: data.rows[rowIndex],
      path: data.rows[rowIndex][0] };
  }

  const cell = (entry, column) => {
    if (!entry) return "";
    const index = entry.header.indexOf(column);
    return index === -1 ? "" : entry.row[index];
  };

  const numberCell = (entry, column, fallback) => {
    const value = parseFloat(cell(entry, column));
    return Number.isFinite(value) ? value : fallback;
  };

  /** fieldEditor by column name rather than index, because a screen knows which
   * property it is placing and not where the reflection put it. Returns null for
   * a column this resource does not have, so a screen can list the fields it
   * would like without asserting the schema. */
  function field(entry, column, metaOverride) {
    const columnIndex = entry.header.indexOf(column);
    if (columnIndex <= 0) return null;
    return fieldEditor(entry, columnIndex, metaOverride);
  }

  /** What an effect's `target` may legally hold, given the scope and stat beside
   * it. Delegates to candidatesFor so the vocabulary lives in one place: the
   * KEY_REFS rules already say which table a target names under which scope. */
  function targetOptionsFor(effect) {
    return candidatesFor(liveRow(effect), "target");
  }

  /* ------------------------------------------------------------ node groups */

  const NODE_FILE = "MyceliumNode";

  const tagsOfNode = (node) => (cell(node, "tags") || "").split("|").filter(Boolean);

  /** The tiers in authored order. Empty when the table is not loaded, which is
   * what keeps a screen that never reads nodes from throwing. */
  function nodeRows() {
    return rowsOf(NODE_FILE)
      .slice()
      .sort((a, b) => numberCell(a, "node_id", 0) - numberCell(b, "node_id", 0));
  }

  /** Every group any tier declares, with how many carry it. There is no authored
   * list of groups: a group is exactly the set of nodes naming it, which is why
   * this is counted rather than looked up. */
  function declaredGroups() {
    const counts = new Map();
    for (const node of nodeRows()) {
      for (const tag of tagsOfNode(node)) counts.set(tag, (counts.get(tag) || 0) + 1);
    }
    return counts;
  }

  /** Puts one tier in or out of a group, by rewriting its own `tags` cell. The
   * membership is authored on the node, never on the effect - the effect only
   * names the group - so this is the one write that can change what a TAG-scoped
   * effect reaches. */
  function toggleNodeTag(node, tag, member) {
    const columnIndex = node.header.indexOf("tags");
    if (columnIndex <= 0 || !tag) return;
    const tags = tagsOfNode(liveRow(node)).filter((each) => each !== tag);
    if (member) tags.push(tag);
    writeCell(NODE_FILE, node.rowIndex, columnIndex, tags.join("|"));
    renderFileList();
    setStatus(`${NODE_FILE}${isDirty(NODE_FILE) ? " - unsaved" : " - no changes"}`);
    // Membership shows in three places at once - this picker, the tier's own
    // Wiring field, and every card's reach table - so the whole view redraws.
    renderActiveView();
  }

  /** Which tiers a group reaches, as toggles.
   *
   * The point of the control: a group only exists as the set of nodes carrying
   * its name, so authoring one otherwise means opening ten node cards and typing
   * the same word into each. Here the effect that names the group is also where
   * its members are picked. */
  function tierPicker(tag) {
    const wrap = document.createElement("div");
    wrap.className = "field game-tiers";
    const label = document.createElement("label");
    label.append("tiers in this group");
    wrap.append(label);

    const nodes = nodeRows();
    if (!nodes.length) {
      const hint = document.createElement("p");
      hint.className = "hint";
      hint.textContent = "No mycelium nodes loaded, so the group's members cannot be picked here.";
      wrap.append(hint);
      return wrap;
    }

    const chips = document.createElement("div");
    chips.className = "game-chips";
    for (const node of nodes) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "game-chip";
      const member = tag && tagsOfNode(node).includes(tag);
      chip.classList.toggle("on", !!member);
      chip.textContent = `${cell(node, "node_id")} · ${cell(node, "name") || "(unnamed)"}`;
      chip.disabled = !tag;
      chip.title = tag
        ? (member ? `Take tier ${cell(node, "node_id")} out of "${tag}"`
                  : `Put tier ${cell(node, "node_id")} into "${tag}"`)
        : "Name the group first";
      chip.onclick = () => toggleNodeTag(node, tag, !member);
      chips.append(chip);
    }
    wrap.append(chips);

    const hint = document.createElement("p");
    hint.className = tag && !declaredGroups().get(tag) ? "hint warn" : "hint";
    if (!tag) {
      hint.textContent = "Name a group above, then pick the tiers it reaches.";
    } else if (!declaredGroups().get(tag)) {
      hint.textContent = `No tier carries "${tag}" yet, so this effect reaches nothing. `
        + "Pick its tiers above.";
    } else {
      hint.textContent = "Membership is stored on the tiers themselves, so this writes "
        + `${NODE_FILE} rather than the effect. Every effect naming "${tag}" reaches the `
        + "same set.";
    }
    wrap.append(hint);
    return wrap;
  }

  /** The entry as it stands right now. An edit clones the file's rows into
   * state.edits, so an entry captured before the first write to that file still
   * points at the pristine array and reads its own scope as whatever it was. */
  function liveRow(entry) {
    const data = dataOf(entry.file);
    if (!data || !data.rows[entry.rowIndex]) return entry;
    return { ...entry, header: data.header, row: data.rows[entry.rowIndex] };
  }

  /** An effect's scope and target as one pair, because neither is editable on its
   * own: the scope decides what the target may say, so changing it has to reissue
   * the target control. GLOBAL has no target at all, and says so rather than
   * leaving a box that looks fillable.
   *
   * `warn` is asked for a complaint about the pair after every repaint. It lives
   * here rather than beside the call so it cannot go stale: a scope changed in
   * place does not redraw the screen, and a warning left over from the previous
   * scope is worse than none. */
  function scopeTargetFields(effect, warn) {
    const wrap = document.createDocumentFragment();
    const scopeField = field(effect, "scope");
    const slot = document.createElement("div");
    slot.className = "game-target";
    if (!scopeField) return wrap;

    const paint = () => {
      slot.replaceChildren();
      if (enumIs(cell(liveRow(effect), "scope"), "GLOBAL")) {
        const editor = field(effect, "target", { type: "text", options: null });
        if (editor) {
          for (const input of editor.querySelectorAll("input, select, textarea")) {
            input.disabled = true;
          }
          slot.append(editor);
        }
        const hint = document.createElement("p");
        hint.className = "hint";
        hint.textContent = "global — every tier, and the cascade applies it once per tier.";
        slot.append(hint);
      } else if (enumIs(cell(liveRow(effect), "scope"), "TAG")) {
        // Typed rather than picked, because this is where a group is born -
        // there is no list of groups to choose from until some tier carries one,
        // and the picker below is what puts the first tier in it. The declared
        // ones ride along as a datalist so an existing group is still one click.
        const editor = field(effect, "target",
          { type: "text", options: null, noSuggestions: true });
        if (editor) {
          const groups = declaredGroups();
          if (groups.size) {
            const list = document.createElement("datalist");
            list.id = `group-list-${effect.file}-${effect.rowIndex}`;
            for (const [tag, count] of groups) {
              list.append(new Option(`${count} node${count === 1 ? "" : "s"}`, tag));
            }
            const input = editor.querySelector("input");
            if (input) input.setAttribute("list", list.id);
            editor.append(list);
          }
          slot.append(editor);
        }
        slot.append(tierPicker(cell(liveRow(effect), "target")));
      } else {
        const editor = field(effect, "target", { type: "text", options: targetOptionsFor(effect) });
        if (editor) slot.append(editor);
      }
      const complaint = warn && warn(liveRow(effect));
      if (complaint) slot.append(complaint);
    };

    // The scope select writes the cell on `input` like every other control, so
    // repainting after it means the target options are read from the new scope.
    scopeField.addEventListener("input", paint);
    paint();
    wrap.append(scopeField, slot);
    return wrap;
  }

  /** A titled group of fields, skipping the ones this resource does not carry. */
  function fieldGroup(title, entry, columns) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    if (title) {
      const head = document.createElement("h4");
      head.textContent = title;
      wrap.append(head);
    }
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of columns) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }
    wrap.append(fields);
    return wrap;
  }

  /** A mantissa/exponent pair edited side by side, with the magnitude they add up
   * to echoed after them. The pair is what is stored - BigNumber itself is not an
   * @export - and reading "5.0" and "3" in two boxes is not the same as seeing
   * "5.00k". */
  function bigField(entry, label, prefix) {
    const wrap = document.createElement("div");
    wrap.className = "game-big";
    const head = document.createElement("label");
    head.textContent = label;
    wrap.append(head);

    const pair = document.createElement("div");
    pair.className = "game-big-pair";
    const mantissa = field(entry, `${prefix}_mantissa`);
    const exponent = field(entry, `${prefix}_exponent`);
    if (!mantissa || !exponent) return wrap;
    pair.append(mantissa, exponent);

    const echo = document.createElement("span");
    echo.className = "game-big-echo";
    const refresh = () => {
      const current = dataOf(entry.file).rows[entry.rowIndex];
      echo.textContent = `= ${formatBig(
        current[entry.header.indexOf(`${prefix}_mantissa`)],
        current[entry.header.indexOf(`${prefix}_exponent`)])}`;
    };
    refresh();
    // The pair's own inputs already write the cell; this only mirrors them.
    for (const input of pair.querySelectorAll("input")) {
      input.addEventListener("input", refresh);
    }
    pair.append(echo);
    wrap.append(pair);
    return wrap;
  }

  /** The engine's own samples for one resource, or null when the report predates
   * it. Screens draw these as dots behind their own line.
   *
   * Several dictionaries, because only one of them holds prices: `curves` is
   * every priced def, `boons` is the well's payoffs, which are granted rather
   * than bought and so carry an effect and no cost, and `heroes` and `workers`
   * are ladders priced per creature rather than per upgrade. Callers want "the
   * samples for this path" either way. */
  const REPORT_KEYS = ["curves", "boons", "achievements", "boosts", "heroes", "workers",
    "prestige"];

  const engineCurve = (path) => {
    const report = view.curves || {};
    for (const key of REPORT_KEYS) {
      if (report[key] && report[key][path]) return report[key][path];
    }
    return null;
  };

  /** One sampled series over the window a chart is drawn on. The engine samples
   * an open-ended def for 50 levels - BalanceData.CURVE_OPEN_ENDED_LEVELS - so a
   * range reaching past that leaves the dots behind rather than inventing them. */
  function engineWindow(samples, from, to, decode) {
    if (!samples) return null;
    const out = [];
    for (let level = from; level <= to; level += 1) {
      out.push(level < samples.length ? decode(samples[level]) : null);
    }
    return out;
  }

  /** True when this row carries edits that have not been written yet. Per row,
   * not per file: one biome's cost moving must not silence the charts of the
   * five others sharing its table. */
  function rowHasChanges(entry) {
    const pristine = entry && state.loaded.get(entry.file);
    if (!pristine) return false;
    const saved = pristine.rows[entry.rowIndex];
    const current = dataOf(entry.file).rows[entry.rowIndex];
    return !!saved && current.some((value, index) => value !== saved[index]);
  }

  /** The engine's samples for one row, as a series to draw behind the mirror.
   *
   * Withdrawn the moment the row is edited, because the samples were computed
   * from what is on disk and now describe a different curve. Leaving them in did
   * more than mislead: a series sets the y scale it is drawn on, so flattening a
   * cost curve left the axis pinned to the old samples' decades and squashed the
   * new curve into a sliver at the floor. The label stays in the legend so the
   * dots read as withheld rather than as missing.
   */
  function engineSeries(entry, samples, from, to, decode) {
    if (!samples) return null;
    if (rowHasChanges(entry)) {
      return { label: "engine · hidden until Save", points: [], color: "var(--muted)", dots: true };
    }
    const points = engineWindow(samples, from, to, decode);
    return points && { label: "engine", points, color: "var(--muted)", dots: true };
  }

  window.GameKit = {
    formatBig, log10Of, growthCurve, powerCurve, effectCurve, enumIs,
    xpLadder, levelForXp, chart, chartBlock, hueOf,
    rowsOf, findRow, cell, numberCell,
    field, fieldGroup, bigField, engineCurve, engineWindow, engineSeries, rowHasChanges,
    targetOptionsFor, scopeTargetFields, liveRow, tierPicker, declaredGroups, tagsOfNode,
  };

  /* ------------------------------------------------------------------- wiring */

  /** Screens whose own open() has run. A screen may need a report of its own -
   * the prestige web is PerkTree run headlessly - and paying for it on the tab
   * that wants it beats paying for every screen's on the way in. */
  const opened = new Set();

  async function ensureOpen(name) {
    const screen = screens()[name];
    if (!screen || !screen.open || opened.has(name)) return;
    await screen.open();
    opened.add(name);
  }

  view.invalidate = async () => {
    // The engine samples go stale the moment a cost is written, and a stale dot
    // off the line reads as a bug in the maths rather than as an old fetch.
    view.curves = await api("/api/curves");
    // Same for whatever a screen computed for itself, but only for the ones that
    // have actually been opened - invalidating a report nobody fetched would
    // fetch it.
    for (const name of opened) {
      const screen = screens()[name];
      if (screen && screen.invalidate) await screen.invalidate();
    }
  };

  view.open = async () => {
    // A screen spans several tables at once - a biome card alone reads BiomeDef,
    // UpgradeDef, UpgradeEffectDef and ScalingSourceDef - so load them all.
    await loadAllFiles();
    buildEdges();
    await view.invalidate();
    await ensureOpen(activeScreen());
  };

  /** The screen showing, defaulting to the first registered one. */
  function activeScreen() {
    const names = Object.keys(screens());
    return names.includes(view.screen) ? view.screen : (names[0] || null);
  }

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "game-view";
    wrap.innerHTML = `<nav class="game-tabs"></nav><div class="game-body"></div>`;
    view.dom.tabs = wrap.querySelector(".game-tabs");
    view.dom.body = wrap.querySelector(".game-body");
    return wrap;
  };

  function renderTabs() {
    view.dom.tabs.replaceChildren();
    const names = Object.keys(screens());
    for (const name of names) {
      const button = document.createElement("button");
      button.className = "game-tab";
      button.textContent = screens()[name].label;
      button.classList.toggle("active", name === view.screen);
      button.onclick = async () => {
        if (view.screen === name) return;
        setStatus(`opening ${screens()[name].label.toLowerCase()}…`);
        try {
          await ensureOpen(name);
        } catch (error) { log(String(error), true); return; }
        view.screen = name;
        view.render();
        view.element.scrollTop = 0;
      };
      view.dom.tabs.append(button);
    }
    view.dom.tabs.append(saveButton());
  }

  /** The header's "Save file" is scoped to whichever file the *table* view has
   * selected, which is unrelated to what was edited here - a screen writes to
   * four tables at once and to none of them by name. "Save all" is the button
   * that actually applies these edits, so the view offers it directly rather
   * than leaving the prominent green one looking like it would work. */
  function saveButton() {
    const button = document.createElement("button");
    button.className = "game-save";
    const files = [...state.edits.keys()];
    button.disabled = !files.length;
    button.textContent = files.length ? `Save ${files.length} file(s)` : "Saved";
    button.title = files.length
      ? `Writes ${files.join(", ")} back to the .tres files`
      : "Nothing edited here yet";
    button.onclick = () => { saveAll(); };
    return button;
  }

  view.render = () => {
    view.screen = activeScreen();
    renderTabs();
    // Every edit and every slot pick redraws the whole page, and this page is a
    // long one - without this the view jumps to the top on each keystroke.
    const scroll = view.element ? view.element.scrollTop : 0;
    sharing.clear();   // the blocks about to be dropped must not keep redrawing
    view.dom.body.replaceChildren();
    if (!view.screen) {
      const empty = document.createElement("p");
      empty.className = "hint";
      empty.textContent = "No game screens are registered.";
      view.dom.body.append(empty);
      return;
    }
    // One screen throwing must not leave the view blank with no explanation.
    try {
      screens()[view.screen].render(view.dom.body, view);
    } catch (error) {
      log(String(error), true);
      const failed = document.createElement("p");
      failed.className = "hint warn";
      failed.textContent = String(error);
      view.dom.body.append(failed);
    }
    applyCollapse(view.dom.body, view.screen);
    if (view.element) view.element.scrollTop = scroll;
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.game = view;
})();
