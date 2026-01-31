extends Node2D

@onready var logic = GameLogic
const CELL_SIZE: int = 96
const GRID_ORIGIN: Vector2 = Vector2(32, 32) # top-left offset
var cursor: Vector2i = Vector2i(0, 0)
var holding_piece_id: int = -1

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
			draw_rect(rect, Color(0.15, 0.15, 0.15))
			# border
			draw_rect(rect, Color(0.3, 0.3, 0.3), false, 2)

func _draw_cells():
	var grid = logic.compute_visible_state()
	for x in range(logic.grid_w):
		for y in range(logic.grid_h):
			var cell = grid[x][y]
			var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			if cell["is_black_due_to_mask"]:
				draw_rect(rect, Color.BLACK)
			elif cell["fill_color"] == "white":
				draw_rect(rect, Color.WHITE)
			elif cell["fill_color"] == "black":
				draw_rect(rect, Color.BLACK)
			else:
				draw_rect(rect, Color(0.08, 0.08, 0.08))
			# optional stroke: if stroke_color supported, draw inner border
			# draw stroke if present
			# draw piece outlines if selected
	# draw piece outlines for selected piece (if any)
	if logic.selected_piece_id != -1:
		var idx = _find_piece_index_by_id(logic.selected_piece_id)
		if idx != -1:
			var p = logic.pieces[idx]
			for c in p["shape_cells"]:
				var pos = GRID_ORIGIN + Vector2(int(c[0]) * CELL_SIZE, int(c[1]) * CELL_SIZE)
				var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
				draw_rect(rect, Color(1,0.6,0), false, 3)

func _draw_cursor():
	var pos = GRID_ORIGIN + Vector2(cursor.x * CELL_SIZE, cursor.y * CELL_SIZE)
	var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
	draw_rect(rect, Color(0.0, 0.0, 1.0, 1.0), false, 3)

func _draw_goal_overlay():
	if logic.level_patterns == null:
		return
	print(logic.level_patterns)
	for y in range(logic.grid_h):
		for x in range(logic.grid_w):
			var want = int(logic.level_patterns[0].allowed_states[y][x])
			if want == 0:
				continue
			var pos = GRID_ORIGIN + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			var rect = Rect2(pos, Vector2(CELL_SIZE, CELL_SIZE))
			var col = Color(0,1,0,0.18) if want == 1 else Color(1,0,0,0.18)
			draw_rect(rect, col)

func _draw():
	_draw_grid()
	_draw_cells()
	_draw_goal_overlay()
	_draw_cursor()
	# draw status text
	#draw_string(get_font("font") if has_font("font") else get_default_font(), Vector2(10, 10), "Tick: %d" % logic.tick, Color(1,1,1))

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
