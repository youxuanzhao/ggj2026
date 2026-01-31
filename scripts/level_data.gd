extends Resource
class_name LevelData

@export var level_name: String = "untitled"
@export var author: String = ""
@export var grid_size: Vector2i = Vector2i(3, 3)

@export var pieces: Array[PieceData] = []
# patterns: sequence of PatternData, used to verify dynamic/time-based goals
@export var patterns: Array[PatternData] = []

# optional meta
@export var ticks_required: int = 0
