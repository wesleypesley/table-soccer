extends Node2D
## Small clock face for the HUD turn timer.
##
## Drawn rather than typed: the default font has no glyph for ⏱/⏰, so a text
## label renders an empty tofu box. Primitives always work.

var radius := 13.0
var color: Color = Design.HUD_TEXT

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.0))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.5)
	# hands: 12 o'clock and 4 o'clock, so it reads as a clock at 26px
	draw_line(Vector2.ZERO, Vector2(0, -radius * 0.62), color, 2.5)
	draw_line(Vector2.ZERO, Vector2(radius * 0.48, radius * 0.30), color, 2.5)
	# crown nub on top
	draw_line(Vector2(0, -radius - 1.0), Vector2(0, -radius - 4.0), color, 3.0)
