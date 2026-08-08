extends Node2D
## Pitch visual — real-Plato look: mottled wood table frame, deep green felt
## with apron, crisp white markings (center circle, penalty areas, arcs),
## rounded walls, goals with depth. Pure rendering (no physics); every value
## from Design tokens. Uses deterministic pseudo-random for the wood grain.

var _rng := RandomNumberGenerator.new()

func _draw() -> void:
	var p := Design.PITCH
	var t := Design.WALL_THICKNESS
	var c := p / 2.0
	var line := Design.LINE_WHITE

	# --- 1. wood table frame (full canvas, procedural grain) ---
	# board is centered: canvas spans (-off) .. (CANVAS-off) in board coords
	var off := (Design.CANVAS - p) / 2.0
	draw_rect(Rect2(-off.x, -off.y, Design.CANVAS.x, Design.CANVAS.y), Design.WOOD_BASE)
	_draw_wood_grain(off)

	# --- 2. felt: deep green + darker apron ring + grass texture ---
	# baked tileable grass-noise texture (seeded, zero assets) — same trick as
	# Claude's flick_soccer: one tile, tinted per stripe so the blade noise
	# reads instead of a dead-flat band.
	var apron := 34.0
	draw_rect(Rect2(-apron, -apron, p.x + apron * 2.0, p.y + apron * 2.0), Design.FELT_APRON)
	draw_rect(Rect2(0, 0, p.x, p.y), Design.PITCH_FELT)
	var tile := _get_grass_tile()
	var stripe_h := p.y / 8.0
	for i in 8:
		var rect := Rect2(0, stripe_h * float(i), p.x, stripe_h)
		# alternate light/dark stripes (~8% like real mowed turf)
		var tint := Color(1, 1, 1) if i % 2 == 0 else Color(0.88, 0.88, 0.88)
		draw_texture_rect(tile, rect, true, tint)
	# soft top-light falloff over the grass
	draw_rect(Rect2(0, 0, p.x, p.y * 0.30), Color(1, 1, 1, 0.03))
	draw_rect(Rect2(0, p.y * 0.78, p.x, p.y * 0.22), Color(0, 0, 0, 0.045))

	# --- 3. markings: center ---
	draw_line(Vector2(0, c.y), Vector2(p.x, c.y), line, 3.0)
	draw_arc(c, Design.CENTER_CIRCLE_R, 0, TAU, 48, line, 3.0)
	draw_circle(c, 5.0, line)

	# --- 4. markings: penalty areas + goal areas + spots + arcs (both ends) ---
	_draw_goal_area_markings(c.x, p, line, true)
	_draw_goal_area_markings(c.x, p, line, false)

	# --- 5. corner arcs ---
	var r := Design.CORNER_ARC_R
	draw_arc(Vector2(r, r), r, PI, PI * 1.5, 16, line, 3.0)
	draw_arc(Vector2(p.x - r, r), r, -PI * 0.5, 0, 16, line, 3.0)
	draw_arc(Vector2(r, p.y - r), r, PI * 0.5, PI, 16, line, 3.0)
	draw_arc(Vector2(p.x - r, p.y - r), r, 0, PI * 0.5, 16, line, 3.0)

	# --- 6. walls: rounded beveled rails ---
	draw_rect(Rect2(0, 0, p.x, t), Design.WALL_COLOR)
	draw_rect(Rect2(0, p.y - t, p.x, t), Design.WALL_COLOR)
	draw_rect(Rect2(0, 0, t, p.y), Design.WALL_COLOR)
	draw_rect(Rect2(p.x - t, 0, t, p.y), Design.WALL_COLOR)
	for cx2 in [t, p.x - t]:
		for cy2 in [t, p.y - t]:
			draw_circle(Vector2(cx2, cy2), t, Design.WALL_COLOR)
	# bevel highlights
	draw_line(Vector2(0, 2), Vector2(p.x, 2), Design.WALL_COLOR.lightened(0.18), 2.0)
	draw_line(Vector2(0, t - 2), Vector2(p.x, t - 2), Design.WALL_COLOR.darkened(0.25), 2.0)
	draw_line(Vector2(0, p.y - t + 2), Vector2(p.x, p.y - t + 2), Design.WALL_COLOR.lightened(0.1), 2.0)
	draw_line(Vector2(t - 2, 0), Vector2(t - 2, p.y), Design.WALL_COLOR.darkened(0.25), 2.0)
	draw_line(Vector2(p.x - t + 2, 0), Vector2(p.x - t + 2, p.y), Design.WALL_COLOR.lightened(0.1), 2.0)
	# white boundary line at the felt edge
	draw_rect(Rect2(0, 0, p.x, p.y), line, false, 3.0)

	# --- 7. goals: deep pocket + net + lit posts ---
	var half := Design.GOAL_WIDTH / 2.0
	_draw_goal(c.x, half, p, true)
	_draw_goal(c.x, half, p, false)

