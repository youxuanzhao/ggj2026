extends Node2D
class_name GameEditor
# EditorScene.gd
# Attach to EditorScene root (Node2D)
# Requires GameLogic autoload and Gamerenderer node (rendering left area) already in scene.

@onready var logic = GameLogic
@onready var gamerenderer = $GameArea/GameRenderer

# Builder UI
@onready var build_grid = $RightPanel/HBoxContainer/BuilderPanel/BuildGrid
@onready var color_option = $RightPanel/HBoxContainer/BuilderPanel/HBoxContainer/ColorOption
@onready var is_mask_cb = $RightPanel/HBoxContainer/BuilderPanel/HBoxContainer/IsMask
@onready var is_inverter_cb = $RightPanel/HBoxContainer/BuilderPanel/HBoxContainer/IsInverter
@onready var is_dynamic_cb = $RightPanel/HBoxContainer/BuilderPanel/HBoxContainer/IsDynamic
@onready var dyn_list = $RightPanel/HBoxContainer/BuilderPanel/DynList
@onready var add_state_btn = $RightPanel/HBoxContainer/BuilderPanel/AddStateBtn
@onready var insert_btn = $RightPanel/HBoxContainer/BuilderPanel/InsertBtn

# Goal UI
@onready var goal_grid = $RightPanel/HBoxContainer/GoalPanel/GoalGrid
@onready var goal_is_dynamic_cb = $RightPanel/HBoxContainer/GoalPanel/GoalIsDynamic
@onready var goal_dyn_list = $RightPanel/HBoxContainer/GoalPanel/GoalDynList
@onready var goal_add_state_btn = $RightPanel/HBoxContainer/GoalPanel/GoalAddStateBtn
@onready var save_goal_btn = $RightPanel/HBoxContainer/GoalPanel/SaveGoalBtn

# Bottom: save level
@onready var level_name_input = $RightPanel/VBoxContainer/LevelNameInput
@onready var save_level_btn = $RightPanel/VBoxContainer/SaveLevelBtn
@onready var reset_level_btn = $RightPanel/VBoxContainer/ResetLevelBtn
@onready var load_level_btn = $RightPanel/VBoxContainer2/LoadLevelBtn
@onready var export_level_btn = $RightPanel/VBoxContainer2/ExportLevelBtn
@onready var level_code_input = $RightPanel/VBoxContainer2/LevelCodeInput


@onready var menu_effect: ColorRect = $CanvasLayer/MenuEffect
@onready var menu: VBoxContainer = $CanvasLayer/Menu
@onready var back_btn: Button = $CanvasLayer/Menu/BackBtn
@onready var exit_btn: Button = $CanvasLayer/Menu/ExitBtn

# internal builder state
var builder_cells := []        # 3x3 bool active layout for piece shape
var builder_color := "white"
var builder_is_mask := false
var builder_is_inverter := false
var builder_is_dynamic := false
var builder_dynamic_frames := []   # array of frames; each frame is 3x3 bool array

# goal state (patterns sequence)
var goal_cells := []          # 3x3 with 0/1/2 semantics for current editing (0 don't care)
var goal_is_dynamic := false
var goal_frames := []         # array of PatternData-like allowed_states (3x3 int arrays)

var initial_z = -1
# id / z generation
func _next_piece_id() -> int:
	var maxid = 0
	for p in logic.pieces:
		if int(p["id"]) > maxid:
			maxid = int(p["id"])
	return maxid + 1

func _next_z_index() -> int:
	initial_z += 1
	return initial_z

func _ready():
	menu.visible = false
	menu_effect.visible = false
	
	load_level_btn.pressed.connect(_on_load_level_btn_pressed)
	export_level_btn.pressed.connect(_on_export_level_btn_pressed)
	back_btn.pressed.connect(_on_back_btn_pressed)
	exit_btn.pressed.connect(_on_exit_btn_pressed)
	logic.pieces.clear()
	logic.level_patterns.clear()
	_init_builder_grid()
	_init_goal_grid()
	_connect_ui()
	_update_builder_ui_visibility()

