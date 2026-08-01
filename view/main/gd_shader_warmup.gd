class_name ShaderWarmup
extends CanvasLayer
## VIEW: forces every canvas_item shader through one real draw call, off-screen,
## right after boot. Godot compiles a shader's pipeline lazily on first draw, so
## without this the compile happens in-frame the first time an unvisited screen
## (a locked biome tab, the offline income popup) uses one, and shows as a hitch.
## Warming up during the empty startup frames trades that for an invisible
## one-off cost.
##
## Shaders are found by scanning res:// at startup, skipping addons/, so a new
## .gdshader is picked up automatically. Frees itself once all have drawn.

const SCAN_ROOT := "res://"
const SKIP_DIRS := ["addons"]

func _ready() -> void:
	# The rect must be on-screen and non-transparent or there is no draw call and
	# no pipeline compile, which is the point of this class. Off-screen items are
	# culled and zero-alpha ones are skipped, so both warm nothing.
	#
	# Hiding is done by depth, not transparency: a negative layer puts this
	# CanvasLayer behind the main screen, which draws over it. 2D has no occlusion
	# culling, so being covered still costs the draw call the warmup needs.
	# Swapping a shader per frame at 1% alpha on top reads as a flicker. Alpha
	# stays low as a second defence, since safe-area insets can leave the
	# top-left corner transparent on mobile. It must stay non-zero.
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

## Recursively lists every .gdshader under path, skipping SKIP_DIRS.
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
			# Packed builds list resources as "<name>.remap". The real
			# resource lives at the path with ".remap" stripped.
			found.append(full_path.trim_suffix(".remap"))
		file_name = dir.get_next()
	dir.list_dir_end()
	return found
