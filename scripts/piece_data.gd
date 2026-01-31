extends Resource
class_name PieceData

@export_category("Identity")
@export var id: int = 0
@export var color: String = "white" # "white" / "black"

@export_category("Layout")
@export var shape_cells: Array = [] # [[x,y], ...]

@export_category("Runtime flags")
@export var z_order: int = 0
@export var is_mask: bool = false
@export var is_inverter: bool = false

@export_category("Dynamics (optional)")
@export var is_dynamic: bool = false
@export var dynamic_pattern: Array = [] # 每项是 [[x,y],...]
