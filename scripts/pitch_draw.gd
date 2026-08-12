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

	# --- 1. ground: grass, then a crowd stand down each touchline ---
	# board is centered: canvas spans (-off) .. (CANVAS-off) in board coords
	var off := (Design.CANVAS - p) / 2.0
	draw_rect(Rect2(-off.x, -off.y, Design.CANVAS.x, Design.CANVAS.y), Design.GRASS_BG)
	_draw_grass_ground(off, p)
	_draw_stands(p)

	# --- 2. felt: deep green + darker apron ring + grass texture ---
	# baked tileable grass-noise texture (seeded, zero assets) — same trick as
	# Claude's flick_soccer: one tile, tinted per stripe so the blade noise
	# reads instead of a dead-flat band.
	var apron := 34.0
	draw_rect(Rect2(-apron, -apron, p.x + apron * 2.0, p.y + apron * 2.0), Design.FELT_APRON)
	draw_rect(Rect2(0, 0, p.x, p.y), Design.PITCH_FELT)
	# Mow bands + vertical vignette, both measured off the reference: the turf
	# runs FELT_EDGE at the two ends and PITCH_FELT across the middle, with the
	# bands alternating by MOW_CONTRAST on top of that gradient.
	var tile := _get_grass_tile()
	var bands := 16
	var stripe_h := p.y / float(bands)
	for i in bands:
		var rect := Rect2(0, stripe_h * float(i), p.x, stripe_h + 1.0)
		# 0 at the ends, 1 at the halfway line
		var mid: float = 1.0 - absf((float(i) + 0.5) / float(bands) - 0.5) * 2.0
		var base: Color = Design.FELT_EDGE.lerp(Design.PITCH_FELT, smoothstep(0.0, 1.0, mid))
		if i % 2 == 1:
			base = base.darkened(Design.MOW_CONTRAST)
		draw_rect(rect, base)
		draw_texture_rect(tile, rect, true, Color(1, 1, 1, 0.5))

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

	# --- 6. walls: silver beveled rails ---
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

	# corner flags sit ON TOP of the rails — drawn before them, the rail's
	# corner circles painted straight over the bottom pair.
	_draw_corner_flags(p)

	# --- 7. goals: net structures outside the goal line ---
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

func _draw_grass_ground(off: Vector2, p: Vector2) -> void:
	## Subtle mottling on the surrounding grass so it does not read as flat
	## paint. Deterministic seed — the ground must not shimmer between frames.
	_rng.seed = 20260812
	var w := Design.CANVAS.x
	var h := Design.CANVAS.y
	for i in 900:
		var x := _rng.randf_range(-off.x, w - off.x)
		var y := _rng.randf_range(-off.y, h - off.y)
		# skip the pitch itself — it is drawn over this anyway
		if x > -60.0 and x < p.x + 60.0 and y > -60.0 and y < p.y + 60.0:
			continue
		var shade := Design.GRASS_BG.lightened(_rng.randf_range(0.0, 0.10)) \
				if _rng.randf() < 0.5 else Design.GRASS_BG.darkened(_rng.randf_range(0.0, 0.12))
		draw_rect(Rect2(x, y, _rng.randf_range(6.0, 22.0), _rng.randf_range(2.0, 5.0)), shade)

func _draw_stands(p: Vector2) -> void:
	## Crowd stands down both touchlines — the reference's most distinctive
	## framing element (the build previously drew a wood table instead).
	## Dark base + bright confetti speckle, which is what the sampled histogram
	## of the reference shows: mostly dark, spectators a colourful minority.
	var w := Design.STAND_WIDTH
	var gap := Design.STAND_GAP
	var over := 60.0                                   # run past both goal ends
	var top := -over
	var height := p.y + over * 2.0
	_rng.seed = 991137
	for side in 2:
		var x: float = -gap - w if side == 0 else p.x + gap
		var rect := Rect2(x, top, w, height)
		draw_rect(rect, Design.STAND_BASE)
		# tiered rows: alternating shade so the stand reads as banked seating
		var row_h := 26.0
		var rows := int(height / row_h)
		for r in rows:
			if r % 2 == 1:
				draw_rect(Rect2(x, top + float(r) * row_h, w, row_h * 0.5), Design.STAND_SHADE)
		# spectators
		var dots := int(height / 5.0)
		for i in dots:
			var cx := x + _rng.randf_range(3.0, w - 3.0)
			var cy := top + _rng.randf_range(2.0, height - 2.0)
			var col: Color = Design.STAND_CONFETTI[_rng.randi() % Design.STAND_CONFETTI.size()]
			draw_rect(Rect2(cx, cy, _rng.randf_range(3.0, 6.0), _rng.randf_range(3.0, 6.0)),
					Color(col, _rng.randf_range(0.55, 1.0)))
		# metal frame around the stand
		draw_rect(rect, Design.STAND_FRAME, false, 4.0)

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
	## White net structure standing OUTSIDE the goal line, as in the reference —
	## not a flat dark pocket. The physical pocket walls live in board.gd; this
	## is purely how it reads.
	var depth := Design.GOAL_DEPTH
	var post := Design.GOAL_POST_RADIUS
	var gx0 := cx - half - post
	var gx1 := cx + half + post
	var line_y := 0.0 if top else p.y
	var outer_y := line_y - depth if top else line_y + depth
	var shell := Rect2(gx0, minf(line_y, outer_y), gx1 - gx0, depth)

	# shaded interior so the mesh reads against the grass behind it
	draw_rect(shell, Design.GOAL_INTERIOR)

	# net mesh — denser than the old crosshatch, and light rather than dark
	var step := 11.0
	var x := shell.position.x + step
	while x < shell.end.x:
		draw_line(Vector2(x, shell.position.y), Vector2(x, shell.end.y), Design.GOAL_NET, 1.5)
		x += step
	var y := shell.position.y + step
	while y < shell.end.y:
		draw_line(Vector2(shell.position.x, y), Vector2(shell.end.x, y), Design.GOAL_NET, 1.5)
		y += step

	# frame: side stanchions + back bar, in white
	var fw := 6.0
	draw_rect(shell, Design.GOAL_FRAME, false, fw)
	draw_line(Vector2(gx0, line_y), Vector2(gx1, line_y), Design.GOAL_FRAME, fw + 2.0)

	# posts at the mouth corners
	for px in [cx - half, cx + half]:
		draw_circle(Vector2(px, line_y), post, Design.GOAL_FRAME)
		draw_circle(Vector2(px - 2, line_y - 2), post * 0.5, Color(1, 1, 1, 0.9))
		draw_arc(Vector2(px, line_y), post, 0, TAU, 24, Design.CAP_RIM_DARK, 1.5)

func _draw_corner_flags(p: Vector2) -> void:
	## Small pennants at the four corners — red at the top end, cyan at the
	## bottom, matching the reference.
	var h := Design.FLAG_HEIGHT
	var inset := Design.WALL_THICKNESS + 6.0
	for corner in [Vector2(inset, inset), Vector2(p.x - inset, inset),
			Vector2(inset, p.y - inset), Vector2(p.x - inset, p.y - inset)]:
		var is_top: bool = corner.y < p.y / 2.0
		var col: Color = Design.FLAG_TOP if is_top else Design.FLAG_BOTTOM
		var tip: Vector2 = corner + Vector2(0, -h)
		draw_line(corner, tip, Design.FLAG_POLE, 3.0)
		var dir := 1.0 if corner.x < p.x / 2.0 else -1.0
		draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(dir * 20.0, 7.0), tip + Vector2(0, 14.0)]), col)