# -------------------------
# UI initialization
# -------------------------
func _init_builder_grid():
	builder_cells = []
	for y in range(3):
		var row = []
		for x in range(3):
			row.append(false)
		builder_cells.append(row)

	# ensure grid has 9 buttons children in row-major order
	# create if empty
	if build_grid.get_child_count() == 0:
		for i in range(9):
			var b = Button.new()
			b.name = "b%d" % i
			b.toggle_mode = true
			b.expand_icon = true
			b.custom_minimum_size = Vector2(36,36)
			build_grid.add_child(b)
			b.button_pressed = false
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_stylebox_override("pressed", preload("res://assets/white_button.tres"))
			b.pressed.connect(_on_builder_cell_toggled.bind(i))
	_update_builder_grid_visuals()

func _init_goal_grid():
	goal_cells = []
	for y in range(3):
		var row = []
		for x in range(3):
			row.append(false) # default black
		goal_cells.append(row)

	if goal_grid.get_child_count() == 0:
		for i in range(9):
			var b = Button.new()
			b.name = "g%d" % i
			b.toggle_mode = true
			b.expand_icon = true
			b.custom_minimum_size = Vector2(36,36)
			goal_grid.add_child(b)
			b.button_pressed = false
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_stylebox_override("pressed", preload("res://assets/white_button.tres"))
			b.pressed.connect(_on_goal_cell_toggled.bind(i))
	_update_goal_grid_visuals()

# -------------------------
# UI events & handlers
# -------------------------
func _connect_ui():
	color_option.clear()
	color_option.add_item("white")
	color_option.add_item("black")
	color_option.select(0)

	is_mask_cb.button_pressed = false
	is_inverter_cb.button_pressed = false
	is_dynamic_cb.button_pressed = false

	add_state_btn.connect("pressed", Callable(self, "_on_add_state_pressed"))
	insert_btn.connect("pressed", Callable(self, "_on_insert_pressed"))

	goal_is_dynamic_cb.button_pressed = false
	goal_add_state_btn.connect("pressed", Callable(self, "_on_goal_add_state_pressed"))
	save_goal_btn.connect("pressed", Callable(self, "_on_save_goal_pressed"))

	save_level_btn.connect("pressed", Callable(self, "_on_save_level_pressed"))
	reset_level_btn.connect("pressed", Callable(self, "_on_reset_level_pressed"))
	# option change
	color_option.connect("item_selected", Callable(self, "_on_color_option_changed"))
	is_mask_cb.connect("toggled", Callable(self, "_on_mask_toggled"))
	is_inverter_cb.connect("toggled", Callable(self, "_on_inverter_toggled"))
	is_dynamic_cb.connect("toggled", Callable(self, "_on_dynamic_toggled"))

	goal_is_dynamic_cb.connect("toggled", Callable(self, "_on_goal_dynamic_toggled"))

# builder cell toggle (index 0..8 row-major)
func _on_builder_cell_toggled(idx: int):
	var x = idx % 3
	var y = idx / 3
	print(y)
	print(x)
	builder_cells[y][x] = not builder_cells[y][x] # toggle
	print(builder_cells[y][x])
	_update_builder_grid_visuals()

# goal cell toggles: cycle 0->1->2->0  (0 don't care,1 white,2 black)
# toggle between black (false) and white (true)
func _on_goal_cell_toggled(idx: int):
	var x = idx % 3
	var y = idx / 3
	goal_cells[y][x] = not goal_cells[y][x]
	_update_goal_grid_visuals()


func _on_color_option_changed(i):
	builder_color = color_option.get_item_text(i)

func _on_mask_toggled(pressed: bool):
	builder_is_mask = pressed

func _on_inverter_toggled(pressed: bool):
	builder_is_inverter = pressed

func _on_dynamic_toggled(pressed: bool):
	builder_is_dynamic = pressed
	_update_builder_ui_visibility()

func _on_goal_dynamic_toggled(pressed: bool):
	goal_is_dynamic = pressed
	goal_dyn_list.visible = pressed
	goal_add_state_btn.visible = pressed

