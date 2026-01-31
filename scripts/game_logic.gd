extends Node

signal state_changed

# runtime model
var pieces : Array = []            # 每项为 Dictionary 的运行时副本（基于 PieceData）
var tick: int = 0
var grid_w: int = 3
var grid_h: int = 3

# selection / undo
var selected_piece_id: int = -1
var selected_offset: Vector2 = Vector2.ZERO
var undo_stack: Array = []
var redo_stack: Array = []

# loaded pattern resources (sequence)
var level_patterns: Array[Resource] = []

# tick timer (auto stepping)
var _tick_timer: Timer = null
var tick_interval: float = 0.8

func _ready():
	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval
	_tick_timer.one_shot = false
	_tick_timer.autostart = false
	add_child(_tick_timer)
	_tick_timer.timeout.connect(Callable(self, "_on_tick_timeout"))

# ---------------------
# Loading
# ---------------------
func load_level_from_resource(res: Resource) -> void:
	# LevelData expected
	pieces.clear()
	tick = 0
	selected_piece_id = -1
	level_patterns.clear()
	var gs = res.grid_size
	grid_w = int(gs.x)
	grid_h = int(gs.y)
	
	for pd in res.pieces:
		var rp := {
			"id": pd.id,
			"color": pd.color,
			"z_order": pd.z_order,
			"shape_cells": pd.shape_cells.duplicate(true),
			"is_mask": pd.is_mask,
			"is_inverter": pd.is_inverter,
			"is_dynamic": pd.is_dynamic,
			"dynamic_pattern": pd.dynamic_pattern.duplicate(true)
		}
		pieces.append(rp)
	# load patterns array (PatternData)
	for p in res.patterns:
		level_patterns.append(p)
	undo_stack.clear()
	redo_stack.clear()
	emit_signal("state_changed")

# ---------------------
# Helpers: find piece runtime index by id
# ---------------------
func _find_piece_index_by_id(pid: int) -> int:
	for i in range(pieces.size()):
		if pieces[i]["id"] == pid:
			return i
	return -1

func _push_undo():
	var snapshot = {
		"pieces": deep_copy(pieces),
		"tick": tick,
		"selected_piece_id": selected_piece_id
	}
	undo_stack.append(snapshot)
	redo_stack.clear()

func undo():
	if undo_stack.is_empty():
		return
	var snap = undo_stack.pop_back()
	redo_stack.append({"pieces": deep_copy(pieces), "tick": tick, "selected_piece_id": selected_piece_id})
	pieces = deep_copy(snap["pieces"])
	tick = snap["tick"]
	selected_piece_id = snap["selected_piece_id"]
	emit_signal("state_changed")

func redo():
	if redo_stack.is_empty():
		return
	var snap = redo_stack.pop_back()
	undo_stack.append({"pieces": deep_copy(pieces), "tick": tick, "selected_piece_id": selected_piece_id})
	pieces = deep_copy(snap["pieces"])
	tick = snap["tick"]
	selected_piece_id = snap["selected_piece_id"]
	emit_signal("state_changed")

# deep copy helper for Arrays/Dictionaries containing primitives / arrays
# Replace existing deep_copy with this robust implementation
func deep_copy(value):
	# Dictionaries
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[k] = deep_copy(value[k])
		return out

	# Arrays
	if value is Array:
		var out := []
		for item in value:
			out.append(deep_copy(item))
		return out

	# Resources (duplicate if possible to avoid shared refs)
	if value is Resource:
		# Some Resources implement duplicate(true) for deep copy
		if value.has_method("duplicate"):
			# try deep duplicate; fallback to returning the resource if duplicate fails
			var ok = null
			# duplicate() may throw in rare cases; guard it
			# Godot's duplicate(true) is standard for Resources
			ok = value.duplicate(true)
			if ok != null:
				return ok
		# if not duplicable, return the reference (acceptable for immutable resources)
		return value

	# Godot built-in typed arrays (Packed*Array) — treat as Array copy
	# These are not 'Array' instances but can be iterated; convert to Array then copy
	if typeof(value) == TYPE_PACKED_BYTE_ARRAY \
		or typeof(value) == TYPE_PACKED_INT32_ARRAY \
		or typeof(value) == TYPE_PACKED_INT64_ARRAY \
		or typeof(value) == TYPE_PACKED_FLOAT32_ARRAY \
		or typeof(value) == TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(value) == TYPE_PACKED_STRING_ARRAY \
		or typeof(value) == TYPE_PACKED_VECTOR2_ARRAY \
		or typeof(value) == TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value) == TYPE_PACKED_COLOR_ARRAY:
		var tmp_arr := []
		for v in value:
			tmp_arr.append(deep_copy(v))
		return tmp_arr

	# For basic value types (int, float, bool, String, Vector2, etc.), return as-is
	return value


# ---------------------
# Occupancy & visibility (supports arbitrary tick)
# ---------------------
# piece_occupies_cell accepts at_tick to evaluate dynamic_pattern
func piece_occupies_cell(piece: Dictionary, x: int, y: int, at_tick: int) -> bool:
	if piece.get("is_dynamic", false) and piece.get("dynamic_pattern", []).size() > 0:
		var patterns = piece["dynamic_pattern"]
		var idx = at_tick % patterns.size()
		var pat = patterns[idx]
		for c in pat:
			if int(c[0]) == x and int(c[1]) == y:
				return true
		return false
	else:
		for c in piece.get("shape_cells", []):
			if int(c[0]) == x and int(c[1]) == y:
				return true
		return false

