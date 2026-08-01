# Coding Standards

Conventions for this codebase, distilled from a consistency pass.
When in doubt, match these - don't introduce a new style even if it's "more correct" in the abstract.

## File & class naming

- Script files: `gd_<snake_case_name>.gd`.
  Resource-definition base classes: `res_<snake_case_name>.gd`.
  Scene files: `sc_<snake_case_name>.tscn`.

- No PascalCase or camelCase in filenames - `gd_base_color_rect.gd`, not `gd_BaseColorRect.gd`.

- `class_name` should mirror the filename: `gd_mycelium_node_data.gd` → `class_name MyceliumNodeData` (drop the `gd_`/`res_` prefix, PascalCase the rest).
  If the class name and filename drift apart, rename one to match - don't leave them implying different things.

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

`view/base_views/` holds shared shader-panel boilerplate (`gd_base_color_rect.gd`, `gd_base_panel_container.gd`).

If a new view needs the same `_update_shader`/`_notification`/`_set_color` triplet, `extends "res://view/base_views/gd_base_..._container.gd"` - don't re-paste the implementation.

If a base script doesn't quite fit, extend it and override, rather than forking a near-duplicate.

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

## Leading-underscore parameters

A `_`-prefixed parameter name (`_value`, `_delta`, `_game`) is a signal that the parameter is **unused** - most commonly in signal handlers that only care that *something* fired. Don't prefix a parameter that the function body actually reads; that's actively misleading to the next reader who trusts the convention. If a parameter starts unused and later gains a use, drop the underscore at the same time.

## Whitespace

No trailing whitespace on any line - including lines that are otherwise blank inside an indented block (a lone tab/space left over from an edit). Also no trailing whitespace after `class_name`/`extends` lines.
