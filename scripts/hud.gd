extends CanvasLayer
## HUD — Plato top bar: team avatar discs, score "0 - 0", goals-to-win,
## turn indicator, depleting turn timer bar. All token-driven.

var board: Node2D
var turn_manager: Node

var _score_label: Label
var _goals_label: Label
var _turn_label: Label
var _timer_bar: ProgressBar
var _avatar_p0: Control
var _avatar_p1: Control

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # don't steal game input
	add_child(root)

	# --- top bar panel ---
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 150.0
	var style := StyleBoxFlat.new()
	style.bg_color = Design.HUD_BG
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	# --- score (center, big) ---
	_score_label = Label.new()
	_score_label.text = "0 - 0"
	_score_label.add_theme_font_size_override("font_size", 44)
	_score_label.add_theme_color_override("font_color", Design.HUD_TEXT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_score_label.offset_top = 30.0
	_score_label.offset_bottom = 90.0
	root.add_child(_score_label)

	# --- goals-to-win (below score, dim) ---
	_goals_label = Label.new()
	_goals_label.text = "Goals to win: %d" % turn_manager.WIN_GOALS
	_goals_label.add_theme_font_size_override("font_size", 16)
	_goals_label.add_theme_color_override("font_color", Design.HUD_DIM)
	_goals_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goals_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_goals_label.offset_top = 92.0
	_goals_label.offset_bottom = 116.0
	root.add_child(_goals_label)

	# --- avatar discs (blue P0 left, red P1 right) ---
	_avatar_p0 = _make_avatar(Design.CAP_BLUE, 62.0)
	_avatar_p0.position = Vector2(44.0, 32.0)
	root.add_child(_avatar_p0)
	_avatar_p1 = _make_avatar(Design.CAP_RED, 62.0)
	_avatar_p1.position = Vector2(1080.0 - 44.0 - 62.0, 32.0)
	root.add_child(_avatar_p1)

	# --- turn label (under the active avatar side) ---
	_turn_label = Label.new()
	_turn_label.text = "P0's turn"
	_turn_label.add_theme_font_size_override("font_size", 15)
	_turn_label.add_theme_color_override("font_color", Design.HUD_DIM)
	_turn_label.position = Vector2(44.0, 104.0)
	root.add_child(_turn_label)

	# --- turn timer bar (full width, thin, red fill) ---
	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = 100.0
	_timer_bar.show_percentage = false
	_timer_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer_bar.offset_top = 146.0
	_timer_bar.offset_bottom = 150.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Design.HUD_TIMER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	_timer_bar.add_theme_stylebox_override("fill", fill)
	_timer_bar.add_theme_stylebox_override("background", bg)
	root.add_child(_timer_bar)

	turn_manager.turn_changed.connect(_on_turn_changed)
	_on_turn_changed(turn_manager.active_player)

func _make_avatar(color: Color, size: float) -> Control:
	# circular avatar disc + inner core + ring (procedural, token colors)
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	var draw := Node2D.new()
	draw.set_script(load("res://scripts/avatar_draw.gd"))
	draw.set("fill_color", color)
	c.add_child(draw)
	return c

func _process(_delta: float) -> void:
	var tm := turn_manager
	_score_label.text = "%d - %d" % [tm.score[0], tm.score[1]]
	# timer bar depletes during a turn
	var frac := clampf(tm.turn_timer / tm.TURN_SECONDS, 0.0, 1.0)
	_timer_bar.value = frac * 100.0

func _on_turn_changed(player: int) -> void:
	var tm := turn_manager
	var name_p := "P0" if player == 0 else "P1"
	var other := "P1" if player == 0 else "P0"
	_turn_label.text = "%s's turn" % name_p
	_turn_label.position.x = 44.0 if player == 0 else 1080.0 - 44.0 - _turn_label.size.x - 20.0
	# ring the active avatar
	_set_avatar_ring(_avatar_p0, player == 0)
	_set_avatar_ring(_avatar_p1, player == 1)

func _set_avatar_ring(avatar: Control, active: bool) -> void:
	for child in avatar.get_children():
		child.set("ring_active", active)