# update grid visuals based on builder_cells
func _update_builder_grid_visuals():
	for i in range(build_grid.get_child_count()):
		var b = build_grid.get_child(i) as Button
		var x = i % 3
		var y = i / 3
		if builder_cells[y][x]:
			# represent active cell by color_option color
			if builder_color == "white":
				b.modulate = Color(1,1,1)
			else:
				b.modulate = Color(0,0,0)
			b.button_pressed = true
		else:
			b.modulate = Color(0.2,0.2,0.2)
			b.button_pressed = false

func _update_goal_grid_visuals():
	for i in range(goal_grid.get_child_count()):
		var b = goal_grid.get_child(i) as Button
		var x = i % 3
		var y = i / 3
		var val = goal_cells[y][x]
		if val:
			b.modulate = Color(1,1,1) # white
			b.button_pressed = true
		else:
			b.modulate = Color(0,0,0) # black
			b.button_pressed = true

func _update_builder_ui_visibility():
	dyn_list.visible = builder_is_dynamic
	add_state_btn.visible = builder_is_dynamic

# -------------------------
# Dynamic frames handling
# -------------------------
# capture current builder grid as a 3x3 bool array frame
func _current_builder_frame() -> Array:
	var f := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append(builder_cells[y][x])
		f.append(row)
	return f

# when Add State pressed in builder: append current frame to builder_dynamic_frames and update DynList
func _on_add_state_pressed():
	var frame = _current_builder_frame()
	builder_dynamic_frames.append(frame)
	_refresh_dyn_list()

func _refresh_dyn_list():
	dyn_list.clear()
	for i in range(builder_dynamic_frames.size()):
		dyn_list.add_item("Frame %d" % i)

# goal add state
func _on_goal_add_state_pressed():
	var frame := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append(bool(goal_cells[y][x])) # boolean snapshot
		frame.append(row)
	goal_frames.append(frame)
	_refresh_goal_dyn_list()


func _refresh_goal_dyn_list():
	goal_dyn_list.clear()
	for i in range(goal_frames.size()):
		goal_dyn_list.add_item("Frame %d" % i)

# -------------------------
# Insert piece into GameLogic
# -------------------------
func _on_insert_pressed():
	# create PieceData resource in memory and instantiate into GameLogic.pieces (runtime dict)
	# but to keep consistent with your load/save pipeline we create a PieceData Resource and then map its fields
	var pd = PieceData.new()
	pd.id = _next_piece_id()
	pd.color = builder_color
	# build shape_cells array from builder_cells
	var shape : Array = []
	for y in range(3):
		for x in range(3):
			print(builder_cells[y][x])
			if builder_cells[y][x]:
				print(1)
				shape.append([x, y])
	pd.shape_cells = shape
	pd.z_order = _next_z_index()
	pd.is_mask = builder_is_mask
	pd.is_inverter = builder_is_inverter
	pd.is_dynamic = builder_is_dynamic
	# dynamic_pattern must be an array of frames where each frame is an array of [x,y] coords
	var dynpat := []
	for f in builder_dynamic_frames:
		var coords := []
		for y in range(3):
			for x in range(3):
				if f[y][x]:
					coords.append([x, y])
		dynpat.append(coords)
	pd.dynamic_pattern = dynpat

	# Map to runtime (same as load_level_from_resource mapping)
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
	logic.pieces.append(rp)
	print("appended")
	print(logic.pieces)
	#logic.reload_pieces()

	# reset builder (optionally)
	_clear_builder()

func _clear_builder():
	for y in range(3):
		for x in range(3):
			builder_cells[y][x] = false
	builder_dynamic_frames.clear()
	_update_builder_grid_visuals()
	_refresh_dyn_list()
	is_mask_cb.button_pressed = false
	is_inverter_cb.button_pressed = false
	is_dynamic_cb.button_pressed = false
	color_option.select(0)
	builder_color = "white"

# -------------------------
# Save goal (Save button in goal editor)
# -------------------------
func _on_save_goal_pressed():
	var patterns : Array[PatternData] = []
	if goal_is_dynamic and goal_frames.size() > 0:
		for f in goal_frames:
			var pat = PatternData.new()
			pat.allowed_states = f.duplicate(true)
			patterns.append(pat)
	else:
		var pat = PatternData.new()
		pat.allowed_states = goal_cells.duplicate(true)
		patterns.append(pat)
	logic.level_patterns = patterns
	logic.emit_signal("state_changed")
	var ok = logic.is_goal_satisfied()
	if ok:
		print("Goal satisfied by current board state")
	else:
		print("Goal NOT satisfied by current board state")

