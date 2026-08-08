extends Node2D
## Cap selection ring: neon gold glow when selected, with a soft pulse
## animation. Sits above the disc (z_index) so the ring always reads.
## Node is named "Draw" — turn_manager toggles `selected` on it.

var selected := false

var _pulse := 0.0
var _tween: Tween

func _ready() -> void:
	# gentle breathing pulse while selected
	_tween = create_tween().set_loops()
	_tween.tween_method(_set_pulse, 0.0, 1.0, 0.8)
	_tween.tween_method(_set_pulse, 1.0, 0.0, 0.8)

func _set_pulse(v: float) -> void:
	_pulse = v
	queue_redraw()

func _draw() -> void:
	if not selected:
		return
	var r := Design.CAP_RADIUS
	var glow := 0.12 + _pulse * 0.14          # breathing alpha
	var ext := 12.0 + _pulse * 6.0            # breathing radius
	# soft outer glow + bright core (layered arcs)
	draw_arc(Vector2.ZERO, r + ext, 0, TAU, 48, Color(Design.SELECT_RING, glow), 14.0)
	draw_arc(Vector2.ZERO, r + 6.0, 0, TAU, 48, Color(Design.SELECT_RING, 0.35), 8.0)
	draw_arc(Vector2.ZERO, r + 2.0, 0, TAU, 48, Design.SELECT_RING, 4.0)