func _draw_wood_grain(off: Vector2) -> void:
	# deterministic pseudo-random streaks across the table (no assets)
	_rng.seed = 1337
	var v := Design.CANVAS
	for i in 140:
		var y := _rng.randf_range(0, v.y) - off.y
		var len2 := _rng.randf_range(60, 340)
		var x := _rng.randf_range(0, v.x) - off.x
		var thick := _rng.randf_range(1.0, 3.5)
		var c: Color
		var r := _rng.randf()
		if r < 0.5:
			c = Design.WOOD_DARK
			c.a = _rng.randf_range(0.25, 0.6)
		elif r < 0.9:
			c = Design.WOOD_LIGHT
			c.a = _rng.randf_range(0.2, 0.5)
		else:
			c = Design.WOOD_KNOT
			c.a = _rng.randf_range(0.5, 0.8)
			draw_circle(Vector2(x, y), _rng.randf_range(3.0, 9.0), c)
			continue
		draw_line(Vector2(x, y), Vector2(x + len2, y + _rng.randf_range(-6, 6)), c, thick)

# Baked tileable grass-noise patch standing in for a photo texture. Seeded so
# it's identical every frame; built once and cached. Base = Design.PITCH_FELT
# with slight per-pixel noise so the mowed stripes don't read as flat bands.
static var _grass_tile: ImageTexture

static func _get_grass_tile() -> ImageTexture:
	if _grass_tile:
		return _grass_tile
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260808
	var base := Design.PITCH_FELT
	for y in size:
		for x in size:
			var n: float = rng.randf_range(-0.045, 0.045)
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	_grass_tile = ImageTexture.create_from_image(img)
	return _grass_tile

func _draw_goal_area_markings(cx: float, p: Vector2, line: Color, top: bool) -> void:
	var y0 := 0.0 if top else p.y
	var dir := 1.0 if top else -1.0
	var pa := Rect2(cx - Design.PENALTY_AREA_W / 2.0, y0, Design.PENALTY_AREA_W, Design.PENALTY_AREA_D)
	if not top:
		pa.position.y = p.y - Design.PENALTY_AREA_D
	var ga := Rect2(cx - Design.GOAL_AREA_W / 2.0, y0, Design.GOAL_AREA_W, Design.GOAL_AREA_D)
	if not top:
		ga.position.y = p.y - Design.GOAL_AREA_D
	draw_rect(pa, Color(1, 1, 1, 0.04))
	draw_rect(ga, Color(1, 1, 1, 0.05))
	draw_rect(pa, line, false, 3.0)
	draw_rect(ga, line, false, 3.0)
	var spot_y := y0 + Design.PENALTY_SPOT_D * dir
	draw_circle(Vector2(cx, spot_y), 4.0, line)
	var arc_r := Design.CENTER_CIRCLE_R
	var emerge := Design.PENALTY_AREA_D - Design.PENALTY_SPOT_D
	var half_ang := acos(clampf(emerge / arc_r, -1.0, 1.0))
	if top:
		draw_arc(Vector2(cx, spot_y), arc_r, PI / 2.0 - half_ang, PI / 2.0 + half_ang, 32, line, 3.0)
	else:
		draw_arc(Vector2(cx, spot_y), arc_r, -PI / 2.0 - half_ang, -PI / 2.0 + half_ang, 32, line, 3.0)

func _draw_goal(cx: float, half: float, p: Vector2, top: bool) -> void:
	# pocket walls are physical (board.gd); draw the pocket shell so it reads
	# as a net: dark pocket, crosshatch, back wall + side walls, posts.
	var pd := 36.0
	var tw := 20.0
	var gx0 := cx - half
	var gx1 := cx + half
	# pocket shell (behind the goal line)
	var shell := Rect2(gx0 - tw, (-pd if top else p.y), (gx1 - gx0) + tw * 2.0, pd)
	if not top:
		shell.position.y = p.y
	# dark pocket interior
	draw_rect(shell, Color(0, 0, 0, 0.30))
	# net crosshatch inside the pocket
	var step := 8.0
	var x := shell.position.x
	while x < shell.end.x:
		draw_line(Vector2(x, shell.position.y), Vector2(x, shell.end.y), Design.GOAL_NET, 1.0)
		x += step
	var y := shell.position.y
	while y < shell.end.y:
		draw_line(Vector2(shell.position.x, y), Vector2(shell.end.x, y), Design.GOAL_NET, 1.0)
		y += step
	# pocket frame (wall color)
	draw_rect(shell, Design.WALL_COLOR, false, tw)
	# net frame edge at the goal line
	var frame := Color(1, 1, 1, 0.4)
	if top:
		draw_line(Vector2(gx0, 0), Vector2(gx1, 0), frame, 3.0)
	else:
		draw_line(Vector2(gx0, p.y), Vector2(gx1, p.y), frame, 3.0)
	# posts: lit charcoal cylinders (highlight + shadow + rim)
	for px in [gx0, gx1]:
		var py := 0.0 if top else p.y
		draw_circle(Vector2(px, py), Design.GOAL_POST_RADIUS, Design.WALL_COLOR)
		draw_circle(Vector2(px - 3, py - 3), Design.GOAL_POST_RADIUS * 0.55, Design.WALL_COLOR.lightened(0.25))
		draw_circle(Vector2(px + 3, py + 3), Design.GOAL_POST_RADIUS * 0.45, Color(0, 0, 0, 0.25))
		draw_arc(Vector2(px, py), Design.GOAL_POST_RADIUS, 0, TAU, 24, Color(1, 1, 1, 0.28), 2.0)
