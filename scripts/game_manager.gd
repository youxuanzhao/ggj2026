extends Node2D

@onready var logic = GameLogic
@onready var level_list: ItemList = $CanvasLayer/LevelSelector/ItemList
@onready var menu_effect: ColorRect = $CanvasLayer/MenuEffect
@onready var menu: VBoxContainer = $CanvasLayer/Menu
@onready var back_btn: Button = $CanvasLayer/Menu/BackBtn
@onready var exit_btn: Button = $CanvasLayer/Menu/ExitBtn
@onready var black_rect: ColorRect = $CanvasLayer/BlackRect

# 'levels' array is provided elsewhere; it should contain base names like "level_1", "level_2", ...
@export var levels: Array = ["level_1", "level_2","level_3","level_4","level_5","level_6","level_7","level_8","level_9","level_10"]
var level_index: int = load("res://assets/save.tres").starting_index

# highest unlocked index (inclusive). We only add levels[0..max_unlocked_index] into the UI.
var max_unlocked_index: int = level_index
var in_transit: bool = false

func _ready() -> void:
	
	menu.visible = false
	menu_effect.visible = false
	
	back_btn.pressed.connect(_on_back_btn_pressed)
	exit_btn.pressed.connect(_on_exit_btn_pressed)
	# connect GameLogic next_level signal
	if not logic.is_connected("next_level", Callable(self, "_on_next_level")):
		logic.connect("next_level", Callable(self, "_on_next_level"))

	# connect UI selection
	if not level_list.is_connected("item_selected", Callable(self, "_on_level_list_selected")):
		level_list.connect("item_selected", Callable(self, "_on_level_list_selected"))

	# initialize list: only unlock & show the first level (if exists)
	_refresh_level_list_initial()

	# load first level if available
	if levels.size() > 0:
		_load_level_by_index(level_index)
	
	var tween = get_tree().create_tween()
	tween.tween_property(black_rect,"color",Color(0,0,0,0), 1.0)
	await tween.finished

# --- populate the visible list only up to max_unlocked_index ---
func _refresh_level_list_initial() -> void:
	level_list.clear()
	if levels.size() == 0:
		return
	for i in range(0, max_unlocked_index+1):
		var name = _level_name_from_index(i)
		level_list.add_item(name)
		level_list.set_item_metadata(i, _level_path_from_index(i))
	level_list.select(0)

# --- helper: add one new unlocked level into the list (append) ---
func _unlock_and_add_level(idx: int) -> void:
	if idx < 0 or idx >= levels.size():
		return
	# only add if it's strictly greater than current max_unlocked_index
	if idx <= max_unlocked_index:
		return
	var name = _level_name_from_index(idx)
	var add_idx = level_list.get_item_count()
	level_list.add_item(name)
	level_list.set_item_metadata(add_idx, _level_path_from_index(idx))
	max_unlocked_index = idx

# --- helpers to build path/name ---
func _level_path_from_index(i: int) -> String:
	return "res://assets/levels/%s.tres" % str(levels[i])

func _level_name_from_index(i: int) -> String:
	return str(levels[i])

# --- load by index and keep UI in sync ---
func _load_level_by_index(i: int) -> void:
	if i < 0 or i >= levels.size():
		return
	# do not allow loading an index that is not yet unlocked (defensive)
	if i > max_unlocked_index:
		push_warning("Level %d is locked and cannot be loaded yet." % i)
		return
	var path = _level_path_from_index(i)
	var res = load(path)
	if res == null:
		push_error("Failed to load level: %s" % path)
		return
	level_index = i
	logic.load_level_from_resource(res)
	# select matching item in UI list (should exist)
	for j in range(level_list.get_item_count()):
		if level_list.get_item_metadata(j) == path:
			level_list.select(j)
			break

# --- signal: user clicked an item in the list ---
func _on_level_list_selected(idx: int) -> void:
	# metadata path expected for unlocked items
	var meta = level_list.get_item_metadata(idx)
	if typeof(meta) == TYPE_STRING and meta != "":
		var res = load(meta)
		if res != null:
			logic.load_level_from_resource(res)
			# keep level_index in sync if possible by matching to levels[]
			for k in range(levels.size()):
				if _level_path_from_index(k) == meta:
					level_index = k
					break

# --- signal: next_level from GameLogic ---
func _on_next_level() -> void:
	if in_transit:
		return
	in_transit = true
	await get_tree().create_timer(1.0).timeout
	var next_idx = level_index + 1
	if next_idx >= 0 and next_idx < levels.size():
		# unlock and add to UI only when this signal arrives (predecessor completed)
		if next_idx > max_unlocked_index:
			_unlock_and_add_level(next_idx)
		# then load it immediately
		_load_level_by_index(next_idx)
	in_transit = false

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("escape"):
		menu.visible = !menu.visible
		menu_effect.visible = !menu_effect.visible

func _on_back_btn_pressed() -> void:
	menu.visible = false
	menu_effect.visible = false

func _on_exit_btn_pressed() -> void:
	var temp: Progress = Progress.new()
	temp.starting_index = max_unlocked_index
	var path = "res://assets/save.tres"
	var err = ResourceSaver.save(temp, path)
	get_tree().change_scene_to_file("res://scenes/title.tscn")
