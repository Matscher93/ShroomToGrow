#!/usr/bin/env python3
"""One-time authoring scaffold for the Ruins expedition chains.

Emits one .tres per expedition (and per new farm), then never runs again: the
files it writes are the authored data from that point on and are edited by hand.
Kept in the tree so the shape of the first cut is reproducible and reviewable.

Curves honour the twelve expeditions that already existed - those keep their
authored durations, payouts and rewards, and the generated steps interpolate
geometrically between them, so a chain is monotonic by construction.
"""
import math, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "ruins"
CHAINS = DATA / "chains"

CUR = {
    "relics": ("res_relics_def.tres", "relic_gain"),
    "ichor":  ("res_ichor_def.tres",  "ichor_gain"),
    "glyphs": ("res_glyphs_def.tres", "glyph_gain"),
}
STEPS = 20
# Steps 6/11/16, zero-indexed, and the hero level each asks for.
GATES = {5: 2, 10: 3, 15: 4}

# id, display, currencies, and the split of one step's payout across them.
HEROES = [
    ("rot_grub",       "Rot Grub",       ["relics"],                     [1.0]),
    ("pale_stalker",   "Pale Stalker",   ["ichor"],                      [1.0]),
    ("chitin_scribe",  "Chitin Scribe",  ["glyphs"],                     [1.0]),
    ("bone_hauler",    "Bone Hauler",    ["relics", "ichor"],            [0.6, 0.4]),
    ("mire_wyrm",      "Mire Wyrm",      ["ichor", "glyphs"],            [0.6, 0.4]),
    ("sanctum_herald", "Sanctum Herald", ["relics", "glyphs"],           [0.6, 0.4]),
    ("sealed_choir",   "The Sealed Choir",["relics", "ichor", "glyphs"], [0.5, 0.3, 0.2]),
]

# The twelve that already existed, pinned to their chain and step (zero-indexed).
# id, step, display, seconds, payout total, reward (stat, op, per_level, cap)
ANCHORS = {
    "rot_grub": [
        (0,  "sift_rubble",          "Sift the Rubble",        45.0,    5.0, ("node_production", 2, 0.1,  None)),
        (2,  "pry_the_flagstones",   "Pry the Flagstones",    120.0,   18.0, ("tick_rate",       0, -0.5, 4.0)),
        (5,  "breach_the_vault",     "Breach the Vault",      420.0,   90.0, ("node_production", 2, 1.0,  None)),
        (10, "plumb_the_undercroft", "Plumb the Undercroft", 1200.0,  400.0, ("biomass_gain",    2, 0.3,  None)),
    ],
    "pale_stalker": [
        (0,  "stalk_the_galleries",  "Stalk the Galleries",    90.0,    4.0, ("farm_slots",      0, 1.0,  None)),
        (2,  "bleed_the_swarm",      "Bleed the Swarm",       300.0,   20.0, ("automation_rate", 2, 0.25, None)),
        (5,  "hollow_the_brood",     "Hollow the Brood",      900.0,  110.0, ("farm_slots",      0, 1.0,  None)),
        (10, "drain_the_warden",     "Drain the Warden",     2400.0,  520.0, ("node_production", 2, 0.5,  None)),
    ],
    "chitin_scribe": [
        (0,  "trace_the_wardstone",  "Trace the Wardstone",   150.0,    3.0, ("water_production",2, 0.15, None)),
        (2,  "read_the_frieze",      "Read the Frieze",       480.0,   15.0, ("crystal_gain",    2, 0.2,  None)),
        (5,  "wake_the_choir",       "Wake the Choir",       1500.0,   80.0, ("farm_slots",      0, 1.0,  None)),
        (10, "unseal_the_sanctum",   "Unseal the Sanctum",   3600.0,  380.0, ("biomass_gain",    2, 1.0,  None)),
    ],
}

