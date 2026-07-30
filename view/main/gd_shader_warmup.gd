class_name ShaderWarmup
extends CanvasLayer
## VIEW — forces every canvas_item shader in the project through one real
## draw call, off-screen, right after boot. Godot compiles a shader's
## pipeline lazily on its first draw, so without this the first time a
## screen the player hasn't visited yet (a locked biome tab, the offline
## income popup, ...) uses one of these shaders, that compile happens
## in-frame and shows up as a hitch. Warming them all up-front during the
## empty startup frames trades an invisible one-off cost for the stutter.
## Shaders are discovered by scanning res:// at startup (skipping addons/),
## so a newly added .gdshader is picked up automatically — nothing to
## register by hand. Frees itself once every shader has drawn once.

const SCAN_ROOT := "res://"
const SKIP_DIRS := ["addons"]

func _ready() -> void:
	# The rect has to be on-screen and non-transparent, or there is no draw call
	# and so no pipeline compile — which is the entire point of this class. It
	# used to sit at (-100, -100) with modulate.a = 0.0: off-screen items are
	# culled and zero-alpha ones are skipped, so it warmed nothing.
	#
	# Hiding it is done by depth, not by transparency: a negative layer puts this
	# whole CanvasLayer behind the main screen, which draws over it. 2D has no
	# occlusion culling, so being covered doesn't cost the draw call the warmup
	# needs. Swapping a shader per frame at 1% alpha *on top* read as a flicker.
	# Alpha stays low as a second defence: the safe-area insets can leave the
	# top-left corner of the main screen transparent on mobile. Non-zero, or the
	# draw is skipped and we're back to warming nothing.
	layer = -100
	var rect := ColorRect.new()
	rect.size = Vector2(4, 4)
	rect.position = Vector2.ZERO
	rect.modulate.a = 0.01
	add_child(rect)
	for shader_path in _find_shaders(SCAN_ROOT):
		var mat := ShaderMaterial.new()
		mat.shader = load(shader_path) as Shader
		rect.material = mat
		await get_tree().process_frame
	queue_free()

## Recursively lists every .gdshader under path (skipping SKIP_DIRS).
func _find_shaders(path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Could not open %s (%s)" % [path, DirAccess.get_open_error()])
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(file_name):
				found.append_array(_find_shaders(full_path))
		elif file_name.ends_with(".gdshader") or file_name.ends_with(".gdshader.remap"):
			# Exported/packed builds list resources as "<name>.remap" — the
			# real resource lives at the path with ".remap" stripped.
			found.append(full_path.trim_suffix(".remap"))
		file_name = dir.get_next()
	dir.list_dir_end()
	return found
