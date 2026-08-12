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
		# soft breathing team-glow under the token (matches Plato's active-team
		# highlight; selected cap gets the brighter gold ring on top)
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
		var glow: Color = base_color
		glow.a = 0.16 + 0.14 * pulse
		draw_circle(Vector2.ZERO, r * (1.25 + 0.08 * pulse), glow)
	var tex: ImageTexture = _get_token_texture(base_color, inner_color)
	draw_texture_rect(tex, Rect2(-r, -r, r * 2.0, r * 2.0), false)
	# crisp white rim ring (Plato signature)
	draw_arc(Vector2.ZERO, r - 2.0, 0, TAU, 48, Color(1, 1, 1, 0.85), 4.0)
	# specular highlight (light from top-left)
	draw_circle(Vector2(-r * 0.34, -r * 0.34), r * 0.15, Color(1, 1, 1, 0.85))

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