# -------------------------
# Save level (resource)
# -------------------------
func _on_save_level_pressed():
	var name = level_name_input.text.strip_edges()
	if name == "":
		push_warning("Please enter level name")
		return

	# Create LevelData in-memory (not written to disk)
	var ld = LevelData.new()
	ld.level_name = name
	ld.grid_size = Vector2i(logic.grid_w, logic.grid_h)

	# pieces: create PieceData resources from current logic.pieces
	var res_pieces : Array[PieceData]= []
	for p in logic.pieces:
		var piece_res = PieceData.new()
		piece_res.id = int(p["id"])
		piece_res.color = p["color"]
		piece_res.z_order = int(p["z_order"])
		# deep copy arrays to avoid sharing references
		piece_res.shape_cells = p["shape_cells"].duplicate(true)
		piece_res.is_mask = bool(p.get("is_mask", false))
		piece_res.is_inverter = bool(p.get("is_inverter", false))
		piece_res.is_dynamic = bool(p.get("is_dynamic", false))
		piece_res.dynamic_pattern = p.get("dynamic_pattern", []).duplicate(true)
		res_pieces.append(piece_res)
	ld.pieces = res_pieces

	# patterns from logic.level_patterns - clone into LevelData.patterns
	var pats : Array[PatternData] = []
	for pat in logic.level_patterns:
		if pat == null:
			continue
		var pcopy = PatternData.new()
		# ensure allowed_states is duplicated (3x3)
		pcopy.allowed_states = pat.allowed_states.duplicate(true)
		pats.append(pcopy)
	ld.patterns = pats

	# Add to GameLogic.custom_levels via provided API
	var new_index = logic.add_custom_level(ld)
	if new_index >= 0:
		print("Saved custom level into GameLogic.custom_levels at index %d" % new_index)
		# Optionally: notify UI to add new item to CustomLevelSelector
		# e.g., call a function in GameManager or emit a custom signal:
		# emit_signal("custom_level_added", new_index, name)
	else:
		push_error("Failed to save custom level into GameLogic")

func _on_reset_level_pressed():
	_clear_builder()
	goal_frames.clear()
	logic.pieces.clear()
	logic.level_patterns.clear()
	initial_z = -1

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("escape"):
		menu.visible = !menu.visible
		menu_effect.visible = !menu_effect.visible

func _on_back_btn_pressed() -> void:
	menu.visible = false
	menu_effect.visible = false

func _on_exit_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")

# Export current runtime level to a shareable string (base64 of XORed JSON).
# passphrase optional; use same passphrase to load.
func export_level_to_string(passphrase: String = "") -> String:
	# 1) Build a lightweight serializable dict representing level
	var payload := {}
	# metadata
	payload["level_name"] = logic.get("level_name") if logic.get("level_name") != "" else "exported_level"
	payload["grid_size"] = [logic.grid_w, logic.grid_h]

	# pieces: convert runtime pieces (dicts) into simple variant-friendly arrays
	var pieces_arr := []
	for p in logic.pieces:
		var pd := {
			"id": int(p.get("id", 0)),
			"color": p.get("color", "black"),
			"z_order": int(p.get("z_order", 0)),
			"shape_cells": p.get("shape_cells", []).duplicate(true),
			"is_mask": bool(p.get("is_mask", false)),
			"is_inverter": bool(p.get("is_inverter", false)),
			"is_dynamic": bool(p.get("is_dynamic", false)),
			"dynamic_pattern": p.get("dynamic_pattern", []).duplicate(true)
		}
		pieces_arr.append(pd)
	payload["pieces"] = pieces_arr

	# patterns: level_patterns may be resources; convert to plain arrays
	var pats := []
	for pat in logic.level_patterns:
		if pat == null:
			continue
		# PatternData.allowed_states assumed to be 3x3 of booleans or 1/2 ints; keep as-is
		pats.append(pat.allowed_states.duplicate(true))
	payload["patterns"] = pats

	# 2) JSON encode
	var json_text = JSON.stringify(payload)

	# 3) UTF-8 bytes
	var bytes = json_text.to_utf8_buffer() # PackedByteArray

	# 4) optional XOR "encryption" with passphrase
	if passphrase != "":
		var key_bytes = passphrase.to_utf8_buffer()
		var klen = key_bytes.size()
		if klen == 0:
			# fallback - shouldn't happen
			pass
		else:
			for i in range(bytes.size()):
				# XOR each byte with key (looped)
				bytes[i] = bytes[i] ^ key_bytes[i % klen]

	# 5) Base64 encode to produce shareable string
	var b64 = Marshalls.raw_to_base64(bytes)  # PackedByteArray -> base64 String
	# Optional: add a small prefix to indicate version / that this is our encoded level
	return "OCCLU" + b64

