extends Node2D
## Shadow layer: soft dark ellipses under every cap and the ball.
## Drawn BELOW the pieces (added before them) in board space, so shadows
## stay fixed on the pitch while pieces move/rotate above them.

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var board := get_parent()
	if board == null:
		return
	for cap in board.caps:
		if cap != null and is_instance_valid(cap):
			_draw_shadow(cap.position, float(cap.get_meta("radius", Design.CAP_RADIUS)) * 0.95)
	if board.ball != null and is_instance_valid(board.ball):
		_draw_shadow(board.ball.position, Design.BALL_RADIUS * 0.9)

func _draw_shadow(pos: Vector2, radius: float) -> void:
	# soft multi-layer shadow, offset down-right (light from top-left)
	var offset := Vector2(6, 8)
	var layers := [0.10, 0.07, 0.04]
	for i in layers.size():
		draw_circle(pos + offset, radius * (0.75 + 0.22 * float(i)), Color(0, 0, 0, layers[i]))
