extends Node2D
class_name GameRenderer

@onready var logic = GameLogic

@export var hover_highlight: Color = Color("#00018d")
@export var inverter_highlight: Color = Color.ORANGE
@export var mask_highlight: Color = Color.RED
@export var selected_highlight: Color = Color("#0001FF")
@export var cursor_color: Color = Color("#ff1b8c")
@export var border_color: Color = Color("#131415")


const CELL_SIZE: int = 96
const GRID_ORIGIN: Vector2 = Vector2(32, 32) # top-left offset
var cursor: Vector2i = Vector2i(0, 0)
var holding_piece_id: int = -1
var fill_rect: bool = true
var text_font: Font = preload("res://assets/fonts/JetBrainsMono-Regular.ttf")

func _ready():
	logic.connect("state_changed", Callable(self, "_on_state_changed"))
	set_process_input(true)
	_on_state_changed()
	# start auto tick for jam; you may choose to stop for manual puzzles
	logic.start_auto_tick(0.8)

func _on_state_changed():
	queue_redraw()

func _draw_grid():
	# draw background grid squares
	for x in range(logic.grid_w):
		for y in range(logic.grid_h):
			var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, Color.BLACK)
			# border
			draw_rect(rect, border_color, false, 2)

# 在 BoardView.gd 中加入 / 替换为以下绘制相关函数
# Assumes: logic (GameLogic singleton), CELL_SIZE, GRID_ORIGIN exist

# helper: invert color name
func _invert_color_name(name: String) -> String:
	if name == "white":
		return "black"
	else:
		return "white"

func _draw_cursor_hover_highlight(at_tick: int):
	# only show when nothing is selected
	if logic.selected_piece_id != -1:
		return

	# find topmost piece occupying the cursor cell (respect z-order)
	var pid = -1
	var sorted = logic.pieces.duplicate()
	sorted.sort_custom(_z_desc_local)  # or use your existing _z_desc/_z_desc_local comparator
	for p in sorted:
		if logic.piece_occupies_cell(p, int(cursor.x), int(cursor.y), at_tick):
			pid = p.get("id", -1)
			break
	if pid == -1:
		return

	# find the runtime piece by id
	var p = null
	for item in logic.pieces:
		if item.get("id", null) == pid:
			p = item
			break
	if p == null:
		return

	# determine occupied cells for this piece (respect dynamic pattern)
	var occ_cells := []
	if p.get("is_dynamic", false) and p.get("dynamic_pattern", []).size() > 0:
		var patterns = p["dynamic_pattern"]
		var frame = patterns[at_tick % patterns.size()]
		for c in frame:
			occ_cells.append(Vector2(int(c[0]), int(c[1])))
	else:
		for c in p.get("shape_cells", []):
			occ_cells.append(Vector2(int(c[0]), int(c[1])))

	# draw highlight per occupied cell (same style as selected highlight)
	var border_width := 4.0
	var highlight_color := hover_highlight # same orange as selection highlight
	if p.get("is_inverter", true):
		highlight_color = inverter_highlight
		
	elif p.get("is_mask", true):
		highlight_color = mask_highlight
	
	for cell in occ_cells:
		var x = int(cell.x)
		var y = int(cell.y)
		if x < 0 or x >= logic.grid_w or y < 0 or y >= logic.grid_h:
			continue
		var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
		var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(rect, highlight_color, false, border_width)
		
func compute_visible_state_from_pieces(pieces_array: Array, at_tick: int) -> Dictionary:
	var grid = []
	var owner = []
	# init
	for x in range(logic.grid_w):
		var col = []
		var own_col = []
		for y in range(logic.grid_h):
			col.append({ "fill_color": null, "is_black_due_to_mask": false })
			own_col.append(null)
		grid.append(col)
		owner.append(own_col)

	# sort by z desc (top-first) for visibility resolution
	var sorted = pieces_array.duplicate()
	sorted.sort_custom(_z_desc_local)  # ensure method on self

	for x in range(logic.grid_w):
		for y in range(logic.grid_h):
			var cell = grid[x][y]
			for i in range(sorted.size()):
				var p = sorted[i]
				# use logic's occupancy test (works with runtime piece dict)
				var occupies = logic.piece_occupies_cell(p, x, y, at_tick)
				if not occupies:
					if p.get("is_mask", false):
						cell["is_black_due_to_mask"] = true
						owner[x][y] = null
						break
					else:
						continue
				# occupies true
				if p.get("is_mask", false):
					var below_color = _find_below_color_local(sorted, i, x, y, at_tick)["color"] # or return string
					cell["fill_color"] = below_color
					break
				if p.get("is_inverter", false):
					# get both color and owner from below
					var below = _find_below_color_local(sorted, i, x, y, at_tick)
					var below_color = below["color"]
					var below_owner = below["owner"]
					var inv = "black" if (below_color == "white") else "white"
					cell["fill_color"] = inv
					# set owner to the below owner (inverter itself is not the color source)
					owner[x][y] = below_owner
					break
				# inside compute_visible_state_from_pieces loop, when p occupies:
				else:
					# normal piece: it is the source
					cell["fill_color"] = p.get("color", "black")
					owner[x][y] = p.get("id", null)
					break
	# pack results into a simple return (so caller can access both)
	return { "grid": grid, "owner": owner }

