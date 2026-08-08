extends Node2D
## Ball: sphere-shaded — radial gradient, specular highlight, pentagon dots.
## Pure _draw() layered circles (no shader).

func _draw() -> void:
	var r := Design.BALL_RADIUS
	# base disc
	draw_circle(Vector2.ZERO, r, Color(0.96, 0.96, 0.97))
	# radial shading: dark rim, light core offset to top-left
	var light_off := Vector2(-r * 0.25, -r * 0.25)
	var rings := 10
	for i in rings:
		var t := float(i) / float(rings - 1)
		var rad := r * (0.05 + 0.95 * t)
		var shade := 1.0 - t * 0.30
		var c := Color(0.96, 0.96, 0.97).lightened((1.0 - shade) * 0.8)
		c.a = 1.0
		draw_circle(light_off * (1.0 - t), rad, c)
	# specular highlight
	draw_circle(Vector2(-r * 0.32, -r * 0.35), r * 0.16, Color(1, 1, 1, 0.95))
	# three dark pentagon dots
	var pent := Color(0.13, 0.13, 0.15)
	draw_circle(Vector2(0, r * 0.35), r * 0.16, pent)
	draw_circle(Vector2(-r * 0.4, -r * 0.1), r * 0.16, pent)
	draw_circle(Vector2(r * 0.4, -r * 0.1), r * 0.16, pent)
