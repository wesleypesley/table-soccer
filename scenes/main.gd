extends Node2D

var board: Node2D
var turn_manager: Node
var hud: CanvasLayer

func _ready() -> void:
	# Match any canvas expansion beyond the design size to the table color —
	# on wider/taller phones the stretch-mode canvas grows and the exposed
	# margin must not show Godot's default gray.
	RenderingServer.set_default_clear_color(Design.TABLE_BG)
	board = preload("res://scripts/board.gd").new()
	board.name = "Board"   # stable node path: Main/Board
	# center the table in the canvas (pitch 720x1080 inside 1080x1920 design)
	board.position = (Design.CANVAS - Design.PITCH) / 2.0
	add_child(board)

	turn_manager = preload("res://scripts/turn_manager.gd").new()
	turn_manager.name = "TurnManager"
	turn_manager.board = board
	add_child(turn_manager)

	hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.board = board
	hud.turn_manager = turn_manager
	add_child(hud)

	print("Main ready — board + turn FSM + HUD attached")
