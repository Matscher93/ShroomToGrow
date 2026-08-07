# Coding Standards

Conventions for this codebase, distilled from a consistency pass.
When in doubt, match these - don't introduce a new style even if it's "more correct" in the abstract.

## File & class naming

- Script files: `gd_<snake_case_name>.gd`.
  Resource-definition base classes: `res_<snake_case_name>.gd`.
  Scene files: `sc_<snake_case_name>.tscn`.

- No PascalCase or camelCase in filenames - `gd_base_color_rect.gd`, not `gd_BaseColorRect.gd`.

- Test files are the one exception to the `gd_` prefix: `<subject>_test.gd`, mirroring the path of what they test (`model/upgrades/gd_upgrade_system.gd` → `test/model/upgrades/upgrade_system_test.gd`). The suffix is what gdUnit4 discovers on, and a `gd_` prefix would put every suite under one letter in the tree.

- `class_name` should mirror the filename: `gd_mycelium_node_data.gd` → `class_name MyceliumNodeData` (drop the `gd_`/`res_` prefix, PascalCase the rest).
  If the class name and filename drift apart, rename one to match - don't leave them implying different things.

- Models and ViewModels always declare a `class_name` - they are constructed by name from `App` and from tests.
  View scripts declare one **only when another script names the type**: a typed `@export`, a parameter or return type, or a static-helper namespace (`BiomePanel`, `PopupLayer`, `UpgradeSlotGrid`, `PerkNode`). A script only ever attached to its own scene and never referenced by name stays anonymous rather than claiming a global identifier for nothing.

- A script's folder follows its layer, not its history. Anything holding game state or rules belongs under `model/`, even when a ViewModel is its only caller - `UpgradeSystem` sat in `viewmodel/` for exactly that reason and was a model the whole time.

- Always two lines:

  ```gdscript
  class_name Foo
  extends Bar
  ```

  Never `class_name Foo extends Bar` on one line.

## Typing

- Every function has an explicit return type, including `-> void`.
  Every parameter is typed.
  This applies everywhere, including `@tool` scripts and `_notification(what: int)`/`_ready()` boilerplate - no exceptions for "small" scripts.

- No stray semicolons at end of statements.

## Naming case

- snake_case for everything: variables, parameters, `@export` properties, function names.
  No `ColorParam`, `inColor`, `inEnabled` - use `color_param`, `in_color`, `in_enabled`.

- Signals are named as event nouns/past-tense, with no `on_` prefix: `node_changed`, `biome_unlocked`, `perk_selected`, `pressed`.
  `on_` is reserved for *handler method names* (`_on_button_down`, `_on_property_changed`) - never for the signal itself.

- Handler methods are private-by-convention: `_on_button_down`, not `on_button_down`.

## ViewModel API shape

ViewModels expose read-only display state as computed properties, not `get_x()` methods:

```gdscript
var buy_button_text: String:
	get:
		return "%s" % _format_number(_mycelium_data.upgrade_cost())
```

Use a plain method only when the accessor needs a parameter (e.g. `get_screen_data(type: ScreenTypes.Types)`) - GDScript properties can't take arguments.

`PROP_*` notification constants (the ones passed to `_notify()` / matched in `_on_property_changed`) are always `StringName` literals (`&"..."`), matching `property_changed(property: StringName)`'s signature - never plain `String`.

## ViewModel-always

Every `Control`-derived view that displays or mutates *dynamic* app state goes through a ViewModel - no direct `App.<system>.*` reads/writes, no direct model-signal subscriptions, for anything that changes at runtime (level, cost, unlocked/afford-check, etc). "ViewModels never touch nodes; Views never touch Models" (`viewmodel/gd_view_model.gd`) is not aspirational - every non-trivial view mixing VM binding with direct `App.*` access is a bug to fix, not a shortcut to take for the next screen.