# Load a level from a string produced by export_level_to_string and load it into logic.
# Returns true on success, false on failure.
func load_level_from_string(s: String, passphrase: String = "") -> bool:
	# validate prefix if present
	var payload_b64 := s
	if s.begins_with("OCCLU"):
		payload_b64 = s.substr(5, s.length() - 5)
	else:
		return false

	# Base64 -> bytes
	var ok_bytes := PackedByteArray()
	# PackedByteArray has a helper to decode base64 in Godot 4; use from_base64() if present.
	# The following works in Godot 4: PackedByteArray.from_base64(payload_b64)
	# If your engine doesn't have that exact API, replace with appropriate base64 decode.
	ok_bytes = Marshalls.base64_to_raw(payload_b64)

	# XOR with passphrase if provided
	if passphrase != "":
		var key_bytes := passphrase.to_utf8_buffer()
		var klen := key_bytes.size()
		if klen > 0:
			for i in range(ok_bytes.size()):
				ok_bytes[i] = ok_bytes[i] ^ key_bytes[i % klen]

	# Convert bytes back to JSON string
	var json_text := ok_bytes.get_string_from_utf8()

	# Parse JSON
	var jres = JSON.parse_string(json_text)
	if jres == null:
		push_error("Failed to parse level JSON: %s" % jres.error_string)
		return false
	var data = jres

	# Build LevelData resource from parsed data
	var ld = LevelData.new()
	if "level_name" in data:
		ld.level_name = str(data["level_name"])
	# grid_size optional (we assume 3x3 generally)
	if "grid_size" in data:
		var gs = data["grid_size"]
		if typeof(gs) == TYPE_ARRAY and gs.size() >= 2:
			ld.grid_size = Vector2i(int(gs[0]), int(gs[1]))

	# reconstruct pieces as PieceData resources
	var res_pieces : Array[PieceData] = []
	if "pieces" in data and typeof(data["pieces"]) == TYPE_ARRAY:
		for pd in data["pieces"]:
			var piece_res = PieceData.new()
			if "id" in pd:
				piece_res.id = int(pd["id"])
			if "color" in pd:
				piece_res.color = str(pd["color"])
			if "z_order" in pd:
				piece_res.z_order = int(pd["z_order"])
			if "shape_cells" in pd:
				piece_res.shape_cells = pd["shape_cells"]
			if "is_mask" in pd:
				piece_res.is_mask = bool(pd["is_mask"])
			if "is_inverter" in pd:
				piece_res.is_inverter = bool(pd["is_inverter"])
			if "is_dynamic" in pd:
				piece_res.is_dynamic = bool(pd["is_dynamic"])
			if "dynamic_pattern" in pd:
				piece_res.dynamic_pattern = pd["dynamic_pattern"]
			res_pieces.append(piece_res)
	ld.pieces = res_pieces

	# patterns
	var pats : Array[PatternData] = []
	if "patterns" in data and typeof(data["patterns"]) == TYPE_ARRAY:
		for p in data["patterns"]:
			var pat_res = PatternData.new()
			pat_res.allowed_states = p
			pats.append(pat_res)
	ld.patterns = pats

	# finally load into logic
	logic.load_level_from_resource(ld)
	return true

func _on_load_level_btn_pressed():
	if level_code_input.text != "":
		load_level_from_string(level_code_input.text)

func _on_export_level_btn_pressed():
	level_code_input.text = export_level_to_string()
