extends CanvasLayer
## Minimal HUD: score, active player, turn timer, passes left. Placeholder styling.

var score_label: Label
var timer_label: Label
var board: Node2D
var turn_manager: Node

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # don't steal game input
	add_child(root)

	score_label = Label.new()
	score_label.position = Vector2(20, 20)
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.text = "0 - 0"
	root.add_child(score_label)

	timer_label = Label.new()
	timer_label.position = Vector2(20, 70)
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.text = "P0 15.0s"
	root.add_child(timer_label)

	turn_manager.turn_changed.connect(_on_turn_changed)

func _process(_delta: float) -> void:
	score_label.text = "%d - %d" % [turn_manager.score[0], turn_manager.score[1]]
	var tm := turn_manager
	if tm.state == tm.State.FLIGHT:
		timer_label.text = "ball in flight…"
	elif tm.state == tm.State.MATCH_OVER:
		timer_label.text = "match over"
	else:
		var passes := "∞" if tm.pass_limit >= tm.INF_PASSES else str(tm.passes_left)
		timer_label.text = "P%d %.1fs  passes:%s" % [tm.active_player, maxf(tm.turn_timer, 0.0), passes]

func _on_turn_changed(player: int) -> void:
	var tm := turn_manager
	var passes := "∞" if tm.pass_limit >= tm.INF_PASSES else str(tm.passes_left)
	timer_label.text = "P%d 15.0s  passes:%s" % [player, passes]