# Where a chain with no anchors starts and ends, and how far past its last anchor
# an anchored one keeps climbing.
CURVE = {
    "rot_grub":       dict(tail_duration=1.30, tail_payout=1.55),
    "pale_stalker":   dict(tail_duration=1.28, tail_payout=1.52),
    "chitin_scribe":  dict(tail_duration=1.26, tail_payout=1.50),
    "bone_hauler":    dict(start=(240.0,   60.0), end=(9000.0,   90000.0)),
    "mire_wyrm":      dict(start=(600.0,  220.0), end=(14400.0, 400000.0)),
    "sanctum_herald": dict(start=(900.0,  400.0), end=(18000.0, 900000.0)),
    "sealed_choir":   dict(start=(1800.0, 1200.0), end=(28800.0, 4.0e6)),
}

# Per-hero word pools, so a generated step still reads as that hero's own work.
WORDS = {
    "rot_grub":       (["Sift", "Grub", "Turn", "Gnaw", "Root", "Burrow", "Churn", "Rake"],
                       ["the Middens", "the Spoil Heaps", "the Sunken Floor", "the Root Cellar",
                        "the Ash Pits", "the Broken Stair", "the Silt Beds", "the Old Kitchens"]),
    "pale_stalker":   (["Stalk", "Bleed", "Cull", "Shadow", "Snare", "Harry", "Thin", "Run Down"],
                       ["the Galleries", "the Nest Ways", "the Brood Halls", "the Long Dark",
                        "the Weeping Vents", "the Spawn Pools", "the Chitin Warrens", "the Drone Line"]),
    "chitin_scribe":  (["Trace", "Read", "Copy", "Gloss", "Transcribe", "Parse", "Annotate", "Recite"],
                       ["the Wardstone", "the Frieze", "the Choir Scrolls", "the Bound Codex",
                        "the Sealed Margin", "the Lament Tablets", "the Root Lexicon", "the Silent Verse"]),
    "bone_hauler":    (["Haul", "Drag", "Shore Up", "Clear", "Break Out", "Winch", "Lever", "Cart Off"],
                       ["the Ossuary", "the Collapsed Nave", "the Reliquary", "the Bone Kilns",
                        "the Fallen Arch", "the Marrow Vats", "the Grave Terrace", "the Cairn Field"]),
    "mire_wyrm":      (["Drown", "Flood", "Sound", "Dredge", "Swallow", "Drain", "Coil Through", "Silt Over"],
                       ["the Sunk Cloister", "the Black Fen", "the Drowned Choir", "the Weeping Deep",
                        "the Bog Reliquary", "the Still Water", "the Leech Beds", "the Green Dark"]),
    "sanctum_herald": (["Herald", "Proclaim", "Consecrate", "Unbar", "Sanctify", "Announce", "Ordain", "Ring Out"],
                       ["the Inner Doors", "the Gilded Nave", "the Herald's Stair", "the Bright Vault",
                        "the Standing Bells", "the Crowned Apse", "the Last Threshold", "the Sun Gate"]),
    "sealed_choir":   (["Unseal", "Wake", "Answer", "Join", "Complete", "Silence", "Inherit", "Become"],
                       ["the Sealed Choir", "the First Voice", "the Whole Song", "the Root Chord",
                        "the Long Note", "the Final Verse", "the Undermind", "the Sleeping Word"]),
}

