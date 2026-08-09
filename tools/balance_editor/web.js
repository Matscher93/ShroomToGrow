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
 * Registered on window.BalanceViews, which index.html turns into a view button.
 */
(() => {
  const SCALES = {
    path_cost: { label: "Path cost", note: "biomass to reach this perk from the core" },
    cost_to_max: { label: "Own cost", note: "biomass to max this perk alone" },
    effect_at_max: { label: "Effect at max", note: "magnitude of its effect when maxed" },
  };

  const view = {
    label: "Web",
    title: "The prestige web, coloured by what each perk costs",
    scale: "path_cost",
    report: null,
    hovered: null,
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

  const valueOf = (perk) => log10Of(perk[view.scale]);

  /** Picks a perk to edit without leaving the web. setFocus keeps the sidebar
   * (and so Save, Revert and Ctrl+S) pointing at the file the perk lives in, and
   * re-renders this view, which draws the editor for it in the panel. */
  const edit = (path) => setFocus(path);

  /* ------------------------------------------------------------------ drawing */

  const PAD = 40;

  /** Cheap blue→red ramp over the observed range, so the eye reads "expensive"
   * without a legend lookup. Returns the branch's own hue when the perk has no
   * value on this scale. */
  function fill(perk, min, max) {
    const value = valueOf(perk);
    if (value === null) return "var(--panel)";
    const t = max > min ? (value - min) / (max - min) : 0.5;
    return `hsl(${(1 - t) * 220} 70% ${58 - t * 18}%)`;
  }

  function drawWeb() {
    const perks = view.report.perks;
    const positions = new Map(perks.map((perk) => [perk.id, perk]));
    const values = perks.map(valueOf).filter((value) => value !== null);
    const min = Math.min(...values);
    const max = Math.max(...values);

    const xs = perks.map((perk) => perk.world_x);
    const ys = perks.map((perk) => perk.world_y);
    const left = Math.min(...xs) - PAD;
    const top = Math.min(...ys) - PAD;
    const width = Math.max(...xs) - left + PAD;
    const height = Math.max(...ys) - top + PAD;

    const svg = svgEl("svg", { id: "web-chart",
      viewBox: `${left} ${top} ${width} ${height}` });

    for (const perk of perks) {
      const parent = positions.get(perk.parent_id);
      if (!parent) continue;
      svg.append(svgEl("line", { class: "link", x1: parent.world_x, y1: parent.world_y,
        x2: perk.world_x, y2: perk.world_y, stroke: `hsl(${perk.hue} 60% 55%)` }));
    }

    for (const perk of perks) {
      const group = svgEl("g");
      if (perk.res_path && perk.res_path === state.focus) group.setAttribute("class", "selected");
      const circle = svgEl("circle", { class: "perk", cx: perk.world_x, cy: perk.world_y,
        r: perk.parent_id ? 15 : 20, fill: fill(perk, min, max),
        stroke: `hsl(${perk.hue} 60% 55%)` });
      group.append(circle);

      const label = svgEl("text", { class: "perk-label", x: perk.world_x, y: perk.world_y + 28 });
      label.setAttribute("text-anchor", "middle");
      label.textContent = perk.display_name;
      group.append(label);

      const tip = svgEl("title");
      tip.textContent = [
        perk.display_name,
        `branch: ${perk.branch_label} · depth ${perk.depth}`,
        `max level: ${perk.max_level} · growth ${perk.cost_growth}`,
        `cost to max: ${format(perk.cost_to_max)}`,
        `path cost: ${format(perk.path_cost)}`,
        perk.stat ? `${perk.stat} (${perk.op}) ${format(perk.effect_at_max)} at max` : "no effect",
      ].join("\n");
      group.append(tip);

      if (perk.res_path) group.onclick = () => edit(perk.res_path);
      svg.append(group);
    }

    if (values.length) {
      const ticks = svgEl("g");
      [min, (min + max) / 2, max].forEach((value, index) => {
        const text = svgEl("text", { class: "scale-tick", x: left + 6, y: top + 16 + index * 14 });
        text.textContent = `${["cheap", "mid", "dear"][index]}: 1e${value.toFixed(1)}`;
        ticks.append(text);
      });
      svg.append(ticks);
    }
    return svg;
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

    const editor = document.createElement("div");
    editor.className = "web-editor";
    panel.append(editor);
    if (focusedRow()) {
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

    // The colouring comes from PerkTree run over what is on disk, so an unsaved
    // change moves the fields but not the web until it is saved.
    if (fileHasChanges(row.file)) {
      const dirty = document.createElement("span");
      dirty.className = "hint";
      dirty.textContent = "unsaved - the web recolours after Save";
      heading.append(dirty);
    } else {
      const reload = document.createElement("button");
      reload.textContent = "Recompute";
      reload.title = "Re-read the web from disk";
      reload.onclick = async () => {
        try {
          view.report = await api("/api/perks");
          view.render();
        } catch (error) { log(String(error), true); }
      };
      heading.append(reload);
    }
    target.append(heading);

    // Only a perk has costs to report; a followed chip is some other resource.
    if (perk) {
      const costs = document.createElement("div");
      costs.className = "web-stats";
      costs.textContent = `${format(perk.cost_to_max)} to max · ${format(perk.path_cost)} to reach `
        + `· depth ${perk.depth} · ${perk.branch_label}`;
      target.append(costs);
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

  /** One of the picked perk's effects, with its own value fields. Reference
   * columns are left out: a dependency is followed through the chips above, and
   * what belongs here are the numbers being tuned. */
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
      if (columnIndex === 0 || references.has(column)) return;
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

  view.open = async () => {
    // Rebuilt on every open: a saved edit changes what PerkTree produces, and
    // the server drops its cached report whenever the data is written.
    view.report = await api("/api/perks");
    // Clicking a perk hands over to the graph view, which spans every file and
    // walks the reference edges, so both have to be in memory before it does.
    await loadAllFiles();
    buildEdges();
  };

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "web-view";
    wrap.innerHTML = `<div class="web-canvas"></div><aside class="web-panel"></aside>`;
    return wrap;
  };

  view.render = () => {
    if (!view.report) return;
    view.element.querySelector(".web-canvas").replaceChildren(drawWeb());
    renderPanel(view.element.querySelector(".web-panel"));
    const row = focusedRow();
    setStatus(row
      ? `editing ${labelOf(row)}${fileHasChanges(row.file) ? " · unsaved" : ""}`
      : `prestige web - ${view.report.perks.length} perks in `
        + `${view.report.branches.length - 1} branches`);
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.web = view;
})();
