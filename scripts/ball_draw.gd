extends Node2D
## Simple ball visual: white circle with center dot.

func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(0.95, 0.95, 0.95))
	draw_circle(Vector2.ZERO, 6.0, Color(0.15, 0.15, 0.15))