# Farms opened by each chain: (farm_id, at step index, cycle seconds, payout total)
NEW_FARMS = {
    "pale_stalker":   [("farm_thin_the_brood",     8,  360.0,  30.0)],
    "bone_hauler":    [("farm_pick_the_ossuary",   3,  300.0,  70.0),
                       ("farm_burn_the_kilns",    13, 1200.0, 900.0)],
    "mire_wyrm":      [("farm_dredge_the_fen",     3,  600.0, 260.0),
                       ("farm_tend_the_leech_beds",13, 1800.0,3200.0)],
    "sanctum_herald": [("farm_ring_the_bells",     3,  900.0, 480.0),
                       ("farm_keep_the_apse",     13, 2400.0,6000.0)],
    "sealed_choir":   [("farm_hold_the_note",      3, 1800.0,1400.0),
                       ("farm_sing_the_undermind",13, 3600.0,20000.0)],
}
# Which of a chain's steps opens each farm above, and the existing five.
EXISTING_FARM_OPENERS = {
    "farm_pick_the_middens":    "sift_rubble",
    "farm_tap_the_seeps":       "stalk_the_galleries",
    "farm_copy_the_frieze":     "read_the_frieze",
    "farm_work_the_undercroft": "plumb_the_undercroft",
    "farm_tend_the_choir":      "wake_the_choir",
}


def big(value):
    """A float as MissionPayoutDef's mantissa/exponent pair."""
    if value <= 0:
        return 0.0, 0
    exp = int(math.floor(math.log10(value)))
    return round(value / (10.0 ** exp), 6), exp


def interpolate(anchors, tail_growth, count):
    """A strictly increasing sequence of `count` values through every anchor.

    Geometric between neighbouring anchors, and continuing at `tail_growth`
    past the last one - so an authored number is never moved and the steps
    around it cannot overtake it.
    """
    out = [None] * count
    for idx, value in anchors:
        out[idx] = value
    known = sorted(i for i, v in enumerate(out) if v is not None)
    for a, b in zip(known, known[1:]):
        ratio = (out[b] / out[a]) ** (1.0 / (b - a))
        for i in range(a + 1, b):
            out[i] = out[i - 1] * ratio
    first, last = known[0], known[-1]
    for i in range(first - 1, -1, -1):
        out[i] = out[i + 1] / tail_growth
    for i in range(last + 1, count):
        out[i] = out[i - 1] * tail_growth
    return out


def chain_values(hero_id):
    """(durations, payouts) for one chain, honouring its anchors."""
    curve = CURVE[hero_id]
    anchors = ANCHORS.get(hero_id)
    if anchors:
        d = interpolate([(s, dur) for s, _, _, dur, _, _ in anchors], curve["tail_duration"], STEPS)
        p = interpolate([(s, pay) for s, _, _, _, pay, _ in anchors], curve["tail_payout"], STEPS)
        return d, p
    (d0, p0), (d1, p1) = curve["start"], curve["end"]
    dg = (d1 / d0) ** (1.0 / (STEPS - 1))
    pg = (p1 / p0) ** (1.0 / (STEPS - 1))
    return ([d0 * dg ** i for i in range(STEPS)],
            [p0 * pg ** i for i in range(STEPS)])


