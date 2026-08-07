extends Node2D

var board: Node2D

func _ready() -> void:
	board = preload("res://scripts/board.gd").new()
	board.name = "Board"   # stable node path: Main/Board
	add_child(board)
	print("Main ready — board attached")
