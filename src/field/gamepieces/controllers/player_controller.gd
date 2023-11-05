## Applied to any gamepiece to allow player control.
##
## The controller responds to player input to handle movement and interaction.
class_name PlayerController extends GamepieceController

const GROUP_NAME: = "_PLAYER_CONTROLLER_GROUP"

var is_active: = false:
	set(value):
		is_active = value
		
		set_process(is_active)
		set_physics_process(is_active)
		set_process_input(is_active)
		set_process_unhandled_input(is_active)

# Keep track of the target of a path. Used to face/interact with the object at a path's end.
# It is reset on cancelling the move path or continuing movement via arrows/gamepad directions.
var _target: Gamepiece = null

@onready var _interaction_searcher: = $InteractionSearcher as Area2D


func _ready() -> void:
	super._ready()
	
	add_to_group(GROUP_NAME)
	
	FieldEvents.cell_selected.connect(_on_cell_selected)
	
	# Connect to a few lambdas that change the cell at which the player searches for interactions.
	# These come into play whenever the player's gamepiece moves to a new cell or changes direction.
	_gamepiece.cell_changed.connect(
		func(old_cell):
			super._on_gamepiece_cell_changed(_gamepiece, old_cell)
			_align_interaction_searcher_to_faced_cell()
	)
	_gamepiece.direction_changed.connect(
		func(_direction): _align_interaction_searcher_to_faced_cell()
	)
	
	set_process(false)
	set_physics_process(false)
	
	is_active = true
	
	_align_interaction_searcher_to_faced_cell()


func _physics_process(_delta: float) -> void:
	var move_dir: = _get_move_direction()
	if move_dir:
		if not _gamepiece.is_moving():
			var target_cell: = Vector2i.ZERO
			
			# Unless using 8-direction movement, one movement axis must be preferred. 
			#	Default to the x-axis.
			if not is_zero_approx(move_dir.x):
				move_dir = Vector2(move_dir.x, 0)
			else:
				move_dir = Vector2(0, move_dir.y)
			
			_gamepiece.direction = move_dir
			target_cell = _gamepiece.cell + Vector2i(move_dir)
			
			# If there is a gamepiece at the target cell, do not move on top of it.
			_update_changed_cells()
			if not is_cell_blocked(target_cell) and \
					not FieldEvents.did_gp_move_to_cell_this_frame(target_cell):
				var move_path: = pathfinder.get_path_cells(_gamepiece.cell, target_cell)
				
				# Path is invalid. Bump animation?
				if move_path.size() <= 1:
					pass
				
				else:
					_gamepiece.travel_to_cell(target_cell)
		
		else:
			_target = null
			_waypoints.clear()


func _get_move_direction() -> Vector2:
	return Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)


func _align_interaction_searcher_to_faced_cell() -> void:
	var cell_coordinates: = Vector2(_gameboard.cell_to_pixel(_gamepiece.get_faced_cell()))
	_interaction_searcher.global_position = cell_coordinates*_gamepiece.global_scale


# The controller's focus will finish travelling this frame unless it is extended.
# There are a few cases where the controller will want to extend the path:
#	a) The gamepiece is following a series of waypoints, and needs to know which cell is next. Note
#		that the controller is responsible for the waypoints (instead of the gamepiece, for
#		instance) so that the path can be checked for any changes *as the gamepiece travels*.
#	b) A movement key/button is held down and the gamepiece should smoothly flow into the next cell.
func _on_gamepiece_arriving(excess_distance: float) -> void:
	# Handle moving to the next waypoint in the path.
	super._on_gamepiece_arriving(excess_distance)
	
	# Allow movement keys/buttons to override path following.
	var move_direction: = _get_move_direction()
	if move_direction:
		_target = null
		_waypoints.clear()
		
		var next_cell: Vector2i
		if not is_zero_approx(move_direction.x):
			next_cell = _gamepiece.cell + Vector2i(int(move_direction.x), 0)
		else:
			next_cell = _gamepiece.cell + Vector2i(0, int(move_direction.y))
		
		if pathfinder.has_cell(next_cell) and not is_cell_blocked(next_cell) and \
				not FieldEvents.did_gp_move_to_cell_this_frame(next_cell):
			_gamepiece.travel_to_cell(next_cell)


func _on_gamepiece_arrived() -> void:
	super._on_gamepiece_arrived()
	
	if _target:
		var distance_to_target: = _target.position - _gamepiece.position
		_gamepiece.direction = distance_to_target
		
		# TODO: Interactions go here.
		
		_target = null


func _on_cell_selected(cell: Vector2i) -> void:
	if not _gamepiece.is_moving():
		# Don't move to the cell the focus is standing on. May want to open inventory.
		if cell == _gamepiece.cell:
			return
			
		# We'll want different behaviour depending on what's underneath the cursor.
		# If there is an interactable, blocking object beneath the cursor, we'll walk *next* to 
		# the cell.
		
		# If the cell beneath the cursor is empty the focus can follow a path to the cell.
		travel_to_cell(cell)
		if not _waypoints.is_empty():
			FieldEvents.player_path_set.emit(_gamepiece, _waypoints.back())
