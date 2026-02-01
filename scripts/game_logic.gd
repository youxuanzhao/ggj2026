extends Node

signal state_changed
signal next_level

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

# move/transaction state
var move_in_progress: bool = false
var _move_snapshot_pushed: bool = false

var goal_frame_status: Array = []          # 每个 pattern/frame 的布尔通过状态（true/false）
var overall_goal_satisfied: bool = false  # 整体是否已满足（上一次检查状态）

var level_patterns: Array[PatternData] = []

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
	overall_goal_satisfied = false
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
					# mask that does not cover -> black and stop
					if p.get("is_mask", false):
						cell["is_black_due_to_mask"] = true
						break
					else:
						continue

				# p occupies this cell
				# if p is mask: reveal below color (don't use p's own color as source)
				if p.get("is_mask", false):
					# find the visible color & owner below this mask layer
					var below = _find_below_color(sorted, i, x, y, at_tick)
					# below may return "black" if nothing below or masked below
					cell["fill_color"] = below
					# is_black_due_to_mask remains false because mask here reveals rather than blackens
					break

				# if p is inverter: use inverted below color (owner resolution handled in helper)
				if p.get("is_inverter", false):
					var below_color = _find_below_color(sorted, i, x, y, at_tick)
					cell["fill_color"] = _invert_color(below_color)
					break

				# normal piece supplies its own color
				cell["fill_color"] = p.get("color", "black")
				break
	return grid


# convenience wrapper for current tick
func compute_visible_state() -> Array:
	return compute_visible_state_at(tick)

func _z_desc(a, b) -> int:
	return b["z_order"] < a["z_order"]

# find the visible color below index start_i in sorted array (with tick)
# returns "white" or "black" representing first visible color below index start_i
func _find_below_color(sorted: Array, start_i: int, x: int, y: int, at_tick: int) -> String:
	for j in range(start_i + 1, sorted.size()):
		var q = sorted[j]
		var occupies = piece_occupies_cell(q, x, y, at_tick)
		if not occupies:
			if q.get("is_mask", false):
				# a mask below that does NOT cover this cell forces black and stops
				return "black"
			else:
				continue
		# q occupies
		if q.get("is_inverter", false):
			# inverter: invert whatever is below it
			return _invert_color(_find_below_color(sorted, j, x, y, at_tick))
		if q.get("is_mask", false):
			# q is a mask that covers -> reveal below q recursively
			return _find_below_color(sorted, j, x, y, at_tick)
		# normal piece: return its color
		return q.get("color", "black")
	# nothing below => black
	return "black"


func _invert_color(c: String) -> String:
	if c == "white":
		return "black"
	else:
		return "white"

# Ensure piece ids are unique and z-orders are normalized (0..N-1 by ascending z)
# Then emit state_changed so views update.
func reload_pieces() -> void:
	# 1) ensure ids unique: if duplicates or <=0, assign next free positive id
	var used := {}
	var next_id := 1
	for i in range(pieces.size()):
		var p = pieces[i]
		var id = int(p.get("id", 0))
		if id <= 0 or id in used:
			# find next free
			while next_id in used:
				next_id += 1
			p["id"] = next_id
			used[next_id] = true
			next_id += 1
		else:
			used[id] = true
			if id >= next_id:
				next_id = id + 1
		pieces[i] = p

	# 2) normalize z-orders: stable sort by current z, then reassign 0..N-1
	var sorted_indices := []
	for i in range(pieces.size()):
		sorted_indices.append(i)
	# sort indices by pieces[idx].z_order then by id to be stable
	sorted_indices.sort_custom(Callable(self, "_cmp_index_by_z_then_id"))

	var new_z := 0
	for idx in sorted_indices:
		pieces[idx]["z_order"] = new_z
		new_z += 1

	emit_signal("state_changed")

# comparator for sorting indices by z, then by id (ascending)
func _cmp_index_by_z_then_id(a_idx, b_idx) -> int:
	var a = pieces[a_idx]
	var b = pieces[b_idx]
	var az = int(a.get("z_order", 0))
	var bz = int(b.get("z_order", 0))
	if az != bz:
		return az - bz
	var aid = int(a.get("id", 0))
	var bid = int(b.get("id", 0))
	return aid - bid

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
			# do NOT push undo here; begin snapshot only when player actually moves or changes z
			_move_snapshot_pushed = false
			move_in_progress = false
			emit_signal("state_changed")
			return selected_piece_id
	selected_piece_id = -1
	emit_signal("state_changed")
	return -1

func move_selected(dx: int, dy: int) -> bool:
	# no selection
	if selected_piece_id == -1:
		return false
	var idx = _find_piece_index_by_id(selected_piece_id)
	if idx == -1:
		return false

	var p = pieces[idx]

	# --- 1) compute new base cells and new dynamic patterns, validate bounds BEFORE mutating state ---
	var new_cells := []
	for c in p.get("shape_cells", []):
		var nx = int(c[0]) + dx
		var ny = int(c[1]) + dy
		# out-of-bounds check
		if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
			return false
		new_cells.append([nx, ny])

	# if dynamic, check every pattern frame
	var new_patterns := []
	if p.get("is_dynamic", false):
		for pat in p.get("dynamic_pattern", []):
			var newpat := []
			for c in pat:
				var nx = int(c[0]) + dx
				var ny = int(c[1]) + dy
				if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
					return false
				newpat.append([nx, ny])
			new_patterns.append(newpat)

	# --- 2) begin transaction (snapshot) once, then apply the validated move ---
	_ensure_begin_move()  # or _push_undo() if you didn't adopt _ensure_begin_move

	# apply new base shape cells
	p["shape_cells"] = new_cells

	# apply dynamic patterns if present
	if p.get("is_dynamic", false):
		p["dynamic_pattern"] = new_patterns

	# commit back
	pieces[idx] = p
	emit_signal("state_changed")
	return true



