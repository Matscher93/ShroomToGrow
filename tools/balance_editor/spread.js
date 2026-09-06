/* Spread view: where every price in the game actually lands.
 *
 * The Curves view answers "what does this one def do over its levels". This one
 * answers the question no per-def chart can: across every priced thing at once,
 * which areas offer something at a given point in a run, and which offer
 * nothing. One lane per authored set, one dot per level of every def in it, so a
 * dead span reads as a hole in a lane and a pile-up as a dark band down several.
 *
 * Two x axes, because neither alone is honest:
 *
 *   price  log10 of what the level costs, straight off GET /api/curves. Every
 *          level the definition declares, so the lane is the whole ladder.
 *          Always available and exact, but a 1e9 in nutrients and a 1e9 in
 *          biomass are not the same moment - hence the currency filter.
 *   time   when a simulated run actually bought it, off GET /api/purchases.
 *          Comparable across currencies because it is one clock, but it only
 *          knows what that run reached: an area the run never got to has no
 *          dots at all, which is itself the finding.
 *
 * Nothing here mirrors a cost formula. Both axes are what the engine produced,
 * so unlike curves.js there is no drift to guard against.
 *
 * The x axis pans and zooms, which is not a convenience: prices in this game
 * span thousands of decades, so no single fixed scale can show the biome lanes
 * and the perk ladders at once. Whatever is scrolled off is counted beside the
 * lane it belongs to rather than dropped or pinned.
 *
 * Registered on window.BalanceViews, which index.html turns into a view button,
 * and on window.BalanceSpread, which game.js re-exports so a screen can embed
 * the same strip filtered to its own rows.
 */
