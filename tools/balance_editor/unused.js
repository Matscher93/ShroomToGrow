/* Unused view: the resources nothing keeps, and a way to be rid of them.
 *
 * Everything here comes from GET /api/unused, which walks res://data with the
 * same loader the rest of the editor uses and asks two questions per file:
 * does any other resource point at it, and does any script, scene or project
 * file name its path, its uid, or the folder it sits in. A file that answers no
 * twice is dead weight - an effect dropped from its last node, an upgrade left
 * behind by a redesign - and is what this view lists.
 *
 * Deleting goes through the same /api/delete the graph's Delete button uses, so
 * a file that turns out to be referenced after all is unlinked properly rather
 * than left as a dangling path.
 *
 * Registered on window.BalanceViews, which index.html turns into a view button.
 */
(() => {
  const view = {
    label: "Unused",
    title: "Resources nothing references, and a way to delete them",
    report: null,
  };

  /* -------------------------------------------------------------------- rows */

  /** Grouped by type, then by name: deleting is decided type by type ("are all
   * these effects really loose?"), not in the order the walker happened to
   * find them. */
  function rows() {
    const found = (view.report && view.report.unused) || [];
    return [...found].sort((a, b) =>
      a.type.localeCompare(b.type) || a.label.localeCompare(b.label));
  }

  const shortPath = (path) => path.replace(/^res:\/\/data\//, "");

  function table() {
    const table = document.createElement("table");
    table.className = "web-table unused-table";
    const head = table.insertRow();
    for (const column of ["what", "type", "file", ""]) {
      const th = document.createElement("th");
      th.textContent = column;
      head.append(th);
    }

    let lastType = null;
    for (const entry of rows()) {
      const row = table.insertRow();
      if (entry.type !== lastType) row.className = "branch";   // the table's group rule
      lastType = entry.type;

      const name = row.insertCell();
      name.textContent = entry.label;
      name.className = "link";
      name.title = "Open this in the graph";
      name.onclick = () => {
        setFocus(entry.res_path);
        setView("graph");
      };

      row.insertCell().textContent = entry.type;
      const file = row.insertCell();
      file.textContent = shortPath(entry.res_path);
      file.className = "web-stats";
      file.title = entry.res_path;

      const actions = row.insertCell();
      const remove = document.createElement("button");
      remove.className = "danger";
      remove.textContent = "Delete";
      remove.title = "Remove this file from disk";
      remove.onclick = async () => {
        // The single-file path keeps its own confirmation and dry-run preview,
        // which is what says whether anything would go down with it.
        await deleteResource(entry.res_path);
        await refresh();
      };
      actions.append(remove);
    }

    if (!rows().length) {
      const row = table.insertRow();
      const cell = row.insertCell();
      cell.colSpan = 4;
      cell.className = "web-stats";
      cell.textContent = view.report
        ? `nothing loose - all ${view.report.checked} resources are spoken for`
        : "not scanned yet";
    }
    return table;
  }

  /* ------------------------------------------------------------------ actions */

  /** Deletes the whole list behind one confirmation. Each file still goes
   * through /api/delete one at a time, so anything that turns out to be
   * referenced is unlinked rather than left dangling, and one failure does not
   * stop the rest. */
  async function deleteAll() {
    const targets = rows().map((entry) => entry.res_path);
    if (!targets.length) return;
    if (anyDirty()) {
      log("save or revert your edits first - deleting re-reads every table", true);
      return;
    }
    const lines = [`Delete ${targets.length} unreferenced resource(s)?`, "",
      ...targets.map(shortPath), "",
      "This writes to disk immediately and cannot be undone from here."];
    if (!confirm(lines.join("\n"))) return;

    let deleted = 0;
    for (const path of targets) {
      try {
        const result = await api("/api/delete", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ res_path: path }),
        });
        state.files = result.files;
        lastVersion = Math.max(lastVersion, result.version || 0);
        deleted += 1;
      } catch (error) {
        log(`${shortPath(path)}: ${error}`, true);
      }
    }

    // One reload for the lot: every table was re-read on the server side as the
    // deletes landed, and the page's copies are all stale by now.
    state.edits.clear();
    state.loaded.clear();
    await loadAllFiles();
    buildEdges();
    renderFileList();
    log(`deleted ${deleted} of ${targets.length} unreferenced resource(s)`);
    await refresh();
  }

  /** Re-runs the scan.
   *
   * The server caches the report until the data is written through it, so after
   * a delete there is nothing to do but ask again. Picking up a file added or
   * unlinked in the Godot editor means having it re-read the .tres files first,
   * which is what `reread` does - and what unsaved edits rule out, since that
   * re-read would discard them. */
  async function refresh(reread = false) {
    if (reread && anyDirty()) {
      log("unsaved edits - showing the last scan rather than re-reading from disk", true);
    } else if (reread) {
      const result = await api("/api/reload", { method: "POST" });
      state.files = result.files;
      lastVersion = Math.max(lastVersion, result.version || 0);
      state.loaded.clear();
      await loadAllFiles();
      buildEdges();
      renderFileList();
    }
    await view.invalidate();
    view.render();
  }

  /* ------------------------------------------------------------------- wiring */

  view.invalidate = async () => {
    view.report = await api("/api/unused");
  };

  view.open = async () => {
    await view.invalidate();
    // Clicking a name hands over to the graph, which spans every file.
    await loadAllFiles();
    buildEdges();
  };

  view.mount = () => {
    const wrap = document.createElement("div");
    wrap.id = "unused-view";
    wrap.innerHTML = `<div class="unused-body"></div>`;
    return wrap;
  };

  view.render = () => {
    const body = view.element.querySelector(".unused-body");
    body.replaceChildren();

    const head = document.createElement("div");
    head.className = "web-editor-head";
    const heading = document.createElement("h2");
    heading.textContent = `Unused resources (${rows().length})`;
    head.append(heading);

    const buttons = document.createElement("div");
    buttons.className = "actions";
    const rescan = document.createElement("button");
    rescan.textContent = "Rescan";
    rescan.title = "Re-read the .tres files and walk them again";
    rescan.onclick = () => { refresh(true).catch((error) => log(String(error), true)); };
    buttons.append(rescan);
    if (rows().length) {
      const all = document.createElement("button");
      all.className = "danger";
      all.textContent = `Delete all ${rows().length}`;
      all.title = "Delete every file listed here";
      all.onclick = () => { deleteAll().catch((error) => log(String(error), true)); };
      buttons.append(all);
    }
    head.append(buttons);
    body.append(head);

    const hint = document.createElement("p");
    hint.className = "hint";
    hint.textContent = "Listed here: files no other resource points at, and that no script, "
      + "scene or project file names by path, by uid, or by the folder it loads whole. "
      + "Anything the game reaches only at runtime through a string it builds itself would "
      + "look loose too - read the list before emptying it.";
    body.append(hint);

    if (view.report && view.report.errors && view.report.errors.length) {
      const errors = document.createElement("p");
      errors.className = "hint warn";
      errors.textContent = view.report.errors.join(" · ");
      body.append(errors);
    }

    body.append(table());

    const kept = view.report ? view.report.kept_by_source.length : 0;
    setStatus(view.report
      ? `${rows().length} unreferenced of ${view.report.checked} resources `
        + `· ${kept} named in scripts or scenes`
      : "unused - press Rescan");
  };

  window.BalanceViews = window.BalanceViews || {};
  window.BalanceViews.unused = view;
})();
