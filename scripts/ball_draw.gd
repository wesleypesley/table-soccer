extends Node2D
## Ball visual: white circle with center dot, token-driven.

func _draw() -> void:
	draw_circle(Vector2.ZERO, Design.BALL_RADIUS, Design.BALL_WHITE)
	draw_circle(Vector2.ZERO, 6.0, Design.BALL_DOT)