Static resource *registries* are the one exception - `App.biomes.biomes`, `App.nodes.mycelium_nodes`, `App.perk_defs` stay directly readable, but **only** for enumeration/spawning and genuinely static per-item fields (position, color, id, display name - anything fixed for the resource's lifetime). The moment a per-item read can change at runtime (level, cost, unlocked, can-afford), it goes through a VM instead of the registry entry, even if the registry entry technically has the field.

Two lifecycles, pick based on shape:
- **List of N items, all need live dynamic state at once** (e.g. every perk button repainting on any purchase): one persistent VM per item, stored in a `Dictionary` on `App`, built once in `App._ready()` - mirrors `App.biome_vms`, `App.perk_vms`. Never disposed by a consuming view; `App` owns the lifetime.
- **Single "currently selected" detail panel over a big item set** (e.g. the biome-upgrade-card grid, the perk detail panel): create the VM fresh on selection, `dispose()` the previous one before replacing - mirrors `BiomeUpgradeCard.select_upgrade()`. Don't pre-allocate one VM per possible selection when only one is ever shown at a time.

## Reuse over duplication

`view/base_views/` holds the shared shader-panel boilerplate:

- `gd_base_color_rect.gd` / `gd_base_panel_container.gd` - the `_update_shader`/`_notification`/`set_shader_color` triplet, one per base node type.
- `gd_base_shader_button.gd` - the above plus a wrapped `Button`: press tracking, the repaint on down/up, `set_button_text()` and a re-emitted `pressed`. A subclass overrides `_state_color()` to say what its current state paints, and nothing else (`gd_screen_button.gd`, `gd_buy_button_visuals.gd`, `gd_collect_offline_income_button.gd`).

If a new view needs any of that, `extends "res://view/base_views/gd_base_....gd"` - don't re-paste the implementation.

If a base script doesn't quite fit, extend it and override, rather than forking a near-duplicate. The shader-button base takes its `Button` through `_bind_button()` in the subclass's `_ready()` rather than exporting one itself, precisely so a subclass can keep whatever export name its scenes already bind by NodePath.

## Save/load data

A model's `to_save()`/`load_from_save()` pair should read from **one** field list (see `PlayerData._BIG_NUMBER_FIELDS` / `_PLAIN_FIELDS` for the pattern), using `get(field)`/`set(field, value)` reflection.

Never hand-list the same fields a second time in a caller (e.g. `SaveManager` copying five fields one by one) - that's a second place to forget when a field is added later.

When loading into a live model that other objects already hold a reference to (e.g. `App.player_data`), mutate it in place through its setters (`load_from_save`) so `*_changed` signals still fire.

Don't construct a new instance and swap the reference, and don't manually copy field-by-field at the call site either.

## Dictionary `.get()` defaults

The default value passed to `.get(key, default)` must be the same *type* the caller goes on to use - e.g. `.get("player_data", {})`, not `.get("player_data", PlayerData.new())`, when the next step is `some_dict.get("field", ...)` on the result.

A wrong-typed default is a latent crash that only fires on the corrupt/missing-data path, so it won't show up until it matters most.

This applies just as much when the `.get()` result is immediately handed to a typed loader: `BigNumber.from_save(d.get("auto_nodes", BigNumber.new(0.0, 0)))` is wrong - `from_save(d: Dictionary)` expects a `Dictionary`, so a missing key hands it a `BigNumber` instead and crashes. The default there must be `{}` (or a full `{"m": 0.0, "e": 0}`), matching what `from_save` actually consumes - not what the *caller* eventually wants back.

## Local variable typing

Prefer `:=` (type inference) over untyped `var x = value` for any local with an initializer:

```gdscript
var total := a.add(b)          # yes
var total = a.add(b)           # no - same value, but the type is now implicit
```

This is the dominant pattern in the codebase already - match it even for "obvious" types like string formatting results (`var label := "%s" % value`).

Exception: don't use `:=` on a call that returns `Variant` - the global `min()`/`max()`, `JSON.parse_string()`, and `Dictionary.get()` on some typed dictionaries all fall into this. `:=` on those either fails to compile ("warning treated as error: variable type is being inferred from a Variant value") or silently degrades to `Variant` - give the variable an explicit type instead (`var min_exp: int = min(a, b)`, `var parsed: Variant = JSON.parse_string(text)`). Test with `godot --headless --path .` after converting a batch of `=` to `:=` - this class of error only shows up at parse time, not at a glance.

## Conditionals

No parentheses around `if`/`while`/`elif` conditions - `if condition:`, never `if(condition):`. GDScript isn't C; the parens are noise.

A single-line `if condition: <statement>` is allowed for **guard clauses only** - a bare `return`, `continue` or `break` that bails out before the real work starts:

```gdscript
if mantissa == 0.0: return other.copy()   # yes, a guard
if lvl <= 0: continue                     # yes, a guard

if ready: _refresh_all()                  # no - that's the work, give it a line
```

The guards cluster at the top of arithmetic and hot-path functions (`gd_big_number.gd`, `UpgradeSystem.modify()`), where one line each keeps the actual body visible in a screenful. Anything that *does* something gets its own indented line.

## Leading-underscore parameters

A `_`-prefixed parameter name (`_value`, `_delta`, `_game`) is a signal that the parameter is **unused** - most commonly in signal handlers that only care that *something* fired. Don't prefix a parameter that the function body actually reads; that's actively misleading to the next reader who trusts the convention. If a parameter starts unused and later gains a use, drop the underscore at the same time.

## Whitespace

No trailing whitespace on any line - including lines that are otherwise blank inside an indented block (a lone tab/space left over from an edit). Also no trailing whitespace after `class_name`/`extends` lines.

## Running the checks

Two commands, both from the project root:

```sh
# 1. Parse the whole project. The only thing that catches the ":= on a Variant"
#    class of failure, which is a parse error rather than a runtime one.
godot --headless --path . --quit

# 2. Run every test suite.
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a test
```

`--ignoreHeadlessMode` is not optional: without it gdUnit4 refuses to run at all and exits 103, because input-driven tests can't work headless. None of these suites synthesize `InputEvent`s, so the warning it prints does not apply to them - if one ever does, it belongs in a run with a display attached.

After moving or adding a script, run `godot --headless --path . --import` first. The global class cache in `.godot/` still points a `class_name` at its old path until then, and the parse check fails with `Could not parse global class` naming a file that no longer exists.