(() => {
  const { formatBig, log10Of, hueOf } = window.GameKit;

  /** The buckets of /api/curves that carry a price. `boons` are granted rather
   * than bought, `achievements` are measured in goals, and `prestige` is a
   * nutrient threshold rather than a purchase - none of them belong on an axis
   * of what things cost. */
  const PRICED = ["curves", "boosts", "heroes", "workers", "fertilizer"];

  /** Lane order. Roughly the order a run meets them, so reading top to bottom is
   * reading the game forwards. Anything unlisted sorts after, alphabetically. */
  const LANE_ORDER = ["nodes", "biome", "biome_size", "perks", "well", "boosts",
    "automations", "fertilizer", "ruins"];

  const MODES = {
    price: { label: "Price", axis: "cost of that level", unit: "" },
    time: { label: "Sim time", axis: "seconds into a simulated run", unit: "s" },
  };

  const LANE_HEIGHT = 26;
  const PAD = { left: 168, right: 18, top: 26, bottom: 74 };
  const HISTOGRAM_HEIGHT = 40;
  const BUCKETS = 48;          // histogram columns, and the density resolution
  /** Decades a range can span before narrowing the opening view is worth it. */
  const NARROW_ENOUGH = 2;
  /** Narrowest viewport a wheel is allowed to reach, in decades. Below this the
   * dots stop separating and the axis labels start repeating. */
  const MIN_SPAN = 0.05;
  const ZOOM_STEP = 1.18;      // per wheel notch

  const view = {
    label: "Spread",
    title: "Every upgrade price at once, by area - where the gaps and the pile-ups are",
    mode: "price",
    curves: null,              // the /api/curves report
    trace: null,               // the /api/purchases report
    defs: [],
    hidden: new Set(),         // lane keys the reader has switched off
    currency: "",              // "" = every currency
    // The stretch of axis currently on screen, per mode, as [from, to] in log
    // space. Per mode because the two are not in the same units, so a viewport
    // panned over the prices means nothing on the run's clock. Null until the
    // first draw fits one - see openingViewport().
    viewports: { price: null, time: null },
    dom: {},
  };

  /* -------------------------------------------------------------- reading rows */

  /** A currency res_path as the word the rest of the report uses. The worker
   * table is the only place a currency arrives as a path rather than a name. */
  const currencyName = (value) => String(value || "")
    .split("/").pop().replace(/^res_/, "").replace(/_def\.tres$/, "");

  /** Every priced def in the report, each already reduced to the levels it
   * offers and what they cost.
   *
   * A worker's ladder is one def per currency rather than one def: the crew is
   * hired with two or three at once, and lumping them would draw a price that
   * nothing is ever charged. */
  function defsOf(report) {
    const out = [];
    for (const bucket of PRICED) {
      for (const [path, curve] of Object.entries(report[bucket] || {})) {
        if (bucket === "workers") {
          for (const price of curve.prices || []) {
            const name = currencyName(price.currency);
            out.push(defOf(path, curve, price.cost, name, ` · ${name}`));
          }
          continue;
        }
        if (Array.isArray(curve.cost)) out.push(defOf(path, curve, curve.cost, curve.currency, ""));
      }
    }
    return out;
  }

  /** One def as the chart reads it.
   *
   * `cost[i]` is what the game charges to leave level i, so it buys level i + 1
   * - which is why the levels below are one-based while the array is not.
   *
   * Every level the definition declares is kept, and only those: the sample past
   * a def's max_level is dropped because it is a price nothing can ever be asked
   * for, and an open-ended def (max_level 0) is however far BalanceData sampled
   * it, which is what "all its levels" means for something with no last one. */
  function defOf(path, curve, cost, currency, suffix) {
    const levels = [];
    cost.forEach((pair, index) => {
      const level = index + 1;
      if (curve.max_level > 0 && level > curve.max_level) return;
      const log10 = log10Of(pair[0], pair[1]);
      if (log10 !== null) levels.push({ level, log10, pair });
    });
    return {
      path, levels, currency,
      id: curve.id || "",
      area: curve.area || "unmapped",
      lane: curve.sub_area ? `${curve.area}:${curve.sub_area}` : (curve.area || "unmapped"),
      maxLevel: curve.max_level,
      label: path.split("/").pop().replace(/\.tres$/, "") + suffix,
    };
  }

  /** area/id#level -> the row the simulated run recorded for it. Levels are the
   * first time each was reached, so a purchase re-made after a prestige does not
   * overwrite the moment it first became affordable. */
  function purchaseIndex(trace) {
    const out = new Map();
    for (const row of (trace && trace.purchases) || []) {
      out.set(`${row.area}/${row.id}#${row.level}`, row);
    }
    return out;
  }

  /* -------------------------------------------------------------- the points */

  /** Every dot the current filters let through, as { x, def, level, ... }.
   *
   * `x` is whatever the mode measures, already in log space, so the axis is one
   * linear mapping either way. A level the run never bought has no x in time
   * mode and is dropped rather than drawn at zero. */
  function pointsFor(defs, options = {}) {
    const mode = options.mode || view.mode;
    const currency = options.currency !== undefined ? options.currency : view.currency;
    const bought = mode === "time" ? purchaseIndex(view.trace) : null;

    const out = [];
    for (const def of defs) {
      if (currency && def.currency !== currency) continue;
      for (const point of def.levels) {
        if (mode === "price") {
          out.push({ x: point.log10, def, level: point.level, cost: point.log10, pair: point.pair });
          continue;
        }
        const row = bought.get(`${def.area}/${def.id}#${point.level}`);
        if (!row) continue;
        // +1 so the first tick, at ten seconds, does not sit a decade from the
        // rest of them and stretch the axis over a moment nothing happens in.
        out.push({ x: Math.log10(row.seconds + 1), def, level: point.level,
          cost: point.log10, pair: point.pair, row });
      }
    }
    return out;
  }

  /** The lanes present in a set of points, in LANE_ORDER and then alphabetical,
   * each with its points and what they say about it.
   *
   * `viewport` is the stretch of axis on screen. A lane's statistics are taken
   * from the points inside it, and the ones outside are counted rather than
   * described: a gap measured across everything scrolled off to the right would
   * be the distance to numbers nobody is currently looking at. */
  function lanesOf(points, viewport) {
    const by = new Map();
    for (const point of points) {
      if (!by.has(point.def.lane)) by.set(point.def.lane, []);
      by.get(point.def.lane).push(point);
    }
    const rank = (lane) => {
      const at = LANE_ORDER.indexOf(lane.split(":")[0]);
      return at === -1 ? LANE_ORDER.length : at;
    };
    return [...by.entries()]
      .sort((a, b) => rank(a[0]) - rank(b[0]) || a[0].localeCompare(b[0]))
      .map(([lane, rows]) => ({
        lane,
        points: rows,
        before: rows.filter((point) => point.x < viewport[0]).length,
        after: rows.filter((point) => point.x > viewport[1]).length,
        ...statsOf(rows.filter((point) =>
          point.x >= viewport[0] && point.x <= viewport[1])),
      }));
  }

  /** What a lane's spread is worth saying out loud: the widest span it offers
   * nothing in, and how many things it offers at its busiest.
   *
   * The gap is measured between consecutive prices rather than against the whole
   * axis, so it is a real hole in *this* lane and not just the distance to where
   * the lane happens to start. A lane with one price has no gap to report. */
  function statsOf(points) {
    const xs = points.map((point) => point.x).sort((a, b) => a - b);
    if (!xs.length) return { gap: null, from: null, to: null, count: 0 };
    let gap = null;
    for (let i = 1; i < xs.length; i++) {
      if (gap === null || xs[i] - xs[i - 1] > gap.width) {
        gap = { from: xs[i - 1], to: xs[i], width: xs[i] - xs[i - 1] };
      }
    }
    return { gap, from: xs[0], to: xs.at(-1), count: xs.length };
  }

  /* ------------------------------------------------------------------ drawing */

  const exp10 = (value) => {
    const exponent = Math.floor(value);
    return formatBig(10 ** (value - exponent), exponent);
  };

  /** The tick spacing nearest `wanted`, off a ladder that keeps labels round in
   * log space: tenths of a decade at the bottom, whole decades and up above. */
  function niceStep(wanted) {
    for (const step of [0.1, 0.25, 0.5, 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000]) {
      if (step >= wanted) return step;
    }
    return Math.ceil(wanted);
  }


  /** An x value as the axis labels it: a power of ten when it is a price, a
   * duration when it is a moment in a run. */
  function axisLabel(value, mode) {
    if (mode === "price") {
      // A fractional decade is a real tick once the window is narrow, and
      // "1e12.5" is not a number anybody reads. Rounded to one place, and only
      // where the fraction is not noise.
      return Math.abs(value - Math.round(value)) < 0.05
        ? `1e${Math.round(value)}` : `1e${value.toFixed(1)}`;
    }
    const seconds = 10 ** value;
    if (seconds < 90) return `${Math.round(seconds)}s`;
    if (seconds < 5400) return `${Math.round(seconds / 60)}m`;
    return `${(seconds / 3600).toFixed(1)}h`;
  }

  /** The whole chart: one row per lane, a density histogram under them, and a
   * shared x axis.
   *
   * Points are drawn at low opacity and jittered off the lane's centre line by a
   * couple of pixels. Both are for the same reason: forty levels of one def land
   * within a pixel of each other on a log axis, and a single flat dot would
   * report that as one offer. */
  function chartOf(lanes, mode, width, viewport, bounds, onViewport) {
    const height = PAD.top + lanes.length * LANE_HEIGHT + HISTOGRAM_HEIGHT + PAD.bottom;
    const plotWidth = Math.max(120, width - PAD.left - PAD.right);
    const svg = svgEl("svg", { class: "spread-chart", viewBox: `0 0 ${width} ${height}`,
      width, height, preserveAspectRatio: "xMidYMid meet" });

    if (!lanes.some((row) => row.points.length)) return svg;
    const [lo, hi] = viewport;
    const span = hi - lo || 1;
    const x = (value) => PAD.left + ((value - lo) / span) * plotWidth;
    const inside = (value) => value >= lo && value <= hi;
    if (onViewport) attachNavigation(svg, width, plotWidth, viewport, bounds, onViewport);

    // Roughly a dozen gridlines however wide the viewport is. Steps come off a
    // nice-number ladder rather than being ceil()'d to whole powers of ten: a
    // simulated run spans about one decade of seconds, and zooming in far enough
    // would otherwise leave an axis with two labels on it.
    const step = niceStep(span / 12);
    for (let tick = Math.ceil(lo / step) * step; tick <= hi; tick += step) {
      svg.append(svgEl("line", { class: "spread-grid", x1: x(tick), x2: x(tick),
        y1: PAD.top - 6, y2: height - PAD.bottom + HISTOGRAM_HEIGHT }));
      const label = svgEl("text", { class: "axis", x: x(tick),
        y: height - PAD.bottom + HISTOGRAM_HEIGHT + 16 });
      label.setAttribute("text-anchor", "middle");
      label.textContent = axisLabel(tick, mode);
      svg.append(label);
    }

    lanes.forEach((row, index) => {
      const top = PAD.top + index * LANE_HEIGHT;
      const middle = top + LANE_HEIGHT / 2;
      const color = `hsl(${hueOf(index)} 60% 50%)`;

      if (index % 2 === 0) {
        svg.append(svgEl("rect", { class: "spread-lane-band", x: PAD.left, y: top,
          width: plotWidth, height: LANE_HEIGHT }));
      }

      // The widest span this lane offers nothing in, drawn before the dots so it
      // reads as ground rather than as a mark of its own. Only worth showing
      // when it is wide enough to be a hole rather than a rounding difference.
      if (row.gap && row.gap.width > span / 12) {
        const from = x(Math.max(row.gap.from, lo));
        const band = svgEl("rect", { class: "spread-gap", x: from, y: top + 3,
          width: Math.max(1, x(Math.min(row.gap.to, hi)) - from), height: LANE_HEIGHT - 6 });
        attachTip(band, `${row.lane}: nothing between ${axisLabel(row.gap.from, mode)} `
          + `and ${axisLabel(row.gap.to, mode)}`);
        svg.append(band);
      }

      const name = svgEl("text", { class: "spread-lane-name", x: PAD.left - 10, y: middle + 4 });
      name.setAttribute("text-anchor", "end");
      // What is scrolled off, on the side it is off. Counted rather than drawn:
      // with a pannable axis a dot pinned to the edge would be a price sitting
      // somewhere it is not, and one more notch of zoom would move it again.
      name.textContent = (row.before ? `◂${row.before} ` : "") + row.lane
        + (row.after ? ` ${row.after}▸` : "");
      attachTip(name, `${row.lane} · ${row.count} level${row.count === 1 ? "" : "s"} in view`
        + (row.before ? `, ${row.before} off to the left` : "")
        + (row.after ? `, ${row.after} off to the right` : ""));
      svg.append(name);

      row.points.forEach((point, at) => {
        if (!inside(point.x)) return;
        // Deterministic, so a redraw does not reshuffle the dots under the
        // pointer: the offset is the point's own position in the lane.
        const jitter = ((at % 5) - 2) * 2.2;
        const dot = svgEl("circle", { class: "spread-dot",
          cx: x(point.x), cy: middle + jitter, r: 2.6, fill: color });
        attachTip(dot, tipFor(point, mode));
        svg.append(dot);
      });
    });

    svg.append(...histogramOf(lanes, x, lo, span, plotWidth,
      PAD.top + lanes.length * LANE_HEIGHT));

    const axis = svgEl("text", { class: "axis-title", x: PAD.left + plotWidth / 2, y: height - 8 });
    axis.setAttribute("text-anchor", "middle");
    axis.textContent = `${MODES[mode].axis} (log) · lane height is one authored set`;
    svg.append(axis);
    return svg;
  }

  /** Wraps a redraw so a gesture can ask for one as often as it likes and get at
   * most one per frame, always with the latest value.
   *
   * A full redraw of the price view is around 50ms with nine thousand dots on
   * screen, and pointermove fires far more often than that. Without this a drag
   * queues up redraws it can never catch up with and the chart trails the
   * pointer by seconds; the intermediate ones were never going to be seen. */
  function coalesced(apply) {
    let queued = null;
    let waiting = false;
    return (value) => {
      queued = value;
      if (waiting) return;
      // Raised before the frame is asked for and lowered inside it, so the flag
      // is right whichever order those happen in. Assigning the handle returned
      // by requestAnimationFrame would clobber a callback that had already run.
      waiting = true;
      requestAnimationFrame(() => { waiting = false; apply(queued); });
    };
  }


  /** Wheel to zoom about the pointer, drag to pan.
   *
   * About the pointer rather than about the middle, because the thing being
   * looked at is under the pointer: zooming about the centre walks whatever that
   * is off the screen after two notches.
   *
   * Every one of these gestures redraws, which replaces this very svg - so a
   * drag captures its whole frame of reference up front (the rendered rectangle,
   * and the viewport as it stood when the pointer went down) and listens on the
   * window rather than on the element. Reading either back off the svg mid-drag
   * would be reading a node that has already been thrown away.
   *
   * The svg carries explicit width/height matching its viewBox, but CSS can
   * still scale it to fit a narrow panel, so a client x is converted through the
   * rendered rectangle rather than used as if it were a viewBox unit. */
  function attachNavigation(svg, width, plotWidth, [lo, hi], bounds, onViewport) {
    const span = hi - lo || 1;
    const push = coalesced(onViewport);
    /** Where a client x falls on the axis, given a rectangle measured earlier. */
    const dataAt = (clientX, box) => {
      const scale = box.width / width || 1;
      return lo + (((clientX - box.left) / scale) - PAD.left) / plotWidth * span;
    };

    svg.addEventListener("wheel", (event) => {
      // Otherwise the canvas it sits in scrolls too, and the chart walks off the
      // top of the view while it is being zoomed.
      event.preventDefault();
      const factor = event.deltaY > 0 ? ZOOM_STEP : 1 / ZOOM_STEP;
      const at = dataAt(event.clientX, svg.getBoundingClientRect());
      push(clampViewport([at - (at - lo) * factor, at + (hi - at) * factor], bounds));
    }, { passive: false });

    svg.addEventListener("pointerdown", (event) => {
      // Left button only: a middle-click drag is the browser's autoscroll and a
      // right-click is the context menu, and hijacking either is a surprise.
      if (event.button !== 0) return;
      event.preventDefault();
      const box = svg.getBoundingClientRect();
      const from = dataAt(event.clientX, box);
      // On the body, because the svg holding it is replaced on the first move.
      document.body.classList.add("spread-panning");

      const move = (moved) => {
        const shift = from - dataAt(moved.clientX, box);
        push(clampViewport([lo + shift, hi + shift], bounds));
      };
      const up = () => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
        window.removeEventListener("pointercancel", up);
        document.body.classList.remove("spread-panning");
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up);
      window.addEventListener("pointercancel", up);
    });
  }


  /** The stretch of axis to open on: everything, unless the tail is so long that
   * opening on all of it would show nothing.
   *
   * A cost_growth_exponent above 1 makes a price doubly exponential
   * (UpgradeSystem.cost()), so perks:reach passes 1e15000 inside its authored
   * levels while the biome lanes never leave 1e2. Drawn end to end, twenty lanes
   * collapse into the leftmost pixel. Opening on the bulk instead is a starting
   * place, not a limit - the axis pans and zooms, and "Fit all" is one click.
   *
   * The three-quarter mark rather than a rounder one because it is what leaves
   * the biome, well and ruins lanes readable against the perk ladders in the
   * current data; it stops mattering the moment the reader scrolls. */
  function openingViewport(values) {
    const sorted = [...values].sort((a, b) => a - b);
    const lo = sorted[0];
    const hi = sorted.at(-1);
    // Already narrow: nothing here can squash anything, and opening on part of a
    // screen whose prices span a third of a decade only hides some of them.
    if (hi - lo <= NARROW_ENOUGH) return [lo, hi];
    const bulk = sorted[Math.floor(sorted.length * 0.75)];
    return [lo, bulk > lo ? bulk : hi];
  }


  /** The viewport to draw with, resolving what the reader last asked for.
   *
   * Null is "wherever this opens", the string "fit" is the Fit all button, and
   * anything else is a stretch they panned or zoomed to - re-clamped against the
   * current bounds, because hiding a lane or switching currency can move them
   * out from under a viewport that was fine a moment ago. */
  function viewportFor(asked, xs, bounds) {
    if (!xs.length) return [0, 1];
    if (asked === "fit") return bounds[1] > bounds[0] ? bounds : [bounds[0], bounds[0] + 1];
    if (!asked) return openingViewport(xs);
    return clampViewport(asked, bounds);
  }


  /** A viewport kept sane: never narrower than MIN_SPAN, never scrolled so far
   * off the data that the chart is empty with no way back. */
  function clampViewport([lo, hi], bounds) {
    const full = Math.max(MIN_SPAN, bounds[1] - bounds[0]);
    const span = Math.min(Math.max(hi - lo, MIN_SPAN), full * 1.5);
    // Half a screen of overscroll at each end, so the outermost dot can be
    // dragged clear of the axis labels but the data can never leave entirely.
    const from = Math.min(Math.max(lo, bounds[0] - span / 2), bounds[1] - span / 2);
    return [from, from + span];
  }

  /** Offers per bucket across every lane at once, so a range several areas all
   * crowd into shows as one tall column instead of having to be counted across
   * rows. */
  function histogramOf(lanes, x, lo, span, plotWidth, top) {
    const counts = new Array(BUCKETS).fill(0);
    for (const row of lanes) {
      for (const point of row.points) {
        // Only what is on screen. The histogram describes the stretch of axis
        // being looked at, so it has to be recounted as that stretch moves.
        if (point.x < lo || point.x > lo + span) continue;
        const at = Math.min(BUCKETS - 1, Math.max(0,
          Math.floor(((point.x - lo) / span) * BUCKETS)));
        counts[at] += 1;
      }
    }
    const tallest = Math.max(...counts, 1);
    const barWidth = plotWidth / BUCKETS;
    return counts.map((count, index) => {
      const barHeight = (count / tallest) * (HISTOGRAM_HEIGHT - 6);
      const bar = svgEl("rect", { class: "spread-bar",
        x: PAD.left + index * barWidth + 0.5,
        y: top + HISTOGRAM_HEIGHT - barHeight,
        width: Math.max(1, barWidth - 1), height: Math.max(0, barHeight) });
      attachTip(bar, `${count} level${count === 1 ? "" : "s"} offered around `
        + `${axisLabel(lo + ((index + 0.5) / BUCKETS) * span, view.mode)}`);
      return bar;
    });
  }

  function tipFor(point, mode) {
    const lines = [`${point.def.label} · level ${point.level}`, `lane ${point.def.lane}`];
    lines.push(`costs ${exp10(point.cost)}${point.def.currency ? ` ${point.def.currency}` : ""}`);
    if (mode === "time" && point.row) {
      lines.push(`first bought ${axisLabel(point.x, "time")} in, `
        + `after ${point.row.prestige} prestige${point.row.prestige === 1 ? "" : "s"}`);
    }
    return lines.join("\n");
  }

  /* ----------------------------------------------------------------- findings */

  /** The chart said in words, worst first: the lanes with the widest holes, and
   * the range the most areas crowd into.
   *
   * Here because the whole point of the view is a judgement - "permafrost is
   * missing a tier here" - and a judgement read off pixels is one nobody can
   * quote in a commit message. */
  function findingsOf(lanes, mode) {
    const out = [];
    const inside = lanes.filter((row) => row.count > 0);
    const span = inside.length ? Math.max(...inside.map((row) => row.to))
      - Math.min(...inside.map((row) => row.from)) : 0;

    const empty = lanes.filter((row) => !row.count);
    if (empty.length) {
      out.push(`${empty.map((row) => row.lane).join(", ")}: nothing at all inside the window`
        + ` - every price they offer is past its right edge`);
    }

    const holes = inside.filter((row) => row.gap && row.gap.width > span / 12)
      .sort((a, b) => b.gap.width - a.gap.width).slice(0, 5);
    for (const row of holes) {
      out.push(`${row.lane} offers nothing between ${axisLabel(row.gap.from, mode)} `
        + `and ${axisLabel(row.gap.to, mode)}`);
    }

    // A bucket several lanes land in at once, which is the other half of the
    // question: not a hole, a heap.
    const crowd = new Map();
    for (const row of inside) {
      for (const point of row.points) {
        const at = Math.round(point.x * 2) / 2;
        if (!crowd.has(at)) crowd.set(at, new Set());
        crowd.get(at).add(row.lane);
      }
    }
    const busiest = [...crowd.entries()].sort((a, b) => b[1].size - a[1].size)[0];
    if (busiest && busiest[1].size > 2) {
      out.push(`${busiest[1].size} areas all offer something around `
        + `${axisLabel(busiest[0], mode)}: ${[...busiest[1]].join(", ")}`);
    }
    return out;
  }

  /* -------------------------------------------------------------- embed / API */

  /** The same chart with no panel, filtered to the areas a screen owns: what a
   * game screen embeds so its own prices can be read against each other and
   * against the run.
   *
   * Filtered by area rather than by a list of res_paths, because AREAS was
   * derived from the tracks App builds and a screen is one of those tracks. A
   * screen that grows a row keeps a correct strip without touching this; a list
   * of paths would quietly go stale.
   *
   * Returns an element with its own `refresh()`, so a screen can hand it to a
   * <details> and forget about it. */
  function strip(areas, options = {}) {
    const wanted = new Set(areas);
    const wrap = document.createElement("div");
    wrap.className = "spread-strip";

    wrap.refresh = () => {
      wrap.replaceChildren();
      if (!view.defs.length) {
        const hint = document.createElement("p");
        hint.className = "hint";
        hint.textContent = "Open the Spread view once to load the price report.";
        wrap.append(hint);
        return;
      }
      const defs = view.defs.filter((def) => wanted.has(def.area));
      const mode = options.mode || "price";
      const points = pointsFor(defs, { mode, currency: "" });
      // Its own viewport, off its own points: a screen is being read on its own
      // terms, and borrowing the whole game's would leave a screen of cheap
      // things squashed against the left edge of somebody else's tail.
      const xs = points.map((point) => point.x);
      const bounds = xs.length ? [Math.min(...xs), Math.max(...xs)] : [0, 1];
      const viewport = viewportFor(options.viewport, xs, bounds);
      const lanes = lanesOf(points, viewport);
      if (!lanes.length) {
        const hint = document.createElement("p");
        hint.className = "hint";
        hint.textContent = mode === "time"
          ? "The last simulated run never bought any of these."
          : "None of these rows carry a price.";
        wrap.append(hint);
        return;
      }
      wrap.append(modeButtons(mode, (next) => {
        // A viewport panned over the prices means nothing on the run's clock.
        options.mode = next;
        options.viewport = null;
        wrap.refresh();
      }));
      wrap.append(chartOf(lanes, mode, options.width || 900, viewport, bounds, (next) => {
        options.viewport = next;
        wrap.refresh();
      }));
      wrap.append(findingsList(findingsOf(lanes, mode)));
    };

    wrap.refresh();
    return wrap;
  }

  /** A screen's strip, folded away until asked for.
   *
   * Collapsed by default and drawn on first open: every screen gets one, and a
   * screen that opens should look the way it always did until the reader asks
   * this question. The report is only fetched by the Spread view's own open(),
   * so a strip opened before that has been visited says so rather than drawing
   * an empty chart. */
  function section(areas, title = "Price spread") {
    const details = document.createElement("details");
    details.className = "game-unused spread-section";
    const summary = document.createElement("summary");
    summary.textContent = `${title} (where these prices land, and what a run reaches)`;
    const body = strip(areas, { width: 860 });
    details.append(summary, body);
    details.ontoggle = () => { if (details.open) body.refresh(); };
    return details;
  }


  function modeButtons(active, onPick) {
    const row = document.createElement("div");
    row.className = "spread-modes";
    for (const [key, mode] of Object.entries(MODES)) {
      const button = document.createElement("button");
      button.textContent = mode.label;
      button.className = key === active ? "active" : "";
      const traced = (view.trace && view.trace.purchases || []).length;
      if (key === "time" && !traced) {
        button.disabled = true;
        button.title = "Run a simulation first - the time axis is what that run bought";
      }
      button.onclick = () => onPick(key);
      row.append(button);
    }
    return row;
  }

  function findingsList(findings) {
    const list = document.createElement("ul");
    list.className = "spread-findings";
    if (!findings.length) {
      const item = document.createElement("li");
      item.className = "hint";
      item.textContent = "No lane has a hole worth naming at this scale.";
      list.append(item);
      return list;
    }
    for (const text of findings) {
      const item = document.createElement("li");
      item.textContent = text;
      list.append(item);
    }
    return list;
  }

  /* -------------------------------------------------------------------- panel */

  function renderPanel(panel) {
    panel.replaceChildren();
    panel.append(modeButtons(view.mode, (next) => { view.mode = next; refresh(); }));

    const currencies = [...new Set(view.defs.map((def) => def.currency).filter(Boolean))].sort();
    const picker = document.createElement("select");
    picker.className = "spread-currency";
    for (const [value, label] of [["", "every currency"], ...currencies.map((c) => [c, c])]) {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      option.selected = value === view.currency;
      picker.append(option);
    }
    picker.onchange = () => { view.currency = picker.value; refresh(); };
    panel.append(labelled("Currency", picker,
      "In price mode a nutrient and a biomass price are not the same moment. "
      + "Pick one to compare like with like."));

    const zoom = document.createElement("div");
    zoom.className = "spread-modes";
    const fit = document.createElement("button");
    fit.textContent = "Fit all";
    fit.title = "Every price on screen at once, however far the longest ladder runs";
    fit.onclick = () => { view.viewports[view.mode] = "fit"; refresh(); };
    const reset = document.createElement("button");
    reset.textContent = "Reset";
    reset.title = "Back to the stretch this view opens on";
    reset.onclick = () => { view.viewports[view.mode] = null; refresh(); };
    zoom.append(fit, reset);
    panel.append(labelled("Axis", zoom,
      "Wheel to zoom about the pointer, drag to pan. It opens on the bulk of the "
      + "prices rather than all of them: a cost_growth_exponent above 1 makes a "
      + "price doubly exponential, so a few ladders run to 1e15000 while the biome "
      + "lanes never leave 1e2, and end to end that is one pixel of chart. "
      + "Anything scrolled off is counted beside its lane name."));

    const lanes = [...new Set(view.defs.map((def) => def.lane))].sort();
    const list = document.createElement("div");
    list.className = "spread-lane-list";
    for (const lane of lanes) {
      const row = document.createElement("label");
      row.className = "spread-lane-row";
      const box = document.createElement("input");
      box.type = "checkbox";
      box.checked = !view.hidden.has(lane);
      box.onchange = () => {
        box.checked ? view.hidden.delete(lane) : view.hidden.add(lane);
        refresh();
      };
      const name = document.createElement("span");
      name.textContent = lane;
      row.append(box, name);
      list.append(row);
    }
    panel.append(labelled("Lanes", list, ""));

    view.dom.findings = document.createElement("div");
    view.dom.findings.className = "spread-findings-slot";
    panel.append(view.dom.findings);
  }

  function labelled(text, control, hint) {
    const wrap = document.createElement("div");
    wrap.className = "spread-field";
    const label = document.createElement("span");
    label.className = "spread-field-label";
    label.textContent = text;
    wrap.append(label, control);
    if (hint) {
      const note = document.createElement("span");
      note.className = "hint";
      note.textContent = hint;
      wrap.append(note);
    }
    return wrap;
  }

  /* ------------------------------------------------------------------- wiring */

  /** Redraws the chart and the findings, leaving the panel alone: ticking a lane
   * off is not a reason to rebuild the list it lives in. */
  function refresh() {
    const canvas = view.element.querySelector(".spread-canvas");
    canvas.replaceChildren();

    const defs = view.defs.filter((def) => !view.hidden.has(def.lane));
    const points = pointsFor(defs);
    const xs = points.map((point) => point.x);
    const bounds = xs.length ? [Math.min(...xs), Math.max(...xs)] : [0, 1];
    const viewport = viewportFor(view.viewports[view.mode], xs, bounds);
    const lanes = lanesOf(points, viewport);
    if (!lanes.length) {
      const hint = document.createElement("p");
      hint.className = "hint";
      hint.textContent = view.mode === "time"
        ? "The last simulated run bought nothing that is currently shown. "
          + "Run a longer one, or switch back to price."
        : "Nothing to plot. Every lane is switched off, or no priced def survived the filter.";
      canvas.append(hint);
      setStatus("spread: nothing to plot");
      return;
    }

    const findings = findingsOf(lanes, view.mode);
    canvas.append(chartOf(lanes, view.mode, Math.max(640, canvas.clientWidth - 24),
      viewport, bounds, (next) => { view.viewports[view.mode] = next; refresh(); }));
    if (view.dom.findings) {
      view.dom.findings.replaceChildren(findingsList(findings));
    }

    const shown = lanes.reduce((total, row) => total + row.count, 0);
    const off = lanes.reduce((total, row) => total + row.before + row.after, 0);
    const traced = ((view.trace && view.trace.purchases) || []).length;
    setStatus(`${shown} of ${points.length} price points across ${lanes.length} lanes`
      + ` · ${axisLabel(viewport[0], view.mode)} to ${axisLabel(viewport[1], view.mode)}`
      + (off ? `, ${off} off screen` : "")
      + (view.mode === "time" ? ` · from a run of ${traced} recorded purchases` : "")
      + (findings.length ? ` · ${findings.length} finding${findings.length === 1 ? "" : "s"}` : ""));
  }

  /** Re-reads both reports. The curves report is cached server-side and dropped
   * whenever the data changes, so this is cheap unless something was saved; the
   * purchase trace only moves when a simulation is run. */
  view.invalidate = async () => {
    view.curves = await api("/api/curves");
    view.trace = await api("/api/purchases");
    view.defs = defsOf(view.curves);
  };

  view.open = async () => {
    await view.invalidate();
  };

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "spread-view";
    wrap.innerHTML = `<div class="spread-canvas"></div><aside class="spread-panel"></aside>`;
    return wrap;
  };

  view.render = () => {
    renderPanel(view.element.querySelector(".spread-panel"));
    refresh();
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.spread = view;
  // The screens reach the strip through window.GameKit, which game.js builds -
  // but game.js has already run by the time this file does, so the re-export is
  // written here rather than read there.
  window.BalanceSpread = { strip, section };
  window.GameKit.spreadStrip = strip;
  window.GameKit.spreadSection = section;
})();