def step_name(hero_id, index):
    verbs, places = WORDS[hero_id]
    return "%s %s" % (verbs[index % len(verbs)], places[(index * 3 + index // len(places)) % len(places)])


def slug(name):
    out = name.lower().replace("'", "")
    return "".join(c if c.isalnum() else "_" for c in out).strip("_").replace("__", "_")


def mission_tres(mission_id, display, description, hero_id, duration, level,
                 payouts, reward, unlocks_farm):
    """One expedition file. `payouts` is [(currency_key, amount)]."""
    ext, sub, refs = [], [], []
    ext.append('[ext_resource type="Script" path="res://model/ruins/res_mission_def.gd" id="1_script"]')
    ext.append('[ext_resource type="Script" path="res://model/ruins/res_mission_payout_def.gd" id="2_payout_script"]')
    n = 3
    for key, amount in payouts:
        file_name, gain = CUR[key]
        ext.append('[ext_resource type="Resource" path="res://data/currencies/%s" id="%d_cur_%s"]' % (file_name, n, key))
        m, e = big(amount)
        sub.append('[sub_resource type="Resource" id="payout_%s"]\n'
                   'script = ExtResource("2_payout_script")\n'
                   'currency = ExtResource("%d_cur_%s")\n'
                   'gain_stat = &"%s"\n'
                   '_amount_mantissa = %s\n'
                   '_amount_exponent = %d' % (key, n, key, gain, m, e))
        refs.append('SubResource("payout_%s")' % key)
        n += 1

    rewards_line = ""
    if reward:
        stat, op, per_level, cap = reward[0], reward[1], reward[2], reward[3]
        scope, target = (reward[4], reward[5]) if len(reward) > 5 else (0, "")
        ext.append('[ext_resource type="Script" path="res://model/upgrades/res_upgrade_effect_def.gd" id="%d_effect_script"]' % n)
        body = ('[sub_resource type="Resource" id="reward_0"]\n'
                'script = ExtResource("%d_effect_script")\n'
                'stat = &"%s"\n'
                'op = %d\n'
                'scope = %d\n'
                'target = &"%s"\n'
                'per_level = %s\n'
                'level_scaling = 0' % (n, stat, op, scope, target, per_level))
        if cap is not None:
            body += "\nmax_magnitude = %s" % cap
        sub.append(body)
        rewards_line = '\nrewards = Array[ExtResource("%d_effect_script")]([SubResource("reward_0")])' % n
        n += 1

    return ('[gd_resource type="Resource" script_class="MissionDef" format=3]\n\n'
            + "\n".join(ext) + "\n\n"
            + "\n\n".join(sub) + "\n\n"
            '[resource]\n'
            'script = ExtResource("1_script")\n'
            'id = &"%s"\n'
            'display_name = "%s"\n'
            'description = "%s"\n'
            'is_farm = false\n'
            'hero_id = &"%s"\n'
            'base_duration_seconds = %.1f\n'
            'min_hero_level = %d\n'
            'min_missions_completed = 0\n'
            'unlock_perk_id = &""\n'
            'requires_mission_id = &""\n'
            'payouts = Array[ExtResource("2_payout_script")]([%s])%s\n'
            % (mission_id, display, description, hero_id, duration, level,
               ", ".join(refs), rewards_line))


def farm_tres(farm_id, display, description, opener, duration, min_level, payouts):
    ext, sub, refs = [], [], []
    ext.append('[ext_resource type="Script" path="res://model/ruins/res_mission_def.gd" id="1_script"]')
    ext.append('[ext_resource type="Script" path="res://model/ruins/res_mission_payout_def.gd" id="2_payout_script"]')
    n = 3
    for key, amount in payouts:
        file_name, gain = CUR[key]
        ext.append('[ext_resource type="Resource" path="res://data/currencies/%s" id="%d_cur_%s"]' % (file_name, n, key))
        m, e = big(amount)
        sub.append('[sub_resource type="Resource" id="payout_%s"]\n'
                   'script = ExtResource("2_payout_script")\n'
                   'currency = ExtResource("%d_cur_%s")\n'
                   'gain_stat = &"%s"\n'
                   '_amount_mantissa = %s\n'
                   '_amount_exponent = %d' % (key, n, key, gain, m, e))
        refs.append('SubResource("payout_%s")' % key)
        n += 1
    return ('[gd_resource type="Resource" script_class="MissionDef" format=3]\n\n'
            + "\n".join(ext) + "\n\n"
            + "\n\n".join(sub) + "\n\n"
            '[resource]\n'
            'script = ExtResource("1_script")\n'
            'id = &"%s"\n'
            'display_name = "%s"\n'
            'description = "%s"\n'
            'is_farm = true\n'
            'hero_id = &""\n'
            'base_duration_seconds = %.1f\n'
            'min_hero_level = %d\n'
            'min_missions_completed = 0\n'
            'unlock_perk_id = &""\n'
            'requires_mission_id = &"%s"\n'
            'payouts = Array[ExtResource("2_payout_script")]([%s])\n'
            % (farm_id, display, description, duration, min_level, opener, ", ".join(refs)))


def split(total, keys, shares):
    return [(k, total * s) for k, s in zip(keys, shares)]


def build():
    order = []                      # every mission id, in list order
    paths = {}                      # mission id -> res:// path
    CHAINS.mkdir(parents=True, exist_ok=True)

    for hero_id, hero_name, keys, shares in HEROES:
        durations, payouts = chain_values(hero_id)
        anchors = {s: a for s, *a in [(s, mid, disp, dur, pay, rew)
                                      for s, mid, disp, dur, pay, rew in ANCHORS.get(hero_id, [])]}
        farms_here = {step: farm for farm in NEW_FARMS.get(hero_id, []) for step in [farm[1]]}
        folder = CHAINS / hero_id
        folder.mkdir(parents=True, exist_ok=True)

        for i in range(STEPS):
            level = GATES.get(i, 1)
            if i in anchors:
                mid, display, duration, total, reward = anchors[i]
            else:
                display = step_name(hero_id, i)
                mid = "%s_%s" % (hero_id, slug(display))
                duration, total, reward = durations[i], payouts[i], None
                # A reward on every fifth step and at the end, so the chain pays
                # in something permanent at the same cadence it gates.
                if i in (4, 9, 14, 19):
                    reward = REWARD_LADDER[hero_id][(i - 4) // 5]
            description = "%s. Step %d of %s's chain." % (display, i + 1, hero_name)
            body = mission_tres(mid, display, description, hero_id, duration, level,
                                split(total, keys, shares), reward, None)
            path = folder / ("%02d_%s.tres" % (i + 1, mid))
            path.write_text(body)
            order.append(mid)
            paths[mid] = "res://data/ruins/chains/%s/%s" % (hero_id, path.name)

        # farms this chain opens
        for farm_id, step, cycle, total in NEW_FARMS.get(hero_id, []):
            opener = order[-STEPS + step]
            display = farm_id.replace("farm_", "").replace("_", " ").title()
            description = "A standing detail, worked by whoever can be spared. Opened by %s." % hero_name
            body = farm_tres(farm_id, display, description, opener, cycle,
                             1, split(total, keys, shares))
            path = DATA / ("res_%s.tres" % farm_id)
            path.write_text(body)
            order.append(farm_id)
            paths[farm_id] = "res://data/ruins/res_%s.tres" % farm_id

    # the five farms that already existed keep their files and their place
    for farm_id in EXISTING_FARM_OPENERS:
        order.append(farm_id)
        paths[farm_id] = "res://data/ruins/res_%s.tres" % farm_id
    return order, paths


# The four rewards a chain pays on its own cadence, at steps 5/10/15/20.
#
# A scoped one (scope 2, targeting a farm id) is how an expedition upgrades a
# farm rather than the whole game: ProductionSystem reads &"mission_speed" and
# &"mission_reward" at the mission's own id, so an effect aimed at one farm lifts
# that farm and nothing else.
REWARD_LADDER = {
    "rot_grub": [
        ("mission_reward",   2, 0.20, None, 2, "farm_pick_the_middens"),
        ("node_production",  2, 0.35, None),
        ("mission_speed",    2, 0.25, None, 2, "farm_work_the_undercroft"),
        ("node_production",  2, 1.00, None),
    ],
    "pale_stalker": [
        ("mission_reward",   2, 0.20, None, 2, "farm_tap_the_seeps"),
        ("automation_rate",  2, 0.30, None),
        ("workers_per_farm", 0, 1.00, None),
        ("ichor_gain",       2, 0.50, None),
    ],
    "chitin_scribe": [
        ("mission_reward",   2, 0.20, None, 2, "farm_copy_the_frieze"),
        ("crystal_gain",     2, 0.30, None),
        ("mission_speed",    2, 0.25, None, 2, "farm_tend_the_choir"),
        ("glyph_gain",       2, 0.50, None),
    ],
    "bone_hauler": [
        ("workers_per_farm", 0, 1.00, None),
        ("relic_gain",       2, 0.35, None),
        ("mission_reward",   2, 0.30, None, 2, "farm_burn_the_kilns"),
        ("node_production",  2, 1.50, None),
    ],
    "mire_wyrm": [
        ("farm_slots",       0, 1.00, None),
        ("water_production", 2, 0.40, None),
        ("mission_speed",    2, 0.30, None, 2, "farm_dredge_the_fen"),
        ("biomass_gain",     2, 0.75, None),
    ],
    "sanctum_herald": [
        ("workers_per_farm", 0, 1.00, None),
        ("tick_rate",        0, -0.75, 4.0),
        ("mission_reward",   2, 0.40, None, 2, "farm_keep_the_apse"),
        ("crystal_gain",     2, 0.80, None),
    ],
    "sealed_choir": [
        ("farm_slots",       0, 1.00, None),
        ("hero_level_cap",   0, 2.00, None),
        ("workers_per_farm", 0, 2.00, None),
        ("node_production",  2, 4.00, None),
    ],
}


# Authored prose, kept here so a re-run of this scaffold cannot flatten it.
DESCRIPTIONS = {'rot_grub': 'A blind digger that was already eating the foundations. It barely notices the difference.', 'pale_stalker': 'Long in the leg and quiet on stone. It hunted these galleries before the doors were shut.', 'chitin_scribe': 'It has copied the wall-marks onto its own shell for so long that the two are hard to tell apart.', 'bone_hauler': 'No talent for anything in particular, and an endless appetite for all of it.', 'mire_wyrm': 'It came up through the flooded undercroft and has not been persuaded to go back down.', 'sanctum_herald': 'Whatever the sanctum was built to hold, this is what it sent out to speak for it.', 'sealed_choir': 'The thing the sanctum was sealed around. It has been singing to itself the whole time, and now it has been answered.'}


def hero_tres(hero_id, display, keys, index):
    """One hero file. Costs climb with the hero's place in the roster."""
    recruit_key = keys[0]
    recruit = [5.0e6, 1.2e2, 6.0e1, 8.0e2, 2.4e3, 6.0e3, 4.0e4][index]
    level_base = [3.0e1, 2.0e1, 1.5e1, 1.2e3, 3.0e3, 8.0e3, 2.5e4][index]
    growth = [1.70, 1.70, 1.75, 1.80, 1.85, 1.90, 1.95][index]
    cap = [5, 6, 6, 8, 10, 12, 14][index]
    gate = [0, 4, 10, 20, 45, 80, 120][index]
    # rot_grub alone is bought with colony nutrients: it is the way in, and the
    # player has no mission currency at all before it.
    recruit_file = "res_nutrients_def.tres" if index == 0 else CUR[recruit_key][0]
    level_file = CUR[keys[-1]][0]

    ext = ['[ext_resource type="Script" path="res://model/ruins/res_hero_def.gd" id="1_script"]',
           '[ext_resource type="Resource" path="res://data/currencies/%s" id="2_recruit_cur"]' % recruit_file,
           '[ext_resource type="Resource" path="res://data/currencies/%s" id="3_level_cur"]' % level_file]
    n = 4
    pay_refs = []
    for key in keys:
        ext.append('[ext_resource type="Resource" path="res://data/currencies/%s" id="%d_pay_%s"]'
                   % (CUR[key][0], n, key))
        pay_refs.append('ExtResource("%d_pay_%s")' % (n, key))
        n += 1

    sub, extra_refs, extra_line = [], [], ""
    if index == len(HEROES) - 1:
        ext.append('[ext_resource type="Script" path="res://model/ruins/res_mission_payout_def.gd" id="%d_payout_script"]' % n)
        script_id = n
        n += 1
        for key, amount in (("ichor", 1.2e4), ("glyphs", 6.0e3)):
            m, e = big(amount)
            sub.append('[sub_resource type="Resource" id="extra_%s"]\n'
                       'script = ExtResource("%d_payout_script")\n'
                       'currency = ExtResource("%s")\n'
                       'gain_stat = &""\n'
                       '_amount_mantissa = %s\n'
                       '_amount_exponent = %d'
                       % (key, script_id,
                          [r for r in pay_refs if key in r][0].split('"')[1], m, e))
            extra_refs.append('SubResource("extra_%s")' % key)
        extra_line = ('\nextra_recruit_costs = Array[ExtResource("%d_payout_script")]([%s])'
                      % (script_id, ", ".join(extra_refs)))

    rm, re_ = big(recruit)
    lm, le = big(level_base)
    return ('[gd_resource type="Resource" script_class="HeroDef" format=3]\n\n'
            + "\n".join(ext) + "\n\n"
            + ("\n\n".join(sub) + "\n\n" if sub else "")
            + '[resource]\n'
            'script = ExtResource("1_script")\n'
            'id = &"%s"\n'
            'display_name = "%s"\n'
            'description = "%s"\n'
            'speed_per_level = %s\n'
            'yield_per_level = %s\n'
            'base_level_cap = %d\n'
            'min_missions_completed = %d\n'
            'payout_currencies = Array[Resource]([%s])\n'
            'recruit_currency = ExtResource("2_recruit_cur")\n'
            '_recruit_cost_mantissa = %s\n'
            '_recruit_cost_exponent = %d\n'
            'level_currency = ExtResource("3_level_cur")\n'
            '_level_base_cost_mantissa = %s\n'
            '_level_base_cost_exponent = %d\n'
            'level_cost_growth = %s%s\n'
            % (hero_id, display, DESCRIPTIONS[hero_id],
               [0.15, 0.18, 0.12, 0.22, 0.20, 0.25, 0.28][index],
               [0.20, 0.16, 0.24, 0.28, 0.26, 0.32, 0.36][index],
               cap, gate, ", ".join(pay_refs), rm, re_, lm, le, growth, extra_line))


def list_tres(class_name, script_path, element_script, field, paths, ids):
    ext = ['[ext_resource type="Script" path="%s" id="1_script"]' % script_path,
           '[ext_resource type="Script" path="%s" id="2_element"]' % element_script]
    refs = []
    for i, mid in enumerate(ids):
        rid = "%d_%s" % (i + 3, mid)
        ext.append('[ext_resource type="Resource" path="%s" id="%s"]' % (paths[mid], rid))
        refs.append('ExtResource("%s")' % rid)
    return ('[gd_resource type="Resource" script_class="%s" format=3]\n\n' % class_name
            + "\n".join(ext) + "\n\n"
            '[resource]\n'
            'script = ExtResource("1_script")\n'
            '%s = Array[ExtResource("2_element")]([%s])\n' % (field, ", ".join(refs)))


if __name__ == "__main__":
    hero_paths = {}
    for i, (hero_id, display, keys, _shares) in enumerate(HEROES):
        path = DATA / ("res_hero_%s.tres" % hero_id)
        path.write_text(hero_tres(hero_id, display, keys, i))
        hero_paths[hero_id] = "res://data/ruins/res_hero_%s.tres" % hero_id
    (DATA / "all_heroes.tres").write_text(list_tres(
        "HeroList", "res://model/ruins/res_hero_list.gd", "res://model/ruins/res_hero_def.gd",
        "heroes", hero_paths, [h[0] for h in HEROES]))

    order, paths = build()
    (DATA / "all_missions.tres").write_text(list_tres(
        "MissionList", "res://model/ruins/res_mission_list.gd", "res://model/ruins/res_mission_def.gd",
        "missions", paths, order))
    print("wrote %d heroes and %d missions" % (len(HEROES), len(order)))