# local below-color finder for compute_visible_state_from_pieces (mirrors GameLogic behavior)
# returns dict { "color": "white"/"black", "owner": piece_id_or_null }
func _find_below_color_local(sorted: Array, start_i: int, x: int, y: int, at_tick: int) -> Dictionary:
	for j in range(start_i + 1, sorted.size()):
		var q = sorted[j]
		var occupies = logic.piece_occupies_cell(q, x, y, at_tick)
		if not occupies:
			if q.get("is_mask", false):
				# mask that does not cover => black; no owner
				return { "color": "black", "owner": null }
			else:
				continue
		# occupies true
		if q.get("is_inverter", false):
			# recursive: get the below color+owner for this inverter's below
			var deeper = _find_below_color_local(sorted, j, x, y, at_tick)
			# invert color but keep owner from deeper (inverter does not become the owner)
			var inv_color = "black" if (deeper["color"] == "white") else "white"
			return { "color": inv_color, "owner": deeper["owner"] }
		else:
			# normal piece: its color and id are the owner
			return { "color": q.get("color", "black"), "owner": q.get("id", null) }
	# nothing below => default black, no owner
	return { "color": "black", "owner": null }

# sort helper used by compute_visible_state_from_pieces (descending)
func _z_desc_local(a, b) -> int:
	return int(b["z_order"]) - int(a["z_order"])



# ---- draw overlays for selected piece elevated z-layers ----
# call this AFTER you draw the base final grid (_draw_layers)
# max_layers: how many +z ghost layers to draw (default 4)
func _draw_z_overlays(at_tick: int, max_layers: int = 4):
	var pid = logic.selected_piece_id
	if pid == -1:
		return

	# find selected runtime piece (must be a dict from logic.pieces)
	var sel_idx = -1
	for i in range(logic.pieces.size()):
		if logic.pieces[i]["id"] == pid:
			sel_idx = i
			break
	if sel_idx == -1:
		return
	var sel_piece = logic.pieces[sel_idx]
	var base_z = int(sel_piece.get("z_order", 0))

	# prepare base pieces copy once
	var base_pieces := []
	for p in logic.pieces:
		# shallow copy dict is enough; we will override z for one piece slot
		base_pieces.append(deep_copy_local(p))
	# find index in base_pieces corresponding to selected piece (by id)
	var sel_copy_idx = -1
	for i in range(base_pieces.size()):
		if base_pieces[i].get("id", null) == pid:
			sel_copy_idx = i
			break
	if sel_copy_idx == -1:
		return

	# for k = 1..max_layers, simulate selected piece z = base_z + k
	var any_drawn = false
	for k in range(1, max_layers + 1):
		# set z override on copy
		base_pieces[sel_copy_idx]["z_order"] = base_z + k
		# simulate visible state with this pieces array
		var sim = compute_visible_state_from_pieces(base_pieces, at_tick)
		var sim_grid = sim["grid"]
		var sim_owner = sim["owner"]

		# compute cells where selected piece is topmost in this simulation
		var cells_to_draw := []
		for x in range(logic.grid_w):
			for y in range(logic.grid_h):
				if sim_owner[x][y] == pid:
					cells_to_draw.append(Vector2(x, y))
		# opacity scheme: +1 -> 0.5, +2 -> 0.25, +3 -> 0.125, ...
		var alpha = 0.5 / pow(2, k - 1)
		if cells_to_draw.is_empty():
			# no visible cells at this elevation: if none drawn for this layer, we can early-stop
			# but continue to next k? typically no need - break.
			if not any_drawn:
				# nothing drawn for first overlay -> continue (maybe occluded by mask); else break
				# but safer: break if empty for this k and also for subsequent k it's unlikely to show new cells
				break
			else:
				break
		# draw translucent rects for these cells
		any_drawn = true
		var color_name = sel_piece.get("color", "black")
		var fill_color = Color.WHITE if color_name == "white" else Color.BLACK
		fill_color.a = alpha
		for cell in cells_to_draw:
			var x = int(cell.x); var y = int(cell.y)
			# sanity bounds
			if x < 0 or x >= logic.grid_w or y < 0 or y >= logic.grid_h:
				continue
			var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(rect, fill_color)

