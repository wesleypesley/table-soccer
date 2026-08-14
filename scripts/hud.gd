extends CanvasLayer
## HUD — laid out against the Plato reference screenshot:
##
##   [ slim turn-timer bar, centred, clock dot at its left ]
##   (back)  name • avatar        0 - 0        avatar  [Your Turn]  (menu)
##                            Goals to win: 3
##
## The active player is marked twice, as in the reference: a bright ring on
## their avatar AND a blue pill where the opponent's name would sit. All
## token-driven; nothing here touches gameplay.

var board: Node2D
var turn_manager: Node

const BAR_H := 168.0
const AVATAR := 62.0
const EDGE := 26.0

var _score_label: Label
var _goals_label: Label
var _timer_bar: ProgressBar
var _avatar_p0: Control
var _avatar_p1: Control
var _name_p0: Label
var _name_p1: Label
var _pill: Panel
var _pill_label: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # don't steal game input
	add_child(root)

	# --- top bar panel ---
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = BAR_H
	var style := StyleBoxFlat.new()
	style.bg_color = Design.HUD_BG
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	# --- turn timer: short, centred, at the very top (reference puts it above
	#     the name row rather than under it) ---
	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = 100.0
	_timer_bar.show_percentage = false
	_timer_bar.position = Vector2(Design.CANVAS.x / 2.0 - 60.0, 16.0)
	_timer_bar.size = Vector2(120.0, 10.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Design.HUD_TIMER
	fill.corner_radius_top_left = 5
	fill.corner_radius_bottom_left = 5
	fill.corner_radius_top_right = 5
	fill.corner_radius_bottom_right = 5
	var track := StyleBoxFlat.new()
	track.bg_color = Design.HUD_TIMER_TRACK
	track.corner_radius_top_left = 5
	track.corner_radius_bottom_left = 5
	track.corner_radius_top_right = 5
	track.corner_radius_bottom_right = 5
	_timer_bar.add_theme_stylebox_override("fill", fill)
	_timer_bar.add_theme_stylebox_override("background", track)
	root.add_child(_timer_bar)
	var clock := Node2D.new()
	clock.set_script(load("res://scripts/clock_icon.gd"))
	clock.position = Vector2(Design.CANVAS.x / 2.0 - 82.0, 21.0)
	root.add_child(clock)

	# --- round chips: back (left) and menu (right) ---
	root.add_child(_chip("←", Vector2(EDGE, 52.0), 30.0))
	root.add_child(_chip("⋮", Vector2(Design.CANVAS.x - EDGE - 60.0, 52.0), 30.0))

	# --- score (centre, big) ---
	_score_label = Label.new()
	_score_label.text = "0 - 0"
	_score_label.add_theme_font_size_override("font_size", 46)
	_score_label.add_theme_color_override("font_color", Design.HUD_TEXT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_score_label.offset_top = 48.0
	_score_label.offset_bottom = 108.0
	root.add_child(_score_label)

	# --- goals-to-win, under the score ---
	_goals_label = Label.new()
	_goals_label.text = "Goals to win: %d" % turn_manager.WIN_GOALS
	_goals_label.add_theme_font_size_override("font_size", 18)
	_goals_label.add_theme_color_override("font_color", Design.HUD_DIM)
	_goals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goals_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_goals_label.offset_top = 110.0
	_goals_label.offset_bottom = 136.0
	root.add_child(_goals_label)

	# --- players: name + avatar inboard of each chip ---
	_name_p0 = _name_label(Design.PLAYER_NAMES[0], HORIZONTAL_ALIGNMENT_RIGHT)
	_name_p0.position = Vector2(96.0, 66.0)
	_name_p0.size = Vector2(160.0, 30.0)
	root.add_child(_name_p0)
	_avatar_p0 = _make_avatar(Design.CAP_BLUE)
	_avatar_p0.position = Vector2(266.0, 50.0)
	root.add_child(_avatar_p0)

	_avatar_p1 = _make_avatar(Design.CAP_RED)
	_avatar_p1.position = Vector2(Design.CANVAS.x - 266.0 - AVATAR, 50.0)
	root.add_child(_avatar_p1)
	_name_p1 = _name_label(Design.PLAYER_NAMES[1], HORIZONTAL_ALIGNMENT_LEFT)
	_name_p1.position = Vector2(Design.CANVAS.x - 256.0, 66.0)
	_name_p1.size = Vector2(160.0, 30.0)
	root.add_child(_name_p1)

	# --- "Your Turn" pill, parked beside whichever side is active ---
	_pill = Panel.new()
	_pill.size = Vector2(150.0, 44.0)
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Design.HUD_PILL
	pill_style.corner_radius_top_left = 22
	pill_style.corner_radius_bottom_left = 22
	pill_style.corner_radius_top_right = 22
	pill_style.corner_radius_bottom_right = 22
	_pill.add_theme_stylebox_override("panel", pill_style)
	root.add_child(_pill)
	_pill_label = Label.new()
	_pill_label.text = "Your Turn"
	_pill_label.add_theme_font_size_override("font_size", 20)
	_pill_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill_label.size = _pill.size
	_pill.add_child(_pill_label)

	turn_manager.turn_changed.connect(_on_turn_changed)
	_on_turn_changed(turn_manager.active_player)

# --- builders ----------------------------------------------------------------

func _chip(glyph: String, pos: Vector2, size: float) -> Control:
	## Round dark chip with a glyph — the reference's back arrow / kebab menu.
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(size * 2.0, size * 2.0)
	var st := StyleBoxFlat.new()
	st.bg_color = Design.HUD_CHIP
	st.corner_radius_top_left = int(size)
	st.corner_radius_bottom_left = int(size)
	st.corner_radius_top_right = int(size)
	st.corner_radius_bottom_right = int(size)
	panel.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = glyph
	l.add_theme_font_size_override("font_size", int(size * 1.1))
	l.add_theme_color_override("font_color", Design.HUD_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = panel.size
	panel.add_child(l)
	return panel

func _name_label(text: String, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Design.HUD_TEXT)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _make_avatar(color: Color) -> Control:
	# circular avatar disc + inner core + ring (procedural, token colors)
	var c := Control.new()
	c.custom_minimum_size = Vector2(AVATAR, AVATAR)
	c.size = Vector2(AVATAR, AVATAR)
	var draw := Node2D.new()
	draw.set_script(load("res://scripts/avatar_draw.gd"))
	draw.set("fill_color", color)
	draw.position = Vector2(AVATAR / 2.0, AVATAR / 2.0)
	c.add_child(draw)
	return c

# --- per-frame ---------------------------------------------------------------

func _process(_delta: float) -> void:
	var tm := turn_manager
	_score_label.text = "%d - %d" % [tm.score[0], tm.score[1]]
	var frac := clampf(tm.turn_timer / tm.TURN_SECONDS, 0.0, 1.0)
	_timer_bar.value = frac * 100.0

func _on_turn_changed(player: int) -> void:
	# Pill sits on the ACTIVE player's side; that player's avatar also rings.
	_pill.position = Vector2(Design.CANVAS.x - 250.0, 104.0) if player == 1 \
			else Vector2(100.0, 104.0)
	_set_avatar_ring(_avatar_p0, player == 0)
	_set_avatar_ring(_avatar_p1, player == 1)

func _set_avatar_ring(avatar: Control, active: bool) -> void:
	for child in avatar.get_children():
		child.set("ring_active", active)