# change Z for selected piece by swapping with nearest piece above/below.
# delta: +1 -> swap with nearest higher z; -1 -> swap with nearest lower z
func change_z_selected(delta: int) -> bool:
	if selected_piece_id == -1:
		return false
	var idx = _find_piece_index_by_id(selected_piece_id)
	if idx == -1:
		return false

	var cur_z = int(pieces[idx]["z_order"])
	var candidate_idx: int = -1
	var candidate_z: int

	if delta > 0:
		candidate_z = cur_z + 1
		for i in range(pieces.size()):
			if i == idx:
				continue
			var z = int(pieces[i]["z_order"])
			if z == candidate_z:
				candidate_idx = i
	else:
		candidate_z = cur_z - 1
		for i in range(pieces.size()):
			if i == idx:
				continue
			var z = int(pieces[i]["z_order"])
			if z == candidate_z:
				candidate_idx = i

	if candidate_idx == -1:
		return false

	# begin transaction (single undo snapshot) instead of pushing every time
	_ensure_begin_move()

	var temp = pieces[idx]["z_order"]
	pieces[idx]["z_order"] = pieces[candidate_idx]["z_order"]
	pieces[candidate_idx]["z_order"] = temp
	
	print("swapped"+str(idx)+str(candidate_idx))
	print(pieces[idx]["z_order"]) 
	print(pieces[candidate_idx]["z_order"])

	emit_signal("state_changed")
	return true

# Ensure we push an undo snapshot exactly once when the player starts mutating the selected piece.
func _ensure_begin_move():
	if selected_piece_id == -1:
		return
	if not _move_snapshot_pushed:
		_push_undo()
		_move_snapshot_pushed = true
		move_in_progress = true


func confirm_selection():
	# finalize selection changes (they are already applied to runtime pieces)
	selected_piece_id = -1
	move_in_progress = false
	_move_snapshot_pushed = false
	emit_signal("state_changed")

func deselect():
	# if you want deselect to undo the in-progress changes instead of confirming them,
	# call undo() here. Decide which UX you prefer.
	# Here we treat deselect as confirming current changes (no rollback).
	selected_piece_id = -1
	move_in_progress = false
	_move_snapshot_pushed = false
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
	_update_goal_status()
	
func _update_goal_status() -> void:
	# compute status for each pattern in level_patterns
	goal_frame_status.clear()
	overall_goal_satisfied = false

	if level_patterns == null or level_patterns.is_empty():
		# nothing to check; leave empty
		emit_signal("state_changed")
		return

	var all_ok := true
	for offset in range(level_patterns.size()):
		var pat = level_patterns[offset]
		if pat == null:
			goal_frame_status.append(false)
			all_ok = false
			continue
		var at_tick = tick + offset
		var grid = compute_visible_state_at(at_tick)
		var frame_ok := true
		for y in range(grid_h):
			for x in range(grid_w):
				var want = pat.allowed_states[y][x]
				var actual = grid[x][y]
				var actual_color = "black" if actual["is_black_due_to_mask"] or actual["fill_color"] == null or actual["fill_color"] == "black" else "white"
				if want and actual_color != "white":
					frame_ok = false
					break
				if !want and actual_color != "black":
					frame_ok = false
					break
			if not frame_ok:
				break
		goal_frame_status.append(frame_ok)
		if not frame_ok:
			all_ok = false

	# if all frames ok and previously not satisfied, print once
	if all_ok and not overall_goal_satisfied:
		emit_signal("next_level")
		print("Goal satisfied")
		all_ok = false
		overall_goal_satisfied = false
		
	overall_goal_satisfied = all_ok

	# notify views
	emit_signal("state_changed")

# === 公开访问函数 ===
func get_goal_frame_status() -> Array:
	# return a shallow copy for safety
	return goal_frame_status.duplicate()

# ---------------------
# Goal check (multi-frame PatternData sequence)
# ---------------------
# PatternData.allowed_states: 0=don't care,1=white,2=black
# level_patterns[0] -> tick, [1] -> tick+1, ...
# New goal check: patterns is an Array of PatternData (each allowed_states[y][x] is boolean)
# Each PatternData corresponds to tick + offset where offset = index in array.
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
				# pattern stores boolean: true => must be white; false => must be black
				var want_white = bool(pat.allowed_states[y][x])
				var actual = grid[x][y]
				var actual_color = "black" if actual["is_black_due_to_mask"] or actual["fill_color"] == "black" or actual["fill_color"] == null else "white"
				if want_white and actual_color != "white":
					return false
				if (not want_white) and actual_color != "black":
					return false
	return true