# small local deep copy helper for piece dicts (only simple types inside)
func deep_copy_local(v):
	if typeof(v) == TYPE_DICTIONARY:
		var out := {}
		for k in v.keys():
			out[k] = deep_copy_local(v[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		var out := []
		for item in v:
			out.append(deep_copy_local(item))
		return out
	# primitives / strings
	return v
	
# draw layers bottom-up for given tick
# draw final visible grid for a given tick using GameLogic's compute_visible_state_at
func _draw_layers(at_tick: int):
	var final = logic.compute_visible_state_at(at_tick)
	for x in range(logic.grid_w):
		for y in range(logic.grid_h):
			var cell = final[x][y]
			var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))

			# if mask forced black
			if cell.get("is_black_due_to_mask", false):
				draw_rect(rect, Color.BLACK)
			else:
				var fc = cell.get("fill_color", null)
				if fc == "white":
					draw_rect(rect, Color.WHITE)
				elif fc == "black":
					draw_rect(rect, Color.BLACK)
				else:
					# nothing visible -> draw background
					draw_rect(rect, border_color)

			# border
			draw_rect(rect, border_color, false, 2)

# BoardView.gd — helper to draw highlight around selected piece
# Place this function in the script and call it from _draw() after _draw_layers(...)
func _draw_selected_highlight(at_tick: int):
	var pid = logic.selected_piece_id
	if pid == -1:
		return
	# optional: only show when move in progress
	# if not logic.move_in_progress:
	#     return

	# find runtime piece by id
	var p = null
	for item in logic.pieces:
		if item["id"] == pid:
			p = item
			break
	if p == null:
		return

	# determine occupied cells for highlight
	var occ_cells := []
	if p.get("is_dynamic", false) and p.get("dynamic_pattern", []).size() > 0:
		var patterns = p["dynamic_pattern"]
		var frame = patterns[at_tick % patterns.size()]
		for c in frame:
			occ_cells.append(Vector2(int(c[0]), int(c[1])))
	else:
		for c in p.get("shape_cells", []):
			occ_cells.append(Vector2(int(c[0]), int(c[1])))

	# draw highlight per occupied cell (on top)
	var border_width := 4.0	
	var highlight_color := selected_highlight # orange
	if p.get("is_mask", true):
		highlight_color = mask_highlight
	if p.get("is_inverter", true):
		highlight_color = inverter_highlight
	for cell in occ_cells:
		var x = int(cell.x)
		var y = int(cell.y)
		# sanity check bounds
		if x < 0 or x >= logic.grid_w or y < 0 or y >= logic.grid_h:
			continue
		var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
		var text_pos = GRID_ORIGIN + Vector2(x * CELL_SIZE + CELL_SIZE/2, y * CELL_SIZE + CELL_SIZE/2)
		var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(rect, highlight_color, fill_rect, border_width)
		draw_string(text_font,text_pos,str(p.get("z_order")))

# sorting helper: z ascending for draw
func _z_asc_for_draw(a, b) -> int:
	return int(a["z_order"]) - int(b["z_order"])

# Replace your _draw() to call _draw_grid(), _draw_layers(current tick), etc.
func _draw():
	_draw_grid()
	# draw layers at current tick (or pass another tick for preview)
	_draw_layers(logic.tick)
	# goal overlay can be drawn on top if you want it visible (optional)
	_draw_z_overlays(logic.tick, 4)
	_draw_goal_overlay()
	_draw_selected_highlight(logic.tick)
	_draw_cursor_hover_highlight(logic.tick)
	if logic.selected_piece_id == -1:
		_draw_cursor()
	# status text
	#draw_string(get_font("font") if has_font("font") else get_default_font(), Vector2(10, 10), "Tick: %d" % logic.tick, Color(1,1,1))


func _draw_cursor():
	var pos = GRID_ORIGIN + Vector2(cursor.x * CELL_SIZE, cursor.y * CELL_SIZE)
	var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
	draw_rect(rect, cursor_color, false, 3)

