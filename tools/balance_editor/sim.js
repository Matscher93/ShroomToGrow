/* Simulator view: how long the authored numbers take to play.
 *
 * POST /api/sim runs tools/sc_balance_sim.tscn headlessly, which drives the real
 * App through a scripted shopping policy and reports two things: a downsampled
 * trace of the run, and the ticks worth naming (a biome unlocked, a prestige
 * taken). Everything unbounded arrives as log10, which is what a chart wants.
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
    nodes: { label: "Nodes bought", log: false },
    symbiosis: { label: "Symbiosis levels", log: false },
    biome_upgrades: { label: "Biome upgrade levels", log: false },
    perks: { label: "Perk levels", log: false },
    // What a tick is worth in real seconds. Every &"tick_rate" upgrade shortens
    // it, and the perks doing that outlive a prestige, so this is where a run
    // shows itself getting faster rather than just richer.
    tick_duration: { label: "Tick duration", log: false, unit: " (seconds)" },
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
    settings: { ticks: 20000, policy: "roi", prestiges: 3, samples: 200 },
    result: null,
    running: false,
    /** Latest /api/sim/progress reading, or null when nothing is running. */
    progress: null,
    /** Where the next run starts: null for a fresh one, otherwise
     * `{save, tick, seconds, label}` from an imported file or a savepoint. */
    start: null,
    shown: new Set(["production", "nodes", "perks"]),
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
    const logX = lastTick / firstTick > Math.pow(10, LOG_X_DECADES);
    const span = Math.log10(lastTick) - Math.log10(firstTick);
    const x = logX
      ? (tick) => CHART.left
        + ((Math.log10(Math.max(tick, firstTick)) - Math.log10(firstTick)) / span) * plotWidth
      : (tick) => CHART.left + (tick / lastTick) * plotWidth;

    tracks.forEach((key, index) => {
      const top = index * (CHART.rowHeight + CHART.gap);
      svg.append(drawTrack(key, index, series, x, top, plotWidth, lastTick));
    });

    const axisY = tracks.length * (CHART.rowHeight + CHART.gap) + 12;
    for (const tick of tickMarks(firstTick, lastTick, logX)) {
      const label = svgEl("text", { class: "axis", x: x(tick), y: axisY });
      label.setAttribute("text-anchor", "middle");
      label.textContent = String(tick);
      svg.append(label);
    }
    const title = svgEl("text", { class: "axis-title", x: CHART.left + plotWidth / 2, y: axisY + 12 });
    title.setAttribute("text-anchor", "middle");
    title.textContent = `tick${logX ? " · log scale" : ""} · dashed lines are milestones`;
    svg.append(title);
    return svg;
  }

  /** How many times over the run has to grow before the tick axis goes log. */
  const LOG_X_DECADES = 3;

  /** Where the tick axis is labelled: whole decades on a log axis, evenly spaced
   * on a linear one, with the last tick always called out - it is the number the
   * run ended on. */
  function tickMarks(first, last, logX) {
    const marks = [];
    if (logX) {
      for (let decade = Math.ceil(Math.log10(first)); decade <= Math.log10(last); decade++) {
        marks.push(Math.pow(10, decade));
      }
      if (!marks.length || marks.at(-1) !== last) marks.push(last);
      return marks;
    }
    const step = Math.max(1, Math.round(last / 8));
    for (let tick = 0; tick <= last; tick += step) marks.push(tick);
    return marks;
  }

  /** One track's panel: its own y axis, its own three labelled gridlines, and
   * the milestone lines running through it. */
  function drawTrack(key, index, series, x, top, plotWidth, lastTick) {
    const track = TRACKS[key];
    const group = svgEl("g");
    const plotTop = top + 16;
    const plotHeight = CHART.rowHeight - 22;
    const points = series
      .map((sample) => ({ tick: sample.tick, value: sample[key] }))
      .filter((point) => typeof point.value === "number");

    if (points.length < 2) {
      const name = svgEl("text", { class: "axis-title", x: CHART.left, y: top + 10 });
      name.textContent = track.label;
      const none = svgEl("text", { class: "axis", x: CHART.left + 8, y: plotTop + plotHeight / 2 });
      none.textContent = "never left zero";
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

    for (const milestone of view.result.milestones) {
      if (milestone.tick > lastTick) continue;
      group.append(svgEl("line", { class: "milestone", x1: x(milestone.tick),
        x2: x(milestone.tick), y1: plotTop, y2: plotTop + plotHeight }));
    }

    const color = `hsl(${hueOf(index)} 65% 50%)`;
    const path = scaled.map((point, i) =>
      `${i ? "L" : "M"}${x(point.tick).toFixed(1)} ${y(point.value).toFixed(1)}`).join(" ");
    group.append(svgEl("path", { class: "track", d: path, stroke: color }));

    // The number the run ended on, spelled out where the line stops, so the
    // panel answers "how much" without anyone reading the axis.
    const last = scaled.at(-1);
    const final = svgEl("text", { class: "axis", x: CHART.left + plotWidth + 6, y: y(last.value) + 3,
      fill: color });
    final.textContent = format(last.value, logged);
    group.append(final);
    return group;
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

    field("ticks", ticks);
    field("prestiges", prestiges);
    field("samples", samples);
    field("policy", policy);
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
