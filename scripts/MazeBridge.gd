extends Node2D
##
## M1 + M2 — drives the C ↔ Godot pipeline and manages maze + fog rendering.
##
## Runs the maze_core executable, reads maze_state.json, renders it onto the
## maze TileMapLayer, fills the FogLayer with dark fog, and spawns the player.
##
## Source IDs:
##   maze_tileset.tres → 0 = floor, 1 = wall
##   fog_tileset.tres  → 0 = dim (previously seen), 1 = dark (never seen)
## Tile values from maze_core JSON are identity-mapped to source ids.

const ATLAS_COORDS := Vector2i(0, 0)
const FOG_DIM_SOURCE := 0
const FOG_DARK_SOURCE := 1
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const PLAYER_SPAWN := Vector2i(1, 1)
const MEMORY_RADIUS := 4  ## Chebyshev radius around player where ever-seen cells stay dim; beyond this → dark

@onready var tile_layer: TileMapLayer = $TileMapLayer
@onready var fog_layer: TileMapLayer = $FogLayer

var _maze: Dictionary
var _revealed: Dictionary  ## Vector2i → true; every cell that has ever been in vision

func _ready() -> void:
	_maze = _run_maze_core()
	if _maze.is_empty():
		return
	_render_maze(_maze)
	_init_fog(_maze)
	_spawn_player()

func is_wall(cell: Vector2i) -> bool:
	if _maze.is_empty():
		return true
	if not _is_in_bounds(cell):
		return true
	var tiles: Array = _maze.get("tiles", [])
	var row: Array = tiles[cell.y]
	return int(row[cell.x]) == 1

func update_vision(center: Vector2i, vision_radius: int) -> void:
	if _maze.is_empty():
		return
	var w := int(_maze.get("width", 0))
	var h := int(_maze.get("height", 0))
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var cheb: int = max(abs(c.x - center.x), abs(c.y - center.y))
			if cheb <= vision_radius:
				fog_layer.set_cell(c, -1)
			elif cheb <= MEMORY_RADIUS and _revealed.has(c):
				fog_layer.set_cell(c, FOG_DIM_SOURCE, ATLAS_COORDS)
			else:
				fog_layer.set_cell(c, FOG_DARK_SOURCE, ATLAS_COORDS)
	for dy in range(-vision_radius, vision_radius + 1):
		for dx in range(-vision_radius, vision_radius + 1):
			var c := center + Vector2i(dx, dy)
			if _is_in_bounds(c):
				_revealed[c] = true

func _is_in_bounds(cell: Vector2i) -> bool:
	if _maze.is_empty():
		return false
	var w := int(_maze.get("width", 0))
	var h := int(_maze.get("height", 0))
	return cell.x >= 0 and cell.y >= 0 and cell.x < w and cell.y < h

func _run_maze_core() -> Dictionary:
	var project_dir := ProjectSettings.globalize_path("res://")
	var exe_name := "maze_core.exe" if OS.has_feature("windows") else "maze_core"
	var exe_path := project_dir.path_join(exe_name)
	var out_path := ProjectSettings.globalize_path("user://maze_state.json")

	if not FileAccess.file_exists(exe_path):
		push_error("maze_core executable not found at %s — run `make` in c_src/" % exe_path)
		return {}

	var output: Array = []
	var args := PackedStringArray([out_path, str(int(Time.get_unix_time_from_system()))])
	var exit_code := OS.execute(exe_path, args, output, true)
	if exit_code != 0:
		push_error("maze_core exited with code %d. stdout/stderr:\n%s" % [exit_code, "\n".join(output)])
		return {}

	var f := FileAccess.open(out_path, FileAccess.READ)
	if f == null:
		push_error("cannot read %s" % out_path)
		return {}
	var json_text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("invalid JSON from maze_core")
		return {}
	return parsed

func _render_maze(maze: Dictionary) -> void:
	var w := int(maze.get("width", 0))
	var h := int(maze.get("height", 0))
	var tiles: Array = maze.get("tiles", [])
	tile_layer.clear()
	for y in h:
		var row: Array = tiles[y]
		for x in w:
			var source_id := int(row[x])
			tile_layer.set_cell(Vector2i(x, y), source_id, ATLAS_COORDS)
	print("maze_core: rendered %dx%d, seed=%s" % [w, h, maze.get("seed", "?")])

func _init_fog(maze: Dictionary) -> void:
	var w := int(maze.get("width", 0))
	var h := int(maze.get("height", 0))
	fog_layer.clear()
	for y in h:
		for x in w:
			fog_layer.set_cell(Vector2i(x, y), FOG_DARK_SOURCE, ATLAS_COORDS)

func _spawn_player() -> void:
	var player := PLAYER_SCENE.instantiate()
	player.cell = PLAYER_SPAWN
	add_child(player)
	print("player: spawned at cell %s" % str(PLAYER_SPAWN))