func _draw_goal_overlay():
	# require patterns
	if logic.level_patterns == null or logic.level_patterns.is_empty():
		return

	# get per-frame status from logic (array of bool)
	var status_arr := logic.get_goal_frame_status()
	# ensure length matches patterns; if not available, default to false
	var frames = logic.level_patterns.size()
	while status_arr.size() < frames:
		status_arr.append(false)

	# sizing
	var SMALL_CELL := 18
	var SMALL_SPACING := 6   # spacing between small boards
	var MARGIN_Y := 12       # vertical gap from main grid to small boards
	var CIRCLE_RADIUS := 6

	# main grid pixel extents
	var main_x = GRID_ORIGIN.x
	var main_y = GRID_ORIGIN.y
	var main_w = logic.grid_w * CELL_SIZE
	var main_h = logic.grid_h * CELL_SIZE

	# layout
	var one_w = 3 * SMALL_CELL
	var total_w = frames * one_w + max(0, frames - 1) * SMALL_SPACING
	var start_x = main_x + (main_w - total_w) * 0.5
	var start_y = main_y + main_h + MARGIN_Y

	# draw each frame and its indicator
	for fi in range(frames):
		var pat = logic.level_patterns[fi]
		if pat == null or not ("allowed_states" in pat):
			continue
		var board_x = start_x + fi * (one_w + SMALL_SPACING)
		var board_y = start_y

		# draw small board
		for y in range(3):
			for x in range(3):
				var val = pat.allowed_states[y][x] # 1 or 2
				var pos = Vector2(board_x + x * SMALL_CELL, board_y + y * SMALL_CELL)
				var rect = Rect2(pos, Vector2(SMALL_CELL, SMALL_CELL))
				if val:
					draw_rect(rect, Color(1,1,1))
				else:
					draw_rect(rect, Color(0,0,0))
				draw_rect(rect, Color(0.28,0.28,0.28), false, 1)

		# draw indicator circle centered below the small board
		var center_x = board_x + one_w * 0.5
		var center_y = board_y + 3 * SMALL_CELL + CIRCLE_RADIUS + 4
		var ok = status_arr[fi]
		var circle_color = Color(0,1,0) if ok else Color(1,0,0)
		# draw filled circle (approx using draw_circle)
		if has_method("draw_circle"):
			# Node2D has draw_circle
			draw_circle(Vector2(center_x, center_y), CIRCLE_RADIUS, circle_color)
		else:
			# fallback: draw small rect
			var r = Rect2(Vector2(center_x - CIRCLE_RADIUS, center_y - CIRCLE_RADIUS), Vector2(CIRCLE_RADIUS*2, CIRCLE_RADIUS*2))
			draw_rect(r, circle_color)


# Replace previous _input/_unhandled_input with this block
func _process(_delta):
	# directional input
	if Input.is_action_just_pressed("left"):
		_handle_left()
	if Input.is_action_just_pressed("right"):
		_handle_right()
	if Input.is_action_just_pressed("up"):
		_handle_up()
	if Input.is_action_just_pressed("down"):
		_handle_down()

	# z / x for z-order
	if Input.is_action_just_pressed("z"):
		logic.change_z_selected(1)
	if Input.is_action_just_pressed("x"):
		logic.change_z_selected(-1)
	if Input.is_action_just_pressed("c"):
		fill_rect = !fill_rect

	# space for select / confirm
	if Input.is_action_just_pressed("space"):
		_handle_space()

# Individual handlers for clarity & reuse
func _handle_left():
	if logic.selected_piece_id == -1:
		cursor.x = max(0, cursor.x - 1)
		queue_redraw()
	else:
		logic.move_selected(-1, 0)

func _handle_right():
	if logic.selected_piece_id == -1:
		cursor.x = min(logic.grid_w - 1, cursor.x + 1)
		queue_redraw()
	else:
		logic.move_selected(1, 0)

func _handle_up():
	if logic.selected_piece_id == -1:
		cursor.y = max(0, cursor.y - 1)
		queue_redraw()
	else:
		logic.move_selected(0, -1)

func _handle_down():
	if logic.selected_piece_id == -1:
		cursor.y = min(logic.grid_h - 1, cursor.y + 1)
		queue_redraw()
	else:
		logic.move_selected(0, 1)

func _handle_space():
	if logic.selected_piece_id == -1:
		var pid = logic.select_piece_at(cursor.x, cursor.y)
		if pid != -1:
			holding_piece_id = pid
	else:
		logic.confirm_selection()
		holding_piece_id = -1


func _on_space_pressed():
	# if nothing selected, select piece at cursor (if any)
	if logic.selected_piece_id == -1:
		var pid = logic.select_piece_at(cursor.x, cursor.y)
		if pid != -1:
			holding_piece_id = pid
	else:
		# if selected, confirm (drop)
		logic.confirm_selection()
		holding_piece_id = -1

# helper to find runtime piece index by id (duplicate of logic's)
func _find_piece_index_by_id(pid: int) -> int:
	for i in range(logic.pieces.size()):
		if logic.pieces[i]["id"] == pid:
			return i
	return -1

# allow arrow keys to move selected piece when selected (alternative to cursor movement)
