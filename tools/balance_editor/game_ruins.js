/* Ruins screen: the mission board, the roster that works it, and what both cost.
 *
 * view/ruins/sc_ruins.tscn is three sub-screens - Missions, Heroes, Boosts - over
 * a board of expeditions and farms. This screen is that, plus the two things the
 * game has no room to say: what a chain's duration and payout curves look like
 * end to end, and everything outside data/ruins that pushes on this economy.
 *
 * The Ruins are the widest block of authored data in the project - 154 missions,
 * 7 heroes, 14 boosts - and they are the one economy with two halves that divide
 * the same clock:
 *
 *   expedition  one hero, one chain, one step at a time. duration divides by
 *               (1 + speed_per_level * level), payout scales by
 *               (1 + yield_per_level * level)
 *   farm        any number of workers, run in parallel across farm_slots.
 *               duration divides by the worker count; the payout does NOT scale
 *               with it - a farm pays its authored rate per cycle whoever turns
 *               it, or stacking one farm would beat running two
 *
 * Five sections, switched rather than stacked. One section at a time because a
 * render rebuilds the whole body on every keystroke, and 154 cards at once is
 * not a page anyone can edit in. Chains go one hero further: a chain is 20 steps,
 * and they are read against each other rather than against another hero's.
 *
 * Registered on window.BalanceScreens, which game.js turns into a tab.
 */
