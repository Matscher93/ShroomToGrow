# Coding Standards

Conventions for this codebase, distilled from a consistency pass.
When in doubt, match these — don't introduce a new style even if it's "more correct" in the abstract.

## File & class naming

- Script files: `gd_<snake_case_name>.gd`.
  Resource-definition base classes: `res_<snake_case_name>.gd`.
  Scene files: `sc_<snake_case_name>.tscn`.

- No PascalCase or camelCase in filenames — `gd_base_color_rect.gd`, not `gd_BaseColorRect.gd`.

- `class_name` should mirror the filename: `gd_mycelium_node_data.gd` → `class_name MyceliumNodeData` (drop the `gd_`/`res_` prefix, PascalCase the rest).
  If the class name and filename drift apart, rename one to match — don't leave them implying different things.

- Always two lines:

  ```gdscript
  class_name Foo
  extends Bar
  ```

  Never `class_name Foo extends Bar` on one line.

## Typing

- Every function has an explicit return type, including `-> void`.
  Every parameter is typed.
  This applies everywhere, including `@tool` scripts and `_notification(what: int)`/`_ready()` boilerplate — no exceptions for "small" scripts.

- No stray semicolons at end of statements.

## Naming case

- snake_case for everything: variables, parameters, `@export` properties, function names.
  No `ColorParam`, `inColor`, `inEnabled` — use `color_param`, `in_color`, `in_enabled`.

- Signals are named as event nouns/past-tense, with no `on_` prefix: `node_changed`, `biome_unlocked`, `perk_selected`, `pressed`.
  `on_` is reserved for *handler method names* (`_on_button_down`, `_on_property_changed`) — never for the signal itself.

- Handler methods are private-by-convention: `_on_button_down`, not `on_button_down`.

## ViewModel API shape

ViewModels expose read-only display state as computed properties, not `get_x()` methods:

```gdscript
var buy_button_text: String:
	get:
		return "%s" % _format_number(_mycelium_data.upgrade_cost())
```

Use a plain method only when the accessor needs a parameter (e.g. `get_screen_data(type: ScreenTypes.Types)`) — GDScript properties can't take arguments.

`PROP_*` notification constants (the ones passed to `_notify()` / matched in `_on_property_changed`) are always `StringName` literals (`&"..."`), matching `property_changed(property: StringName)`'s signature — never plain `String`.

## Reuse over duplication

`view/base_views/` holds shared shader-panel boilerplate (`gd_base_color_rect.gd`, `gd_base_panel_container.gd`).

If a new view needs the same `_update_shader`/`_notification`/`_set_color` triplet, `extends "res://view/base_views/gd_base_..._container.gd"` — don't re-paste the implementation.

If a base script doesn't quite fit, extend it and override, rather than forking a near-duplicate.

## Save/load data

A model's `to_save()`/`load_from_save()` pair should read from **one** field list (see `PlayerData._BIG_NUMBER_FIELDS` / `_PLAIN_FIELDS` for the pattern), using `get(field)`/`set(field, value)` reflection.

Never hand-list the same fields a second time in a caller (e.g. `SaveManager` copying five fields one by one) — that's a second place to forget when a field is added later.

When loading into a live model that other objects already hold a reference to (e.g. `App.player_data`), mutate it in place through its setters (`load_from_save`) so `*_changed` signals still fire.

Don't construct a new instance and swap the reference, and don't manually copy field-by-field at the call site either.

## Dictionary `.get()` defaults

The default value passed to `.get(key, default)` must be the same *type* the caller goes on to use — e.g. `.get("player_data", {})`, not `.get("player_data", PlayerData.new())`, when the next step is `some_dict.get("field", ...)` on the result.

A wrong-typed default is a latent crash that only fires on the corrupt/missing-data path, so it won't show up until it matters most.
