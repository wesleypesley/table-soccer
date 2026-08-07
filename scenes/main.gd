extends Node2D

var board: Node2D
var turn_manager: Node
var hud: CanvasLayer

func _ready() -> void:
	board = preload("res://scripts/board.gd").new()
	board.name = "Board"   # stable node path: Main/Board
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