# compute at arbitrary tick without modifying global tick
func compute_visible_state_at(at_tick: int) -> Array:
	var grid = []
	for x in range(grid_w):
		var col = []
		for y in range(grid_h):
			col.append({
				"fill_color": null,         # "white"/"black"/null
				"stroke_color": null,
				"is_black_due_to_mask": false
			})
		grid.append(col)

	var sorted = pieces.duplicate()
	sorted.sort_custom(_z_desc)

	for x in range(grid_w):
		for y in range(grid_h):
			var cell = grid[x][y]
			for i in range(sorted.size()):
				var p = sorted[i]
				var occupies = piece_occupies_cell(p, x, y, at_tick)
				if not occupies:
					if p.get("is_mask", false):
						cell["is_black_due_to_mask"] = true
						break
					else:
						continue
				# occupies true
				if p.get("is_inverter", false):
					var below_color = _find_below_color(sorted, i, x, y, at_tick)
					cell["fill_color"] = _invert_color(below_color)
					break
				else:
					cell["fill_color"] = p.get("color", "black")
					break
	return grid

# convenience wrapper for current tick
func compute_visible_state() -> Array:
	return compute_visible_state_at(tick)

func _z_desc(a, b) -> int:
	return b["z_order"] - a["z_order"]

# find the visible color below index start_i in sorted array (with tick)
func _find_below_color(sorted: Array, start_i: int, x: int, y: int, at_tick: int) -> String:
	for j in range(start_i + 1, sorted.size()):
		var q = sorted[j]
		var occupies = piece_occupies_cell(q, x, y, at_tick)
		if not occupies:
			if q.get("is_mask", false):
				return "black"
			else:
				continue
		# occupies true
		if q.get("is_inverter", false):
			return _invert_color(_find_below_color(sorted, j, x, y, at_tick))
		else:
			return q.get("color", "black")
	return "black"

func _invert_color(c: String) -> String:
	if c == "white":
		return "black"
	else:
		return "white"

# ---------------------
# Selection / Movement (keyboard-driven)
# ---------------------
# select piece at grid pos (x,y). returns piece id or -1
func select_piece_at(x: int, y: int) -> int:
	var sorted = pieces.duplicate()
	sorted.sort_custom(_z_desc)
	for p in sorted:
		if piece_occupies_cell(p, x, y, tick):
			selected_piece_id = p["id"]
			selected_offset = Vector2.ZERO
			emit_signal("state_changed")
			return selected_piece_id
	selected_piece_id = -1
	emit_signal("state_changed")
	return -1

# move selected piece by dx,dy (grid)
func move_selected(dx: int, dy: int) -> bool:
	if selected_piece_id == -1:
		return false
	var idx = _find_piece_index_by_id(selected_piece_id)
	if idx == -1:
		return false
	_push_undo()
	var p = pieces[idx]
	# move base shape_cells
	var new_cells = []
	for i in range(p["shape_cells"].size()):
		new_cells.append([ int(p["shape_cells"][i][0]) + dx, int(p["shape_cells"][i][1]) + dy ])
	p["shape_cells"] = new_cells
	# move dynamic patterns if present
	if p.get("is_dynamic", false):
		var new_patterns = []
		for pat in p["dynamic_pattern"]:
			var newpat = []
			for c in pat:
				newpat.append([ int(c[0]) + dx, int(c[1]) + dy ])
			new_patterns.append(newpat)
		p["dynamic_pattern"] = new_patterns
	pieces[idx] = p
	emit_signal("state_changed")
	return true

# change Z for selected piece by delta (+1 up, -1 down)
func change_z_selected(delta: int) -> bool:
	if selected_piece_id == -1:
		return false
	var idx = _find_piece_index_by_id(selected_piece_id)
	if idx == -1:
		return false
	_push_undo()
	pieces[idx]["z_order"] = int(pieces[idx]["z_order"]) + delta
	emit_signal("state_changed")
	return true

func deselect():
	selected_piece_id = -1
	emit_signal("state_changed")

# confirm (drop) selection: simply deselect in this model
func confirm_selection():
	selected_piece_id = -1
	emit_signal("state_changed")

# ---------------------
# Tick control
# ---------------------
func start_auto_tick(interval: float = 0.8):
	tick_interval = interval
	_tick_timer.wait_time = tick_interval
	if not _tick_timer.is_stopped():
		_tick_timer.stop()
	_tick_timer.start()

func stop_auto_tick():
	if _tick_timer:
		_tick_timer.stop()

func step_tick():
	_push_undo()
	tick += 1
	emit_signal("state_changed")

func _on_tick_timeout():
	step_tick()

# ---------------------
# Goal check (multi-frame PatternData sequence)
# ---------------------
# PatternData.allowed_states: 0=don't care,1=white,2=black
# level_patterns[0] -> tick, [1] -> tick+1, ...
func is_goal_satisfied() -> bool:
	if level_patterns.is_empty():
		return false
	for offset in range(level_patterns.size()):
		var pat = level_patterns[offset]
		if pat == null:
			return false
		var at_tick = tick + offset
		var grid = compute_visible_state_at(at_tick)
		for y in range(grid_h):
			for x in range(grid_w):
				var want = int(pat.allowed_states[y][x])
				if want == 0:
					continue
				var actual = grid[x][y]
				var color = "black" if actual["is_black_due_to_mask"] or actual["fill_color"] == "black" or actual["fill_color"] == null else "white"
				if want == 1 and color != "white":
					return false
				if want == 2 and color != "black":
					return false
	return true