(() => {
  const {
    formatBig, log10Of, growthCurve, hueOf, chartBlock, enumIs,
    engineCurve, engineSeries, rowsOf, cell, numberCell,
    field, fieldGroup, bigField, scopeTargetFields,
  } = window.GameKit;

  /* Constants the game holds in GDScript rather than in .tres, so this editor
   * cannot write them. Listed because leaving them out would imply a board with
   * no slots and a farm that keeps paying however long the game was closed. */
  const CODE = {
    farmSlots: 1,          // MissionSystem.BASE_FARM_SLOTS
    workersPerFarm: 1,     // WorkerSystem.BASE_WORKERS_PER_FARM
    offlineCap: 86400,     // OfflineProgress.MAX_SECONDS - one day
  };

  /* What test/data/authored_data_test.gd asserts about the shape of this data.
   * Mirrored rather than enforced: a half-finished edit is allowed to be invalid,
   * and the screen's job is to say so, not to refuse it. */
  const SHAPE = {
    chains: 7,
    steps: 20,
    // Zero-indexed step -> the hero level it asks for. Steps 6, 11 and 16.
    gates: { 5: 2, 10: 3, 15: 4 },
  };

  /* Every stat ProductionSystem reads on behalf of the Ruins - see
   * mission_speed(), farm_slots(), workers_per_farm(), hero_level_bonus() and
   * modify_mission_reward() - plus the three currency gains a payout carries. */
  const RUINS_STATS = [
    "mission_speed", "mission_reward", "farm_slots", "workers_per_farm",
    "hero_level_cap", "relic_gain", "ichor_gain", "glyph_gain",
  ];

  const SECTIONS = [
    { key: "chains", label: "Chains" },
    { key: "farms", label: "Farms" },
    { key: "heroes", label: "Heroes" },
    { key: "workers", label: "Workers" },
    { key: "boosts", label: "Boosts" },
  ];

  const screen = {
    label: "Ruins",
    section: "chains",
    hero: null,        // which chain is showing, by hero id
  };

  /* ------------------------------------------------------------------ basics */

  const list = (value) => (value || "").split("|").filter(Boolean);
  const isTrue = (value) => value === "true";
  const rowFor = (path) => (path ? rowIndexOf(path) : null);
  const nameOf = (entry) => (entry && cell(entry, "display_name")) || "(unnamed)";

  /** Enough of a path to place a row without it running off a card. */
  const shortPath = (path) => (path || "").split("::")[0]
    .replace(/^res:\/\/data\//, "").split("/").slice(-2).join("/");

  /** A currency def's path as the one word anybody calls it. */
  const currencyName = (path) => (path || "").split("/").pop()
    .replace(/^res_/, "").replace(/_def\.tres$/, "") || "—";

  /* Which gain stat rides on which currency. Mirrors the table in
   * authored_data_test.test_every_payout_gain_stat_matches_its_currency(), which
   * is where the pairing is actually decided - a CurrencyDef does not carry its
   * own stat, so there is nothing in the data to read it off. Anything not
   * listed here is expected to carry no gain_stat at all, which is what that
   * test asserts too.
   *
   * Note the singulars: the currency is "relics", the stat is "relic_gain". */
  const GAIN_STATS = {
    relics: "relic_gain",
    ichor: "ichor_gain",
    glyphs: "glyph_gain",
  };

  /** Seconds as the card would rather read them. */
  function duration(seconds) {
    if (!Number.isFinite(seconds) || seconds <= 0) return "—";
    if (seconds < 90) return `${Math.round(seconds)}s`;
    if (seconds < 5400) return `${(seconds / 60).toFixed(1)}m`;
    return `${(seconds / 3600).toFixed(2)}h`;
  }

  const hint = (text, warn) => {
    const note = document.createElement("p");
    note.className = warn ? "hint warn" : "hint";
    note.textContent = text;
    return note;
  };

  const heading = (text) => {
    const head = document.createElement("h4");
    head.textContent = text;
    return head;
  };

  function group(title, ...children) {
    const wrap = document.createElement("div");
    wrap.className = "game-group";
    if (title) wrap.append(heading(title));
    wrap.append(...children);
    return wrap;
  }

  /** A heading that governs the cards after it rather than the ones inside it,
   * which is what lets one fold reach a whole section. */
  function band(text, note) {
    const wrap = document.createElement("div");
    wrap.className = "game-group game-section";
    wrap.append(heading(text));
    if (note) wrap.append(hint(note));
    return wrap;
  }

  /* -------------------------------------------------------------- the tables */

  const missionListRow = () => rowsOf("MissionList")[0] || null;
  const workerRow = () => rowsOf("WorkerCostDef")[0] || null;

  /** Rows of `table` in the order the registry holds them, which is the order the
   * game walks them in. Falls back to the table's own order when the registry is
   * missing, so the screen degrades rather than empties. */
  function ordered(table, registry, column) {
    const rows = rowsOf(table);
    const registryRow = rowsOf(registry)[0];
    const paths = registryRow ? list(cell(registryRow, column)) : [];
    if (!paths.length) return rows;
    const byPath = new Map(rows.map((entry) => [entry.path, entry]));
    const out = paths.map((path) => byPath.get(path)).filter(Boolean);
    // Anything the registry does not name is unreachable in game, but hiding it
    // would leave it uneditable and invisible at once.
    for (const entry of rows) if (!paths.includes(entry.path)) out.push(entry);
    return out;
  }

  const missionEntries = () => ordered("MissionDef", "MissionList", "missions");
  const heroEntries = () => ordered("HeroDef", "HeroList", "heroes");
  const boostEntries = () => ordered("MissionBoostDef", "MissionBoostList", "boosts");

  /** The expeditions of each hero, in chain order, keyed by hero id.
   *
   * Chain order is MissionList's order and nothing else - there is no index
   * field, and the NN_ filename prefix is a convention the game never reads.
   * MissionSystem buckets by hero_id over that same list at construction. */
  function chains() {
    const out = new Map();
    for (const entry of missionEntries()) {
      if (isTrue(cell(entry, "is_farm"))) continue;
      const hero = cell(entry, "hero_id");
      if (!out.has(hero)) out.set(hero, []);
      out.get(hero).push(entry);
    }
    return out;
  }

  const farmEntries = () => missionEntries().filter((entry) => isTrue(cell(entry, "is_farm")));

  /** One mission's payouts, or a hero's or the crew's prices - the same
   * MissionPayoutDef either way, which is why one reader serves all three. */
  function payoutsOf(entry, column) {
    return list(cell(entry, column)).map((path, index) => {
      const payout = rowFor(path);
      return {
        index, path, payout,
        currency: currencyName(payout && cell(payout, "currency")),
        amount: payout
          ? numberCell(payout, "_amount_mantissa", 0) * 10 ** numberCell(payout, "_amount_exponent", 0)
          : 0,
      };
    });
  }

  /** What one run of this mission pays, summed across its currencies.
   *
   * Summed linearly, which is safe here and would not be on a cost curve: the
   * deepest authored payout is around 1e4 per currency, decades inside a double.
   * Summing across currencies is the measure the chains were authored to - the
   * generator splits one step's total over a hero's currencies - and it is the
   * measure the pacing assertion reads. */
  const payoutTotal = (entry) => payoutsOf(entry, "payouts")
    .reduce((total, slot) => total + (Number.isFinite(slot.amount) ? slot.amount : 0), 0);

  /* ---------------------------------------------------------------- warnings */

  /** Where a series stops climbing strictly. A dip is invisible on a log chart
   * spanning four decades, and it is the one thing the suite fails a chain for. */
  function dips(values) {
    const out = [];
    for (let i = 1; i < values.length; i += 1) {
      if (values[i] === null || values[i - 1] === null) continue;
      if (values[i] <= values[i - 1]) out.push(i + 1);
    }
    return out;
  }

  /* ------------------------------------------------------- create and delete */

  /** The refresh every write through /api/create or /api/delete owes: the file
   * list changed, every table was re-read, and the screen is showing rows that
   * may no longer exist. Mirrors the tail of index.html's createChild(). */
  async function refresh(result) {
    state.files = result.files || state.files;
    lastVersion = Math.max(lastVersion, result.version || 0);
    state.loaded.clear();
    await loadAllFiles();
    buildEdges();
    log((result.changes || []).join("\n"));
    renderFileList();
    renderActiveView();
  }

  /** A create box for one reference column, using the same rule table and the
   * same POST the graph panel uses. Returns null for a column with no rule, so a
   * screen can offer the box wherever one exists without asserting which. */
  function createBox(entry, column) {
    const rule = pathRefFor(entry.file, column);
    return rule && rule.creates ? createRow(entry, column, rule) : null;
  }

  function deleteButton(path, title) {
    const button = document.createElement("button");
    button.className = "danger";
    button.textContent = "Delete";
    button.title = title;
    button.onclick = () => { deleteResource(path); };
    return button;
  }

  /** Adds a mission and links it into MissionList at the right place.
   *
   * The plain create box would append it to the end of the list, which for an
   * expedition means the end of the *last* chain rather than of this hero's -
   * and the list's order is the chain's order. So this posts the index itself.
   */
  async function addMission({ heroId, isFarm, after, path, id, values }) {
    if (anyDirty()) {
      log("save or revert your edits first - creating re-reads every table", true);
      return;
    }
    const registry = missionListRow();
    if (!registry) {
      log("no MissionList is loaded, so a new mission would have nothing to link into", true);
      return;
    }
    const paths = list(cell(registry, "missions"));
    const index = after ? paths.indexOf(after) + 1 : paths.length;
    try {
      const result = await api("/api/create", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          table: "MissionDef",
          path,
          values: {
            id,
            display_name: values.display_name,
            is_farm: isFarm ? "true" : "false",
            hero_id: heroId || "",
            ...values,
          },
          link: { res_path: registry.path, column: "missions", index },
        }),
      });
      await refresh(result);
      setFocus(result.path);
    } catch (error) {
      log(String(error), true);
    }
  }

  /* ================================================================== chains */

  function chainsSection(body) {
    const all = chains();
    const heroes = heroEntries();
    // Chain order follows the roster where it can, so the picker reads in the
    // order the player meets them rather than in whatever order the files sort.
    const ids = heroes.map((entry) => cell(entry, "id")).filter((id) => all.has(id));
    for (const id of all.keys()) if (!ids.includes(id)) ids.push(id);

    if (!ids.length) {
      body.append(hint("No expeditions are loaded. Press \"Reload from .tres\" and try again."));
      return;
    }
    if (!ids.includes(screen.hero)) screen.hero = ids[0];

    body.append(chainPicker(ids, all, heroes));

    const steps = all.get(screen.hero) || [];
    const hero = heroes.find((entry) => cell(entry, "id") === screen.hero) || null;
    body.append(chainOverview(screen.hero, steps, hero));
    steps.forEach((entry, index) => body.append(missionCard(entry, index, steps, hero)));
    setStatus(`${screen.hero} · ${steps.length} steps · `
      + `${ids.length} chains · ${missionEntries().length} missions in all`);
  }

  function chainPicker(ids, all, heroes) {
    const wrap = document.createElement("div");
    wrap.className = "web-modes ruins-picker";
    for (const id of ids) {
      const hero = heroes.find((entry) => cell(entry, "id") === id);
      const button = document.createElement("button");
      button.textContent = `${hero ? nameOf(hero) : id} (${(all.get(id) || []).length})`;
      button.classList.toggle("active", id === screen.hero);
      button.onclick = () => {
        if (screen.hero === id) return;
        screen.hero = id;
        renderActiveView();
      };
      wrap.append(button);
    }
    return wrap;
  }

  /** The two curves a chain is authored as, and the complaints about them. */
  function chainOverview(heroId, steps, hero) {
    const wrap = band(`${hero ? nameOf(hero) : heroId} — ${steps.length} steps`,
      "One expedition at a time, in this order. The order is MissionList's, not the "
      + "NN_ filename prefix and not the table's - nothing reads the prefix.");

    const seconds = steps.map((entry) => numberCell(entry, "base_duration_seconds", 0));
    const payouts = steps.map(payoutTotal);
    const asLog = (value) => (value > 0 ? Math.log10(value) : null);

    wrap.append(chartBlock("Duration and payout over the chain", [
      { label: "seconds", points: seconds.map(asLog), color: "var(--accent)" },
      { label: "payout per run", points: payouts.map(asLog), color: hueOf(3) },
    ], { log: true, width: 900, height: 200, xLabel: "step", xOffset: 1 }));

    const complaints = [];
    const slowerAt = dips(seconds);
    const poorerAt = dips(payouts);
    if (slowerAt.length) {
      complaints.push(`Duration stops climbing at step ${slowerAt.join(", ")}.`);
    }
    if (poorerAt.length) {
      complaints.push(`Payout stops climbing at step ${poorerAt.join(", ")}.`);
    }
    if (steps.length !== SHAPE.steps) {
      complaints.push(`This chain has ${steps.length} steps, not ${SHAPE.steps}.`);
    }
    for (const [at, level] of Object.entries(SHAPE.gates)) {
      const step = steps[Number(at)];
      if (!step) continue;
      const asked = Math.round(numberCell(step, "min_hero_level", 1));
      if (asked !== level) {
        complaints.push(`Step ${Number(at) + 1} asks for level ${asked}, not ${level}.`);
      }
    }
    if (complaints.length) {
      wrap.append(hint(`${complaints.join(" ")} `
        + "test/data/authored_data_test.gd asserts each of these, so the suite is red "
        + "until it is either fixed here or changed there.", true));
    }

    const add = document.createElement("button");
    add.textContent = "+ step";
    add.title = `Appends a step to ${heroId}'s chain, linked into MissionList right after `
      + "its last one. The suite asserts seven chains of exactly twenty, so this turns it "
      + "red until that constant is changed too.";
    add.onclick = () => {
      const last = steps[steps.length - 1];
      const number = String(steps.length + 1).padStart(2, "0");
      const id = `${heroId}_step_${number}`;
      addMission({
        heroId,
        isFarm: false,
        after: last && last.path,
        path: `res://data/ruins/chains/${heroId}/${number}_${id}.tres`,
        id,
        values: {
          display_name: `Step ${steps.length + 1}`,
          description: `Step ${steps.length + 1} of ${heroId}'s chain.`,
          base_duration_seconds: String(
            Math.round((last ? numberCell(last, "base_duration_seconds", 60) : 60) * 1.3)),
          min_hero_level: "1",
        },
      });
    };
    wrap.append(add);
    return wrap;
  }

  /* ------------------------------------------------------------ mission card */

  function missionCard(entry, index, steps, hero) {
    const farm = isTrue(cell(entry, "is_farm"));
    const wrap = document.createElement("section");
    wrap.className = "game-card ruins-card";
    wrap.append(missionHead(entry, index, steps.length, farm));

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["id", "display_name", "description"]));
    body.append(gateBlock(entry, farm, index));
    body.append(payoutBlock(entry, hero, farm));
    if (!farm) body.append(rewardBlock(entry));
    return wrap;
  }

  function missionHead(entry, index, total, farm) {
    const row = document.createElement("header");
    row.className = "game-card-head";

    const icon = document.createElement("span");
    icon.className = "game-card-icon";
    row.append(icon);

    const names = document.createElement("div");
    names.className = "game-card-names";
    const name = document.createElement("strong");
    name.textContent = nameOf(entry);
    const description = document.createElement("span");
    description.textContent = cell(entry, "description");
    names.append(name, description);
    row.append(names);

    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    const seconds = numberCell(entry, "base_duration_seconds", 0);
    badge.textContent = farm
      ? `${duration(seconds)} per cycle`
      : `step ${index + 1} / ${total} · ${duration(seconds)}`;
    row.append(badge);

    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.title = "Open this mission in the dependency graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    row.append(open, deleteButton(entry.path,
      `Deletes ${shortPath(entry.path)} and unlinks it from MissionList`));
    return row;
  }

  /** What has to be true before this mission may be started, and what it costs in
   * time once it is. The two halves of the roster divide the clock the same way,
   * so the same block serves both with a different denominator. */
  function gateBlock(entry, farm, index) {
    const wrap = group(farm ? "Cycle & gates" : "Timing & gates");
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of farm
      ? ["base_duration_seconds", "min_missions_completed", "requires_mission_id",
        "unlock_perk_id", "is_farm"]
      : ["base_duration_seconds", "min_hero_level", "hero_id", "unlock_perk_id", "is_farm"]) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }
    wrap.append(fields);

    if (!farm) {
      const asked = Math.round(numberCell(entry, "min_hero_level", 1));
      const expected = SHAPE.gates[index] || 1;
      wrap.append(hint("An expedition opens when every step before it is home and its hero "
        + "is levelled far enough - nothing else. min_missions_completed and "
        + "requires_mission_id are read for farms only, and the suite asserts both stay "
        + `empty here. This step asks for level ${asked}; the ladder puts ${expected} on it.`,
        asked !== expected));
      const tally = Math.round(numberCell(entry, "min_missions_completed", 0));
      const requires = cell(entry, "requires_mission_id");
      if (tally !== 0 || requires) {
        wrap.append(hint(`This expedition carries ${tally ? `min_missions_completed ${tally}` : ""}`
          + `${tally && requires ? " and " : ""}${requires ? `requires_mission_id "${requires}"` : ""}`
          + ". Neither is read for an expedition, and the suite fails on both.", true));
      }
    } else {
      wrap.append(hint(`A farm runs on workers rather than on a hero: every worker on it `
        + `divides the cycle, so ${duration(numberCell(entry, "base_duration_seconds", 0))} `
        + `becomes ${duration(numberCell(entry, "base_duration_seconds", 0) / 4)} with four. `
        + `The board holds ${CODE.farmSlots} farm at once before farm_slots widens it, and `
        + `${CODE.workersPerFarm} worker per farm before workers_per_farm does. Offline `
        + `progress settles at most ${CODE.offlineCap / 3600}h, so a cycle longer than that `
        + "cannot complete more than once while the game is closed."));
    }
    return wrap;
  }

  /* ------------------------------------------------------------- the payouts */

  function payoutBlock(entry, hero, farm) {
    const slots = payoutsOf(entry, "payouts");
    const wrap = group(`Payouts (${slots.length})`);

    if (!slots.length) {
      wrap.append(hint("This mission pays nothing, which the suite fails it for.", true));
    }
    for (const slot of slots) wrap.append(payoutRow(slot, entry));

    const box = createBox(entry, "payouts");
    if (box) wrap.append(box);

    const total = payoutTotal(entry);
    if (total > 0) {
      const scaled = !farm && hero
        ? 1 + numberCell(hero, "yield_per_level", 0) * Math.round(numberCell(hero, "base_level_cap", 0))
        : 1;
      wrap.append(hint(farm
        ? `${formatBig(total / 10 ** Math.floor(Math.log10(total)), Math.floor(Math.log10(total)))} `
          + "per cycle, flat: a farm pays its authored rate however many workers turn it. "
          + "The workers are already paid for in cycles."
        : `${total.toPrecision(3)} per run at level 1, ${(total * scaled).toPrecision(3)} at `
          + `the level cap - the hero's yield_per_level scales an expedition's payout, and `
          + `mission_reward scales it again on top.`));
    }

    // Every currency a mission pays has to be one its hero pays in, and its
    // gain_stat has to be the one that currency answers to. Both are asserted.
    if (hero) {
      const allowed = list(cell(hero, "payout_currencies")).map(currencyName);
      const stray = slots
        .filter((slot) => slot.payout && !allowed.includes(slot.currency))
        .map((slot) => slot.currency);
      if (stray.length) {
        wrap.append(hint(`${nameOf(hero)} pays in ${allowed.join(", ") || "nothing"}, but this `
          + `mission pays ${stray.join(", ")}. A chain that quietly starts paying a fourth `
          + "currency is what that assertion exists to catch.", true));
      }
    }
    return wrap;
  }

  function payoutRow(slot, owner) {
    const wrap = document.createElement("div");
    wrap.className = "ruins-row";
    if (!slot.payout) {
      wrap.append(hint(`${shortPath(owner.path)} lists ${slot.path}, but no payout answers `
        + "to it.", true));
      return wrap;
    }
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["currency", "gain_stat"]) {
      const editor = field(slot.payout, column);
      if (editor) fields.append(editor);
    }
    fields.append(bigField(slot.payout, `amount (${slot.currency})`, "_amount"));
    wrap.append(fields, deleteButton(slot.path, "Removes this payout from the mission"));

    // A payout's gain_stat is what the per-currency gain effects find it by; the
    // wrong one silently drops it out of every bonus. Empty is allowed and means
    // "scales on nothing" - a price is authored that way, and so is a payout that
    // deliberately sits outside the gain stats.
    const stat = cell(slot.payout, "gain_stat");
    const expected = GAIN_STATS[slot.currency] || "";
    if (stat && stat !== expected) {
      wrap.append(hint(`gain_stat is "${stat}" but this pays ${slot.currency}, which scales on `
        + `${expected ? `"${expected}"` : "nothing"}. The payout still lands; nothing that `
        + `boosts ${slot.currency} finds it.`, true));
    }
    return wrap;
  }

  /* ------------------------------------------------------------- the rewards */

  /** What completing this expedition grants for good. Registered through
   * ExpeditionRewardTree as a one-level UpgradeDef, so it has a magnitude and no
   * price - which is why there is no cost curve here and one on every boost. */
  function rewardBlock(entry) {
    const paths = list(cell(entry, "rewards"));
    const wrap = group(`Rewards (${paths.length})`);

    if (!paths.length) {
      wrap.append(hint("No permanent reward. Most steps carry none - the anchors and the "
        + "reward ladder (steps 1, 3, 6, 11 and every fifth) are where they sit."));
    }
    for (const path of paths) {
      const effect = rowFor(path);
      if (!effect) {
        wrap.append(hint(`${shortPath(entry.path)} lists ${path}, but no effect answers to it.`,
          true));
        continue;
      }
      wrap.append(effectRow(effect, path));
    }
    const box = createBox(entry, "rewards");
    if (box) wrap.append(box);
    return wrap;
  }

  /** One UpgradeEffectDef, laid out the way every other screen lays one out. */
  function effectRow(effect, path) {
    const wrap = document.createElement("div");
    wrap.className = "ruins-row";
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["stat", "op"]) {
      const editor = field(effect, column);
      if (editor) fields.append(editor);
    }
    // Paired, because the scope decides what the target may say.
    fields.append(scopeTargetFields(effect));
    for (const column of ["per_level", "level_scaling", "max_magnitude", "dependency"]) {
      const editor = field(effect, column);
      if (editor) fields.append(editor);
    }
    wrap.append(fields, deleteButton(path, "Removes this effect from the resource carrying it"));

    // A reward is granted at one level, so a COMPOUND scaling and a per_level
    // meant to accumulate both do nothing an author would expect.
    if (enumIs(cell(effect, "level_scaling"), "COMPOUND")) {
      wrap.append(hint("This is granted at level 1 and never levelled, so COMPOUND and LINEAR "
        + "are the same thing here.", false));
    }
    return wrap;
  }

  /* =================================================================== farms */

  function farmsSection(body) {
    const farms = farmEntries();
    body.append(band(`Farms (${farms.length})`,
      "Standing details, worked by however many of the crew can be spared. A farm has no "
      + "chain and no hero: it opens on one expedition being home, and after that it runs "
      + "as often as the board has slots for."));

    const registry = missionListRow();
    if (registry) {
      const add = document.createElement("button");
      add.textContent = "+ farm";
      add.title = "Creates a farm under data/ruins and appends it to MissionList";
      add.onclick = () => {
        const id = `farm_new_${farms.length + 1}`;
        addMission({
          heroId: "", isFarm: true, after: null,
          path: `res://data/ruins/res_${id}.tres`,
          id,
          values: {
            display_name: "New Farm",
            description: "A standing detail, worked by whoever can be spared.",
            base_duration_seconds: "60", min_hero_level: "1",
          },
        });
      };
      body.append(add);
    }

    if (!farms.length) {
      body.append(hint("No farms are loaded. Press \"Reload from .tres\" and try again."));
      return;
    }

    body.append(chartBlock("Cycle length and payout across the farms", [
      {
        label: "seconds",
        points: farms.map((entry) => {
          const seconds = numberCell(entry, "base_duration_seconds", 0);
          return seconds > 0 ? Math.log10(seconds) : null;
        }),
        color: "var(--accent)",
      },
      {
        label: "payout per cycle",
        points: farms.map((entry) => {
          const total = payoutTotal(entry);
          return total > 0 ? Math.log10(total) : null;
        }),
        color: hueOf(3),
      },
    ], { log: true, width: 900, height: 200, xLabel: "farm, in board order" }));

    farms.forEach((entry, index) => {
      const opener = cell(entry, "requires_mission_id");
      const openerRow = opener
        ? missionEntries().find((row) => cell(row, "id") === opener) : null;
      const hero = openerRow
        ? heroEntries().find((row) => cell(row, "id") === cell(openerRow, "hero_id")) : null;
      const card = missionCard(entry, index, farms, hero);
      if (opener && !openerRow) {
        card.querySelector(".game-card-body").append(hint(
          `requires_mission_id names "${opener}", and no mission answers to it. The farm `
          + "never opens.", true));
      }
      body.append(card);
    });

    setStatus(`${farms.length} farms · ${CODE.farmSlots} slot before farm_slots widens it`);
  }

  /* ================================================================== heroes */

  function heroesSection(body) {
    const heroes = heroEntries();
    body.append(band(`Heroes (${heroes.length})`,
      "One hero per chain. Levelling one divides its expeditions' duration and scales their "
      + "payout - both linear in the level, not compounding - and nothing else in the game "
      + "reads a hero's level."));

    const registryRow = rowsOf("HeroList")[0];
    const box = registryRow && createBox(registryRow, "heroes");
    if (box) body.append(box);

    if (!heroes.length) {
      body.append(hint("No heroes are loaded. Press \"Reload from .tres\" and try again."));
      return;
    }
    const all = chains();
    heroes.forEach((entry) => body.append(heroCard(entry, (all.get(cell(entry, "id")) || []).length)));
    setStatus(`${heroes.length} heroes · caps ${heroes
      .map((entry) => Math.round(numberCell(entry, "base_level_cap", 0))).join("/")}`);
  }

  function heroCard(entry, steps) {
    const wrap = document.createElement("section");
    wrap.className = "game-card ruins-card";

    const head = document.createElement("header");
    head.className = "game-card-head";
    head.append(Object.assign(document.createElement("span"), { className: "game-card-icon" }));
    const names = document.createElement("div");
    names.className = "game-card-names";
    names.append(
      Object.assign(document.createElement("strong"), { textContent: nameOf(entry) }),
      Object.assign(document.createElement("span"), { textContent: cell(entry, "description") }));
    head.append(names);
    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    const gate = Math.round(numberCell(entry, "min_missions_completed", 0));
    badge.textContent = `${steps} steps · cap ${Math.round(numberCell(entry, "base_level_cap", 0))}`
      + ` · ${gate > 0 ? `opens at ${gate} missions` : "open from the start"}`;
    head.append(badge);
    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    head.append(open, deleteButton(entry.path, "Deletes this hero and unlinks it from HeroList"));
    wrap.append(head);

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["id", "display_name", "description"]));
    body.append(recruitBlock(entry));
    body.append(levelBlock(entry));
    return wrap;
  }

  /** What taking this hero over costs, once. */
  function recruitBlock(entry) {
    const wrap = group("Recruiting");
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["min_missions_completed", "recruit_currency", "payout_currencies"]) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }
    fields.append(bigField(entry, `recruit cost (${currencyName(cell(entry, "recruit_currency"))})`,
      "_recruit_cost"));
    wrap.append(fields);

    const extras = payoutsOf(entry, "extra_recruit_costs");
    if (extras.length) wrap.append(heading(`Also charged (${extras.length})`));
    for (const slot of extras) wrap.append(payoutRow(slot, entry));
    const box = createBox(entry, "extra_recruit_costs");
    if (box) wrap.append(box);

    wrap.append(hint("payout_currencies is what this hero's whole chain may pay in - the suite "
      + "checks every step against it. It is not what the hero is bought with; that is "
      + "recruit_currency, plus anything listed above."));
    return wrap;
  }

  /** The level ladder: what it costs, and what it is worth. */
  function levelBlock(entry) {
    const wrap = group("Levelling");
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["base_level_cap", "level_currency", "level_cost_growth",
      "speed_per_level", "yield_per_level"]) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }
    fields.append(bigField(entry, `level base cost (${currencyName(cell(entry, "level_currency"))})`,
      "_level_base_cost"));
    wrap.append(fields);

    const cap = Math.max(1, Math.round(numberCell(entry, "base_level_cap", 1)));
    const sampled = engineCurve(entry.path);

    // base * growth^(level - 1), so the step to level 2 is priced at base. Level
    // 0 is the same price as level 1 rather than free: nothing buys it, and
    // leaving a hole there would break the line the eye is following.
    const costBuild = (from, to) => {
      const base = log10Of(numberCell(entry, "_level_base_cost_mantissa", 1),
        numberCell(entry, "_level_base_cost_exponent", 1));
      const growth = numberCell(entry, "level_cost_growth", 1.8);
      const own = growthCurve(base, growth, 1, Math.max(0, from - 1), Math.max(0, to - 1));
      const series = [{ label: "cost of the next level", points: own, color: "var(--accent)" }];
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => (mantissa === 0 ? null : Math.log10(Math.abs(mantissa)) + exponent));
      if (dots) series.push(dots);
      return series;
    };
    wrap.append(chartBlock("Cost of the next level", costBuild, {
      log: true, xLabel: "level",
      range: { key: "hero-level-cost", from: 1, to: cap, label: "level" },
    }));

    const worthBuild = (from, to) => {
      const speed = numberCell(entry, "speed_per_level", 0);
      const yield_ = numberCell(entry, "yield_per_level", 0);
      const over = (rate, floor) => {
        const out = [];
        for (let level = from; level <= to; level += 1) out.push(Math.max(floor, 1 + rate * level));
        return out;
      };
      return [
        { label: "speed multiplier", points: over(speed, 0.01), color: "var(--accent)" },
        { label: "yield multiplier", points: over(yield_, 0), color: hueOf(3) },
      ];
    };
    wrap.append(chartBlock("What a level is worth", worthBuild, {
      zeroBased: true, xLabel: "level",
      range: { key: "hero-level-worth", from: 0, to: cap, label: "level" },
    }));

    const speed = numberCell(entry, "speed_per_level", 0);
    const yield_ = numberCell(entry, "yield_per_level", 0);
    wrap.append(hint(`At the cap, expeditions run ${(1 + speed * cap).toFixed(2)}x faster and pay `
      + `${(1 + yield_ * cap).toFixed(2)}x more. The cap here is the authored one; the `
      + "hero_level_cap stat lifts it per hero on top, so the real ceiling is higher for "
      + "anyone who has bought that."));
    return wrap;
  }

  /* ================================================================= workers */

  function workersSection(body) {
    const entry = workerRow();
    body.append(band("Workers",
      "The crew is a number, not a roster: workers have no ids, no levels and no stats. "
      + "Everything authored about them is one price per currency and the rate that price "
      + "climbs by."));

    if (!entry) {
      body.append(hint("No WorkerCostDef is loaded. Press \"Reload from .tres\" and try again."));
      return;
    }

    const wrap = document.createElement("section");
    wrap.className = "game-card ruins-card";
    const inner = document.createElement("div");
    inner.className = "game-card-body";
    wrap.append(inner);
    body.append(wrap);

    const prices = payoutsOf(entry, "prices");
    const costs = group(`Hire price (${prices.length} currencies)`);
    costs.append(field(entry, "cost_growth") || document.createComment(""));
    for (const slot of prices) costs.append(payoutRow(slot, entry));
    const box = createBox(entry, "prices");
    if (box) costs.append(box);
    costs.append(hint("Every price climbs on the same growth - WorkerSystem raises it once and "
      + "multiplies all of them by it - so the lines below are parallel and this chart is "
      + "really about where each one starts. gain_stat is unread on a price; it is only "
      + "meaningful on a payout."));
    inner.append(costs);

    const sampled = engineCurve(entry.path);
    const growth = numberCell(entry, "cost_growth", 1.35);
    const build = (from, to) => {
      const series = prices.map((slot, index) => ({
        label: slot.currency,
        points: growthCurve(
          log10Of(numberCell(slot.payout, "_amount_mantissa", 1),
            numberCell(slot.payout, "_amount_exponent", 0)),
          growth, 1, from, to),
        color: hueOf(index),
      }));
      const first = sampled && sampled.prices && sampled.prices[0];
      const dots = engineSeries(entry, first && first.cost, from, to,
        ([mantissa, exponent]) => (mantissa === 0 ? null : Math.log10(Math.abs(mantissa)) + exponent));
      if (dots) series.push(dots);
      return series;
    };
    inner.append(chartBlock("What the next worker costs", build, {
      log: true, xLabel: "workers already hired",
      range: { key: "worker-hire", from: 0, to: 30, label: "hired" },
    }));

    inner.append(hint(`A worker divides one farm's cycle. The board starts at `
      + `${CODE.workersPerFarm} worker per farm and ${CODE.farmSlots} farm at once, so the `
      + "crew is worth nothing beyond that until workers_per_farm and farm_slots have been "
      + "widened - both of which are boosts, perks and expedition rewards rather than "
      + "anything authored here."));
    setStatus(`worker hire price climbs ${growth}x per worker`);
  }

  /* ================================================================== boosts */

  function boostsSection(body) {
    const boosts = boostEntries();
    body.append(band(`Boosts (${boosts.length})`,
      "The Ruins' own upgrade ladder, priced in the currencies the missions pay and gated on "
      + "the running tally of missions completed - which counts every expedition collected "
      + "and every farm cycle settled, so farms move these gates too."));

    const registryRow = rowsOf("MissionBoostList")[0];
    const box = registryRow && createBox(registryRow, "boosts");
    if (box) body.append(box);

    if (!boosts.length) {
      body.append(hint("No boosts are loaded. Press \"Reload from .tres\" and try again."));
      return;
    }
    boosts.forEach((entry) => body.append(boostCard(entry)));
    setStatus(`${boosts.length} boosts · gates at ${boosts
      .map((entry) => Math.round(numberCell(entry, "min_missions_completed", 0)))
      .sort((a, b) => a - b).join(", ")} missions`);
  }

  function boostCard(entry) {
    const wrap = document.createElement("section");
    wrap.className = "game-card ruins-card";

    const head = document.createElement("header");
    head.className = "game-card-head";
    head.append(Object.assign(document.createElement("span"), { className: "game-card-icon" }));
    const names = document.createElement("div");
    names.className = "game-card-names";
    names.append(
      Object.assign(document.createElement("strong"), { textContent: nameOf(entry) }),
      Object.assign(document.createElement("span"), { textContent: cell(entry, "description") }));
    head.append(names);
    const max = Math.round(numberCell(entry, "max_level", 0));
    const gate = Math.round(numberCell(entry, "min_missions_completed", 0));
    const badge = document.createElement("span");
    badge.className = "game-card-badge";
    badge.textContent = `${max > 0 ? `${max} levels` : "unlimited"} · `
      + `${gate > 0 ? `opens at ${gate} missions` : "open from the start"}`;
    head.append(badge);
    const open = document.createElement("button");
    open.className = "game-card-open";
    open.textContent = "Graph";
    open.onclick = () => { setFocus(entry.path); setView("graph"); };
    head.append(open, deleteButton(entry.path,
      "Deletes this boost and unlinks it from MissionBoostList"));
    wrap.append(head);

    const body = document.createElement("div");
    body.className = "game-card-body";
    wrap.append(body);

    body.append(fieldGroup("Identity", entry, ["id", "display_name", "description"]));

    const cost = group("Price");
    const fields = document.createElement("div");
    fields.className = "game-fields";
    for (const column of ["currency", "cost_growth", "max_level", "min_missions_completed"]) {
      const editor = field(entry, column);
      if (editor) fields.append(editor);
    }
    fields.append(bigField(entry, `base cost (${currencyName(cell(entry, "currency"))})`,
      "_base_cost"));
    cost.append(fields);

    const levels = max > 0 ? max : 50;
    const sampled = engineCurve(entry.path);
    const build = (from, to) => {
      const series = [{
        label: "cost of the next level",
        points: growthCurve(
          log10Of(numberCell(entry, "_base_cost_mantissa", 1),
            numberCell(entry, "_base_cost_exponent", 1)),
          numberCell(entry, "cost_growth", 1.5), 1, from, to),
        color: "var(--accent)",
      }];
      const dots = engineSeries(entry, sampled && sampled.cost, from, to,
        ([mantissa, exponent]) => (mantissa === 0 ? null : Math.log10(Math.abs(mantissa)) + exponent));
      if (dots) series.push(dots);
      return series;
    };
    cost.append(chartBlock("Cost of the next level", build, {
      log: true, xLabel: "levels bought",
      range: { key: "ruin-boost-cost", from: 0, to: levels, label: "level" },
    }));
    if (max === 0) {
      cost.append(hint("max_level 0 means unlimited, so the chart above stops at 50 for the "
        + "sake of having an end. Nothing caps this but the price."));
    }
    body.append(cost);

    const paths = list(cell(entry, "effects"));
    const effects = group(`Effects (${paths.length})`);
    if (!paths.length) {
      effects.append(hint("This boost does nothing: it can be bought and changes no stat.", true));
    }
    for (const path of paths) {
      const effect = rowFor(path);
      if (!effect) {
        effects.append(hint(`${shortPath(entry.path)} lists ${path}, but no effect answers to it.`,
          true));
        continue;
      }
      effects.append(effectRow(effect, path));
    }
    const effectBox = createBox(entry, "effects");
    if (effectBox) effects.append(effectBox);
    body.append(effects);
    return wrap;
  }

  /* ========================================================= cross-reference */

  /** Every authored effect that pushes on this economy, wherever it lives.
   *
   * The point of the block: about sixty of these sit outside data/ruins - in the
   * Ruins biome's ten upgrades, in the Dominion perk branch, in the boosts above -
   * and tuning mission_speed meant grepping for them. It is nearly free, because
   * every table is already in memory by the time a screen renders. */
  function writersSection(body) {
    const rows = rowsOf("UpgradeEffectDef")
      .filter((entry) => RUINS_STATS.includes(cell(entry, "stat")));
    const wrap = band(`Everything that touches the Ruins (${rows.length})`,
      "Authored effects on the stats this economy reads, from anywhere in the data. "
      + "Folded away by default - open it when a number here is not doing what it says.");

    const table = document.createElement("table");
    table.className = "web-table";
    const head = document.createElement("tr");
    for (const label of ["stat", "op", "scope", "target", "per_level", "lives in"]) {
      const cellEl = document.createElement("th");
      cellEl.textContent = label;
      head.append(cellEl);
    }
    table.append(head);

    const byStat = [...rows].sort((a, b) =>
      cell(a, "stat").localeCompare(cell(b, "stat")) || a.path.localeCompare(b.path));
    for (const entry of byStat) {
      const tr = document.createElement("tr");
      for (const column of ["stat", "op", "scope", "target", "per_level"]) {
        const td = document.createElement("td");
        td.textContent = cell(entry, column) || "—";
        if (column === "per_level") td.className = "num";
        tr.append(td);
      }
      const where = document.createElement("td");
      where.className = "link";
      where.textContent = shortPath(entry.path);
      where.onclick = () => { setFocus(entry.path); setView("graph"); };
      tr.append(where);
      table.append(tr);
    }
    wrap.append(table);
    body.append(wrap);
  }

  /* ------------------------------------------------------------------ render */

  function sectionBar() {
    const wrap = document.createElement("div");
    wrap.className = "web-modes ruins-sections";
    for (const section of SECTIONS) {
      const button = document.createElement("button");
      button.textContent = section.label;
      button.classList.toggle("active", section.key === screen.section);
      button.onclick = () => {
        if (screen.section === section.key) return;
        screen.section = section.key;
        renderActiveView();
      };
      wrap.append(button);
    }
    return wrap;
  }

  const RENDERERS = {
    chains: chainsSection,
    farms: farmsSection,
    heroes: heroesSection,
    workers: workersSection,
    boosts: boostsSection,
  };

  screen.render = (body) => {
    body.append(sectionBar());
    if (!rowsOf("MissionDef").length) {
      body.append(hint("No Ruins data is loaded. Press \"Reload from .tres\" and try again."));
      return;
    }
    (RENDERERS[screen.section] || chainsSection)(body);
    writersSection(body);
  };

  window.BalanceScreens = window.BalanceScreens || {};
  window.BalanceScreens.ruins = screen;
})();
