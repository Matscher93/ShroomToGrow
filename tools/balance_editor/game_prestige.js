/* Prestige web view: the mycelial web as the game lays it out, coloured by what
 * it costs.
 *
 * Everything here comes from GET /api/perks, which is PerkTree.build() run
 * headlessly - the same positions, parents and effects the player will see,
 * including the branch default_effects fallback. Two numbers no table can show
 * drive the colouring:
 *
 *   cost_to_max  what maxing this one perk costs
 *   path_cost    what maxing everything from the core down to it costs, which is
 *                the real price of reaching a deep perk
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab: the web is
 * one of the game's screens, so it is read next to the biomes rather than beside
 * the tables.
 */
(() => {
  const {
    growthCurve, effectCurve, chartBlock, engineCurve, engineSeries, cell, numberCell, enumIs,
    log10Of: bigLog10,   // the local log10Of below takes a pair, this one a pair's halves
    fromLog10, formatBig, logSumExp, costToMaxLog10, resetRange,
    scopeTargetFields, rowsOf, fieldGroup, bigField, hueOf, dependencyField,
  } = window.GameKit;

  /* The one resource pricing a finished run: PrestigeCurveDef, authored as
   * data/prestige/res_prestige_curve.tres. One row, so it is read by table
   * rather than looked up by path. */
  const PAYOUT_FILE = "PrestigeCurveDef";

  /* Each scale is a span, not a number: `from` is what the perk is worth at its
   * first level, `to` at its last. A perk is drawn as the gradient between the
   * two, so a node that stays cheap and one that climbs three decades over its
   * levels no longer look alike. `to` is what the perk is ranked and compared
   * by, and is the colour a perk falls back to when its `from` is missing. */
  const SCALES = {
    path_cost: {
      label: "Path cost", note: "biomass to reach this perk from the core, first level to last",
      from: (perk) => perk.entry_cost, to: (perk) => perk.path_cost,
    },
    cost_to_max: {
      label: "Own cost", note: "biomass to max this perk alone, from its first level up",
      from: (perk) => perk.first_level_cost, to: (perk) => perk.cost_to_max,
    },
    effect_at_max: {
      label: "Effect at max", note: "magnitude of its effect, one level to maxed",
      from: (perk) => perk.effect_at_first, to: (perk) => perk.effect_at_max,
    },
  };

  /* What "highlight these" is asking, empty until something is asked. Text
   * matches a name or an id, `stat` picks one effect stat (biome points are
   * level_points), and from/to bound the perk on whichever scale is showing -
   * in log10, the units the legend already speaks, because a deep perk's path
   * cost runs past what a float holds. */
  const NO_EFFECT = "\u0000none";   // cannot collide with a stat name

  const view = {
    label: "Prestige",
    scale: "path_cost",
    filter: { text: "", stat: "", branch: "", from: null, to: null,
      depthFrom: null, depthTo: null },
    matched: null,     // how many perks the filter caught, null when it is off
    // The perks under bulk edit, as res_paths. Beside state.focus rather than
    // instead of it: focus still says which single row the field editor and the
    // header's Save act on, and picking a set does not change that.
    picked: new Set(),
    rampMode: "geometric",   // remembered between applies
    drawn: new Map(),  // res_path -> the perk drawWeb last laid out, for ramp order
    report: null,
    warnings: [],      // what PerkTree would push_error about the staged shape
    widest: new Map(), // branch key -> its widest sibling offset, from webLayout
    spreadLimit: null, // the offset past which a branch outgrows its slice
    hovered: null,
    element: null,   // this screen's own root, kept across renders
    chart: null,     // the live <svg>, so a pan can move it without a redraw
    // The window on the web, as a viewBox, and the whole web's own bounds it is
    // read against. Outlive the drawing: a redraw from an edit must not move the
    // corner being looked at.
    camera: null,
    fit: null,
    homeWidth: 0,    // the fitted window's width, which the zoom readout is 100% of
  };

  /* ------------------------------------------------------------------ numbers */

  /** log10 of a [mantissa, exponent] pair, or null when there is nothing to
   * plot. Kept in log space throughout: a deep perk's path cost runs past what
   * a float can hold. */
  function log10Of(pair) {
    if (!pair || pair[0] === 0) return null;
    return Math.log10(Math.abs(pair[0])) + pair[1];
  }

  const format = (pair) => {
    if (!pair) return "-";
    const [mantissa, exponent] = pair;
    if (mantissa === 0) return "0";
    if (exponent >= -2 && exponent < 4) return (mantissa * Math.pow(10, exponent)).toPrecision(3);
    return `${mantissa.toFixed(2)}e${exponent}`;
  };

  const filterActive = () => {
    const f = view.filter;
    return !!(f.text || f.stat || f.branch || f.from !== null || f.to !== null
      || f.depthFrom !== null || f.depthTo !== null);
  };

  /** Whether one perk is what the filter is asking for. Every clause is an AND:
   * "biome point upgrades costing between 1e4 and 1e6" is the question worth
   * asking, and either half alone answers a different one. */
  function matchesFilter(perk) {
    const f = view.filter;
    if (f.text && !`${perk.id} ${perk.display_name}`.toLowerCase()
        .includes(f.text.toLowerCase())) {
      return false;
    }
    if (f.stat) {
      const stat = perk.stat || "";
      if (f.stat === NO_EFFECT ? stat !== "" : stat !== f.stat) return false;
    }
    // Branch and depth are clauses rather than a picker of their own, so "the
    // outer half of tempo" is one question and dims the web like every other.
    if (f.branch && perk.branch_key !== f.branch) return false;
    if (f.depthFrom !== null && perk.depth < f.depthFrom) return false;
    if (f.depthTo !== null && perk.depth > f.depthTo) return false;
    if (f.from !== null || f.to !== null) {
      const value = valueOf(perk);
      // A perk with nothing on this scale is not "cheap", it is unanswerable -
      // and a bound it silently passed would be read as an answer.
      if (value === null) return false;
      if (f.from !== null && value < f.from) return false;
      if (f.to !== null && value > f.to) return false;
    }
    return true;
  }

  const scaleOf = () => SCALES[view.scale];
  /** What the perk is worth on the current scale once maxed, and at its first
   * level. Both in log space, and null when the scale does not apply - a perk
   * with no effect has neither end on the effect scale. */
  const valueOf = (perk) => log10Of(scaleOf().to(perk));
  const startOf = (perk) => log10Of(scaleOf().from(perk));

  /** Picks a perk to edit without leaving the web. setFocus keeps the sidebar
   * (and so Save, Revert and Ctrl+S) pointing at the file the perk lives in, and
   * re-renders this view, which draws the editor for it in the panel. */
  const edit = (path) => setFocus(path);

  /* ---------------------------------------------------------------- selection */

  /* Balancing is rarely a question about one perk: a branch is retuned against
   * its neighbours, and doing that a field at a time was fifteen clicks and a
   * drift. `view.picked` is that set, filled four ways - ctrl-click, shift-click
   * for a subtree, the Highlight bar's "Select these", and the branch and depth
   * clauses feeding it - and read by the bulk panel, which is the only thing
   * that writes through it. */

  const pickedPaths = () => [...view.picked];

  function togglePicked(path) {
    if (!view.picked.delete(path)) view.picked.add(path);
    view.render();
  }

  /** Everything hanging off `perk`, itself included. Parentage is by id, so the
   * children of a node are found by asking who names it as a parent - the same
   * direction reparent's cycle check walks. */
  function subtreeOf(perk, byId) {
    const children = new Map();
    for (const other of byId.values()) {
      if (!other.parent_id) continue;
      if (!children.has(other.parent_id)) children.set(other.parent_id, []);
      children.get(other.parent_id).push(other);
    }
    const out = [];
    const stack = [perk];
    while (stack.length) {
      const at = stack.pop();
      if (at.res_path) out.push(at.res_path);
      for (const child of children.get(at.id) || []) stack.push(child);
    }
    return out;
  }

  /** Shift-click takes the whole subtree, and takes it as a whole: if every perk
   * under this one is already picked the gesture is read as "not those after
   * all", so the same click undoes itself. */
  function pickSubtree(perk, byId) {
    const paths = subtreeOf(perk, byId);
    const all = paths.every((path) => view.picked.has(path));
    for (const path of paths) {
      if (all) view.picked.delete(path);
      else view.picked.add(path);
    }
    view.render();
  }

  /* ------------------------------------------------------------------ drawing */

  const PAD = 40;
  /* World units, matching the width sc_perk_node.tscn wraps a perk name at. The
   * positions here are PerkTree's, so a name that needs two lines in the game
   * needs two lines here, and a label that would sit on its neighbour in one
   * view sits on it in the other. */
  const LABEL_WIDTH = 88;
  const LABEL_LINE = 10;   // the 9px .perk-label font, leaded

  /* SVG text does not wrap, so a long name is measured and broken by hand.
   * measureText on a 2d context is the same shaping the SVG text will get, as
   * long as it is asked in the font the stylesheet gives .perk-label. */
  const measure = (() => {
    const context = document.createElement("canvas").getContext("2d");
    context.font = "9px ui-sans-serif, system-ui, sans-serif";
    return (text) => context.measureText(text).width;
  })();

  function wrapLabel(text) {
    const lines = [];
    let line = "";
    for (const word of text.split(" ")) {
      const candidate = line ? `${line} ${word}` : word;
      // A single word wider than the wrap width still goes on its own line:
      // there is nowhere else to put it, and breaking mid-word reads worse.
      if (line && measure(candidate) > LABEL_WIDTH) {
        lines.push(line);
        line = word;
      } else {
        line = candidate;
      }
    }
    if (line) lines.push(line);
    return lines;
  }

  /** Cheap blue→red ramp over the observed range, so the eye reads "expensive"
   * without a legend lookup. */
  function ramp(value, min, max) {
    const t = max > min ? (value - min) / (max - min) : 0.5;
    return `hsl(${(1 - t) * 220} 70% ${58 - t * 18}%)`;
  }

  /** How to paint one perk: a gradient running from what its first level is
   * worth to what it is worth maxed, which is the difference between a perk that
   * stays cheap and one that climbs decades over its levels.
   *
   * Flat when there is only one end to show - a perk with no effect on the
   * effect scale, a single-level perk, or a report cached by a server started
   * before the span was reported. Each gradient goes in `defs` once and is
   * referenced by id. */
  function paint(perk, min, max, defs) {
    const value = valueOf(perk);
    if (value === null) return "var(--panel)";
    const start = startOf(perk);
    if (start === null || start === value) return ramp(value, min, max);

    const id = `web-fill-${perk.id}`;
    const gradient = svgEl("linearGradient", { id, x1: "0%", y1: "0%", x2: "100%", y2: "100%" });
    gradient.append(svgEl("stop", { offset: "0%", "stop-color": ramp(start, min, max) }));
    gradient.append(svgEl("stop", { offset: "100%", "stop-color": ramp(value, min, max) }));
    defs.append(gradient);
    return `url(#${id})`;
  }

  /* ------------------------------------------------------------------ layout */

  /* PerkTree's placement, mirrored.
   *
   * The report carries positions, but it is PerkTree run over what is on disk -
   * so until this existed, dragging a perk into a different place among its
   * siblings moved nothing until the file was saved, which is precisely the edit
   * whose result has to be seen to be judged. Sibling index is the angle and
   * nesting is the radius, so the web is the only readout order has.
   *
   * Mirrored rather than fetched, the way the biome and node charts mirror the
   * game's own formulas. Constants and maths from model/prestige/gd_perk_tree.gd;
   * if that file's layout changes, this follows.
   */
  const CANVAS_CENTER = 520;
  const ROOT_RADIUS = 200;
  const DEPTH_RADIUS_STEP = 170;
  const SIBLING_SPREAD_DEG = 26;
  /* PerkTree.SPREAD_FALLOFF: how hard sibling spacing narrows as a branch reaches
   * outward. Spacing is an angle, so the arc it buys is that angle times the
   * radius - at a flat 26 degrees the tenth ring's siblings sit ten times further
   * apart than the first's, and a long branch reads as a fan rather than a line.
   * 1.0 holds the gap between siblings exactly constant the whole way out, 0.0 is
   * the flat spacing this replaced. */
  const SPREAD_FALLOFF = 0.5;
  const BRANCH_START_DEG = -90;   // the first branch points straight up
  const BRANCH_SLICE_FILL = 0.8;  // the rest of a branch's slice is gutter

  /* The chart kinds drawn about one perk, as chartBlock keys. Named here so the
   * range specs below and the reset in render() cannot drift apart. */
  const PERK_COST_CHART = "perk-cost";
  const PERK_EFFECT_CHART = "perk-effect";
  const PERK_CHART_KEYS = [PERK_COST_CHART, PERK_EFFECT_CHART];

  const LIST_FILE = "PerkBranchList";
  const BRANCH_FILE = "PerkBranchDef";

  const paths = (value) => (value || "").split("|").filter(Boolean);

  /** The rows one list column points at, each carrying where it sits in that
   * cell. The position is kept from before the unresolved ones are dropped: it
   * is what a reorder rewrites, and an index counted after a gap would move the
   * wrong entry. */
  function nodesOf(entry, column) {
    const list = paths(cell(entry, column));
    return list
      .map((path, cellIndex) => {
        const row = rowIndexOf(path);
        return row && { ...row, cellIndex, cellCount: list.length };
      })
      .filter(Boolean);
  }

  /** PerkTree._depth_falloff: what one ring's sibling step is worth against a
   * root's. 1.0 at the root ring, and smaller the further out a ring sits. */
  function depthFalloff(depth) {
    if (SPREAD_FALLOFF <= 0) return 1;
    return Math.pow(ROOT_RADIUS / (ROOT_RADIUS + DEPTH_RADIUS_STEP * depth), SPREAD_FALLOFF);
  }

  /** PerkTree._widest_offset: how far from its branch's centre line the branch
   * reaches, in root-ring sibling steps. Offsets accumulate down a chain, so this
   * is what decides the spacing the whole branch gets - and past the limit
   * webLayout works out the branch stops fitting its slice, which perk_tree_test
   * asserts.
   *
   * Counted in root-ring steps, not in siblings: an offset picked up out at depth
   * eight counts for a fraction of one picked up at depth one, the same weighting
   * place() lays the branch out with. Without it the cap would be measured against
   * a spread the branch no longer uses and would shrink every long branch for
   * angles it never reaches. */
  function widestOffset(siblings, parentOffset, seen, depth = 0) {
    let widest = Math.abs(parentOffset);
    const falloff = depthFalloff(depth);
    siblings.forEach((node, index) => {
      const id = cell(node, "id");
      if (seen.has(id)) return;
      seen.add(id);
      const offset = parentOffset + (index - (siblings.length - 1) / 2) * falloff;
      widest = Math.max(widest, widestOffset(nodesOf(node, "children"), offset, seen, depth + 1));
    });
    return widest;
  }

  /** The whole web from the staged rows: every perk with the position PerkTree
   * would give it, plus the warnings PerkTree would push_error about. */
  function webLayout() {
    const listRow = rowsOf(LIST_FILE)[0];
    if (!listRow) return null;
    const coreRow = rowIndexOf(cell(listRow, "core"));
    if (!coreRow) return null;

    const perks = [];
    const warnings = [];
    const widest = new Map();
    const seen = new Set([cell(coreRow, "id")]);

    perks.push({
      ...authoredFields(coreRow),
      parent_id: "", branch_key: "", branch_label: "core", hue: 0, depth: 0,
      world_x: CANVAS_CENTER, world_y: CANVAS_CENTER,
    });

    const branches = paths(cell(listRow, "branches")).map(rowIndexOf).filter(Boolean);
    const step = 360 / Math.max(1, branches.length);
    const halfSlice = toRadians(step * 0.5 * BRANCH_SLICE_FILL);

    branches.forEach((branch, index) => {
      const roots = nodesOf(branch, "roots");
      // A branch whose last root was dragged away still takes its slice of the
      // circle and draws nothing in it, which reads as a rendering fault rather
      // than as an edit. perk_tree_test asserts exactly one root per branch.
      if (roots.length !== 1) {
        warnings.push(`${cell(branch, "label") || cell(branch, "key")} has `
          + `${roots.length} roots - every branch is authored with exactly one.`);
      }
      // Measured on its own copy of `seen`: the duplicate-id skip below decides
      // what is drawn, while the spread PerkTree picks is measured over the
      // authored shape before any of that.
      const reach = widestOffset(roots, 0, new Set());
      widest.set(cell(branch, "key"), reach);
      const spread = reach <= 0
        ? toRadians(SIBLING_SPREAD_DEG)
        : Math.min(toRadians(SIBLING_SPREAD_DEG), halfSlice / reach);
      place(branch, roots, cell(coreRow, "id"),
        toRadians(BRANCH_START_DEG + step * index), 0, spread, branch, "roots");
    });

    // Where _spread_for starts cutting: a branch keeps the full
    // SIBLING_SPREAD_DEG only while its widest offset still fits inside half a
    // slice at that spacing. It moves with the branch count, so it is worked out
    // here rather than written down - an added branch narrows every slice.
    const spreadLimit = halfSlice / toRadians(SIBLING_SPREAD_DEG);
    return { perks, warnings, widest, spreadLimit };

    /** PerkTree._place_children, one branch deep at a time. `ownerRow` and
     * `ownerColumn` are the cell these siblings are listed in - the branch's
     * `roots` at the top, a parent's `children` below it - which is what a perk
     * dragged or nudged into a different place among them rewrites. */
    function place(branch, siblings, parentId, parentAngle, depth, spread,
        ownerRow, ownerColumn) {
      siblings.forEach((node, index) => {
        const id = cell(node, "id");
        // The engine skips a repeated id and everything under it rather than
        // building two perks that would collapse into one save key.
        if (seen.has(id)) {
          warnings.push(`${cell(branch, "label") || cell(branch, "key")} reuses the id `
            + `"${id}" - that perk and everything under it is not drawn.`);
          return;
        }
        seen.add(id);
        const angle = parentAngle
          + spread * (index - (siblings.length - 1) / 2) * depthFalloff(depth);
        const radius = ROOT_RADIUS + DEPTH_RADIUS_STEP * depth;
        perks.push({
          ...authoredFields(node),
          parent_id: parentId,
          branch_key: cell(branch, "key"),
          branch_label: cell(branch, "label") || cell(branch, "key"),
          hue: numberCell(branch, "hue", 0),
          // The report counts a perk's ancestors, so its roots are depth 1 while
          // PerkTree places them at depth 0. Report's convention wins - the
          // tooltip has always shown that number.
          depth: depth + 1,
          world_x: CANVAS_CENTER + Math.cos(angle) * radius,
          world_y: CANVAS_CENTER + Math.sin(angle) * radius,
          // Where this perk sits, and in which cell - the web is radial, so a
          // control that moves it has to know which way along the arc that is.
          angle,
          order: { path: ownerRow.row[0], column: ownerColumn,
            index: node.cellIndex, count: node.cellCount },
        });
        place(branch, nodesOf(node, "children"), id, angle, depth + 1, spread,
          node, "children");
      });
    }
  }

  const toRadians = (degrees) => (degrees * Math.PI) / 180;

  /** What the authored row says about a perk, as the report names those fields.
   * Read from the staged cells so a renamed perk is renamed on the web too. */
  const authoredFields = (node) => ({
    id: cell(node, "id"),
    // row[0], not node.path: rowIndexOf's entries carry no `path` the way
    // GameKit.rowsOf's do, and a res_path of undefined is a perk that cannot be
    // selected, cannot be clicked and never grows its ⊕.
    res_path: node.row[0],
    display_name: cell(node, "display_name") || cell(node, "id"),
    max_level: numberCell(node, "max_level", 0),
    cost_growth: numberCell(node, "cost_growth", 0),
    cost_growth_exponent: numberCell(node, "cost_growth_exponent", 0),
  });

  function drawWeb() {
    // Positions and shape come from the staged rows so a reorder shows at once;
    // the costs they are coloured by come from the report, which is PerkTree run
    // over what is on disk and so only moves on Save.
    const layout = webLayout();
    const priced = new Map(view.report.perks.map((perk) => [perk.id, perk]));
    const perks = layout
      ? layout.perks.map((perk) => ({ ...(priced.get(perk.id) || {}), ...perk }))
      : view.report.perks;
    view.warnings = layout ? layout.warnings : [];
    view.widest = layout ? layout.widest : new Map();
    view.spreadLimit = layout ? layout.spreadLimit : null;
    const positions = new Map(perks.map((perk) => [perk.id, perk]));
    // Keyed by id rather than path, because parentage is expressed in ids: the
    // ancestor walk a reparent has to refuse a cycle on runs through this.
    const byId = positions;
    // Both ends of every perk's span set the ramp, so the cheap end of the
    // cheapest perk and the dear end of the dearest are the colours at the far
    // ends of the legend.
    const values = perks.flatMap((perk) => [startOf(perk), valueOf(perk)])
      .filter((value) => value !== null);
    const min = Math.min(...values);
    const max = Math.max(...values);

    const xs = perks.map((perk) => perk.world_x);
    const ys = perks.map((perk) => perk.world_y);
    const left = Math.min(...xs) - PAD;
    const top = Math.min(...ys) - PAD;
    const width = Math.max(...xs) - left + PAD;
    const height = Math.max(...ys) - top + PAD;

    const svg = svgEl("svg", { id: "web-chart" });
    // The window on the web, not the web itself: the camera keeps whatever the
    // last zoom and pan left it on, so a redraw from an edit does not throw away
    // the corner that was being read.
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    view.chart = svg;
    applyCamera(cameraFor({ left, top, width, height }));
    enableZoomPan(svg);
    const defs = svgEl("defs");
    svg.append(defs);

    // Highlighting is a property of the whole drawing rather than of one node,
    // so it is decided once here: what matches stays lit and everything else
    // recedes, which reads as "these ones" far faster than a marker per hit.
    const filtering = filterActive();
    const matched = filtering ? new Set(perks.filter(matchesFilter).map((p) => p.id)) : null;
    view.matched = matched ? matched.size : null;

    for (const perk of perks) {
      const parent = positions.get(perk.parent_id);
      if (!parent) continue;
      // A link is only as lit as the two ends it joins, or the highlighted nodes
      // would sit in a cobweb of full-strength lines.
      const lit = !filtering || (matched.has(perk.id) && matched.has(parent.id));
      svg.append(svgEl("line", { class: lit ? "link" : "link dim",
        x1: parent.world_x, y1: parent.world_y,
        x2: perk.world_x, y2: perk.world_y, stroke: `hsl(${perk.hue} 60% 55%)` }));
    }

    // What the panel's ramp orders by, and what its chips are labelled from.
    // Kept here rather than recomputed: renderPanel runs straight after this,
    // over the same layout, and webLayout is the expensive half of a render.
    view.drawn = new Map(perks.filter((perk) => perk.res_path)
      .map((perk) => [perk.res_path, perk]));

    for (const perk of perks) {
      const group = svgEl("g");
      const classes = [];
      const selected = perk.res_path && perk.res_path === state.focus;
      const picked = perk.res_path && view.picked.has(perk.res_path);
      if (selected) classes.push("selected");
      if (picked) classes.push("picked");
      // The perk being edited is never dimmed, whether or not it matches: the
      // panel beside it is showing its fields, and fading the node they belong
      // to leaves that panel pointing at nothing on screen. A picked one is not
      // dimmed either - the bulk panel is about to write to it.
      if (filtering) {
        if (matched.has(perk.id)) classes.push("match");
        else if (!selected && !picked) classes.push("dim");
      }
      if (classes.length) group.setAttribute("class", classes.join(" "));
      const circle = svgEl("circle", { class: "perk", cx: perk.world_x, cy: perk.world_y,
        r: perk.parent_id ? 15 : 20, fill: paint(perk, min, max, defs),
        stroke: `hsl(${perk.hue} 60% 55%)` });
      group.append(circle);

      const label = svgEl("text", { class: "perk-label", x: perk.world_x, y: perk.world_y + 28 });
      label.setAttribute("text-anchor", "middle");
      for (const [index, line] of wrapLabel(perk.display_name).entries()) {
        // x repeated per tspan: without it a wrapped line resumes where the
        // previous one ended instead of centring under the node again.
        const span = svgEl("tspan", { x: perk.world_x, dy: index ? LABEL_LINE : 0 });
        span.textContent = line;
        label.append(span);
      }
      group.append(label);

      attachTip(group, [
        perk.display_name,
        `branch: ${perk.branch_label} · depth ${perk.depth}`,
        `max level: ${perk.max_level} · growth ${perk.cost_growth}^(level·${perk.cost_growth_exponent}^level)`,
        `level cost: ${format(perk.first_level_cost)} → ${format(perk.last_level_cost)}`,
        `cost to max: ${format(perk.cost_to_max)}`,
        `path cost: ${format(perk.entry_cost)} to reach → ${format(perk.path_cost)} maxed`,
        perk.stat ? `${perk.stat} (${perk.op}) ${format(perk.effect_at_max)} at max` : "no effect",
        // What the two ends of this perk's gradient stand for on the scale being
        // shown, so the colouring never has to be guessed at.
        `${scaleOf().label}: ${format(scaleOf().from(perk))} → ${format(scaleOf().to(perk))}`,
      ].join("\n"));

      if (perk.res_path) {
        group.setAttribute("data-path", perk.res_path);
        // A drag that reparents ends in a pointerup over some node, and the
        // click that follows would otherwise re-focus whichever one that was.
        group.onclick = (event) => {
          if (dragSuppressedClick()) return;
          if (event.shiftKey) pickSubtree(perk, byId);
          else if (event.ctrlKey || event.metaKey) togglePicked(perk.res_path);
          // A plain click is still "edit this one", and it drops the set: a
          // selection left standing would keep the bulk panel over the fields
          // of the perk that was just asked for.
          else { view.picked.clear(); edit(perk.res_path); }
        };
        // The core is nobody's child, so there is nothing to move it out of.
        if (perk.order) enableReparentDrag(group, perk, byId);
      }
      // Growing the tree where it is being read. Only on the perk being edited,
      // so the web is not a field of buttons, and never on the core: its
      // `children` is not walked - a branch's first perks hang off the branch's
      // own `roots`, and a new branch is a different operation entirely.
      // Not while a set is picked: those badges act on one perk each, and the
      // panel beside them is showing what the whole set is about to become.
      if (!view.picked.size && perk.res_path && perk.res_path === state.focus
          && perk.parent_id) {
        group.append(addChildBadge(perk), orderBadges(perk));
      }
      svg.append(group);
    }

    if (values.length) {
      // Bottom-left, not top: the cost chart hangs over the top-left corner of
      // the canvas, and the legend used to sit exactly under it.
      //
      // Pinned to the camera rather than to the drawing: the ramp is what the
      // colours are read against, and a legend left at the web's own corner is
      // off screen the moment anything is zoomed into. applyCamera moves it, so
      // the transform here is only what the first frame needs.
      const ticks = svgEl("g", { class: "scale-legend" });
      [min, (min + max) / 2, max].forEach((value, index) => {
        const text = svgEl("text", { class: "scale-tick", x: 6, y: -34 + index * 14 });
        text.textContent = `${["cheap", "mid", "dear"][index]}: 1e${value.toFixed(1)}`;
        ticks.append(text);
      });
      svg.append(ticks);
      placeLegend();
    }
    return svg;
  }

  /* ----------------------------------------------------------------- camera */

  /* Wheel to zoom about the cursor, drag the background to pan, double-click to
   * fit. The web is eight branches ten rings deep, so at a width that shows all
   * of it a perk's label is a few pixels tall; before this the only way in was
   * the browser's own page zoom, which took the panel with it.
   *
   * Held as the SVG's viewBox rather than as a scroll offset: the drawing is
   * rebuilt on every keystroke in the panel, and a scroller starts a fresh child
   * at its top-left corner. A viewBox is set on the new element for nothing, and
   * it zooms out past the web's own bounds, which a scroller cannot do.
   *
   * A pan or a zoom writes the attribute on the live SVG and stops there. Only a
   * layout change redraws - moving the window is not a reason to lay out several
   * hundred nodes again.
   */

  const ZOOM_STEP = 1.2;      // one wheel notch
  const MIN_SPAN = 260;       // world units across: about two perks and a label
  const MAX_SPAN_FILL = 4;    // how far out past the whole web a zoom may go

  const canvasOf = () => view.element && view.element.querySelector(".web-canvas");

  /** The camera to draw `fit` with. Kept across redraws; only its shape follows
   * the canvas, so that "meet" never letterboxes and a zoom about the cursor
   * lands exactly on the point it was pointed at. */
  function cameraFor(fit) {
    view.fit = fit;
    const aspect = canvasAspect() || fit.width / Math.max(fit.height, 1);
    const home = fittedTo(fit, aspect);
    // What the readout calls 100%. The web is taller than it is wide, so the
    // window that holds all of it is wider than the web's own bounds - measuring
    // the zoom against those would call the fitted view a third of itself.
    view.homeWidth = home.w;
    if (!view.camera) view.camera = home;
    else view.camera = shapedTo(view.camera, aspect);
    return view.camera;
  }

  function canvasAspect() {
    const canvas = canvasOf();
    if (!canvas) return 0;
    const rect = canvas.getBoundingClientRect();
    return rect.height > 0 ? rect.width / rect.height : 0;
  }

  /** The whole web, grown - never cropped - to the canvas's shape. */
  function fittedTo(fit, aspect) {
    let width = fit.width;
    let height = fit.height;
    if (width / height < aspect) width = height * aspect;
    else height = width / aspect;
    return { x: fit.left + fit.width / 2 - width / 2, y: fit.top + fit.height / 2 - height / 2,
      w: width, h: height };
  }

  /** The same window in a canvas of a different shape - the panel's drag bar is
   * what changes it. Width is what is kept: the web is wider than it is tall, so
   * holding it is what keeps a branch in frame when the panel grows. */
  function shapedTo(camera, aspect) {
    const height = camera.w / aspect;
    return { x: camera.x, y: camera.y + camera.h / 2 - height / 2, w: camera.w, h: height };
  }

  /** Writes the camera onto the live drawing. Everything that moves the window
   * goes through here, and nothing here redraws. */
  function applyCamera(camera) {
    view.camera = camera;
    if (!view.chart) return camera;
    view.chart.setAttribute("viewBox", `${camera.x} ${camera.y} ${camera.w} ${camera.h}`);
    placeLegend();
    showZoom();
    return camera;
  }

  /** The ramp legend, held at the camera's bottom-left corner and counter-scaled
   * so it stays the size it is drawn at rather than growing with the zoom. */
  function placeLegend() {
    const legend = view.chart && view.chart.querySelector(".scale-legend");
    if (!legend || !view.fit) return;
    const camera = view.camera;
    const scale = camera.w / view.fit.width;
    legend.setAttribute("transform",
      `translate(${camera.x} ${camera.y + camera.h}) scale(${scale})`);
  }

  /** Zoom is read against the fitted window, so 100% is "the whole web" whatever
   * size the canvas happens to be. */
  const zoomFactor = () =>
    (view.homeWidth && view.camera ? view.homeWidth / view.camera.w : 1);

  function showZoom() {
    const readout = view.element && view.element.querySelector(".web-zoom-level");
    if (readout) readout.textContent = `${Math.round(zoomFactor() * 100)}%`;
  }

  /** Zooms by `factor` about a point in world units, or about the middle of the
   * window when none is given. Clamped at both ends: further in than MIN_SPAN
   * there is one node and no context, and further out the web is a smudge. */
  function zoomBy(factor, about) {
    if (!view.camera || !view.fit) return;
    const camera = view.camera;
    const maxSpan = Math.max(view.fit.width, view.fit.height) * MAX_SPAN_FILL;
    const width = Math.min(Math.max(camera.w * factor, MIN_SPAN), maxSpan);
    const scale = width / camera.w;
    if (scale === 1) return;
    const at = about || { x: camera.x + camera.w / 2, y: camera.y + camera.h / 2 };
    applyCamera({ x: at.x - (at.x - camera.x) * scale, y: at.y - (at.y - camera.y) * scale,
      w: width, h: camera.h * scale });
  }

  function fitCamera() {
    if (!view.fit) return;
    const home = fittedTo(view.fit, canvasAspect() || view.fit.width / view.fit.height);
    view.homeWidth = home.w;
    applyCamera(home);
  }

  /** The pan in progress, if any. Outside enableZoomPan because a redraw can
   * replace the drawing under a gesture - the camera it moves does not. */
  let panning = null;

  function enableZoomPan(svg) {
    svg.addEventListener("wheel", (event) => {
      // Not passive: a wheel over the web is a zoom, and the canvas no longer
      // scrolls - there is nothing for the page to do with it instead.
      event.preventDefault();
      zoomBy(event.deltaY < 0 ? 1 / ZOOM_STEP : ZOOM_STEP, toUserSpace(svg, event));
    }, { passive: false });

    svg.addEventListener("pointerdown", (event) => {
      // Left on a node is a reparent drag and left on a badge is a press; the
      // background is what is left. Middle drags anywhere, which is the way to
      // pan out of a corner packed with nodes.
      const onNode = event.target.closest && event.target.closest("g[data-path], .perk-badge");
      if (event.button === 1 || (event.button === 0 && !onNode)) {
        const matrix = svg.getScreenCTM();
        if (!matrix || !matrix.a) return;
        panning = { x: event.clientX, y: event.clientY, scale: matrix.a, from: view.camera };
        event.preventDefault();
        svg.classList.add("panning");
      }
    });

    // Double-click, not a button alone: the gesture that undoes a zoom belongs
    // where the zoom was made. The buttons in the corner keep it discoverable.
    svg.addEventListener("dblclick", (event) => {
      if (event.target.closest && event.target.closest("g[data-path], .perk-badge")) return;
      fitCamera();
    });
  }

  // On the window rather than on the SVG: a pan that wanders off the canvas is
  // still a pan, and the drawing under it can be replaced mid-gesture.
  window.addEventListener("pointermove", (event) => {
    if (!panning) return;
    applyCamera({ ...panning.from,
      x: panning.from.x - (event.clientX - panning.x) / panning.scale,
      y: panning.from.y - (event.clientY - panning.y) / panning.scale });
  });
  const endPan = () => {
    if (!panning) return;
    panning = null;
    if (view.chart) view.chart.classList.remove("panning");
  };
  window.addEventListener("pointerup", endPan);
  window.addEventListener("pointercancel", endPan);

  /** The zoom controls, over the canvas rather than in the panel: they act on
   * what is under them, and the panel is already a column of fields. */
  function zoomControls() {
    const wrap = document.createElement("div");
    wrap.className = "web-zoom";
    const button = (glyph, tip, onClick) => {
      const element = document.createElement("button");
      element.type = "button";
      element.textContent = glyph;
      element.title = tip;
      element.onclick = onClick;
      return element;
    };
    const level = document.createElement("span");
    level.className = "web-zoom-level";
    wrap.append(
      button("−", "Zoom out (wheel down over the web)", () => zoomBy(ZOOM_STEP)),
      level,
      button("+", "Zoom in (wheel up over the web)", () => zoomBy(1 / ZOOM_STEP)),
      button("⤢", "Fit the whole web (double-click the background)", fitCamera));
    return wrap;
  }

  /* ------------------------------------------------------------ reparenting */

  /* Dragging one perk onto another moves it there: out of whatever list holds it
   * now, onto the end of the new parent's `children`. Both halves are staged
   * cell edits, so the web re-lays-out under the cursor and Revert undoes the
   * whole move.
   *
   * Pointer events rather than HTML5 drag-and-drop: SVG elements do not answer
   * to the `draggable` attribute, and the panel's chips - which do - are lists,
   * where the drop target is a slot. Here it is a node, found by hit-testing.
   */
  const DRAG_THRESHOLD = 5;   // below this the gesture was a click, not a drag

  let drag = null;
  /* A drag ends with a pointerup over a node, and the browser follows that with
   * a click on whatever is under it. Without this the drop would also re-focus
   * the node that was dropped on. */
  let suppressClick = false;
  const dragSuppressedClick = () => suppressClick;

  /** Swallows the one click a finished drag leaves behind. The timeout is what
   * bounds it: a drag released over empty canvas is followed by no click at all,
   * and a flag left standing would eat the next real one instead. That click
   * arrives in the same task as the pointerup, so a zero timeout lands after
   * it - the same ordering index.html relies on for its deferred redraws. */
  function swallowNextClick() {
    suppressClick = true;
    setTimeout(() => { suppressClick = false; }, 0);
  }

  /** Client coordinates in the SVG's own units, so the ghost line lands under
   * the cursor at any zoom or scroll offset. */
  function toUserSpace(svg, event) {
    const matrix = svg.getScreenCTM();
    if (!matrix) return { x: 0, y: 0 };
    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
    return { x: point.x, y: point.y };
  }

  /** Whether `perk` may hang off `target`, and why not when it may not.
   *
   * Three refusals, each of them something the data cannot express rather than
   * something merely unwise: a perk is a sub-resource of one branch file and
   * cannot be written into another; a node containing one of its own ancestors
   * has no serialisation; and the core's `children` is never walked, so a perk
   * dropped there would vanish from the web rather than become a root. */
  function reparentCheck(perk, target, byId) {
    if (!target || !target.res_path || target.res_path === perk.res_path) return null;
    if (!target.parent_id) {
      return "the core is not a parent - a branch's first perk is authored in its roots";
    }
    if (fileOfPath(target.res_path) !== fileOfPath(perk.res_path)) {
      return `${target.branch_label} is a different branch file - a perk cannot move between them here`;
    }
    for (let walk = target; walk; walk = byId.get(walk.parent_id)) {
      if (walk.id === perk.id) return "that perk already hangs off this one";
    }
    return "";
  }

  /** Moves `perk` out of the list holding it and onto the end of `target`'s
   * children. Two staged writes, one redraw. */
  function reparent(perk, target) {
    const owner = rowIndexOf(perk.order.path);
    const parent = rowIndexOf(target.res_path);
    if (!owner || !parent) return;
    const fromColumn = owner.header.indexOf(perk.order.column);
    const toColumn = parent.header.indexOf("children");
    if (fromColumn <= 0 || toColumn <= 0) return;

    if (owner.file === parent.file && owner.rowIndex === parent.rowIndex
        && fromColumn === toColumn) {
      // Already this parent's child: the only thing left to change is where in
      // the order it sits, which is the same move the chevrons make.
      moveRef({ file: owner.file, rowIndex: owner.rowIndex, columnIndex: fromColumn,
        list: true, partIndex: perk.order.index }, perk.order.count - 1);
    } else {
      const without = dataOf(owner.file).rows[owner.rowIndex][fromColumn]
        .split("|").filter(Boolean);
      without.splice(perk.order.index, 1);
      writeCell(owner.file, owner.rowIndex, fromColumn, without.join("|"));
      // Read after that write, not before: when both rows live in the same table
      // the first edit has already cloned it, and the stale copy would put the
      // removed entry back.
      const raw = dataOf(parent.file).rows[parent.rowIndex][toColumn];
      writeCell(parent.file, parent.rowIndex, toColumn,
        raw ? `${raw}|${perk.res_path}` : perk.res_path);
      renderFileList();
      buildEdges();
    }

    // Focus follows what moved, and not only to show it: the header's Save and
    // Revert act on the file `state.focus` lives in, so a perk dragged without
    // being selected first would stage an edit neither button could reach.
    if (state.focus === perk.res_path) renderActiveView();
    else setFocus(perk.res_path);
    log(`${perk.display_name} now hangs off ${target.display_name} (unsaved)`);
  }

  /** Arms one node for dragging. Nothing is written until the pointer comes up
   * over a legal target; until then this only draws. */
  function enableReparentDrag(group, perk, byId) {
    group.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      const svg = group.ownerSVGElement;
      if (!svg) return;
      drag = { perk, svg, byId, from: { x: event.clientX, y: event.clientY },
        group, ghost: null, target: null, moved: false };
      // Listened for on the window: the pointer leaves this node immediately,
      // and a node that is redrawn mid-gesture would take its listeners with it.
      window.addEventListener("pointermove", onDragMove);
      window.addEventListener("pointerup", onDragUp, { once: true });
    });
  }

  function onDragMove(event) {
    if (!drag) return;
    if (!drag.moved) {
      const far = Math.hypot(event.clientX - drag.from.x, event.clientY - drag.from.y);
      if (far < DRAG_THRESHOLD) return;
      drag.moved = true;
      drag.group.classList.add("dragging");
      drag.ghost = svgEl("line", { class: "drag-ghost",
        x1: drag.perk.world_x, y1: drag.perk.world_y,
        x2: drag.perk.world_x, y2: drag.perk.world_y });
      drag.svg.append(drag.ghost);
    }
    const at = toUserSpace(drag.svg, event);
    drag.ghost.setAttribute("x2", at.x);
    drag.ghost.setAttribute("y2", at.y);

    // The ghost is pointer-events: none, so what is under the cursor is a node.
    const over = document.elementFromPoint(event.clientX, event.clientY);
    const hit = over && over.closest("#web-chart g[data-path]");
    const target = hit ? drag.byId.get(idOfPath(hit.getAttribute("data-path"))) : null;
    const why = target ? reparentCheck(drag.perk, target, drag.byId) : null;

    if (drag.target !== hit) {
      if (drag.target) drag.target.classList.remove("drop-ok", "drop-bad");
      drag.target = hit && why !== null ? hit : null;
      if (drag.target) drag.target.classList.add(why === "" ? "drop-ok" : "drop-bad");
    }
    drag.onto = why === "" ? target : null;
    drag.why = why;
  }

  function onDragUp() {
    window.removeEventListener("pointermove", onDragMove);
    const held = drag;
    drag = null;
    if (!held) return;
    if (held.ghost) held.ghost.remove();
    held.group.classList.remove("dragging");
    if (held.target) held.target.classList.remove("drop-ok", "drop-bad");
    if (!held.moved) return;
    swallowNextClick();
    if (held.onto) reparent(held.perk, held.onto);
    else if (held.why) log(`${held.perk.display_name} cannot go there - ${held.why}`, true);
  }

  const idOfPath = (path) => {
    const row = rowIndexOf(path);
    return row ? cell(row, "id") : "";
  };

  /* --------------------------------------------------------------- badges */

  const BADGE_RADIUS = 8;
  /* Far enough off a 15px node that the badge clears its outline, close enough
   * that it reads as belonging to that node rather than to its neighbour. */
  const BADGE_OFFSET = 24;

  /** One round button hanging off a perk. `spin` turns the glyph so a chevron
   * points along the arc rather than along the screen - on a radial web "left"
   * is only left at the top of the circle. */
  function perkBadge(x, y, glyph, tip, onClick, spin) {
    const badge = svgEl("g", { class: "perk-badge" });
    badge.append(svgEl("circle", { cx: x, cy: y, r: BADGE_RADIUS }));
    const text = svgEl("text", { x, y: y + 3.5 });
    text.setAttribute("text-anchor", "middle");
    if (spin !== undefined) text.setAttribute("transform", `rotate(${spin} ${x} ${y})`);
    text.textContent = glyph;
    badge.append(text);
    attachTip(badge, tip);
    badge.onclick = (event) => {
      // The group under it opens the editor; both firing would fight over focus.
      event.stopPropagation();
      onClick();
    };
    return badge;
  }

  /** The two chevrons that move a perk among its siblings.
   *
   * Placed on the arc the perk would travel along and rotated to point that way,
   * because sibling order *is* the angle: the perk moves towards whichever badge
   * is pressed. Nothing is drawn at the ends of the list - a first child has
   * nowhere earlier to go - so the pair says how much room is left as well.
   */
  function orderBadges(perk) {
    const group = svgEl("g");
    if (!perk.order || perk.order.count < 2) return group;
    // Tangent of the circle the perk sits on, pointing the way the index grows.
    const tx = -Math.sin(perk.angle);
    const ty = Math.cos(perk.angle);
    const spin = (perk.angle * 180) / Math.PI + 90;
    const siblings = perk.order.count;

    for (const step of [-1, 1]) {
      const to = perk.order.index + step;
      if (to < 0 || to >= siblings) continue;
      group.append(perkBadge(
        perk.world_x + tx * BADGE_OFFSET * step,
        perk.world_y + ty * BADGE_OFFSET * step,
        step < 0 ? "‹" : "›",
        `Move ${perk.display_name} to place ${to + 1} of ${siblings} among its siblings`,
        () => moveInOrder(perk, to),
        spin));
    }
    return group;
  }

  /** Rewrites the owning cell so this perk sits at `to`. The same moveRef the
   * panel's chips drag through, handed the position the arc names. */
  function moveInOrder(perk, to) {
    const owner = rowIndexOf(perk.order.path);
    if (!owner) return;
    const columnIndex = owner.header.indexOf(perk.order.column);
    if (columnIndex <= 0) return;
    moveRef({ file: owner.file, rowIndex: owner.rowIndex, columnIndex,
      list: true, partIndex: perk.order.index }, to);
  }

  /** The ⊕ that hangs a new perk off the one being edited.
   *
   * The id is asked for rather than derived: it is the runtime key AND the save
   * key, so a generated one would have to be renamed straight away, and renaming
   * a perk orphans whatever level players had banked against the old name. */
  function addChildBadge(perk) {
    return perkBadge(perk.world_x + 17, perk.world_y - 17, "+",
      "Add a perk under this one", () => {
        const row = rowIndexOf(perk.res_path);
        const rule = pathRefFor("PerkNodeDef", "children");
        if (!row || !rule) return;
        const id = prompt(`New perk under ${perk.display_name}.\n\n`
          + "Its id is the runtime key and the save key, so pick the one it keeps.", "");
        if (id === null || !id.trim()) return;
        // createChild does the rest: POST /api/create, re-read every table,
        // focus the new node. It refuses while anything is unsaved, since
        // creating re-reads the tables and would throw staged edits away.
        createChild(row, "children", rule, id.trim(), "");
      });
  }

  /* ------------------------------------------------------------- highlighting */

  /** Every effect stat any perk carries, for the picker. Read off the report
   * rather than listed here: whichever stat a branch is retuned onto next is
   * offered without this screen being told about it. */
  function statVocabulary() {
    const counts = new Map();
    for (const perk of view.report.perks) {
      const stat = perk.stat || NO_EFFECT;
      counts.set(stat, (counts.get(stat) || 0) + 1);
    }
    return [...counts].sort((a, b) => (a[0] === NO_EFFECT ? 1 : b[0] === NO_EFFECT ? -1
      : a[0].localeCompare(b[0])));
  }

  /** The controls that pick out part of the web.
   *
   * They redraw the canvas alone rather than going through view.render: the
   * panel rebuilds its children on every render, and a text box that is replaced
   * between keystrokes loses the caret on each one.
   */
  function filterBar() {
    const wrap = document.createElement("div");
    wrap.className = "web-filter";

    const head = document.createElement("div");
    head.className = "web-filter-head";
    const title = document.createElement("span");
    title.textContent = "Highlight";
    const count = document.createElement("span");
    count.className = "web-filter-count";
    head.append(title, count);

    // The whole point of asking "which ones": the set the filter names is the
    // set the bulk panel edits, so it is one press from lit to picked.
    const take = document.createElement("button");
    take.type = "button";
    take.className = "web-filter-take";
    take.textContent = "Select these";
    take.title = "Put every highlighted perk under bulk edit";
    take.onclick = () => {
      for (const perk of view.drawn.values()) {
        if (matchesFilter(perk)) view.picked.add(perk.res_path);
      }
      view.render();
    };
    head.append(take);

    const clear = document.createElement("button");
    clear.type = "button";
    clear.className = "revert";
    clear.textContent = "↺";
    clear.title = "Show every perk again";
    head.append(clear);
    wrap.append(head);

    const apply = () => {
      const where = canvasOf();
      if (!where) return;
      // drawWeb rebuilds the svg, and the camera it puts on the new one is the
      // one the old one was left at - so the window does not move.
      where.replaceChildren(drawWeb());
      sync();
    };

    const text = document.createElement("input");
    text.type = "search";
    text.placeholder = "name or id";
    text.value = view.filter.text;
    text.oninput = () => { view.filter.text = text.value.trim(); apply(); };

    const stat = document.createElement("select");
    stat.append(new Option("any effect", ""));
    for (const [name, howMany] of statVocabulary()) {
      stat.append(new Option(
        `${name === NO_EFFECT ? "no effect" : name} · ${howMany}`, name));
    }
    stat.value = view.filter.stat;
    stat.onchange = () => { view.filter.stat = stat.value; apply(); };

    const branch = document.createElement("select");
    branch.append(new Option("any branch", ""));
    for (const entry of view.report.branches) {
      // The core is its own rollup with an empty key, and is not an arm anyone
      // retunes as a unit.
      if (!entry.branch_key) continue;
      branch.append(new Option(
        `${entry.branch_label || entry.branch_key} · ${entry.perk_count}`, entry.branch_key));
    }
    branch.value = view.filter.branch;
    branch.onchange = () => { view.filter.branch = branch.value; apply(); };

    const range = document.createElement("div");
    range.className = "web-filter-range";
    const bound = (part, tip, step = "0.5") => {
      const box = document.createElement("input");
      box.type = "number";
      box.step = step;
      box.placeholder = "any";
      box.title = tip;
      box.value = view.filter[part] === null ? "" : String(view.filter[part]);
      box.oninput = () => {
        const parsed = Number(box.value);
        view.filter[part] = box.value.trim() === "" || !Number.isFinite(parsed)
          ? null : parsed;
        apply();
      };
      return box;
    };
    // Exponents, not values: this is the space the colouring and the legend
    // already work in, and 1e6 is a number the panel has room for.
    range.append(Object.assign(document.createElement("i"), { textContent: "1e" }),
      bound("from", `Lowest ${scaleOf().label.toLowerCase()} to highlight, as a power of ten`),
      Object.assign(document.createElement("i"), { textContent: "– 1e" }),
      bound("to", `Highest ${scaleOf().label.toLowerCase()} to highlight, as a power of ten`));

    // Depth is how far down an arm a perk sits, which is the axis a branch is
    // usually retuned along - the outer half is dear and the inner half is not.
    const depth = document.createElement("div");
    depth.className = "web-filter-range";
    depth.append(Object.assign(document.createElement("i"), { textContent: "depth" }),
      bound("depthFrom", "Shallowest depth to highlight", "1"),
      Object.assign(document.createElement("i"), { textContent: "–" }),
      bound("depthTo", "Deepest depth to highlight", "1"));

    wrap.append(text, stat, branch, range, depth);

    clear.onclick = () => {
      view.filter = { text: "", stat: "", branch: "", from: null, to: null,
        depthFrom: null, depthTo: null };
      text.value = "";
      stat.value = "";
      branch.value = "";
      for (const box of wrap.querySelectorAll(".web-filter-range input")) box.value = "";
      apply();
    };

    function sync() {
      const on = filterActive();
      clear.hidden = !on;
      // view.matched is counted by drawWeb, which apply() has just re-run.
      take.hidden = !on || !view.matched;
      take.textContent = `Select these ${view.matched || 0}`;
      count.textContent = on
        ? `${view.matched} of ${view.report.perks.length}`
        : `${scaleOf().label.toLowerCase()}, or a name`;
      wrap.classList.toggle("on", on);
    }
    sync();
    return wrap;
  }

  /* ------------------------------------------------------------------ payout */

  /** The row pricing the prestige payout, or null before its table is loaded. */
  const payoutRow = () => rowsOf(PAYOUT_FILE)[0] || null;

  /** What a run is worth, which is the other half of this screen: the web says
   * what biomass buys, and this says where the biomass comes from.
   *
   * Two ladders of storage areas - one filled by the nutrients a run produced,
   * one by the ticks it survived - each area a fixed factor more than the one
   * below it, and the payout an exponential of the two counts summed. Every
   * number here is an @export on PrestigeCurveDef, so all of it is editable
   * rather than described.
   */
  function payoutSection(open) {
    const entry = payoutRow();
    const wrap = document.createElement("details");
    wrap.className = "web-payout";
    wrap.open = open;
    const summary = document.createElement("summary");
    summary.textContent = "Run payout - storage areas";
    wrap.append(summary);

    if (!entry) {
      const missing = document.createElement("p");
      missing.className = "hint";
      missing.textContent = `No ${PAYOUT_FILE} row loaded.`;
      wrap.append(missing);
      return wrap;
    }

    const note = document.createElement("div");
    note.className = "hint";
    note.textContent = "A run fills whole areas on both ladders; area k above a "
      + "ladder's base costs base x growth ^ (k x growth exponent ^ k), and every "
      + "filled area pays a step of its own, all of them summed: payout base x "
      + "(payout growth ^ areas - 1) / (payout growth - 1).";
    wrap.append(note);

    const nutrients = fieldGroup("Nutrient storage", entry,
      ["nutrient_growth", "nutrient_growth_exponent"]);
    nutrients.prepend(bigField(entry, "First area at", "_nutrient_base"));
    const ticks = fieldGroup("Time storage", entry,
      ["tick_growth", "tick_growth_exponent"]);
    ticks.prepend(bigField(entry, "First area at", "_tick_base"));
    const payout = fieldGroup("Payout", entry, ["payout_growth", "max_areas"]);
    payout.prepend(bigField(entry, "One area pays", "_payout_base"));
    wrap.append(nutrients, ticks, payout, ladderChart(entry), payoutChart(entry));
    return wrap;
  }

  /** growthCurve() over area indices. The ladder is
   * `base * growth^(k * growth_exponent^k)` at k areas above the base, which is
   * the shared curve shifted one place: area 1 is the base itself, so the
   * sampled window starts one below where it is drawn. `exponentColumn` is left
   * out by the payout curve, which reuses this shape but carries no exponent. */
  const ladderCurve = (entry, prefix, growthColumn, from, to, exponentColumn) => growthCurve(
    bigLog10(numberCell(entry, `${prefix}_mantissa`, 0),
      numberCell(entry, `${prefix}_exponent`, 0)),
    numberCell(entry, growthColumn, 10),
    exponentColumn ? Math.max(numberCell(entry, exponentColumn, 1), 1) : 1,
    Math.max(from - 1, 0), to - 1);

  /** What each area on either ladder costs the run, area by area. */
  function ladderChart(entry) {
    const build = (from, to) => {
      const start = Math.max(from, 1);
      const pad = new Array(start - from).fill(null);
      const series = [
        { label: "run nutrients", color: "var(--accent)",
          points: pad.concat(ladderCurve(entry, "_nutrient_base", "nutrient_growth", start, to,
            "nutrient_growth_exponent")) },
        { label: "ticks survived", color: hueOf(3),
          points: pad.concat(ladderCurve(entry, "_tick_base", "tick_growth", start, to,
            "tick_growth_exponent")) },
      ];
      const sampled = engineCurve(entry.row[0]);
      const nutrientDots = engineSeries(entry, sampled && sampled.nutrient_threshold,
        from, to, log10Of);
      const tickDots = engineSeries(entry, sampled && sampled.tick_threshold, from, to, log10Of);
      if (nutrientDots) series.push(nutrientDots);
      if (tickDots) series.push(tickDots);
      return series;
    };
    return chartBlock("What an area costs", build, {
      space: "log10", xLabel: "area", width: 320, height: 200,
      range: { key: "prestige-area", from: 0, to: 20, label: "area" },
      scaleKey: "prestige-ladder",
    });
  }

  /** Biomass a run standing on N total areas converts into, before the
   * &"biomass_gain" stacks the perks themselves add: one step per filled area,
   * all of them summed.
   *
   * Sampled from area 1 whatever the window starts at - the total at area N
   * carries every step below it, including the ones off the left of the chart -
   * and accumulated with logSumExp, because a late run's steps run past what a
   * double holds long before the ladder runs out of areas. */
  function payoutChart(entry) {
    const build = (from, to) => {
      const start = Math.max(from, 1);
      const pad = new Array(start - from).fill(null);
      const steps = ladderCurve(entry, "_payout_base", "payout_growth", 1, to);
      const totals = [];
      let running = null;
      steps.forEach((step, index) => {
        running = logSumExp([running, step]);
        if (index + 1 >= start) totals.push(running);
      });
      const series = [{
        label: "biomass at N areas", color: "var(--accent)",
        points: pad.concat(totals),
      }];
      const sampled = engineCurve(entry.row[0]);
      const dots = engineSeries(entry, sampled && sampled.payout, from, to, log10Of);
      if (dots) series.push(dots);
      return series;
    };
    return chartBlock("What a run pays", build, {
      space: "log10", xLabel: "areas filled, both ladders", width: 320, height: 200,
      range: { key: "prestige-area", from: 0, to: 20, label: "area" },
      // Its own scale key though it shares the range: the two charts are read
      // against the same x axis but answer different questions on y.
      scaleKey: "prestige-payout",
    });
  }

  /* -------------------------------------------------------------------- panel */

  function renderPanel(panel) {
    panel.replaceChildren();

    const scales = document.createElement("div");
    scales.className = "web-modes";
    for (const [key, scale] of Object.entries(SCALES)) {
      const button = document.createElement("button");
      button.textContent = scale.label;
      button.title = scale.note;
      button.className = key === view.scale ? "active" : "";
      button.onclick = () => { view.scale = key; view.render(); };
      scales.append(button);
    }
    panel.append(scales);

    const note = document.createElement("div");
    note.className = "hint";
    note.textContent = SCALES[view.scale].note;
    panel.append(note);

    panel.append(filterBar());

    // PerkTree skips a repeated id and everything under it. Silently, in the
    // engine - here it is the difference between a subtree that is missing and
    // one that was never authored, so it is said out loud.
    for (const warning of view.warnings) {
      const warn = document.createElement("p");
      warn.className = "hint warn";
      warn.textContent = warning;
      panel.append(warn);
    }

    // Folded away while a perk is being edited - the payout is what the whole
    // web is priced against, but the panel is 340px and the perk's own fields
    // are what a click asked for.
    const focused = focusedRow();
    panel.append(payoutSection(!focused && !view.picked.size));

    const editor = document.createElement("div");
    editor.className = "web-editor";
    panel.append(editor);
    // A picked set outranks the focus: the focus is only still set because
    // something had to be clicked to start picking.
    if (view.picked.size) {
      renderBulk(editor);
    } else if (focused) {
      renderEditor(editor);
    } else {
      panel.append(branchTable());
      panel.append(deepestTable());
    }
  }

  const selectedPerk = () =>
    view.report.perks.find((perk) => perk.res_path && perk.res_path === state.focus);

  /** Whatever is being edited. Usually the perk that was clicked, but following
   * one of its reference chips lands on an effect or a child, and editing those
   * is the point of following the chip - so the panel goes wherever the focus
   * goes rather than snapping back to the branch totals. */
  const focusedRow = () => (state.focus ? rowIndexOf(state.focus) : null);

  /** The picked perk's own fields, edited here rather than somewhere else.
   *
   * The editor itself is the graph view's - the same renderDeps that builds a
   * control per property and a chip per reference, pointed at this panel instead
   * of its own. Duplicating it here would mean two editors to keep honest. */
  function renderEditor(target) {
    const perk = selectedPerk();
    const row = focusedRow();

    const heading = document.createElement("div");
    heading.className = "web-editor-head";
    const back = document.createElement("button");
    back.textContent = "← All branches";
    back.title = "Stop editing and show the branch totals again";
    back.onclick = () => { setFocus(null); };
    heading.append(back);

    // Shape is mirrored here, so a reorder moves the web at once; the colouring
    // is PerkTree run over what is on disk, and that still waits for a save.
    if (fileHasChanges(row.file)) {
      const dirty = document.createElement("span");
      dirty.className = "hint";
      dirty.textContent = "unsaved - positions preview live, costs recolour after Save";
      heading.append(dirty);
    } else {
      const reload = document.createElement("button");
      reload.textContent = "Recompute";
      reload.title = "Re-read the web from disk";
      reload.onclick = async () => {
        try {
          // ?fresh=1 rather than the plain path: the server caches this report
          // until the data is written, and what this button is pressed after is
          // usually a layout constant moving in PerkTree, which no write touches.
          view.report = await api("/api/perks?fresh=1");
          view.render();
        } catch (error) { log(String(error), true); }
      };
      heading.append(reload);
    }
    target.append(heading);

    const gates = perkIdReferences(row);
    if (gates.length) {
      // /api/delete only follows res:// references, and these are StringNames -
      // so its preview neither reports nor unlinks them. Deleting reach_5 leaves
      // node tier 4 gated on a perk no branch authors, which is a gate that can
      // never open, and fails authored_data_test.
      const warn = document.createElement("p");
      warn.className = "hint warn";
      warn.textContent = `${gates.length} other resource(s) name this perk by id: `
        + `${gates.join(", ")}. Deleting or renaming it leaves those gated on a perk `
        + "nothing authors - and the id is the save key, so players lose the levels "
        + "they banked against it.";
      target.append(warn);
    }

    // Only a perk has costs to report; a followed chip is some other resource.
    if (perk) {
      const costs = document.createElement("div");
      costs.className = "web-stats";
      costs.textContent = `${format(perk.cost_to_max)} to max · ${format(perk.path_cost)} to reach `
        + `· depth ${perk.depth} · ${perk.branch_label}`;
      target.append(costs);

      // What a reorder actually costs the branch. Sibling offsets accumulate
      // down a chain, and the widest one is what caps the spacing every node in
      // the branch gets; past the limit the branch spills out of its slice, which
      // is where perk_tree_test stops it. Reach alternates its two children side
      // to side for exactly this reason.
      const reach = view.widest.get(perk.branch_key);
      const limit = view.spreadLimit;
      if (reach !== undefined && limit) {
        const spread = document.createElement("div");
        const tight = reach > limit;
        spread.className = tight ? "web-stats warn" : "web-stats";
        spread.textContent = `widest sibling offset ${reach.toFixed(2)} of ${limit.toFixed(2)}`
          + (tight ? " - this branch is past its slice, so its spread is cut to fit" : "");
        target.append(spread);
      }
    }


    // Effects first, before the perk's own fields. What a perk *does* lives on
    // an UpgradeEffectDef one hop away - and on most perks that def belongs to
    // the branch, so the node's own `effects` list is empty and there is no chip
    // to follow. Put below the deps panel it also landed off the bottom of the
    // panel, behind a description box and two lists of references.
    //
    // A report cached by a server started before effect_paths existed has none;
    // the perk's own fields still edit fine, so degrade rather than throw.
    for (const path of (perk ? perk.effect_paths : null) || []) {
      // One bad effect row must not take the rest of the panel down with it -
      // a silent throw here is indistinguishable from "the feature is missing".
      try {
        target.append(effectEditor(perk, path));
      } catch (error) {
        log(`could not build the editor for ${path}: ${error}`, true);
      }
    }
    if (perk && !perk.effect_paths) {
      const stale = document.createElement("div");
      stale.className = "hint";
      stale.textContent = "Effects are not in this web report - press \"Reload from .tres\" "
        + "(or restart server.py) to pick them up.";
      target.append(stale);
    }

    const fields = document.createElement("div");
    fields.className = "deps-panel";   // the styling the graph's own panel carries
    target.append(fields);
    renderDeps(row.row[0], fields);
  }

  /* ---------------------------------------------------------------- bulk edit */

  /* Retuning a set instead of a perk.
   *
   * Every write here goes through writeCell, the one place a value changes, so a
   * bulk apply is staged exactly like a typed one: the web re-lays-out under it,
   * Revert undoes it, and Save sends the lot as a single patch - snapshot()
   * groups rows by class rather than by file, so every perk in all eight branch
   * files is one table and one request.
   */

  /** The perk fields worth moving as a set.
   *
   * `big` marks the ones stored as a mantissa/exponent pair. Those are read and
   * written in log10 throughout: a base cost passes 1e150, and multiplying the
   * mantissa either overflows the double or leaves a mantissa of 1000. An offset
   * on one of them adds decades, which is the only offset meaning anything at
   * that size. */
  const BULK_FIELDS = [
    { key: "base_cost", label: "Base cost", big: "_base_cost", log: true,
      addLabel: "+ decades", hint: "1e50" },
    { key: "max_level", label: "Max level", column: "max_level", integer: true, min: 1 },
    { key: "cost_growth", label: "Cost growth", column: "cost_growth", min: 0.000001 },
    { key: "cost_growth_exponent", label: "Growth exponent", column: "cost_growth_exponent",
      min: 0.000001 },
  ];

  const EFFECT_FIELDS = [
    { key: "per_level", label: "Per level", column: "per_level" },
    { key: "max_magnitude", label: "Max magnitude", column: "max_magnitude" },
  ];

  /* Both lists by key, so the solve can name a field without repeating its shape. */
  const BULK_FIELD_BY_KEY = Object.fromEntries(
    [...BULK_FIELDS, ...EFFECT_FIELDS].map((field) => [field.key, field]));

  /* The two tables a bulk apply can stage into. Two of them means Save all
   * rather than Save, which is worth saying before the perks are saved and the
   * effects are not. */
  const BULK_TABLES = ["PerkNodeDef", "UpgradeEffectDef"];

  const columnIndexOf = (row, column) => {
    const index = row.header.indexOf(column);
    return index > 0 ? index : -1;   // 0 is res_path, which is never written
  };

  const nameOf = (path) => {
    const perk = view.drawn.get(path);
    return (perk && perk.display_name) || labelOf(path);
  };

  /** What one field is worth on one row right now, in the unit its ops compose
   * in: log10 for a big pair, the plain number otherwise. Read off the staged
   * rows, not the pristine ones, so two applies compose. */
  function readField(path, field) {
    const row = rowIndexOf(path);
    if (!row) return null;
    if (field.big) {
      return bigLog10(numberCell(row, `${field.big}_mantissa`, 0),
        numberCell(row, `${field.big}_exponent`, 0));
    }
    const index = columnIndexOf(row, field.column);
    if (index === -1) return null;
    const value = Number(row.row[index]);
    return Number.isFinite(value) ? value : null;
  }

  /** Writes one field back, and answers which table it landed in. */
  function writeField(path, field, value) {
    const row = rowIndexOf(path);
    if (!row) return null;
    if (field.big) {
      const mantissa = columnIndexOf(row, `${field.big}_mantissa`);
      const exponent = columnIndexOf(row, `${field.big}_exponent`);
      if (mantissa === -1 || exponent === -1) return null;
      const pair = fromLog10(value);
      writeCell(row.file, row.rowIndex, mantissa, String(pair[0]));
      writeCell(row.file, row.rowIndex, exponent, String(pair[1]));
      return row.file;
    }
    const index = columnIndexOf(row, field.column);
    if (index === -1) return null;
    writeCell(row.file, row.rowIndex, index, String(value));
    return row.file;
  }

  const lerp = (from, to, t) => from + (to - from) * t;

  /** What a field becomes on one row. `t` is where that row sits in the picked
   * order, 0 at the first and 1 at the last; only a ramp reads it.
   *
   * A big field's boxes still take the number the way it is written - 1e50, ×10
   * - and the conversion into log10 happens here rather than asking anyone to
   * type exponents. */
  function nextValue(field, current, op, a, b, t) {
    if (field.log) {
      if (op === "set") return Math.log10(a);
      if (op === "mul") return current + Math.log10(a);
      if (op === "add") return current + a;   // decades: +2 is a hundredfold
      // Always geometric. A linear ramp from 1e50 to 1e200 leaves every perk but
      // the last sitting at 1e200, and those numbers do not fit a double anyway.
      return lerp(Math.log10(a), Math.log10(b), t);
    }
    if (op === "set") return a;
    if (op === "mul") return current * a;
    if (op === "add") return current + a;
    return view.rampMode === "geometric" && a > 0 && b > 0
      ? 10 ** lerp(Math.log10(a), Math.log10(b), t)
      : lerp(a, b, t);
  }

  function clamped(field, value) {
    if (!Number.isFinite(value)) return null;
    let out = value;
    if (field.integer) out = Math.round(out);
    if (field.min !== undefined) out = Math.max(field.min, out);
    return out;
  }

  /** The picked perks in the order a ramp runs along: down the arms, and around
   * the web within one depth, which is the order they are read in. A ramp over
   * two branches at once interleaves them, so it is one branch at a time that
   * this is for. */
  function orderedPicked() {
    return pickedPaths()
      .map((path) => ({ path, perk: view.drawn.get(path) }))
      .sort((left, right) => {
        if (!left.perk || !right.perk) return 0;
        return (left.perk.depth - right.perk.depth)
          || ((left.perk.angle || 0) - (right.perk.angle || 0));
      });
  }

  /** Every row an op would touch, with what it holds and what it would become.
   * The same list backs the preview and the apply, so what is shown is what is
   * written. */
  function planPerks(field, op, a, b) {
    const ordered = orderedPicked();
    const rows = [];
    ordered.forEach((entry, index) => {
      const current = readField(entry.path, field);
      if (current === null) return;
      const t = ordered.length > 1 ? index / (ordered.length - 1) : 0;
      const raw = nextValue(field, current, op, a, b, t);
      const next = field.log ? (Number.isFinite(raw) ? raw : null) : clamped(field, raw);
      if (next === null) return;
      rows.push({ path: entry.path, name: nameOf(entry.path), current, next });
    });
    return rows;
  }

  /** The effect defs the picked perks point at, deduped by path.
   *
   * Deduped because most perks do not own their effect: an empty `effects` list
   * inherits the branch's `default_effects`, one resource shared by the whole
   * arm. A ×1.2 applied once per perk that points at it would be ×1.2 to the
   * power of however many were picked. */
  function pickedEffects() {
    const used = new Map();
    for (const perk of view.report.perks) {
      for (const path of perk.effect_paths || []) {
        if (!used.has(path)) used.set(path, { path, picked: 0, total: 0, others: [] });
        const entry = used.get(path);
        entry.total += 1;
        if (perk.res_path && view.picked.has(perk.res_path)) entry.picked += 1;
        else entry.others.push(perk.display_name);
      }
    }
    return [...used.values()].filter((entry) => entry.picked > 0);
  }

  function planEffects(field, op, a, b) {
    const rows = [];
    for (const entry of pickedEffects()) {
      const current = readField(entry.path, field);
      if (current === null) continue;
      const next = clamped(field, nextValue(field, current, op, a, b, 0));
      if (next === null) continue;
      rows.push({ path: entry.path, name: labelOf(entry.path), current, next });
    }
    return rows;
  }

  /** A value the way this field is read: a big one through the same formatter
   * the mantissa/exponent boxes echo with, so the preview and the field agree. */
  function showValue(field, value) {
    if (field.log) {
      const pair = fromLog10(value);
      return formatBig(pair[0], pair[1]);
    }
    if (!Number.isFinite(value)) return "-";
    return Math.abs(value) >= 100000 ? value.toExponential(2)
      : String(Number(value.toPrecision(6)));
  }

  const bulkBox = (placeholder) => {
    const box = document.createElement("input");
    box.type = "number";
    box.step = "any";
    box.placeholder = placeholder;
    return box;
  };

  /** One field's controls: the op, its one or two values, and what the picked
   * rows would become. Nothing is staged until Apply - a bulk write is not a
   * gesture to discover by watching the numbers move. */
  function bulkRow(field, target) {
    const wrap = document.createElement("div");
    wrap.className = "bulk-row";

    const head = document.createElement("label");
    head.textContent = field.label;
    wrap.append(head);

    const controls = document.createElement("div");
    controls.className = "bulk-controls";

    const op = document.createElement("select");
    const ops = [["set", "="], ["mul", "×"], ["add", field.addLabel || "+"]];
    if (target.ramp) ops.push(["ramp", "ramp"]);
    for (const [value, label] of ops) op.append(new Option(label, value));

    const first = bulkBox(field.hint || "value");
    const second = bulkBox("to");
    const apply = document.createElement("button");
    apply.type = "button";
    apply.textContent = "Apply";
    controls.append(op, first, second, apply);
    wrap.append(controls);

    // Only offered where a ramp is: a big field ramps geometrically or not at
    // all, and the effects have no per-perk position to ramp along.
    const shape = document.createElement("select");
    shape.className = "bulk-shape";
    shape.append(new Option("geometric", "geometric"), new Option("linear", "linear"));
    shape.value = view.rampMode;
    shape.title = "How the values between the two ends are spaced";
    shape.onchange = () => { view.rampMode = shape.value; refresh(); };
    if (target.ramp && !field.log) wrap.append(shape);

    const preview = document.createElement("div");
    preview.className = "bulk-preview";
    wrap.append(preview);

    /** The numbers as typed, or null when this op cannot be run with them. A
     * log field cannot be set to or scaled by a number that has no logarithm. */
    function args() {
      const a = first.value.trim() === "" ? NaN : Number(first.value);
      const b = second.value.trim() === "" ? NaN : Number(second.value);
      if (!Number.isFinite(a)) return null;
      if (op.value === "ramp" && !Number.isFinite(b)) return null;
      if (field.log && op.value !== "add") {
        if (a <= 0) return null;
        if (op.value === "ramp" && b <= 0) return null;
      }
      return [a, b];
    }

    function refresh() {
      second.hidden = op.value !== "ramp";
      shape.hidden = op.value !== "ramp";
      const pair = args();
      const rows = pair ? target.plan(op.value, pair[0], pair[1]) : [];
      const allowed = !target.allow || target.allow();
      apply.disabled = !rows.length || !allowed;
      if (!rows.length) {
        preview.textContent = pair ? "nothing this field applies to" : "";
        return;
      }
      const shown = rows.slice(0, 5)
        .map((row) => `${row.name}  ${showValue(field, row.current)} → ${showValue(field, row.next)}`);
      if (rows.length > shown.length) shown.push(`… and ${rows.length - shown.length} more`);
      preview.textContent = shown.join("\n");
    }

    op.onchange = refresh;
    first.oninput = refresh;
    second.oninput = refresh;
    target.watch(refresh);

    apply.onclick = () => {
      const pair = args();
      if (!pair) return;
      const rows = target.plan(op.value, pair[0], pair[1]);
      if (!rows.length || (target.allow && !target.allow())) return;
      const files = new Set();
      for (const row of rows) {
        const file = writeField(row.path, field, row.next);
        if (file) files.add(file);
      }
      finishBulk(files, `${field.label}: ${rows.length} row(s) staged`);
    };

    refresh();
    return wrap;
  }

  /** What every bulk apply ends with.
   *
   * The sidebar has to move with it: the header's Save and Revert act on the
   * file `state.current` names, so a set written while the sidebar pointed
   * elsewhere would stage edits neither button could reach - the same reason
   * reparent re-focuses whatever it moved. */
  function finishBulk(files, message) {
    const [first] = files;
    if (first && state.current !== first) state.current = first;
    renderFileList();
    view.render();
    log(message);
  }

  /** One removable chip per picked perk, so a set gathered by four gestures can
   * be corrected without starting it again. */
  function pickedChips() {
    const wrap = document.createElement("div");
    wrap.className = "bulk-chips";
    const paths = orderedPicked();
    for (const entry of paths.slice(0, 40)) {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "bulk-chip";
      chip.textContent = `${nameOf(entry.path)} ✕`;
      chip.title = "Drop this one from the set";
      chip.onclick = () => togglePicked(entry.path);
      wrap.append(chip);
    }
    if (paths.length > 40) {
      const more = document.createElement("span");
      more.className = "hint";
      more.textContent = `and ${paths.length - 40} more`;
      wrap.append(more);
    }
    return wrap;
  }

  /** The effect half of the panel, and the one place a bulk edit can reach
   * further than it was pointed: a shared def belongs to perks nobody picked. */
  function effectSection() {
    // The rows built below, so ticking the shared-effect box re-enables their
    // Apply buttons without rebuilding the panel under the cursor.
    const watchers = [];
    const wrap = document.createElement("div");
    wrap.className = "deps-panel web-effect";
    const title = document.createElement("h3");
    title.textContent = "Effects";
    wrap.append(title);

    const effects = pickedEffects();
    if (!effects.length) {
      const none = document.createElement("p");
      none.className = "hint";
      none.textContent = "No effect in this report belongs to the picked perks.";
      wrap.append(none);
      return wrap;
    }

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = `${effects.length} effect def(s) behind ${view.picked.size} perks. `
      + "Each is changed once, however many perks point at it.";
    wrap.append(note);

    const spill = effects.filter((entry) => entry.total > entry.picked);
    const gate = { open: spill.length === 0 };
    if (spill.length) {
      const warn = document.createElement("p");
      warn.className = "hint warn";
      const others = [...new Set(spill.flatMap((entry) => entry.others))];
      warn.textContent = `${spill.length} of these is shared with `
        + `${others.length} perk(s) that were not picked: `
        + `${others.slice(0, 6).join(", ")}${others.length > 6 ? ", …" : ""}. `
        + "Changing it changes those too.";
      wrap.append(warn);

      const label = document.createElement("label");
      label.className = "bulk-gate";
      const box = document.createElement("input");
      box.type = "checkbox";
      box.onchange = () => { gate.open = box.checked; for (const fn of watchers) fn(); };
      label.append(box, document.createTextNode(" change the shared effects anyway"));
      wrap.append(label);
    }

    for (const field of EFFECT_FIELDS) {
      wrap.append(bulkRow(field, {
        ramp: false,
        allow: () => gate.open,
        plan: (op, a, b) => planEffects(field, op, a, b),
        watch: (fn) => watchers.push(fn),
      }));
    }
    return wrap;
  }

  /** Puts every picked row - and the effect defs behind them - back the way the
   * file has them. writeCell drops a file from state.edits the moment nothing in
   * it differs, so reverting the last set reverts the file. */
  function revertPicked() {
    const files = new Set();
    const paths = [...pickedPaths(), ...pickedEffects().map((entry) => entry.path)];
    for (const path of paths) {
      const row = rowIndexOf(path);
      if (!row) continue;
      const pristine = state.loaded.get(row.file).rows[row.rowIndex];
      pristine.forEach((value, index) => {
        if (index > 0) writeCell(row.file, row.rowIndex, index, value);
      });
      files.add(row.file);
    }
    finishBulk(files, `reverted ${paths.length} row(s)`);
  }

  function bulkFooter() {
    const wrap = document.createElement("div");
    const dirty = BULK_TABLES.filter((file) => state.loaded.has(file) && fileHasChanges(file));

    const line = document.createElement("p");
    line.className = dirty.length ? "hint warn" : "hint";
    line.textContent = dirty.length
      ? `unsaved in ${dirty.join(" and ")}`
        + (dirty.length > 1 ? " - two tables, so save with Ctrl+Shift+S (Save all). " : ". ")
        + "Costs recolour after Save, and adding or deleting a perk is refused until then."
      : "Nothing staged yet. Positions preview live; costs recolour after Save.";
    wrap.append(line);

    const revert = document.createElement("button");
    revert.type = "button";
    revert.textContent = "Revert these";
    revert.title = "Put the picked perks and their effects back to what the files hold";
    revert.disabled = !dirty.length;
    revert.onclick = revertPicked;
    wrap.append(revert);
    return wrap;
  }

  /* ------------------------------------------------------------ auto-balance */

  /* Working out what the numbers should be, rather than moving them by hand.
   *
   * The whole solve is closed form, which is why there is no search loop here.
   * The engine prices a level as `base * g^(l * ge^l)` and maxing costs the sum
   * of those over l = 0..L-1, so:
   *
   *   cost_to_max = base * S(g, ge, L)      <- linear in base
   *   last/first  = g^((L-1) * ge^(L-1))    <- the climb across its own levels
   *
   * Name what reaching depth d should cost and how far a perk climbs, and both
   * knobs fall out by inversion: g from the climb, then base from the budget.
   * Nothing is iterated and nothing is simulated - the sim comes afterwards, to
   * say what the pacing became, and is never in this loop.
   */

  /* Two curves across depth, both in log10: what a perk's first level should
   * cost at that depth, and what its last should. Each is the shape the game
   * itself prices with - `start * 10^(ratio * (d-1) * accel^(d-1))` - so a
   * branch can widen as it deepens rather than only sliding up.
   *
   * Those two points are what a perk is solved from. `cost(l) = base * g^(l *
   * ge^l)` is exactly `base` at level 0, so the first curve *is* base_cost; the
   * last curve then fixes how far the perk has to climb over its levels. That is
   * one equation and two growth fields, so cost_growth_exponent is left as
   * authored and cost_growth is the one that moves - the perk keeps whatever
   * curvature it was given, and only its steepness is retuned. */
  const AUTO = {
    anchor: "",
    // Each curve's start is typed as a mantissa and an exponent, the same split
    // the .tres stores a base cost in, so 2.5e3 is two boxes rather than a
    // logarithm worked out by hand. `first0`/`last0` are what everything else
    // reads, recomputed from the pair whenever either half moves.
    firstMantissa: null, firstExponent: null, first0: null,
    firstRatio: null, firstAccel: 1,
    lastMantissa: null, lastExponent: null, last0: null,
    lastRatio: null, lastAccel: 1,
    levels: "keep",    // keep | set
    levelValue: 100,
    holdEffect: true,  // per_level follows max_level, so effect_at_max is held
  };

  /** Least squares over one branch, in the space the costs live in: where the
   * curve starts and how many decades each depth adds. `valueOf` picks which
   * cost is being fitted - a perk's first level or its last. */
  function fitCurve(perks, valueOf) {
    const points = perks
      .map((perk) => ({ x: perk.depth - 1, y: log10Of(valueOf(perk)) }))
      .filter((point) => point.x >= 0 && point.y !== null && Number.isFinite(point.y));
    if (points.length < 2) return null;
    const n = points.length;
    const sx = points.reduce((sum, p) => sum + p.x, 0);
    const sy = points.reduce((sum, p) => sum + p.y, 0);
    const sxx = points.reduce((sum, p) => sum + p.x * p.x, 0);
    const sxy = points.reduce((sum, p) => sum + p.x * p.y, 0);
    const denom = n * sxx - sx * sx;
    if (!denom) return null;
    const ratio = (n * sxy - sx * sy) / denom;
    return { start: (sy - ratio * sx) / n, ratio };
  }

  /** Recomputes a curve's start from the two boxes it is typed in. Null when the
   * mantissa is not a positive number, which has no logarithm. */
  function restart(which) {
    const mantissa = AUTO[`${which}Mantissa`];
    const exponent = AUTO[`${which}Exponent`];
    AUTO[`${which}0`] = mantissa > 0 && Number.isFinite(exponent)
      ? Math.log10(mantissa) + exponent : null;
  }

  /** Puts a log10 into the two boxes, then recomputes the start from what they
   * now hold - so what is used is always what is shown, rounding included. */
  function setStart(which, value) {
    const [mantissa, exponent] = fromLog10(value);
    // Four figures, not six: this is a least-squares estimate over a handful of
    // perks, and 1.31072 claims a precision the fit does not have - while
    // costing the box the room to show its last two digits.
    AUTO[`${which}Mantissa`] = Number(mantissa.toPrecision(4));
    AUTO[`${which}Exponent`] = exponent;
    restart(which);
  }

  /** Fills both curves from a branch already priced the way you want the rest to
   * be. Two straight-line fits, so adopting a branch adopts straight lines -
   * curving them is a deliberate move away from that. */
  function adoptAnchor(branchKey) {
    const perks = view.report.perks.filter((perk) => perk.branch_key === branchKey);
    const first = fitCurve(perks, (perk) => perk.first_level_cost);
    const last = fitCurve(perks, (perk) => perk.last_level_cost);
    if (!first || !last) return false;
    setStart("first", first.start);
    AUTO.firstRatio = Number(first.ratio.toPrecision(4));
    AUTO.firstAccel = 1;
    setStart("last", last.start);
    AUTO.lastRatio = Number(last.ratio.toPrecision(4));
    AUTO.lastAccel = 1;
    return true;
  }

  /** Where one of the two curves sits at `depth`, in log10. Taken from
   * growthCurve rather than written out again, so the target and every cost
   * curve on this screen are the same expression. */
  const curveAt = (which, depth) => growthCurve(
    AUTO[`${which}0`], 10 ** AUTO[`${which}Ratio`], AUTO[`${which}Accel`],
    depth - 1, depth - 1)[0];

  /* cost_growth has to stay above 1.0 - authored_data_test and the pacing test
   * both refuse a curve that never rises - so a perk is never asked to climb
   * fewer decades than this over all its levels. */
  const MIN_CLIMB = 1e-6;

  /** The whole solve: one plan, per field, plus everything worth refusing over.
   *
   * Built in one pass so the preview and the apply cannot disagree, and so the
   * per_level rows can be worked out from the max_level a perk is *about to*
   * have while its old one is still readable. */
  function solvePlan() {
    const perField = new Map();
    const warnings = [];
    const push = (key, row) => {
      if (!perField.has(key)) perField.set(key, []);
      perField.get(key).push(row);
    };

    const ready = ["first0", "firstRatio", "last0", "lastRatio"]
      .every((key) => Number.isFinite(AUTO[key]));
    if (!ready) {
      return { perField, warnings: ["Pick a branch to match, or type both curves."] };
    }
    if (!(AUTO.firstAccel > 0) || !(AUTO.lastAccel > 0)) {
      return { perField, warnings: ["A depth exponent has to be above 0."] };
    }

    const solved = new Map();
    for (const entry of orderedPicked()) {
      const perk = view.drawn.get(entry.path) || {};
      const priced = view.report.perks.find((p) => p.res_path === entry.path) || {};
      const depth = perk.depth ?? priced.depth;
      if (!depth) {
        warnings.push(`${nameOf(entry.path)} is the core - it has no depth to price.`);
        continue;
      }
      const row = rowIndexOf(entry.path);
      if (!row) continue;

      // The level count first: everything below is priced for the perk it is
      // about to be, not the one it was.
      const wasLevel = Math.max(1, Math.round(numberCell(row, "max_level", 1)));
      const level = AUTO.levels === "set"
        ? Math.max(1, Math.round(AUTO.levelValue)) : wasLevel;
      if (level !== wasLevel) {
        push("max_level", { path: entry.path, name: nameOf(entry.path),
          current: wasLevel, next: level });
      }

      // Level 0 costs base_cost exactly, so the first curve is not solved for -
      // it is written straight in.
      const first = curveAt("first", depth);
      const last = curveAt("last", depth);
      if (!Number.isFinite(first) || !Number.isFinite(last)) {
        warnings.push(`${nameOf(entry.path)} at depth ${depth} is off the end of these curves.`);
        continue;
      }
      push("base_cost", { path: entry.path, name: nameOf(entry.path),
        current: readField(entry.path, BULK_FIELD_BY_KEY.base_cost), next: first });

      if (level > 1) {
        const ge = numberCell(row, "cost_growth_exponent", 1);
        // How far level 0 is from level L-1 in the exponent, with the perk's own
        // curvature left in. cost_growth is what is left to solve.
        const reach = (level - 1) * ge ** (level - 1);
        let span = last - first;
        if (!(span > 0)) {
          warnings.push(`${nameOf(entry.path)} is asked to end no dearer than it starts at `
            + `depth ${depth} - its last level would need a cost_growth of 1.0 or less, `
            + "which authored_data_test refuses. Raised to the smallest rise there is.");
          span = MIN_CLIMB;
        }
        const growth = reach > 0 ? 10 ** (span / reach) : numberCell(row, "cost_growth", 1.6);
        push("cost_growth", { path: entry.path, name: nameOf(entry.path),
          current: numberCell(row, "cost_growth", 1.6), next: growth });
      } else if (Math.abs(last - first) > 1e-9) {
        warnings.push(`${nameOf(entry.path)} has one level, so its first level is its last - `
          + "only the first curve reaches it.");
      }

      solved.set(entry.path, { baseLog: first, level, wasLevel, depth,
        parent_id: perk.parent_id || priced.parent_id, id: perk.id || priced.id });
    }

    // A perk has to cost more than the one it hangs off - authored_data_test
    // asserts it on base_cost, and a curve can rise with depth while a fork
    // inside a branch still breaks it. Reported, never quietly fixed.
    const byId = new Map([...solved].map(([path, entry]) => [entry.id, { path, ...entry }]));
    for (const entry of byId.values()) {
      const parent = byId.get(entry.parent_id);
      if (parent && !(entry.baseLog > parent.baseLog)) {
        warnings.push(`${nameOf(entry.path)} would not cost more than `
          + `${nameOf(parent.path)} - authored_data_test asserts a perk is dearer `
          + "than its parent.");
      }
    }

    if (AUTO.holdEffect && AUTO.levels === "set") {
      for (const row of effectRowsHoldingMagnitude(solved)) push("per_level", row);
    }
    return { perField, warnings };
  }

  /** per_level rebuilt so a perk gives what it gave before its level count moved.
   *
   * Effect defs are shared - one belongs to eight perks on the Reach arm - so a
   * def is only touched when every picked perk using it lands on the *same* new
   * level. Otherwise there is no single per_level that holds all their
   * magnitudes, and picking one silently would be a guess. */
  function effectRowsHoldingMagnitude(solved) {
    const byPath = new Map();
    for (const perk of view.report.perks) {
      const entry = solved.get(perk.res_path);
      if (!entry) continue;
      for (const path of perk.effect_paths || []) {
        if (!byPath.has(path)) byPath.set(path, []);
        byPath.get(path).push(entry);
      }
    }
    const rows = [];
    for (const [path, users] of byPath) {
      const level = users[0].level;
      const wasLevel = users[0].wasLevel;
      if (users.some((user) => user.level !== level || user.wasLevel !== wasLevel)) {
        continue;   // reported by the section itself, which knows the names
      }
      const effect = rowIndexOf(path);
      if (!effect) continue;
      const perLevel = numberCell(effect, "per_level", 0);
      const compound = cell(effect, "level_scaling") === "COMPOUND";
      // LINEAR magnitude is per_level * L, COMPOUND is (1+per_level)^L - 1.
      // Both invert directly for the per_level that keeps the old magnitude.
      const next = compound
        ? (1 + perLevel) ** (wasLevel / level) - 1
        : (perLevel * wasLevel) / level;
      if (!Number.isFinite(next) || Math.abs(next - perLevel) < 1e-12) continue;
      rows.push({ path, name: labelOf(path), current: perLevel, next });
    }
    return rows;
  }

  /** The auto-balance controls, the plan they produce, and one Apply that hands
   * it to the same staging every manual op goes through.
   *
   * Six boxes in a grid rather than a column of labelled rows: they are two
   * readings of the same three questions - where the curve starts, what each
   * depth multiplies it by, and whether that multiplier itself grows - and read
   * far quicker as two rows under one set of headings. Every one of them is an
   * exponent, so there is nothing to echo; the ladder underneath shows what the
   * numbers actually come to, which is better feedback than a restatement.
   */
  function autoSection() {
    const wrap = document.createElement("div");
    wrap.className = "bulk-auto";
    const title = document.createElement("h3");
    title.textContent = "Auto-balance";
    wrap.append(title);

    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = "Say what a perk's first and last level should cost at each depth. "
      + "base_cost and cost_growth are solved from the two; cost_growth_exponent is left "
      + "as authored. Nothing is written until Apply.";
    wrap.append(note);

    const anchor = document.createElement("select");
    anchor.append(new Option("price it like…", ""));
    for (const branch of view.report.branches) {
      if (!branch.branch_key) continue;
      anchor.append(new Option(branch.branch_label, branch.branch_key));
    }
    anchor.title = "Fit both curves to a branch already costing what you want";
    anchor.onchange = () => {
      AUTO.anchor = anchor.value;
      if (AUTO.anchor && adoptAnchor(AUTO.anchor)) fill();
      refresh();
    };
    wrap.append(anchor);

    const grid = document.createElement("div");
    grid.className = "bulk-auto-grid";
    for (const heading of ["", "start", "×1e / depth", "exp"]) {
      const cell = document.createElement("i");
      cell.className = "bulk-auto-head";
      cell.textContent = heading;
      grid.append(cell);
    }

    const boxes = {};
    const box = (key, tip, step) => {
      const input = document.createElement("input");
      input.type = "number";
      input.step = step;
      input.dataset.auto = key;
      input.title = tip;
      input.oninput = () => {
        const raw = input.value.trim() === "" ? NaN : Number(input.value);
        AUTO[key] = Number.isFinite(raw) ? raw : null;
        // A start is stored as a pair and read as a logarithm; moving either
        // half has to move the logarithm with it.
        const start = /^(first|last)(Mantissa|Exponent)$/.exec(key);
        if (start) restart(start[1]);
        // Typing makes the curves yours, not the branch's - the picker stops
        // claiming a fit these numbers may no longer be.
        AUTO.anchor = "";
        anchor.value = "";
        refresh();
      };
      boxes[key] = input;
      return input;
    };

    /** The mantissa and exponent of one curve's start, side by side with the `e`
     * between them - the same pair the .tres stores a base cost as, so a price
     * of 2.5e3 is typed rather than converted. */
    const startPair = (which, label) => {
      const pair = document.createElement("span");
      pair.className = "bulk-auto-pair";
      const mantissa = box(`${which}Mantissa`, `What this ${label} costs at depth 1`, "any");
      mantissa.min = "0";
      const e = document.createElement("i");
      e.textContent = "e";
      const exponent = box(`${which}Exponent`,
        `The power of ten this ${label} costs at depth 1`, "1");
      pair.append(mantissa, e, exponent);
      return pair;
    };

    // Short labels: the heading says these are starts, and the row names cost the
    // exponent boxes room they need more.
    for (const [which, label] of [["first", "first"], ["last", "last"]]) {
      const name = document.createElement("label");
      name.textContent = label;
      grid.append(name,
        startPair(which, label),
        box(`${which}Ratio`, `Decades each step down the branch adds to this ${label}`, "0.5"),
        box(`${which}Accel`, "How much more each step adds than the one before it. "
          + "1 is a straight line in log space. The same knob cost_growth_exponent "
          + "is on a perk.", "0.005"));
    }
    wrap.append(grid);

    /* Level counts, not prices. Closed by default: a branch's costs can be
     * retuned without changing how long its perks are, and that is the change
     * worth making by default. */
    const adjust = document.createElement("details");
    adjust.className = "bulk-auto-adjust";
    const summary = document.createElement("summary");
    summary.textContent = "Adjust levels";
    adjust.append(summary);

    const levels = document.createElement("select");
    levels.append(new Option("keep max levels", "keep"), new Option("set max level", "set"));
    levels.value = AUTO.levels;
    const levelBox = document.createElement("input");
    levelBox.type = "number";
    levelBox.step = "1";
    levelBox.dataset.auto = "levels";
    levelBox.value = String(AUTO.levelValue);
    levelBox.oninput = () => {
      const value = Number(levelBox.value);
      if (Number.isFinite(value)) AUTO.levelValue = value;
      refresh();
    };
    levels.onchange = () => { AUTO.levels = levels.value; refresh(); };
    const levelRow = document.createElement("div");
    levelRow.className = "bulk-auto-row";
    levelRow.append(levels, levelBox);

    const hold = document.createElement("label");
    hold.className = "bulk-auto-hold";
    const holdBox = document.createElement("input");
    holdBox.type = "checkbox";
    holdBox.checked = AUTO.holdEffect;
    holdBox.onchange = () => { AUTO.holdEffect = holdBox.checked; refresh(); };
    hold.append(holdBox, document.createTextNode(" hold effect at max (per_level follows)"));
    adjust.append(levelRow, hold);
    wrap.append(adjust);

    const warnings = document.createElement("div");
    const ladder = document.createElement("table");
    ladder.className = "web-table bulk-auto-ladder";
    const staged = document.createElement("div");
    staged.className = "bulk-preview";
    const apply = document.createElement("button");
    apply.type = "button";
    apply.textContent = "Apply";
    wrap.append(warnings, ladder, staged, apply);

    const asValue = (log) => (log === null || log === undefined || !Number.isFinite(log)
      ? "-" : formatBig(...fromLog10(log)));

    function fill() {
      for (const [key, input] of Object.entries(boxes)) {
        input.value = AUTO[key] === null || AUTO[key] === undefined
          ? "" : String(Number(AUTO[key].toPrecision(6)));
      }
    }

    const startsFilled = () => ["firstMantissa", "firstExponent", "lastMantissa", "lastExponent"]
      .every((key) => AUTO[key] !== null && AUTO[key] !== undefined);

    /* Column widths for the ladder, remembered the way every other dragged width
     * in the editor is. Keyed per column rather than per table: there is one
     * ladder, and its three columns hold very different things - a depth number,
     * and two "now → target" pairs that can each run to 1e1354. */
    const LADDER_WIDTHS = ["ladder:depth", "ladder:first", "ladder:last"];
    const LADDER_MIN = 40;

    /** Puts a drag handle on one of the ladder's headers. The table is
     * table-layout: fixed, so a width set on a header is the column's width. */
    function ladderResizer(table, index) {
      const handle = document.createElement("div");
      handle.className = "resizer";
      handle.title = "drag to resize · double-click to reset";
      handle.onpointerdown = (event) => {
        event.preventDefault();
        handle.setPointerCapture(event.pointerId);
        handle.classList.add("dragging");
        const startX = event.clientX;
        const startWidth = table.rows[0].cells[index].getBoundingClientRect().width;
        const onMove = (moveEvent) => {
          const width = Math.max(LADDER_MIN,
            Math.round(startWidth + moveEvent.clientX - startX));
          panelWidths[LADDER_WIDTHS[index]] = width;
          table.rows[0].cells[index].style.width = `${width}px`;
        };
        const onUp = () => {
          handle.classList.remove("dragging");
          handle.removeEventListener("pointermove", onMove);
          handle.removeEventListener("pointerup", onUp);
          savePanelWidths();
        };
        handle.addEventListener("pointermove", onMove);
        handle.addEventListener("pointerup", onUp);
      };
      handle.ondblclick = (event) => {
        event.preventDefault();
        delete panelWidths[LADDER_WIDTHS[index]];
        savePanelWidths();
        table.rows[0].cells[index].style.width = "";
      };
      return handle;
    }

    /** Both ends of a perk at each depth, now against target. The endpoints are
     * what the two curves name, so they are what the ladder has to show - a
     * multiplier per depth cannot be judged from the multiplier. */
    function renderLadder() {
      ladder.replaceChildren();
      const head = ladder.insertRow();
      ["depth", "first level", "last level"].forEach((column, index) => {
        const th = document.createElement("th");
        th.textContent = column;
        // Re-applied on every rebuild: the ladder is thrown away and remade on
        // each keystroke, so a width that lived only on the element would last
        // until the next character typed.
        const width = panelWidths[LADDER_WIDTHS[index]];
        if (width) th.style.width = `${width}px`;
        th.append(ladderResizer(ladder, index));
        head.append(th);
      });
      const depths = new Map();
      for (const path of view.picked) {
        const perk = view.report.perks.find((p) => p.res_path === path);
        if (!perk || !perk.depth) continue;
        const at = depths.get(perk.depth) || { first: -Infinity, last: -Infinity };
        at.first = Math.max(at.first, log10Of(perk.first_level_cost) ?? -Infinity);
        at.last = Math.max(at.last, log10Of(perk.last_level_cost) ?? -Infinity);
        depths.set(perk.depth, at);
      }
      const ready = ["first0", "firstRatio", "last0", "lastRatio"]
        .every((key) => Number.isFinite(AUTO[key])) && AUTO.firstAccel > 0 && AUTO.lastAccel > 0;
      for (const depth of [...depths.keys()].sort((a, b) => a - b)) {
        const row = ladder.insertRow();
        row.insertCell().textContent = String(depth);
        for (const which of ["first", "last"]) {
          const cell = row.insertCell();
          cell.className = "num";
          const now = depths.get(depth)[which];
          cell.textContent = `${asValue(now === -Infinity ? null : now)} → `
            + `${ready ? asValue(curveAt(which, depth)) : "-"}`;
        }
      }
    }

    let plan = null;
    function refresh() {
      levelBox.hidden = AUTO.levels !== "set";
      hold.hidden = AUTO.levels !== "set";
      plan = solvePlan();
      warnings.replaceChildren();
      for (const line of plan.warnings) {
        const warn = document.createElement("p");
        warn.className = "hint warn";
        warn.textContent = line;
        warnings.append(warn);
      }
      renderLadder();
      const counts = [...plan.perField].map(([key, rows]) =>
        `${BULK_FIELD_BY_KEY[key].label} ${rows.length}`);
      staged.textContent = counts.length ? `stages ${counts.join(" · ")}` : "nothing to solve for";
      apply.disabled = !counts.length;
    }

    if (!startsFilled() && view.report.branches.length > 1) {
      // Opens on something real: the cheapest arm is the one the others tend to
      // need bringing towards, and it means the boxes are never blank.
      const cheapest = view.report.branches
        .filter((branch) => branch.branch_key && log10Of(branch.total_cost_to_max) !== null)
        .sort((a, b) => log10Of(a.total_cost_to_max) - log10Of(b.total_cost_to_max))[0];
      if (cheapest && adoptAnchor(cheapest.branch_key)) AUTO.anchor = cheapest.branch_key;
    }
    anchor.value = AUTO.anchor;
    fill();
    refresh();

    apply.onclick = () => {
      if (!plan) return;
      const files = new Set();
      let count = 0;
      // max_level before per_level: the magnitude each row holds was worked out
      // against the level the perk is about to have.
      for (const key of ["max_level", "base_cost", "cost_growth", "per_level"]) {
        for (const row of plan.perField.get(key) || []) {
          const file = writeField(row.path, BULK_FIELD_BY_KEY[key], row.next);
          if (file) { files.add(file); count += 1; }
        }
      }
      finishBulk(files, `auto-balance: ${count} value(s) staged`);
    };
    return wrap;
  }

  /* ------------------------------------------------------------------- verify */

  /* What the pacing became. One run, not a search: the objective is
   * self-referential - prices decide what the run can afford, which decides when
   * it prestiges, which decides the payout, which decides affordability again -
   * and the payout is quantised in whole storage areas, so it moves in steps.
   * Something optimising against that would be fitting the robot, not the game. */

  const PACING_WINDOW = [20, 1500];   // balance_pacing_test.gd MIN/MAX_FIRST_PRESTIGE_TICK

  function verifySection() {
    const wrap = document.createElement("div");
    wrap.className = "bulk-verify";
    const title = document.createElement("h3");
    title.textContent = "Check the pacing";
    wrap.append(title);

    const dirty = BULK_TABLES.some((file) => state.loaded.has(file) && fileHasChanges(file));
    const note = document.createElement("p");
    note.className = dirty ? "hint warn" : "hint";
    note.textContent = dirty
      ? "Unsaved edits are not simulated - the run reads the .tres files. Save first."
      : "One run over what is on disk, reporting what the robot did under "
        + "BalancePolicy's cheapest-affordable-perk rule. That is not a player.";
    wrap.append(note);

    const out = document.createElement("div");
    out.className = "bulk-preview";
    if (view.pacing) out.textContent = view.pacing;

    const run = document.createElement("button");
    run.type = "button";
    run.textContent = "Run the sim";
    run.disabled = dirty;
    run.onclick = async () => {
      run.disabled = true;
      out.textContent = "running…";
      try {
        // samples=0, breakdowns=off: the cheapest invocation there is, and the
        // one --report mode uses. The breakdown is ~250 re-resolve probes.
        const report = await api("/api/sim", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ticks: 20000, prestiges: 3, samples: 0,
            policy: "roi", breakdowns: "off" }),
        });
        view.pacing = readPacing(report);
        out.textContent = view.pacing;
      } catch (error) {
        out.textContent = String(error);
      }
      run.disabled = false;
    };
    wrap.append(run, out);
    return wrap;
  }

  /** The run, read against the only bounds this repo actually states. */
  function readPacing(report) {
    const milestones = report.milestones || [];
    const prestiges = milestones.filter((stone) => stone.event === "prestige");
    const lines = [];
    const first = prestiges[0];
    if (!first) {
      lines.push("no prestige inside the tick budget - balance_pacing_test asserts at least one");
    } else {
      const inside = first.tick >= PACING_WINDOW[0] && first.tick <= PACING_WINDOW[1];
      lines.push(`first prestige at tick ${first.tick}`
        + ` ${inside ? "· inside" : "· OUTSIDE"} the ${PACING_WINDOW.join("-")} window`
        + " balance_pacing_test asserts");
    }
    lines.push(`${prestiges.length} of ${report.prestige_target} prestiges`
      + ` · ${report.seconds ? `${Math.round(report.seconds / 60)} min played` : "?"}`);

    const biomes = milestones.filter((stone) => stone.event === "biome")
      .map((stone) => stone.detail);
    for (const needed of ["meadow", "forest", "permafrost"]) {
      if (!biomes.some((name) => String(name).includes(needed))) {
        lines.push(`${needed} never unlocked - balance_pacing_test requires it`);
      }
    }

    // The jump between payouts is the sharpest signal the pacing is not smooth:
    // a run whose third prestige pays 122 orders more than its second is not a
    // curve, it is a cliff.
    const orders = prestiges.map((stone) => {
      const match = /([0-9.]+)e([0-9+-]+)/.exec(String(stone.detail || ""));
      return match ? Math.log10(Number(match[1])) + Number(match[2]) : null;
    });
    for (let i = 1; i < orders.length; i += 1) {
      if (orders[i] === null || orders[i - 1] === null) continue;
      lines.push(`payout #${i} → #${i + 1}: +${(orders[i] - orders[i - 1]).toFixed(0)} orders`);
    }
    return lines.join("\n");
  }

  function renderBulk(target) {
    const head = document.createElement("div");
    head.className = "web-editor-head";
    const title = document.createElement("b");
    title.textContent = `${view.picked.size} perks picked`;
    const clear = document.createElement("button");
    clear.textContent = "Clear";
    clear.title = "Stop bulk editing";
    clear.onclick = () => { view.picked.clear(); view.render(); };
    head.append(title, clear);
    target.append(head);

    target.append(pickedChips());

    const hint = document.createElement("p");
    hint.className = "hint";
    hint.textContent = "Ctrl-click a perk to add or drop it, shift-click for its whole subtree.";
    target.append(hint);

    const fields = document.createElement("div");
    fields.className = "bulk-fields";
    for (const field of BULK_FIELDS) {
      fields.append(bulkRow(field, {
        ramp: true,
        plan: (op, a, b) => planPerks(field, op, a, b),
        watch: () => {},
      }));
    }
    target.append(autoSection());
    target.append(fields);
    target.append(effectSection());
    target.append(bulkFooter());
    target.append(verifySection());
  }

  /** Everything outside the perk tree that names this perk by id.
   *
   * unlock_perk_id and max_level_perk_id are StringNames, not paths, so nothing
   * in the reference machinery sees them. Found by column name rather than by a
   * list of tables: whichever resource grows one next is covered without this
   * screen being told about it. */
  function perkIdReferences(node) {
    const id = node && cell(node, "id");
    if (!id || node.file !== "PerkNodeDef") return [];
    const out = [];
    for (const file of state.files) {
      if (file === "PerkNodeDef") continue;
      for (const entry of rowsOf(file)) {
        for (const column of entry.header) {
          if (!column.endsWith("perk_id") || cell(entry, column) !== id) continue;
          out.push(`${labelOf(entry)} (${file}.${column})`);
        }
      }
    }
    return out;
  }

  /** True for a row the cost formula applies to. A chip followed out of the web
   * can land on an effect or a branch, which have no price of their own. */
  const isPriced = (entry) => entry
    && entry.header.includes("_base_cost_mantissa") && entry.header.includes("cost_growth");

  /** What each level of this perk costs, level by level.
   *
   * UpgradeSystem.cost() prices a perk the same way it prices everything else,
   * so the curve comes from GameKit rather than from a copy here, and the
   * engine's own samples ride behind it as dots: if the mirror ever drifts from
   * the game, the dots leave the line. */
  function costChart(entry) {
    const build = (from, to) => {
      const series = [{
        label: "cost of the next level",
        color: "var(--accent)",
        points: growthCurve(
          bigLog10(numberCell(entry, "_base_cost_mantissa", 0),
            numberCell(entry, "_base_cost_exponent", 0)),
          numberCell(entry, "cost_growth", 1.15),
          numberCell(entry, "cost_growth_exponent", 1),
          from, to),
      }];
      const sampled = engineCurve(entry.row[0]);
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => bigLog10(mantissa, exponent));
      if (dots) series.push(dots);
      return series;
    };

    const maxLevel = Math.round(numberCell(entry, "max_level", 0));
    return chartBlock("Biomass per level", build, {
      space: "log10", xLabel: "level", width: 560, height: 300,
      range: { key: PERK_COST_CHART, from: 0, to: maxLevel > 0 ? maxLevel : 50, label: "level" },
    });
  }

  /** The cost chart, floated over the canvas's top-left corner rather than
   * folded into the field list on the right.
   *
   * The web is radial, so its corners are empty while the panel is 340px of
   * contested width - the curve is the thing being read against the drawing, and
   * it wants the room. Absolutely placed rather than laid out in the canvas, so
   * panning the web does not carry it off screen. */
  /** What one level of this perk actually gives, level by level.
   *
   * The cost curve alone says what a perk costs to climb, never whether the
   * climb is worth it - and the two are authored on different resources, the
   * price on the perk and the payout on an UpgradeEffectDef one hop away (often
   * the branch's, shared by every perk on the arm). Read together they are the
   * ratio being tuned, which is why this sits under the price rather than in the
   * field list on the right.
   *
   * Only the first effect is drawn. Every authored perk carries one, and a perk
   * with several has no single curve to plot - the note says so rather than
   * picking one silently. */
  function effectChart(perk) {
    const path = ((perk && perk.effect_paths) || [])[0];
    if (!path) return null;
    const effect = rowIndexOf(path);
    if (!effect) return null;

    const perLevel = numberCell(effect, "per_level", 0);
    const compound = enumIs(cell(effect, "level_scaling"), "COMPOUND");
    const cap = numberCell(effect, "max_magnitude", 0);
    let capped = false;

    const build = (from, to) => {
      const curve = effectCurve({ perLevel, compound, cap, factor: null }, from, to);
      capped = curve.capped;
      const series = [{
        label: `${cell(effect, "stat") || "effect"} magnitude`,
        color: "var(--accent)",
        points: curve.raw,
      }];
      // Keyed on the perk, which is what the engine files its samples under -
      // the effect resource has no curve of its own in the report.
      const sampled = engineCurve(state.focus);
      const dots = engineSeries(effect, sampled && sampled.effect, from, to,
        ([mantissa, exponent]) => mantissa * 10 ** exponent);
      if (dots) series.push(dots);
      return series;
    };

    const maxLevel = Math.round(numberCell(focusedRow(), "max_level", 0));
    const block = chartBlock("Effect per level", build, {
      space: "linear", zeroBased: true, xLabel: "level", width: 560, height: 220,
      range: { key: PERK_EFFECT_CHART, from: 0, to: maxLevel > 0 ? maxLevel : 50, label: "level" },
    });

    const notes = [];
    if (capped) notes.push("max_magnitude clamps this curve — the flat top is the cap.");
    if (cell(effect, "dependency")) {
      notes.push("This effect scales by a ScalingSourceDef as well, which is not drawn: "
        + "the line is the authored magnitude before that multiplier.");
    }
    if (((perk && perk.effect_paths) || []).length > 1) {
      notes.push(`Only the first of ${perk.effect_paths.length} effects is drawn.`);
    }
    if (notes.length) {
      const hint = document.createElement("p");
      hint.className = "hint";
      hint.textContent = notes.join(" ");
      block.append(hint);
    }
    return block;
  }

  function costOverlay(row, perk = selectedPerk()) {
    const wrap = document.createElement("div");
    wrap.className = "web-cost";
    const name = document.createElement("div");
    name.className = "web-cost-name";
    name.textContent = labelOf(row);
    wrap.append(name, costChart(row));

    // A followed chip can be priced without being a perk, and then there is no
    // effect to pair with the price.
    const effect = effectChart(perk);
    if (effect) wrap.append(effect);
    return wrap;
  }

  /* ------------------------------------------------------- many at once */

  /* Comparing a set is the reason to have picked one. Both overlays draw a curve
   * per picked perk rather than the one that happens to be focused.
   *
   * The engine's own samples are left off here: a dot series per perk would bury
   * the twelve lines they are meant to be checked against. Pick one perk to see
   * them. */

  /* Past this the legend is taller than the chart and every line is one of
   * twenty in the same colour family, so the count is said instead. */
  const MAX_OVERLAY_SERIES = 12;

  /** The picked perks that have a price to draw, in the order the web reads. */
  function pickedForCharts() {
    return orderedPicked()
      .map((entry) => ({ path: entry.path, row: rowIndexOf(entry.path),
        perk: view.report.perks.find((p) => p.res_path === entry.path) }))
      .filter((entry) => isPriced(entry.row));
  }

  /** Blanks a curve past the last level that perk actually has.
   *
   * The window is shared by every series, so it runs to the deepest perk's level
   * count. Without this a perk maxing at 5 draws a confident line out to 150,
   * which is a price nobody can ever be charged. */
  const upToMax = (points, from, maxLevel) =>
    points.map((value, index) => (from + index < maxLevel ? value : null));

  function costChartMany(entries) {
    const shown = entries.slice(0, MAX_OVERLAY_SERIES);
    const build = (from, to) => shown.map((entry, index) => {
      const maxLevel = Math.round(numberCell(entry.row, "max_level", 0));
      return {
        label: nameOf(entry.path),
        color: hueOf(index),
        points: upToMax(growthCurve(
          bigLog10(numberCell(entry.row, "_base_cost_mantissa", 0),
            numberCell(entry.row, "_base_cost_exponent", 0)),
          numberCell(entry.row, "cost_growth", 1.15),
          numberCell(entry.row, "cost_growth_exponent", 1),
          from, to), from, maxLevel),
      };
    });
    const maxLevel = Math.max(...shown.map((entry) =>
      Math.round(numberCell(entry.row, "max_level", 0))));
    return chartBlock("Biomass per level", build, {
      space: "log10", xLabel: "level", width: 560, height: 300,
      range: { key: PERK_COST_CHART, from: 0, to: maxLevel > 0 ? maxLevel : 50, label: "level" },
    });
  }

  function effectChartMany(entries) {
    const withEffect = entries
      .map((entry) => ({ ...entry, effect: rowIndexOf(((entry.perk
        && entry.perk.effect_paths) || [])[0] || "") }))
      .filter((entry) => entry.effect);
    if (!withEffect.length) return null;
    const shown = withEffect.slice(0, MAX_OVERLAY_SERIES);

    const build = (from, to) => shown.map((entry, index) => {
      const maxLevel = Math.round(numberCell(entry.row, "max_level", 0));
      const curve = effectCurve({
        perLevel: numberCell(entry.effect, "per_level", 0),
        compound: enumIs(cell(entry.effect, "level_scaling"), "COMPOUND"),
        cap: numberCell(entry.effect, "max_magnitude", 0),
        factor: null,
      }, from, to);
      return {
        label: `${nameOf(entry.path)} · ${cell(entry.effect, "stat") || "effect"}`,
        color: hueOf(index),
        points: upToMax(curve.raw, from, maxLevel),
      };
    });

    const maxLevel = Math.max(...shown.map((entry) =>
      Math.round(numberCell(entry.row, "max_level", 0))));
    const block = chartBlock("Effect per level", build, {
      space: "linear", zeroBased: true, xLabel: "level", width: 560, height: 220,
      range: { key: PERK_EFFECT_CHART, from: 0, to: maxLevel > 0 ? maxLevel : 50, label: "level" },
    });

    // Two stats on one axis are two different units sharing a scale, which is
    // worth saying before a tick_rate of -7.5 is read as smaller than 40 points.
    const stats = [...new Set(shown.map((entry) => cell(entry.effect, "stat")).filter(Boolean))];
    const notes = [];
    if (stats.length > 1) {
      notes.push(`${stats.length} different stats share this axis (${stats.join(", ")}) - `
        + "their magnitudes are not comparable.");
    }
    if (withEffect.length < entries.length) {
      notes.push(`${entries.length - withEffect.length} picked perk(s) have no effect to draw.`);
    }
    if (notes.length) {
      const hint = document.createElement("p");
      hint.className = "hint";
      hint.textContent = notes.join(" ");
      block.append(hint);
    }
    return block;
  }

  /** Both charts over the whole picked set. */
  function costOverlayMany(entries) {
    const wrap = document.createElement("div");
    wrap.className = "web-cost";
    const name = document.createElement("div");
    name.className = "web-cost-name";
    name.textContent = entries.length > MAX_OVERLAY_SERIES
      ? `${MAX_OVERLAY_SERIES} of ${entries.length} picked perks`
      : `${entries.length} picked perks`;
    wrap.append(name, costChartMany(entries));
    const effect = effectChartMany(entries);
    if (effect) wrap.append(effect);
    return wrap;
  }

  /** One of the picked perk's effects, with its own value fields. Reference
   * columns are left out, except the scaling source: that one is a closed set of
   * authored rows, so it is picked here rather than through the chips above. */
  function effectEditor(perk, path) {
    const entry = rowIndexOf(path);
    const block = document.createElement("div");
    block.className = "deps-panel web-effect";
    if (!entry) {
      block.textContent = `${path} is missing`;
      return block;
    }

    const title = document.createElement("h3");
    title.textContent = `Effect · ${labelOf(entry)}`;
    block.append(title);

    // A branch's default_effects is one resource shared by every node on the
    // arm, so changing it here changes all of them. Saying so beats finding out.
    if (perk.effects_inherited) {
      const shared = document.createElement("div");
      shared.className = "hint";
      shared.textContent = `Shared by the whole ${perk.branch_label} branch - `
        + "every perk on it uses this effect.";
      block.append(shared);
    }

    const references = referenceColumns(entry.file);
    entry.header.forEach((column, columnIndex) => {
      // `target` is a reference column, so the generic loop skips it and the
      // graph's chip picker is where it would otherwise be edited. A perk that
      // names a group has nothing to pick there - a group is a vocabulary, not a
      // row - so scope and target are placed here as the same pair every other
      // screen shows, tier picker included.
      if (column === "scope") {
        block.append(scopeTargetFields(entry));
        return;
      }
      // Also a reference the generic loop would skip, and the one every other
      // screen now picks in place.
      if (column === "dependency") {
        const dependency = dependencyField(entry);
        if (dependency) block.append(dependency);
        return;
      }
      if (columnIndex === 0 || column === "target" || references.has(column)) return;
      block.append(fieldEditor(entry, columnIndex));
    });
    return block;
  }


  /** The comparison the web itself cannot answer: is one arm priced like the
   * others, and does it hand back a comparable amount? */
  function branchTable() {
    const table = document.createElement("table");
    table.className = "web-table";
    const head = table.insertRow();
    for (const column of ["branch", "perks", "depth", "total cost", "deepest path"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }
    for (const branch of view.report.branches) {
      const row = table.insertRow();
      row.className = "branch";
      const name = row.insertCell();
      name.innerHTML = `<i style="display:inline-block;width:8px;height:8px;border-radius:2px;`
        + `background:hsl(${branch.hue} 60% 55%);margin-right:5px"></i>`;
      name.append(branch.branch_label || "core");
      row.insertCell().textContent = String(branch.perk_count);
      row.insertCell().textContent = String(branch.max_depth);
      for (const pair of [branch.total_cost_to_max, branch.deepest_path_cost]) {
        const cell = row.insertCell();
        cell.className = "num";
        cell.textContent = format(pair);
      }

      const stats = Object.entries(branch.stats);
      if (stats.length) {
        const statRow = table.insertRow();
        const cell = statRow.insertCell();
        cell.colSpan = 5;
        cell.className = "web-stats";
        cell.textContent = stats
          .map(([key, value]) => `${key}: ${format(value)} at max`).join(" · ");
      }
    }
    return table;
  }

  /** The five priciest perks to reach, which is where pacing goes wrong first. */
  function deepestTable() {
    const table = document.createElement("table");
    table.className = "web-table";
    const head = table.insertRow();
    for (const column of ["priciest to reach", "branch", "path cost"]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }
    const sorted = view.report.perks
      .filter((perk) => log10Of(perk.path_cost) !== null)
      .sort((a, b) => log10Of(b.path_cost) - log10Of(a.path_cost))
      .slice(0, 5);
    for (const perk of sorted) {
      const row = table.insertRow();
      const name = row.insertCell();
      name.textContent = perk.display_name;
      if (perk.res_path) {
        name.className = "link";
        name.onclick = () => edit(perk.res_path);
      }
      row.insertCell().textContent = perk.branch_label;
      const cost = row.insertCell();
      cost.className = "num";
      cost.textContent = format(perk.path_cost);
    }
    return table;
  }

  /* ------------------------------------------------------------------- wiring */

  /** Re-runs PerkTree over what is now on disk. Cheap unless something was
   * written: the server caches this report until the data changes. */
  view.invalidate = async () => {
    view.report = await api("/api/perks");
  };

  view.open = async () => {
    // Rebuilt on every open: a saved edit changes what PerkTree produces, and
    // the server drops its cached report whenever the data is written.
    await view.invalidate();
    // Clicking a perk hands over to the graph view, which spans every file and
    // walks the reference edges, so both have to be in memory before it does.
    await loadAllFiles();
    buildEdges();
  };

  /** The canvas and its panel, built once and re-filled on every render. A tab
   * hands over a fresh container each time, so the root is re-appended rather
   * than rebuilt. */
  function root() {
    if (!view.element) {
      view.element = document.createElement("div");
      view.element.id = "web-view";
      view.element.innerHTML = `<div class="web-canvas"></div><aside class="web-panel"></aside>`;
      const panel = view.element.querySelector(".web-panel");
      // Where the panel is scrolled to, remembered as it moves rather than read
      // at the top of render(): the tab detaches this whole element before
      // calling us (game.js empties the body first), and a detached element comes
      // back with the offset already at zero. By the time render() runs there is
      // nothing left to read. The canvas needs none of this - it does not scroll,
      // the camera in the viewBox is what holds where the web is being read.
      panel.addEventListener("scroll", () => { view.panelTop = panel.scrollTop; });
      view.element.append(zoomControls());

      // The same drag bar the file list and the graph panel get. The web is a
      // screen inside the Game view rather than a view of its own, so it never
      // passed through the wiring that gives every view panel one.
      makeGridResizer(view.element, panel, "panel:web", "end", 340, 240, 1000);
      // The cost overlay is placed against the view, not the canvas, so that
      // panning does not carry it off screen - which means its width has to be
      // told how much of the view the panel is taking. Watched as well as
      // measured on render: a drag moves it between renders, and a render can
      // happen before the observer has ever fired.
      if (window.ResizeObserver) new ResizeObserver(measurePanel).observe(panel);
    }
    return view.element;
  }

  /** Tells the stylesheet how much of the view the panel is taking, for the one
   * rule that has to know: the cost overlay's width. */
  function measurePanel() {
    if (!view.element) return;
    const panel = view.element.querySelector(".web-panel");
    if (panel) view.element.style.setProperty("--web-panel", `${panel.offsetWidth}px`);
  }

  view.render = (body) => {
    // The Recompute button calls this with nothing to append to; the root is
    // already in the DOM by then, so re-appending is only for the first render.
    if (body) body.append(root());
    else root();
    if (!view.report) {
      view.element.querySelector(".web-panel").replaceChildren(
        Object.assign(document.createElement("p"),
          { className: "hint", textContent: "The web has not been read yet." }));
      return;
    }
    // A render happens on every selection, every keystroke in the panel and every
    // scale switch, and each one replaces both halves' children. The web keeps
    // its place through that because the camera outlives the drawing; the panel
    // has to be put back by hand.
    const canvas = view.element.querySelector(".web-canvas");
    const panel = view.element.querySelector(".web-panel");
    // The panel holds different content per perk, so its offset is only worth
    // keeping while the same one stays selected: a redraw from an edit should
    // leave the field under the cursor where it was, but picking a new perk
    // should start at the top of what it says rather than partway down it.
    const sameFocus = view.lastFocus === state.focus;
    view.lastFocus = state.focus;
    // Both charts are about the perk that was just picked, so they are drawn over
    // that perk's own levels. A window is otherwise remembered per chart kind -
    // which is what lets two of them be compared - and a perk maxing at 5 was
    // being drawn out to the 150 levels of whichever one was looked at first.
    // Dropped only when the focus actually moves, so a window typed while
    // reading one perk survives the redraw every keystroke in the panel causes.
    // The charts are about the picked set when there is one, so a change to
    // either what is focused or what is picked means they are about something
    // else and the window refits.
    const pickedKey = [...view.picked].join("|");
    const samePicked = view.lastPicked === pickedKey;
    view.lastPicked = pickedKey;
    if (!sameFocus || !samePicked) for (const key of PERK_CHART_KEYS) resetRange(key);

    canvas.replaceChildren(drawWeb());
    renderPanel(panel);

    // After the content is back, so there is something to scroll to. The browser
    // clamps whatever the new content is too short for.
    panel.scrollTop = sameFocus ? (view.panelTop || 0) : 0;

    measurePanel();
    view.element.querySelector(".web-cost")?.remove();
    // A picked set outranks the focus, the same way the panel's editor does:
    // the focus is only still set because something had to be clicked to start
    // picking, and the charts are what the set was gathered to compare.
    const charted = pickedForCharts();
    if (charted.length > 1) {
      view.element.append(costOverlayMany(charted));
    } else if (charted.length === 1) {
      view.element.append(costOverlay(charted[0].row, charted[0].perk));
    } else {
      const priced = focusedRow();
      if (isPriced(priced)) view.element.append(costOverlay(priced));
    }
    const row = focusedRow();
    setStatus(row
      ? `editing ${labelOf(row)}${fileHasChanges(row.file) ? " · unsaved" : ""}`
      : `prestige web - ${view.report.perks.length} perks in `
        + `${view.report.branches.length - 1} branches`);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.prestige = view;
})();
