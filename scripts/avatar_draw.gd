extends Node2D
## HUD avatar disc: team-color circle + inner core + gold ring when the
## player's turn is active. Pure _draw() (no shader, no assets).

var fill_color: Color = Design.CAP_BLUE
var ring_active := false

func _draw() -> void:
	var size := 62.0
	var r := size / 2.0
	# outer ring (gold when active, dim idle)
	var ring_col := Design.SELECT_RING if ring_active else Color(1, 1, 1, 0.25)
	draw_circle(Vector2.ZERO, r, ring_col)
	# disc
	draw_circle(Vector2.ZERO, r - 4.0, fill_color)
	# lighter inner core
	draw_circle(Vector2.ZERO, r * 0.55, fill_color.lightened(0.35))
	# player initial placeholder (P0 / P1)
	var text := "P0" if fill_color == Design.CAP_BLUE else "P1"
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-10, 5), text, HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color(1, 1, 1, 0.9))
