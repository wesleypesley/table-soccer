extends Node2D
## Cap disc: sphere-shaded token via a BAKED radial-gradient texture
## (dark rim, light from upper-left) + crisp white rim ring + specular.
## Texture is baked once per team color and cached — 10 caps cost 2 bakes.
## Pure _draw() output (no shader — robust on all renderers).

var base_color: Color = Design.CAP_BLUE
var inner_color: Color = Design.CAP_BLUE_INNER
var team_active := false          # true when this cap's team has the turn

static var _texture_cache: Dictionary = {}

func _process(_delta: float) -> void:
	if team_active:
		queue_redraw()   # only redraw every frame while the glow pulses

func _draw() -> void:
	# Per-cap radius: the goalkeeper is physically bigger, so its face must be
	# drawn bigger too. Falls back to the outfield token when unset.
	var r: float = get_parent().get_meta("radius", Design.CAP_RADIUS)
	if team_active:
		# Bright cyan halo ring around every cap of the side to move — the
		# reference's most legible "your turn" cue. Layered rings give a soft
		# falloff without a shader.
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
		for i in 4:
			var t := float(i) / 3.0
			var ring: Color = Design.TEAM_HALO
			ring.a = (0.42 - 0.09 * float(i)) * (0.75 + 0.25 * pulse)
			draw_arc(Vector2.ZERO, r + 5.0 + t * 11.0, 0, TAU, 48, ring,
					7.0 - t * 3.0)
	# metallic rim: dark seat under a bright ring, so the token reads as a
	# machined disc rather than a flat circle
	draw_circle(Vector2.ZERO, r, Design.CAP_RIM_DARK)
	draw_arc(Vector2.ZERO, r - 3.0, 0, TAU, 48, Design.CAP_RIM, 6.0)
	var tex: ImageTexture = _get_token_texture(base_color, inner_color)
	var face := r - 7.0
	draw_texture_rect(tex, Rect2(-face, -face, face * 2.0, face * 2.0), false)
	# club badge: a light disc with the team colour behind a simple emblem
	_draw_badge(face)
	# specular highlight (light from top-left)
	draw_circle(Vector2(-r * 0.34, -r * 0.34), r * 0.13, Color(1, 1, 1, 0.8))

func _draw_badge(face: float) -> void:
	## Stand-in for the club crest the reference caps carry. Not a real badge —
	## a legible emblem at cap size, built from primitives only.
	var br := face * 0.52
	draw_circle(Vector2.ZERO, br, Color(1, 1, 1, 0.92))
	draw_circle(Vector2.ZERO, br * 0.86, inner_color)
	# vertical bars, the way a striped kit reads at this size
	var bars := 4
	for i in bars:
		if i % 2 == 1:
			continue
		var w := br * 0.34
		var x := -br * 0.7 + float(i) * (br * 1.4 / float(bars))
		draw_rect(Rect2(x, -br * 0.62, w, br * 1.24), base_color.darkened(0.25))
	draw_arc(Vector2.ZERO, br * 0.86, 0, TAU, 32, Color(1, 1, 1, 0.75), 2.0)

## Bakes a radially-shaded disc into an Image once per (base,inner) pair and
## caches it. Light from the upper-left; darker rim; lighter concentric inner
## core — same idea as the earlier shader writeup, but done as a baked
## ImageTexture so it works with vector _draw() output directly.
static func _get_token_texture(base_color: Color, inner_color: Color) -> ImageTexture:
	var key := base_color.to_html() + "|" + inner_color.to_html()
	if _texture_cache.has(key):
		return _texture_cache[key]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 4.0
	var light_dir := Vector2(-0.55, -0.65).normalized()
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var d := center.distance_to(p)
			if d > radius:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var n := (p - center) / radius
			var ndotl: float = clamp(-n.dot(light_dir) + 0.55, 0.0, 1.0)
			var shade: float = lerp(0.55, 1.25, ndotl)
			var c: Color = base_color * shade
			# lighter inner core (Plato two-tone)
			var core: float = smoothstep(radius * 0.55, 0.0, d)
			c = c.lerp(inner_color * shade, core * 0.7)
			c.a = 1.0
			# darker rim
			var edge: float = smoothstep(radius * 0.75, radius, d)
			c = c.lerp(Color(0, 0, 0, 1), edge * 0.45)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex
