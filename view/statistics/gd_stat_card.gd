extends PanelContainer
## VIEW: one card in the statistics overlay - an icon, a title, something small
## beside it, an optional caption, and any number of rows underneath.
##
## Shared by the three list tabs because they are the same card: a milestone is a
## title and a date, a run is a title and a date with its fields under it, and a
## resource in the bonus breakdown is a title and a multiplier with its upgrades
## under it. Only what goes in `rows` differs, and the caller fills that.
##
## The bonus cards are additionally collapsible, which the other two tabs leave
## off. See set_collapsible().

## Emitted when the header is pressed, on a collapsible card. The owner decides
## what the new state is and pushes it back through set_expanded() - this card
## holds no fold state of its own, because it is respawned on every rebuild.
signal toggled

@export var icon: ColorRect
@export var biome_icon: ColorRect
@export var arrow: ColorRect
@export var btn_header: Button
@export var lbl_title: Label
@export var lbl_meta: Label
@export var lbl_caption: Label
@export var rows: VBoxContainer

func _ready() -> void:
	btn_header.pressed.connect(_on_header_pressed)

func set_card(title: String, meta: String, caption: String) -> void:
	lbl_title.text = title
	lbl_meta.text = meta
	lbl_meta.visible = not meta.is_empty()
	lbl_caption.text = caption
	lbl_caption.visible = not caption.is_empty()

# --- Icons ---

## One of the overlay's flat glyphs, for the milestones and runs that are not a
## place: a node tier, a sporation, the run in progress.
func set_icon(id: StatIcons.Icon, color: Color = StatIcons.ROW_COLOR) -> void:
	biome_icon.visible = false
	icon.visible = true
	var shader_material := icon.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter(&"icon_id", int(id))
		shader_material.set_shader_parameter(&"icon_color", color)

## A biome's own authored icon, tinted with its own colour - the same tile the
## nav menu and the biome cards draw, so a biome reads as one identity wherever
## it turns up.
##
## Its own ColorRect rather than a shader swap on the one above: the biome
## shaders paint a filled tile and take a different set of uniforms, and a single
## rect would have to keep re-seeding whichever set it was not showing.
func set_biome_icon(shader: Shader, color: Color) -> void:
	icon.visible = false
	biome_icon.visible = true
	biome_icon.set_icon_shader(shader)
	biome_icon.set_shader_color(color)

func clear_icon() -> void:
	icon.visible = false
	biome_icon.visible = false

# --- Collapsing ---

## Off by default: the timeline and the runs list are read straight down, and an
## arrow on every card there would promise a fold that does nothing.
func set_collapsible(collapsible: bool) -> void:
	arrow.visible = collapsible
	btn_header.visible = collapsible

func set_expanded(expanded: bool) -> void:
	rows.visible = expanded
	arrow.offset_transform_rotation = PI if expanded else 0.0

func _on_header_pressed() -> void:
	toggled.emit()
