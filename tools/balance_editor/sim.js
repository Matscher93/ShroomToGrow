/* Simulator view: how long the authored numbers take to play.
 *
 * POST /api/sim runs tools/sc_balance_sim.tscn headlessly, which drives the real
 * App through a scripted shopping policy and reports two things: a downsampled
 * trace of the run, and the ticks worth naming (a biome unlocked, a prestige
 * taken). Everything unbounded arrives as log10, which is what a chart wants.
 *
 * It also reports, unless asked not to, a bonus breakdown: what every levelled
 * upgrade is contributing and what the run would lose without it. The page
 * regroups that resource first - every bonus feeding nutrients together, every
 * one shortening the tick together. See breakdownSection().
 *
 * A run takes seconds to minutes, so nothing here happens until the button is
 * pressed. Saved edits are picked up automatically - the simulator reads the
 * .tres files, not this page's state - but unsaved ones are not, and the panel
 * says so when the editor is dirty.
 *
 * Registered on window.BalanceViews, which index.html turns into a view button.
 */
(() => {
  const TRACKS = {
    production: { label: "Production / tick", log: true },
    nutrients: { label: "Nutrients", log: true },
    biomass: { label: "Biomass", log: true },
    // The Caves' currency and the Well's. Both are held rather than produced -
    // crystals only arrive on an achievement claim, water only on a pump - so a
    // sawtooth here is the run spending them and a plateau is it saving up.
    crystals: { label: "Crystals", log: true },
    water: { label: "Water", log: true },
    nodes: { label: "Nodes bought", log: false },
    symbiosis: { label: "Symbiosis levels", log: false },
    biome_upgrades: { label: "Biome upgrade levels", log: false },
    perks: { label: "Perk levels", log: false },
    boosts: { label: "Boost levels", log: false },
    well_projects: { label: "Well fundings", log: false },
    // The account ladder. `player_level` is what lifetime nutrients have earned,
    // `level_points` what the policy has spread across the four producers - they
    // only part company when a run earns points faster than it spends them.
    player_level: { label: "Player level", log: false },
    level_points: { label: "Level Points spent", log: false },
    // What a tick is worth in real seconds. Every &"tick_rate" upgrade shortens
    // it, and the perks doing that outlive a prestige, so this is where a run
    // shows itself getting faster rather than just richer.
    tick_duration: { label: "Tick duration", log: false, unit: " (seconds)" },
    // Ticks between pumps. Goes the same way and for the same reason: every
    // &"water_rate" upgrade shortens it, down to WaterSystem.MIN_INTERVAL.
    water_interval: { label: "Pump interval", log: false, unit: " (ticks)" },
  };

  /** Seconds as a span someone can judge. Mirrors BalanceSim.format_duration. */
  function duration(seconds) {
    const total = Math.round(seconds || 0);
    if (total < 60) return `${total}s`;
    if (total < 3600) return `${Math.floor(total / 60)}m ${total % 60}s`;
    if (total < 86400) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`;
    return `${Math.floor(total / 86400)}d ${Math.floor((total % 86400) / 3600)}h`;
  }

  const view = {
    label: "Sim",
    title: "Run the game headlessly and see how long things take",
    settings: { ticks: 20000, policy: "roi", prestiges: 3, samples: 200,
      breakdowns: "milestones" },
    result: null,
    running: false,
    /** Latest /api/sim/progress reading, or null when nothing is running. */
    progress: null,
    /** Where the next run starts: null for a fresh one, otherwise
     * `{save, tick, seconds, label}` from an imported file or a savepoint. */
    start: null,
    shown: new Set(["production", "nodes", "perks"]),
    /** Which bonus breakdown the table shows: -1 for the run's end, otherwise an
     * index into result.breakdowns. Kept on the view so a progress redraw or a
     * track toggle does not throw the choice away. */
    breakdownAt: -1,
    breakdownOpen: false,
    /** Which resource groups in the breakdown are open. Kept by name rather than
     * by index: a redraw rebuilds every one of them, and a new run can leave a
     * resource out entirely. */
    breakdownOpenGroups: new Set(),
    /** The stretch of ticks the chart is showing, or null for the whole run.
     * Wheel, drag and double-click move it; nothing else reads it. */
    zoom: null,
    /** Index into result.milestones of the one under the pointer, in either the
     * chart or the list - hovering one lights up the other. Null for none. */
    hoverMilestone: null,
  };

  const hueOf = (index) => (index * 53) % 360;

  /* ------------------------------------------------------------------ drawing */

  const CHART = { width: 900, left: 74, right: 90, rowHeight: 132, gap: 10, axis: 26 };

  /** One panel per track, stacked and sharing the tick axis.
   *
   * They are not drawn on top of each other because they have no common scale:
   * production is a log10 of a BigNumber and node count is a count. Sharing an
   * axis would mean normalising both into a 0-1 band, which is what makes a
   * chart pretty and useless - the numbers are the whole point here, so each
   * panel keeps its own labelled axis. */
  function drawRun() {
    const tracks = [...view.shown];
    const series = view.result ? view.result.series : [];
    const height = tracks.length * (CHART.rowHeight + CHART.gap) + CHART.axis;
    const svg = svgEl("svg", { id: "sim-chart",
      viewBox: `0 0 ${CHART.width} ${Math.max(height, 120)}` });

    if (series.length < 2 || !tracks.length) {
      const empty = svgEl("text", { x: CHART.width / 2, y: 60, class: "empty" });
      empty.setAttribute("text-anchor", "middle");
      empty.textContent = !tracks.length ? "pick a track on the right"
        : view.result ? "the run ended before it could be sampled - raise samples"
        : "press Run";
      svg.append(empty);
      return svg;
    }

    const plotWidth = CHART.width - CHART.left - CHART.right;
    const firstTick = Math.max(1, series[0].tick);
    const lastTick = series.at(-1).tick;

    // A long run spends most of its ticks on the last flat stretch, so a linear
    // tick axis squeezes everything interesting - the first biome, the first
    // prestige - into the leftmost pixels. Past a thousandfold spread the axis
    // goes log and those early ticks get room again.
    //
    // Decided by the whole run rather than by whatever is zoomed into, so that
    // zooming moves the window and never the kind of axis under it - a chart that
    // changed shape as it was scrolled would be unreadable.
    const logX = lastTick / firstTick > Math.pow(10, LOG_X_DECADES);
    const bounds = { from: logX ? firstTick : 0, to: lastTick };
    const shown = view.zoom || bounds;
    const span = Math.log10(shown.to) - Math.log10(Math.max(shown.from, 1));
    const x = logX
      ? (tick) => CHART.left
        + ((Math.log10(Math.max(tick, shown.from)) - Math.log10(shown.from)) / span) * plotWidth
      : (tick) => CHART.left + ((tick - shown.from) / (shown.to - shown.from)) * plotWidth;
    // The inverse, for a wheel that has to know which tick it is pointing at.
    const tickAt = logX
      ? (px) => Math.pow(10, Math.log10(shown.from) + ((px - CHART.left) / plotWidth) * span)
      : (px) => shown.from + ((px - CHART.left) / plotWidth) * (shown.to - shown.from);

    tracks.forEach((key, index) => {
      const top = index * (CHART.rowHeight + CHART.gap);
      svg.append(drawTrack(key, index, series, x, top, plotWidth, shown));
    });

    const axisY = tracks.length * (CHART.rowHeight + CHART.gap) + 12;
    // Deduplicated after rounding: zoomed in far enough, two marks a fraction of
    // a tick apart round to the same number and print on top of each other.
    let printed = null;
    for (const tick of tickMarks(shown.from, shown.to, logX)) {
      const text = String(Math.round(tick));
      if (text === printed) continue;
      printed = text;
      const label = svgEl("text", { class: "axis", x: x(tick), y: axisY });
      label.setAttribute("text-anchor", "middle");
      label.textContent = text;
      svg.append(label);
    }
    const title = svgEl("text", { class: "axis-title", x: CHART.left + plotWidth / 2, y: axisY + 12 });
    title.setAttribute("text-anchor", "middle");
    title.textContent = `tick${logX ? " · log scale" : ""} · dashed lines are milestones`
      + (view.zoom
        ? ` · showing ${Math.round(shown.from)}-${Math.round(shown.to)}, double-click to reset`
        : " · wheel to zoom, drag to pan, shift-wheel to scroll");
    svg.append(title);
    zoomable(svg, tickAt, plotWidth, bounds, logX);
    return svg;
  }

  /** Wheel to zoom about the cursor, drag to pan, double-click to reset.
   *
   * Every one of them moves view.zoom and redraws the chart alone: the panel
   * beside it holds the form and a few hundred breakdown rows, and rebuilding
   * that on a wheel notch would drop frames for no reason.
   *
   * The y axes come along by themselves - drawTrack() scales each panel to the
   * points still in the window - which is the point of zooming into a chart whose
   * tracks span twenty decades. */
  function zoomable(svg, tickAt, plotWidth, bounds, logX) {
    svg.addEventListener("wheel", (event) => {
      // Shift is the way out: thirteen tracks make a chart taller than the canvas
      // it sits in, and a wheel that only ever zoomed would leave no way to reach
      // the bottom of it.
      if (event.shiftKey) return;
      // Not passive: a wheel over the chart is a zoom, not a page scroll.
      event.preventDefault();
      const at = tickAt(svgX(svg, event.clientX));
      view.zoom = zoomedTo(view.zoom || bounds, at, event.deltaY < 0 ? 1 / ZOOM_STEP : ZOOM_STEP,
        bounds, logX);
      redrawChart();
    }, { passive: false });

    svg.addEventListener("pointerdown", (event) => {
      const box = svg.getBoundingClientRect();
      panning = { at: svgX(svg, event.clientX), from: view.zoom || bounds,
        left: box.left, width: box.width, plotWidth, bounds, logX };
      // No pointer capture: the first pan redraws the chart, and this element is
      // out of the document before the next move arrives - a capture on it would
      // be released the moment it went. The listeners below are on the document
      // for the same reason, which is also what keeps a drag that wanders off the
      // chart working.
      event.preventDefault();
    });
    svg.addEventListener("dblclick", () => { view.zoom = null; redrawChart(); });
  }

  /** The pan in progress, if any. Outside drawRun() because the chart it started
   * on is replaced by its own first move. */
  let panning = null;

  document.addEventListener("pointermove", (event) => {
    if (!panning) return;
    const px = panning.width
      ? (event.clientX - panning.left) * (CHART.width / panning.width) : panning.at;
    const moved = (px - panning.at) / panning.plotWidth;
    if (!moved) return;
    view.zoom = pannedBy(panning.from, -moved, panning.bounds, panning.logX);
    redrawChart();
  });
  document.addEventListener("pointerup", () => { panning = null; });
  document.addEventListener("pointercancel", () => { panning = null; });

  /** Redraws the chart and nothing else. The panel beside it holds the form and a
   * few hundred breakdown rows, and rebuilding that on a wheel notch would drop
   * frames for no reason. */
  function redrawChart() {
    const canvas = view.element && view.element.querySelector(".sim-canvas");
    if (canvas) canvas.replaceChildren(drawRun());
  }

  /** How far one wheel notch moves the window. */
  const ZOOM_STEP = 1.3;

  /** The smallest window a zoom will leave: a thousandth of the run on a linear
   * axis, a fiftieth of a decade on a log one. Past that there is nothing left to
   * see - the run was only sampled a few hundred times. Never fewer than a couple
   * of ticks either, which is what a thousandth of a seventy-tick run would be. */
  const MIN_LINEAR_SPAN = 1 / 1000;
  const MIN_LINEAR_TICKS = 2;
  const MIN_LOG_SPAN = 0.02;

  /** A mouse position in the chart's own coordinates. The SVG scales to whatever
   * width the canvas gives it, so a client x has to be scaled back into the 900
   * units the viewBox is drawn in. */
  function svgX(svg, clientX) {
    const box = svg.getBoundingClientRect();
    return box.width ? (clientX - box.left) * (CHART.width / box.width) : 0;
  }

  /** `window` scaled by `factor` about the tick under the cursor, so the point
   * being pointed at stays under the pointer. Null once it covers the whole run
   * again, which is what "not zoomed" is stored as. */
  function zoomedTo(window, at, factor, bounds, logX) {
    const [from, to, low, high] = logSpace([window.from, window.to, bounds.from, bounds.to], logX);
    const whole = high - low;
    const floor = logX ? MIN_LOG_SPAN : Math.max(whole * MIN_LINEAR_SPAN, MIN_LINEAR_TICKS);
    const span = Math.min(Math.max((to - from) * factor, floor), whole);
    if (span >= whole) return null;
    const centre = logX ? Math.log10(Math.max(at, 1)) : at;
    const start = centre - (centre - from) * (span / (to - from));
    return clamped(start, start + span, low, high, logX);
  }

  /** `window` slid along by `moved` of its own width. */
  function pannedBy(window, moved, bounds, logX) {
    const [from, to, low, high] = logSpace([window.from, window.to, bounds.from, bounds.to], logX);
    const step = (to - from) * moved;
    return clamped(from + step, to + step, low, high, logX);
  }

  /** Both ends in the space the axis is drawn in, so one piece of arithmetic
   * serves a log axis and a linear one. */
  function logSpace(values, logX) {
    return logX ? values.map((value) => Math.log10(Math.max(value, 1))) : values;
  }

  /** A window pushed back inside the run it belongs to, keeping its width, and
   * handed back in tick space. */
  function clamped(from, to, low, high, logX) {
    let start = from;
    if (start < low) start = low;
    if (start + (to - from) > high) start = high - (to - from);
    const end = start + (to - from);
    return logX
      ? { from: Math.pow(10, start), to: Math.pow(10, end) }
      : { from: start, to: end };
  }

  /** How many times over the run has to grow before the tick axis goes log. */
  const LOG_X_DECADES = 3;

  /** Where the tick axis is labelled: whole decades on a log axis, eight even
   * steps on a linear one, across whatever stretch is being shown. A log axis
   * always calls out its right-hand end too - zoomed out that is the tick the run
   * finished on, and a decade label alone would never land there. */
  function tickMarks(first, last, logX) {
    const marks = [];
    if (logX) {
      for (let decade = Math.ceil(Math.log10(first)); decade <= Math.log10(last); decade++) {
        marks.push(Math.pow(10, decade));
      }
      // Zoomed inside a decade or two there are no whole decades to label, or one
      // stranded in the middle. Six evenly spaced marks instead - evenly along the
      // axis, which is a constant ratio apart on this one.
      if (marks.length < 3) {
        const steps = 5;
        const ratio = Math.pow(last / first, 1 / steps);
        return Array.from({ length: steps + 1 }, (_, step) => first * Math.pow(ratio, step));
      }
      if (marks.at(-1) !== last) marks.push(last);
      return marks;
    }
    const step = (last - first) / 8;
    if (step <= 0) return [last];
    for (let tick = first; tick <= last + step / 2; tick += step) marks.push(tick);
    return marks;
  }

  /** One track's panel: its own y axis, its own three labelled gridlines, and
   * the milestone lines running through it. */
  function drawTrack(key, index, series, x, top, plotWidth, shown) {
    const track = TRACKS[key];
    const group = svgEl("g");
    const plotTop = top + 16;
    const plotHeight = CHART.rowHeight - 22;
    const points = inWindow(series
      .map((sample) => ({ tick: sample.tick, value: sample[key] }))
      .filter((point) => typeof point.value === "number"), shown);

    if (points.length < 2) {
      const name = svgEl("text", { class: "axis-title", x: CHART.left, y: top + 10 });
      name.textContent = track.label;
      const none = svgEl("text", { class: "axis", x: CHART.left + 8, y: plotTop + plotHeight / 2 });
      // Two different nothings: a track that never moved, and a zoom window that
      // happens to hold no sample of it.
      none.textContent = view.zoom ? "nothing sampled in this stretch" : "never left zero";
      group.append(name, none);
      return group;
    }

    // Plotted in log10 whenever the track covers more than a couple of decades,
    // which is most of them once a run gets going: on a linear axis a run that
    // ends at 1e9 draws its first 1e6 ticks flat against the bottom.
    //
    // Production, nutrients and biomass already arrive as log10 from the
    // simulator, so they are on a log axis by construction. A count is logged
    // here, once, from the range the whole series covers.
    const logged = track.log || spansDecades(points.map((point) => point.value));
    const scaled = track.log || !logged
      ? points
      : points.map((point) => ({ tick: point.tick, value: Math.log10(point.value) }));
    if (scaled.length < 2) return group;

    const name = svgEl("text", { class: "axis-title", x: CHART.left, y: top + 10 });
    name.textContent = track.label
      + (logged ? " · log scale" : track.log ? "" : (track.unit || " (count)"));
    group.append(name);

    const values = scaled.map((point) => point.value);
    let min = Math.min(...values);
    let max = Math.max(...values);
    if (max - min < 1e-9) { min -= 0.5; max += 0.5; }   // a flat track still needs a band
    const y = (value) => plotTop + (1 - (value - min) / (max - min)) * plotHeight;

    for (const at of ticksFor(min, max, logged)) {
      group.append(svgEl("line", { class: "grid", x1: CHART.left, x2: CHART.left + plotWidth,
        y1: y(at), y2: y(at) }));
      const label = svgEl("text", { class: "axis", x: CHART.left - 6, y: y(at) + 3 });
      label.setAttribute("text-anchor", "end");
      label.textContent = format(at, logged);
      group.append(label);
    }

    view.result.milestones.forEach((milestone, index) => {
      if (milestone.tick < shown.from || milestone.tick > shown.to) return;
      const at = x(milestone.tick);
      const line = svgEl("line", { class: milestoneClass(index), "data-milestone": index,
        x1: at, x2: at, y1: plotTop, y2: plotTop + plotHeight });
      // A dashed hairline is a hard thing to point at, so the pointer gets a wide
      // invisible one over it. It carries the same index, so it lights up with
      // the line it stands in for.
      const hit = svgEl("line", { class: "milestone-hit", "data-milestone": index,
        x1: at, x2: at, y1: plotTop, y2: plotTop + plotHeight });
      const label = svgEl("title");
      label.textContent = `${milestone.event} · tick ${milestone.tick}`
        + (milestone.detail ? ` · ${milestone.detail}` : "");
      hit.append(label);
      hit.addEventListener("mouseenter", () => hoverMilestone(index));
      hit.addEventListener("mouseleave", () => hoverMilestone(null));
      group.append(line, hit);
    });

    // Clipped to its own panel: the two points that hold the line up at the edges
    // of the window sit outside it, and an unclipped line would run out over the
    // axis labels and the next panel down.
    const clip = svgEl("clipPath", { id: `sim-clip-${index}` });
    clip.append(svgEl("rect", { x: CHART.left, y: plotTop, width: plotWidth, height: plotHeight }));
    group.append(clip);

    const color = `hsl(${hueOf(index)} 65% 50%)`;
    const path = scaled.map((point, i) =>
      `${i ? "L" : "M"}${x(point.tick).toFixed(1)} ${y(point.value).toFixed(1)}`).join(" ");
    group.append(svgEl("path", { class: "track", d: path, stroke: color,
      "clip-path": `url(#sim-clip-${index})` }));

    // The number the line stops on, spelled out where it stops, so the panel
    // answers "how much" without anyone reading the axis. Zoomed in that is the
    // right-hand edge of the window rather than the end of the run, which is the
    // number being looked at either way.
    const last = scaled.at(-1);
    const final = svgEl("text", { class: "axis", x: CHART.left + plotWidth + 6, y: y(last.value) + 3,
      fill: color });
    final.textContent = format(last.value, logged);
    group.append(final);
    return group;
  }

  /** The samples inside the zoom window, plus the one either side of it.
   *
   * The neighbours are what keep the line touching both edges: without them a
   * window landing between two samples draws nothing, and one landing just past a
   * sample starts the line a third of the way in. They are clipped away where
   * they leave the panel, so all they contribute is the slope at the edge. */
  function inWindow(points, shown) {
    return points.filter((point, index) => {
      if (point.tick >= shown.from && point.tick <= shown.to) return true;
      const before = points[index - 1];
      const after = points[index + 1];
      return (after && point.tick < shown.from && after.tick >= shown.from)
        || (before && point.tick > shown.to && before.tick <= shown.to);
    });
  }

  /** Lights up one milestone wherever it is drawn - a line in every open track
   * panel, and a row in the list beside them - and puts out whatever was lit.
   *
   * Done by toggling a class rather than by redrawing: a redraw would replace the
   * very line the pointer is over, which the browser reads as leaving it, and the
   * highlight would flicker itself off. Everything that draws a milestone asks
   * milestoneClass()/milestoneRowClass() for the class instead, so a zoom in the
   * middle of a hover comes back lit. */
  function hoverMilestone(index) {
    view.hoverMilestone = index;
    if (!view.element) return;
    for (const node of view.element.querySelectorAll("[data-milestone]")) {
      node.classList.toggle("hot", Number(node.dataset.milestone) === index);
    }
  }

  /** The class a milestone line is drawn with, lit or not. */
  function milestoneClass(index) {
    return view.hoverMilestone === index ? "milestone hot" : "milestone";
  }

  /** More than this many decades between the smallest and largest value and the
   * track is drawn on a log axis. Two is where a linear axis starts hiding the
   * early half of a run against the bottom edge. */
  const LOG_DECADES = 2;

  /** True when a count track covers enough ground to deserve a log axis. Only
   * positive values can be logged, so a track that touches zero stays linear. */
  function spansDecades(values) {
    const min = Math.min(...values);
    const max = Math.max(...values);
    return min > 0 && Math.log10(max / min) > LOG_DECADES;
  }

  /** Gridlines: whole decades on a log axis, thinned so a twenty-decade run
   * still gets a readable handful, and top/middle/bottom on a linear one. */
  function ticksFor(min, max, logged) {
    if (!logged) return [max, (max + min) / 2, min];
    const first = Math.ceil(min);
    const last = Math.floor(max);
    if (last < first) return [max, min];       // inside a single decade
    const step = Math.max(1, Math.ceil((last - first + 1) / 5));
    const ticks = [];
    for (let decade = first; decade <= last; decade += step) ticks.push(decade);
    return ticks;
  }

  /** Log tracks arrive as log10 and are printed as the value they stand for;
   * counts are printed as themselves. */
  function format(value, log) {
    if (!log) return compact(value);
    const exponent = Math.floor(value);
    const mantissa = Math.pow(10, value - exponent);
    if (exponent >= -2 && exponent < 5) return compact(mantissa * Math.pow(10, exponent));
    // A gridline sits on a whole decade, and "1e12" reads better there than the
    // "1.0e12" a fixed decimal would print.
    return mantissa < 1.05 ? `1e${exponent}` : `${mantissa.toFixed(1)}e${exponent}`;
  }

  /** Three significant figures, and no "4.81e+3" for a number that fits on the
   * axis as 4810 - JS switches to exponential far earlier than a reader wants. */
  function compact(value) {
    if (Math.abs(value) >= 1e5) return value.toExponential(1).replace("e+", "e");
    return String(Number(value.toPrecision(3)));
  }

  /* -------------------------------------------------------------------- panel */

  function renderPanel(panel) {
    panel.replaceChildren();

    const form = document.createElement("div");
    form.className = "sim-form";
    const field = (label, control) => {
      const name = document.createElement("label");
      name.textContent = label;
      form.append(name, control);
    };

    const ticks = numberInput("ticks", 1, 10000000);
    const prestiges = numberInput("prestiges", 1, 50);
    const samples = numberInput("samples", 10, 2000);
    const policy = document.createElement("select");
    for (const option of ["roi", "cheapest", "nodes_only"]) {
      policy.append(new Option(option, option));
    }
    policy.value = view.settings.policy;
    policy.onchange = () => { view.settings.policy = policy.value; };

    // How often the run measures what each upgrade is contributing. It is the
    // expensive part of a run - one probe per levelled upgrade, per snapshot - so
    // a long run has somewhere to turn it down to.
    const breakdowns = document.createElement("select");
    for (const option of ["milestones", "end", "off"]) {
      breakdowns.append(new Option(option, option));
    }
    breakdowns.value = view.settings.breakdowns;
    breakdowns.title = "when to measure each upgrade's contribution";
    breakdowns.onchange = () => { view.settings.breakdowns = breakdowns.value; };

    field("ticks", ticks);
    field("prestiges", prestiges);
    field("samples", samples);
    field("policy", policy);
    field("bonuses", breakdowns);
    panel.append(form);

    const actions = document.createElement("div");
    actions.className = "sim-actions";
    const run = document.createElement("button");
    run.className = "primary";
    run.textContent = view.running ? "Running…" : view.start ? "Continue" : "Run";
    run.disabled = view.running;
    run.onclick = () => start();
    actions.append(run, continueButton(), importButton(), exportButton());
    panel.append(actions);

    panel.append(startFrom());
    if (view.running) panel.append(progressBar());

    if (anyDirty()) {
      const warning = document.createElement("div");
      warning.className = "hint";
      warning.textContent = "Unsaved edits are not simulated - the run reads the .tres files.";
      panel.append(warning);
    }

    if (view.result) panel.append(summary());
    panel.append(trackToggles());
    if (view.result) panel.append(milestoneTable());
    if (view.result) panel.append(breakdownSection());
  }

  /* --------------------------------------------------------------- breakdown */

  /** Which upgrade is carrying the run, grouped by the resource it moves and,
   * inside that, by the track the bonus comes from. Both groupings, and the
   * totals on their headings, are the simulator's - see BalanceSim.RESOURCES.
   *
   * Each row carries two numbers because neither answers on its own. The
   * magnitude is what the upgrade writes into its stat bucket - exact, but a
   * +0.15 INCREASED and a +0.15 MORE are not comparable and across two stats
   * nothing is. The impact is measured: the simulator zeroes the level, lets
   * everything re-resolve, and reports what the run and that stat's own bucket
   * fall to without it.
   *
   * Collapsed by default. It is a few hundred rows, and the chart above it is
   * what the view is normally for. */
  function breakdownSection() {
    const wrap = document.createElement("details");
    wrap.className = "sim-breakdown";
    wrap.open = view.breakdownOpen;
    wrap.ontoggle = () => { view.breakdownOpen = wrap.open; };
    const head = document.createElement("summary");
    head.textContent = "Bonus breakdown";
    wrap.append(head);

    const snapshot = breakdownAt();
    if (!snapshot) {
      const none = document.createElement("div");
      none.className = "hint";
      none.textContent = view.result.breakdown === null
        ? "this run was asked for no breakdowns - set bonuses to milestones or end"
        : "nothing was contributing yet";
      wrap.append(none);
      return wrap;
    }

    wrap.append(snapshotPicker(), snapshotSummary(snapshot), trackTotals(snapshot));
    for (const group of resourceGroups(snapshot)) wrap.append(resourceSection(group));
    return wrap;
  }

  /** Every breakdown this result carries, newest thinking first: the run's end,
   * then each milestone that was measured, labelled by the milestone it sits on. */
  function breakdownChoices() {
    const rows = [];
    if (view.result.breakdown) rows.push({ at: -1, label: "run end", snapshot: view.result.breakdown });
    (view.result.breakdowns || []).forEach((snapshot, index) => {
      // Matched by tick rather than by index: a stitched result can carry
      // milestones from a leg that was run without breakdowns, and then the two
      // arrays are no longer parallel.
      const milestone = view.result.milestones.find((row) => row.tick === snapshot.tick);
      rows.push({ at: index, snapshot,
        label: milestone ? `${milestone.event} · tick ${snapshot.tick}` : `tick ${snapshot.tick}` });
    });
    return rows;
  }

  /** The chosen snapshot, falling back to whatever is available when the choice
   * is gone - a fresh run replaces the whole result under it. */
  function breakdownAt() {
    const choices = breakdownChoices();
    if (!choices.length) return null;
    const found = choices.find((row) => row.at === view.breakdownAt);
    if (!found) view.breakdownAt = choices[0].at;
    return (found || choices[0]).snapshot;
  }

  function snapshotPicker() {
    const choices = breakdownChoices();
    const picker = document.createElement("select");
    picker.className = "sim-breakdown-at";
    for (const choice of choices) picker.append(new Option(choice.label, String(choice.at)));
    picker.value = String(view.breakdownAt);
    picker.onchange = () => {
      view.breakdownAt = Number(picker.value);
      renderPanel(view.element.querySelector(".sim-panel"));
    };
    return picker;
  }

  /** What the run stood at when this snapshot was taken, so the percentages
   * below have something to be percentages of. */
  function snapshotSummary(snapshot) {
    const line = document.createElement("div");
    line.className = "hint";
    line.textContent = `${format(snapshot.production, true)} production/tick`
      + ` · tick ${snapshot.tick_duration.toFixed(2)}s`
      + ` · pump every ${snapshot.water_interval.toFixed(1)} ticks`
      + ` · ${duration(snapshot.seconds)} played`;
    return line;
  }

  /** What each whole track is worth, measured with its every level zeroed at
   * once. The one cut the resource grouping cannot make: a track split across
   * five resources is five headings below, and this is the line that says what it
   * comes to as a track - which is how the tracks are bought and balanced. */
  function trackTotals(snapshot) {
    const line = document.createElement("div");
    line.className = "hint";
    // Pipes between the tracks, because impactText() already spends the middle
    // dot on the two or three numbers inside one track's total.
    line.textContent = "measured per track: " + snapshot.tracks
      .map((group) => `${group.track} ${impactText(group.impact)}`).join(" | ");
    return line;
  }

  /** The snapshot's tracks turned inside out: resource first, then the track the
   * bonus comes from, then the upgrades.
   *
   * Which stat feeds which resource, what order the resources read in, and both
   * levels of total all come from the simulator - see BalanceSim.RESOURCES. They
   * have to: a group's total is a probe of that whole group taken away at once,
   * and only the run can take it away. Summing the rows instead would put fifteen
   * upgrades each worth "the run falls 99% without it" at 1485%, which ranks the
   * tracks by how many upgrades they happen to hold.
   *
   * So this walks those groups again to hang the upgrade rows off them, and sorts
   * only the rows.
   *
   * An upgrade writing two resources - a perk that adds nutrients and shortens
   * the tick - is listed under both, carrying only that resource's effect lines
   * in each. Its own impact is not split between them: one probe takes the whole
   * level away, so the same number is what the run loses in either group. */
  function resourceGroups(snapshot) {
    const metrics = new Map((snapshot.resources || []).map((g) => [g.resource, g.metric]));
    const rows = new Map();      // resource -> track -> rows
    for (const track of snapshot.tracks) {
      for (const upgrade of track.upgrades) {
        for (const [resource, effects, counted] of splitByResource(upgrade.effects)) {
          const metric = metrics.get(resource) || "stat";
          ensure(ensure(rows, resource, () => new Map()), track.track, () => []).push({
            id: upgrade.id, name: upgrade.name, level: upgrade.level,
            impact: upgrade.impact, effects,
            influence: influenceOf(metric, upgrade.impact, counted),
            // The biggest bucket this row writes into this resource, as the
            // fraction it loses and as the distance that fraction saturates at.
            // They rank the tail the metric cannot separate, and in a run
            // -measured group that tail is real: a &"node_production" upgrade
            // scoped to node 7 moves the run's total production by nothing
            // measurable, because node 0 dwarfs it - but it is not nothing inside
            // node 7's own bucket, and that is what says which of them is bigger.
            share: topOf(upgrade.impact.stat_drop, counted),
            shareOrders: topOf(upgrade.impact.stat_orders, counted),
            weight: weightOf(effects),
          });
        }
      }
    }

    return (snapshot.resources || []).map((group) => {
      const byTrack = rows.get(group.resource) || new Map();
      const sources = group.sources.map((source) => ({
        source: source.track,
        impact: source.impact,
        rows: (byTrack.get(source.track) || []).sort((a, b) =>
          descending(a.influence, b.influence)
          || descending(a.shareOrders, b.shareOrders)
          || descending(a.share, b.share) || descending(a.weight, b.weight)),
      }));
      return {
        resource: group.resource, metric: group.metric, impact: group.impact,
        count: sources.reduce((total, source) => total + source.rows.length, 0),
        sources,
      };
    });
  }

  /** One entry per resource an upgrade's effects touch, carrying just the effects
   * that touch it: [[resource, effects], ...].
   *
   * Two effects writing the same bucket - the same stat at the same scope - are
   * both listed, but only the first counts towards the resource's influence: they
   * share one bucket, and its share is measured once. */
  function splitByResource(effects) {
    const split = new Map();
    for (const effect of effects) {
      // Named by the simulator, which grouped the probes the same way. A snapshot
      // from before it did falls back to the stat, which is a group of one.
      const resource = effect.resource || effect.stat;
      const entry = ensure(split, resource,
        () => ({ resource, effects: [], counted: [], buckets: new Set() }));
      entry.effects.push(effect);
      const bucket = `${effect.stat}@${effect.key}`;
      if (!entry.buckets.has(bucket)) {
        entry.buckets.add(bucket);
        entry.counted.push(effect);
      }
    }
    return [...split.values()].map((entry) => [entry.resource, entry.effects, entry.counted]);
  }

  /** What a row is ranked by: the measurement this resource's upgrades actually
   * move. Positive is the upgrade helping in all four - both deltas are what
   * taking it away puts back, and both distances are what it takes with it.
   *
   * The two production-shaped metrics rank on orders of magnitude rather than on
   * the fraction, because a fraction stops separating anything up here: at 1e1400
   * every real upgrade reads as -100%. See BalanceSim._orders_between().
   *
   * A `stat` group ranks on the biggest bucket this upgrade writes into *this*
   * resource, so a perk adding nutrients and biomass is ranked in the biomass
   * group by its biomass bucket alone. */
  function influenceOf(metric, impact, effects) {
    if (metric === "tick") return impact.tick_delta;
    if (metric === "water") return impact.water_delta;
    if (metric !== "stat") return impact.production_orders || impact.production_drop;
    return topOf(impact.stat_orders, effects) || topOf(impact.stat_drop, effects);
  }

  /** The biggest reading `measured` holds for the buckets `effects` write into.
   *
   * Biggest, not summed: a share of mission speed and a share of mission payout
   * are shares of two different things, and adding them would rank a row by how
   * many buckets it happens to touch. Keyed the way BalanceSim writes it,
   * "stat@scope_key" - the two fields the effect row already carries - and 0 when
   * the run predates the measurement. */
  function topOf(measured, effects) {
    let top = 0;
    for (const effect of effects) {
      const value = (measured || {})[`${effect.stat}@${effect.key}`];
      if (typeof value === "number") top = Math.max(top, value);
    }
    return top;
  }

  /** The loudest magnitude in a row's effects, as log10, and only ever a
   * tiebreaker: in a group nothing can measure - &"biomass_gain" moves no
   * production, no tick and no pump - every influence is zero and the magnitude
   * is the only thing left to rank by. A null is a magnitude of zero, which
   * BalanceSim._log10() refuses to take a log of; it ranks below any real one. */
  function weightOf(effects) {
    let top = -Infinity;
    for (const effect of effects) {
      if (typeof effect.mag_log === "number") top = Math.max(top, effect.mag_log);
    }
    return top;
  }

  /** Biggest first, and safe on the infinities weightOf() hands out - subtracting
   * one from itself is NaN, which a comparator must never see. */
  function descending(a, b) {
    return a > b ? -1 : a < b ? 1 : 0;
  }

  /** Get-or-create, so a grouping loop reads as one line per level. */
  function ensure(map, key, make) {
    if (!map.has(key)) map.set(key, make());
    return map.get(key);
  }

  /** One resource: the tracks feeding it, biggest first, each with its upgrades.
   *
   * Folded shut until it is asked for. Thirteen resources of a few hundred rows
   * between them is a scroll, not a table - closed, the headings alone are the
   * answer to "what is pushing what", and opening one is the follow-up question.
   *
   * Which ones are open lives on the view, not in the DOM: the panel is rebuilt
   * whole on every redraw, and a snapshot picked from the dropdown would
   * otherwise slam every group shut. */
  function resourceSection(group) {
    const wrap = document.createElement("details");
    wrap.className = "sim-resource";
    wrap.open = view.breakdownOpenGroups.has(group.resource);
    wrap.ontoggle = () => {
      if (wrap.open) view.breakdownOpenGroups.add(group.resource);
      else view.breakdownOpenGroups.delete(group.resource);
    };
    const head = document.createElement("summary");
    head.append(groupHead("sim-track-head", group.resource, group.count,
      group.impact, group.metric));
    wrap.append(head);
    for (const source of group.sources) {
      wrap.append(groupHead("sim-source-head", source.source, source.rows.length,
        source.impact, group.metric), sourceTable(source, group.metric));
    }
    return wrap;
  }

  /** A heading with what is under it on the right, measured rather than added up:
   * every upgrade below it zeroed at once, everything re-resolved, and what the
   * resource falls to reported.
   *
   * It sits above the table rather than in it. As a spanning cell it has to be a
   * flex row to keep the total off three lines in a panel this narrow, and a cell
   * that is display:flex stops taking part in the column widths - which leaves
   * the columns below it sized off nothing. */
  function groupHead(className, name, count, impact, metric) {
    const heading = document.createElement("div");
    heading.className = className;
    const label = document.createElement("span");
    label.textContent = name;
    const total = document.createElement("span");
    total.className = "num";
    total.textContent = `${count} · ${groupText(metric, impact)}`;
    total.title = "measured with every upgrade under this heading taken away at once,"
      + " which is less than they add up to separately - MORE effects compound";
    heading.append(label, total);
    return heading;
  }

  /** A measured group total, in the unit its resource is measured in. The probe
   * behind it covers exactly this group, so its stat_drop holds this resource's
   * buckets and nothing else - the biggest of them is what the heading shows, for
   * the same reason topOf() takes the biggest of a row's. */
  function groupText(metric, impact) {
    if (metric === "tick") {
      return Math.abs(impact.tick_delta) > 1e-9 ? `${signed(-impact.tick_delta)}s tick` : "-";
    }
    if (metric === "water") {
      return Math.abs(impact.water_delta) > 1e-9 ? `${signed(-impact.water_delta)} pump` : "-";
    }
    if (metric !== "stat") {
      return dropText(impact.production_drop, impact.production_orders) || "-";
    }
    return shareText(biggest(impact.stat_drop), biggest(impact.stat_orders));
  }

  /** The largest value in a measured-by-bucket dictionary, or 0 when it is empty
   * or missing - which is what a snapshot from before the sim measured buckets
   * carries. */
  function biggest(measured) {
    return Object.values(measured || {}).reduce((top, value) => Math.max(top, value), 0);
  }

  /** What this resource loses without one row, as the row's hover title.
   *
   * Not a column any more: a counterfactual per row asks the reader to hold "what
   * the run would be without this one thing" in their head for every line, and
   * the heading above already says what the whole group is worth. It still ranks
   * the rows, and it is still one hover away.
   *
   * A run-measured group reports the run-level probe whole - all three numbers,
   * because a perk that adds nutrients and shortens the tick is worth seeing in
   * both groups. A `stat` group reports its own bucket share instead, which is
   * the one thing the run-level probe was blind to. A snapshot from before
   * stat_drop existed has no share to report and falls back to the run-level
   * numbers, which for these groups is the "-" it always was. */
  function withoutText(metric, row) {
    if (metric === "stat") return shareText(row.share, row.shareOrders);
    const run = impactText(row.impact);
    // "-" means the run-level probe saw nothing, which for a node-scoped upgrade
    // is true of the run and false of the node. The share says which.
    return run === "-" ? shareText(row.share, row.shareOrders) : run;
  }

  /** A bucket share, told apart from a run-level number by the word after it -
   * the two are fractions of different things, and a column that mixed them
   * silently would read as one. */
  function shareText(share, orders) {
    return dropText(share, orders) ? `${dropText(share, orders)} share` : "-";
  }

  /** A drop as a fraction, or as the distance it really is once the fraction has
   * stopped separating anything.
   *
   * Production runs past 1e1400 here, so every track worth having reads as
   * -100.0% and so does the next one - the ratio behind it has fallen under what
   * a float carries. Past 99.95% the orders of magnitude are shown instead, which
   * go on separating long after the percentage cannot. */
  function dropText(drop, orders) {
    if (Math.abs(drop) <= 1e-6) return "";
    if (drop > 0.9995 && typeof orders === "number" && orders >= 1) {
      return `-${Number(orders.toPrecision(3))} decades`;
    }
    return `${(-drop * 100).toFixed(1)}%`;
  }

  /** One track's upgrades inside one resource, already sorted. Every row is
   * listed, including the ones the run-level probe cannot see: those are what a
   * `stat` group is made of, so collapsing them into a count would empty it. */
  function sourceTable(source, metric) {
    const table = document.createElement("table");
    table.className = "web-table sim-breakdown-table";
    const columns = table.insertRow();
    for (const column of ["upgrade", "level", "effects"]) {
      const th = document.createElement("th");
      th.textContent = column;
      columns.append(th);
    }

    for (const upgrade of source.rows) {
      const row = table.insertRow();
      // The order is the measurement: biggest first. What each row measured is on
      // the row itself rather than in a column of its own - see withoutText().
      row.title = `${upgrade.id} · without it: ${withoutText(metric, upgrade)}`;
      row.insertCell().textContent = upgrade.name || upgrade.id;
      const level = row.insertCell();
      level.className = "num";
      level.textContent = String(upgrade.level);
      row.insertCell().append(effectList(upgrade.effects));
    }
    return table;
  }

  /** What the run loses without it: the production drop, plus the two stats a
   * production drop cannot show - a tick_rate upgrade moves no production at all
   * and would otherwise read as contributing nothing. */
  function impactText(impact) {
    const bits = [];
    // Bare, with no "prod" after it: the column it sits under is the production
    // drop, and in a panel this narrow the extra word wraps every row in two.
    const production = dropText(impact.production_drop, impact.production_orders);
    if (production) bits.push(production);
    // Reported the way the upgrade acts rather than the way the probe measured:
    // removing it lengthens the tick, so the upgrade shortens it.
    if (Math.abs(impact.tick_delta) > 1e-9) bits.push(`${signed(-impact.tick_delta)}s tick`);
    if (Math.abs(impact.water_delta) > 1e-9) bits.push(`${signed(-impact.water_delta)} pump`);
    return bits.length ? bits.join(" · ") : "-";
  }

  function signed(value) {
    return `${value > 0 ? "+" : ""}${Number(value.toPrecision(3))}`;
  }

  /** One line per effect: the bucket it writes into, how, and how much. */
  function effectList(effects) {
    const list = document.createElement("div");
    list.className = "sim-effects";
    for (const effect of effects) {
      const line = document.createElement("div");
      line.textContent = `${effect.stat} ${effect.op} ${effect.mag}`;
      // "g" is global and says nothing; a tag or node key is worth spelling out.
      if (effect.key && effect.key !== "g") line.textContent += ` @${effect.key}`;
      list.append(line);
    }
    return list;
  }

  /* ------------------------------------------------------------------- saves */

  /** What the next run starts from, and a way back to a fresh one.
   *
   * Shown only when it is not the default, because "starts from the beginning"
   * is not news - but starting from somewhere else silently would be. */
  function startFrom() {
    const line = document.createElement("div");
    if (!view.start) return line;
    line.className = "sim-start";
    const label = document.createElement("span");
    label.textContent = `continuing from ${view.start.label}`;
    label.title = `tick ${view.start.tick} · ${duration(view.start.seconds)} played`;
    const clear = document.createElement("button");
    clear.textContent = "start fresh";
    clear.onclick = () => { view.start = null; view.render(); };
    line.append(label, clear);
    return line;
  }

  /** Plays another `ticks` ticks on from where the last run stopped, under
   * whatever the form says now.
   *
   * One button rather than two, because "carry on" is one thought: it picks the
   * end of the last run as the starting state and starts. Pressing it again
   * carries on from the end of *that* run, so a run can be extended as far as
   * anyone's patience goes without ever exporting a file.
   *
   * The prestige target counts afresh each time, since it is a target for the
   * run being asked for - three more prestiges, not three in total. */
  function continueButton() {
    const button = document.createElement("button");
    button.textContent = "Continue run";
    button.disabled = view.running || !view.result || !view.result.save;
    button.title = view.result
      ? `play ${view.settings.ticks} more ticks on from tick ${view.result.last_tick || 0}`
      : "runs on from where the last run stopped";
    button.onclick = () => {
      view.start = {
        save: view.result.save,
        tick: view.result.last_tick || 0,
        seconds: view.result.seconds || 0,
        // Named by the tick alone, not by "the end of the last run": press this
        // again and there is a newer last run, but tick 3000 is still tick 3000.
        label: `tick ${view.result.last_tick || 0}`,
      };
      start();
    };
    return button;
  }

  /** Downloads the state the last run ended on, in the game's own save format -
   * so it can be dropped into user://save.json and played, or handed back to
   * this page to carry on from. */
  function exportButton() {
    const button = document.createElement("button");
    button.textContent = "Export save";
    button.disabled = view.running || !view.result || !view.result.save;
    button.title = "the state this run ended on, as a save file";
    button.onclick = () => download(view.result.save,
      `sim-${view.result.policy}-tick${view.result.last_tick || 0}.json`);
    return button;
  }

  /** Loads a save file to start the next run from. Accepts both shapes the
   * simulator does - a save straight out of the game, and a savepoint exported
   * from here - because the file picker cannot tell them apart either. */
  function importButton() {
    const label = document.createElement("label");
    label.className = "sim-import";
    label.textContent = "Import save";
    label.title = "run from a save file instead of from a fresh start";
    const picker = document.createElement("input");
    picker.type = "file";
    picker.accept = ".json,application/json";
    picker.onchange = async () => {
      const file = picker.files && picker.files[0];
      if (!file) return;
      try {
        const save = JSON.parse(await file.text());
        // A file carries no tick number worth trusting, so a continued run from
        // one starts its own count at zero rather than inventing an origin.
        view.start = { save, tick: 0, seconds: 0, label: file.name };
        log(`starting the next run from ${file.name}`);
      } catch (error) {
        log(`${file.name} is not a save file (${error.message})`, true);
      }
      picker.value = "";       // so picking the same file twice fires again
      view.render();
    };
    label.append(picker);
    return label;
  }

  function download(data, name) {
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(data, null, 1)], { type: "application/json" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = name;
    link.click();
    URL.revokeObjectURL(url);
  }

  /** Where the running simulation has got to.
   *
   * A run takes anywhere from seconds to minutes and used to show nothing at all
   * while it did, which reads identically to a hung server. Two bars, because a
   * run has two ends it can finish at: it stops at the tick budget or at the
   * prestige target, whichever it reaches first, and which one is moving faster
   * is the interesting part. */
  function progressBar() {
    const wrap = document.createElement("div");
    wrap.className = "sim-progress";
    const at = view.progress;
    if (!at || typeof at.tick !== "number") {
      const waiting = document.createElement("div");
      waiting.className = "hint";
      waiting.textContent = "starting Godot…";
      wrap.append(waiting);
      return wrap;
    }

    wrap.append(
      bar("ticks", at.tick, at.ticks, `${at.tick} of ${at.ticks}`),
      bar("prestiges", at.prestiges, at.prestige_target,
        `${at.prestiges} of ${at.prestige_target}`));

    const line = document.createElement("div");
    line.className = "hint";
    // The played span is what the run is actually measuring, so it goes next to
    // the wall clock rather than being left to the summary at the end.
    line.textContent = `${at.played || duration(at.seconds)} played`
      + (at.elapsed ? ` · ${at.elapsed.toFixed(0)}s elapsed` : "");
    wrap.append(line);
    return wrap;
  }

  /** One labelled bar. A zero-length target would divide by zero, and a run can
   * legitimately be asked for zero prestiges. */
  function bar(label, value, target, text) {
    const row = document.createElement("div");
    row.className = "sim-bar";
    const name = document.createElement("span");
    name.textContent = label;
    const track = document.createElement("div");
    track.className = "sim-bar-track";
    const fill = document.createElement("i");
    fill.style.width = `${Math.min(100, target > 0 ? (value / target) * 100 : 0)}%`;
    track.append(fill);
    const count = document.createElement("span");
    count.className = "num";
    count.textContent = text;
    row.append(name, track, count);
    return row;
  }

  /** What the run cost in real time. Ticks are the simulator's unit, but nobody
   * plays in ticks, and a tick is not even a fixed length once &"tick_rate"
   * upgrades land - so the wall clock is stated outright. */
  function summary() {
    const result = view.result;
    const last = result.series.length ? result.series.at(-1) : null;
    const line = document.createElement("div");
    line.className = "sim-summary";
    line.textContent = `${duration(result.seconds)} played · ${last ? last.tick : 0} ticks · `
      + prestigeCount(result);
    line.title = `${Math.round(result.seconds || 0)} seconds of real time, `
      + `summed from every tick's own duration`;
    const rate = document.createElement("div");
    rate.className = "hint";
    // A result carried over from before the simulator reported tick duration has
    // no such field, and a missing footnote beats a broken panel.
    rate.textContent = last && typeof last.tick_duration === "number"
      ? `tick is ${last.tick_duration.toFixed(2)}s by the end, from 10s`
      : "";
    line.append(rate);
    return line;
  }

  /** How many prestiges the chart in front of you covers.
   *
   * Counted off the milestones rather than read off `prestiges`, which is the
   * last segment's tally: a run continued three times has three of those and one
   * milestone list. The target is only quoted for a run that started fresh,
   * because on a continuation it was a target for that leg alone. */
  function prestigeCount(result) {
    const total = result.milestones.filter((row) => row.event === "prestige").length;
    return result.from_tick
      ? `${total} prestiges`
      : `${total} of ${result.prestige_target} prestiges`;
  }

  function numberInput(key, min, max) {
    const input = document.createElement("input");
    input.type = "number";
    input.min = String(min);
    input.max = String(max);
    input.value = String(view.settings[key]);
    input.onchange = () => {
      const value = Math.max(min, Math.min(max, Number(input.value) || min));
      view.settings[key] = value;
      input.value = String(value);
    };
    return input;
  }

  function trackToggles() {
    const legend = document.createElement("div");
    legend.className = "sim-legend";
    [...view.shown].forEach((key, index) => {
      const shown = document.createElement("span");
      shown.innerHTML = `<i style="background:hsl(${hueOf(index)} 65% 50%)"></i>`;
      shown.append(TRACKS[key].label);
      legend.append(shown);
    });

    const picker = document.createElement("div");
    picker.className = "curve-list";
    for (const [key, track] of Object.entries(TRACKS)) {
      const row = document.createElement("label");
      row.className = "curve-row";
      const box = document.createElement("input");
      box.type = "checkbox";
      box.checked = view.shown.has(key);
      box.onchange = () => {
        box.checked ? view.shown.add(key) : view.shown.delete(key);
        view.render();
      };
      const name = document.createElement("span");
      name.textContent = track.label;
      const note = document.createElement("span");
      note.className = "curve-note";
      note.textContent = track.log ? "log" : (track.unit || " (count)").trim().replace(/[()]/g, "");
      row.append(box, name, note);
      picker.append(row);
    }

    const wrap = document.createElement("div");
    wrap.append(legend, picker);
    return wrap;
  }

  /** The answer the whole view exists for: which tick each thing happened on,
   * and how long a player would have been sitting there when it did.
   *
   * Each row is also a branch point: the run carries a save taken at every one
   * of these ticks, so any of them can be run on from or downloaded. */
  function milestoneTable() {
    const table = document.createElement("table");
    table.className = "web-table";
    const head = table.insertRow();
    for (const column of ["tick", "played", "event", "detail", ""]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }
    const savepoints = view.result.savepoints || [];
    view.result.milestones.forEach((milestone, index) => {
      const row = table.insertRow();
      // The other half of the highlight: this row and the lines the chart draws
      // for the same milestone carry the same index, and hovering either lights
      // both. A row whose tick is outside the zoom window lights alone - there is
      // no line on the chart to light with it.
      row.dataset.milestone = index;
      if (view.hoverMilestone === index) row.classList.add("hot");
      row.onmouseenter = () => hoverMilestone(index);
      row.onmouseleave = () => hoverMilestone(null);
      const tick = row.insertCell();
      tick.className = "num";
      tick.textContent = String(milestone.tick);
      const played = row.insertCell();
      played.className = "num";
      played.textContent = duration(milestone.seconds);
      played.title = `${Math.round(milestone.seconds || 0)}s`;
      row.insertCell().textContent = milestone.event;
      row.insertCell().textContent = milestone.detail;
      row.insertCell().append(...savepointActions(savepoints[index], milestone));
    });
    if (!view.result.milestones.length) {
      const row = table.insertRow();
      const cell = row.insertCell();
      cell.colSpan = 5;
      cell.className = "web-stats";
      cell.textContent = "nothing happened in this many ticks";
    }
    return table;
  }

  /** Run on from this milestone, or take its save away. Nothing at all for a
   * result from before savepoints existed, rather than two dead buttons. */
  function savepointActions(point, milestone) {
    if (!point || !point.save) return [];
    const label = `${milestone.event} at tick ${milestone.tick}`;
    const resume = document.createElement("button");
    resume.className = "sim-tiny";
    resume.textContent = "continue";
    resume.title = `start the next run from ${label}`;
    resume.onclick = () => {
      view.start = { save: point.save, tick: point.tick, seconds: point.seconds, label };
      log(`the next run continues from ${label}`);
      view.render();
    };
    const save = document.createElement("button");
    save.className = "sim-tiny";
    save.textContent = "save";
    save.title = `download the save taken at ${label}`;
    save.onclick = () => download(point.save,
      `sim-${milestone.event}-tick${milestone.tick}.json`);
    return [resume, save];
  }

  /* ------------------------------------------------------------------- wiring */

  /** How often the page asks the server where the run has got to. The simulator
   * republishes every 250ms, so anything faster only re-reads the same file. */
  const POLL_MS = 300;

  async function start() {
    view.running = true;
    view.progress = null;
    view.render();
    const started = Date.now();
    setStatus(`simulating ${view.settings.ticks} ticks under ${view.settings.policy}…`);
    const polling = watch();
    // The starting state travels with the settings rather than in the settings,
    // so it is never one of the fields the form persists between runs.
    const request = view.start
      ? { ...view.settings, save: view.start.save,
          from_tick: view.start.tick, from_seconds: view.start.seconds }
      : view.settings;
    const before = view.start ? view.result : null;
    const branch = view.start ? view.start.tick : 0;
    try {
      const segment = await api("/api/sim", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(request),
      });
      view.result = stitch(before, segment, branch);
      view.breakdownAt = -1;      // the old choice indexed a result that is gone
      view.zoom = null;           // and the old window was ticks this run may not reach
      view.hoverMilestone = null; // and the pointer is nowhere near the new list
      log(`simulated ${segment.ticks} ticks in ${((Date.now() - started) / 1000).toFixed(1)}s`);
    } catch (error) {
      log(String(error), true);
    } finally {
      clearInterval(polling);
      view.running = false;
      view.progress = null;
      view.render();
    }
  }

  /** Joins a continued run onto the one it grew out of, so the chart keeps the
   * whole history instead of restarting at the branch point.
   *
   * Everything is labelled with an absolute tick, so this is a concatenation
   * rather than a merge. What the earlier run had *after* the branch is dropped:
   * continuing from the end keeps all of it, and branching from a milestone
   * halfway up drops the road not taken, which is the point of branching.
   *
   * The scalars come from the new segment. Its `seconds` was seeded with where
   * the branch stood, so it is already the total; its `prestiges` deliberately
   * is not, being a count for the run that was asked for. */
  function stitch(before, segment, branch) {
    if (!before) return segment;
    const upTo = (rows) => (rows || []).filter((row) => row.tick <= branch);
    return {
      ...segment,
      series: [...upTo(before.series), ...segment.series],
      milestones: [...upTo(before.milestones), ...segment.milestones],
      savepoints: [...upTo(before.savepoints), ...(segment.savepoints || [])],
      // Tagged with their own tick, so the same filter works on them - which is
      // why they are not simply indexed off the milestones they sit on.
      breakdowns: [...upTo(before.breakdowns), ...(segment.breakdowns || [])],
    };
  }

  /** Polls the progress endpoint for as long as the run lasts.
   *
   * Redraws only the panel, not the chart: the chart has nothing new to show
   * until the run returns, and rebuilding its SVG three times a second for
   * nothing is visible as a flicker. A failed poll is ignored rather than
   * reported - the run is what matters, and it is still going. */
  function watch() {
    return setInterval(async () => {
      if (!view.running) return;
      try {
        const at = await api("/api/sim/progress");
        if (!view.running || !at.running) return;
        view.progress = at;
        renderPanel(view.element.querySelector(".sim-panel"));
      } catch (error) {
        // still running, still nothing to say about it
      }
    }, POLL_MS);
  }

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "sim-view";
    wrap.innerHTML = `<div class="sim-canvas"></div><aside class="sim-panel"></aside>`;
    return wrap;
  };

  view.render = () => {
    view.element.querySelector(".sim-canvas").replaceChildren(drawRun());
    renderPanel(view.element.querySelector(".sim-panel"));
    if (view.running) return;
    setStatus(view.result
      ? `${view.result.policy} - ${prestigeCount(view.result)} `
        + `in ${duration(view.result.seconds)} of play`
      : "simulator - press Run");
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.sim = view;
})();
