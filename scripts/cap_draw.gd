extends Node2D
## Simple cap visual: filled circle + ring. `selected` draws a highlight ring.

@export var cap_color: Color = Color(0.5, 0.5, 0.5)
var selected := false

func _draw() -> void:
	draw_circle(Vector2.ZERO, 44.0, cap_color)
	draw_arc(Vector2.ZERO, 44.0, 0, TAU, 48, Color(1, 1, 1, 0.35), 4.0)
	if selected:
		draw_arc(Vector2.ZERO, 52.0, 0, TAU, 48, Color(1.0, 0.85, 0.2, 0.95), 5.0)
