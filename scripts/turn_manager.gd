extends Node
## Turn FSM — Plato Table Soccer pass-chain model.
## Ball is HELD (stuck to a player) or IN_FLIGHT (pass/shot). No free-roll settle.
## Turn = drag/position caps → pass ×N (limit 3/5/∞) → shot.
## Own cap captures ball → turn continues (pass used). Opponent cap → possession lost.

enum State { TURN_START, MOVING, FLIGHT, MATCH_OVER }

const TURN_SECONDS := 15.0
const MAX_TIMEOUTS := 3
const WIN_GOALS := 3                # reference screenshot: "Goals to win: 3"
const INF_PASSES := 999

const BALL_SPEED_SCALE := 2.0
const BALL_SPEED_MIN := 300.0
const BALL_SPEED_MAX := 1400.0
# Geometry is NOT redefined here — Design is the single source of truth.
const CAP_RADIUS := Design.CAP_RADIUS
const BALL_RADIUS := Design.BALL_RADIUS
const CAPTURE_DIST := Design.CAPTURE_DIST            # 66 px — ball sticks on contact
const STOP_THRESHOLD := 8.0                          # px/s — ball stopped = lost ball
const MAX_PASS_DIST := 500.0
const MAX_PULL := 150.0                           # max slingshot pull-back (px)
const MOMENTUM_CARRY := 0.15                      # receiver shove on capture — momentum conservation as impulse (see _attach_ball)

# --- tuning margins ----------------------------------------------------------
# Previously bare literals repeated at the call sites. Values are unchanged;
# only the names are new, so behaviour is identical.
const ATTACH_SLOP := 12.0      # attach-placement sanity: arrival vector must be near contact
const LAUNCH_SPAWN_GAP := 6.0      # ball spawns this far past contact so the puck kicks it
const TAP_TOLERANCE := 6.0         # finger slop when tapping a cap to select it
const CONTACT_SLOP := 6.0          # cap-to-cap touch test for the release rule
const ATTACH_MIN_REL := 30.0       # shorter arrival vectors are too degenerate to aim with
const ATTACH_FALLBACK_OFFSET := 34.0  # stick offset used when the arrival vector is unusable

# --- tether spring -----------------------------------------------------------
# Custom spring (community-validated over DampedSpringJoint2D — see skill
# references/godot-joint2d-pitfalls.md): F = k·(rest−dist) − c·rel_v applied
# as forces on both bodies. The engine integrates it; tangential velocity is
# untouched (force is purely radial) so the orbit emerges from physics.
const TETHER_STIFFNESS := 200.0     # spring constant k — ball tracks a gliding cap, no whip
const TETHER_DAMPING := 18.0        # damping c ≈ 2·√(k·m_ball) — near-critical, few bounces

# --- holder facing (Plato) ---------------------------------------------------
# When a cap catches the ball it SWINGS AROUND THE BALL to sit behind it,
# facing the goal it attacks (ball between cap and goal, badge toward the
# goal). The cap's centre orbits the ball — no self-spin — driven by a
# velocity write toward the target point on the orbit circle, so caps in the
# arc get shoved and a wall really stops it (nothing phases). The swing only
# starts once the cap has ridden out any shove (speed gate), and a mid-swing
# shove freezes it until the cap settles again. Player input stays locked
# until the swing completes or gives up.
const FACING_STOP_SPEED := 15.0     # px/s — below this the cap is "stopped", the swing may start
const FACING_RIDEOUT_TIMEOUT := 1.0 # s coasting after a shove — the shove is spent, swing may start
const FACING_ORBIT_SPEED := 220.0   # px/s — max swing speed (~0.3s to cross 66px)
const FACING_ORBIT_GAIN := 3.0      # swing speed = gap to target × gain (clamped)
const FACING_TOLERANCE_PX := 3.0    # px — within this of the target = facing complete
const FACING_BADGE_RATE := 5.0      # rad/s — badge turn speed (smooth, no snap at swing start)
const FACING_STALL_TIME := 0.25     # s of blocked swing — then wall contact gives up
const FACING_GIVE_UP_TIME := 2.0    # s of blocked swing — give up regardless (no soft-lock)
const FACING_SETTLE_TIMEOUT := 3.0  # s in settling — force-release if the pair can't stop

var board: Node2D
var state: int = State.TURN_START
var active_player: int = 0                            # 0 = bottom (blue), 1 = top (red)
var score := [0, 0]
var turn_timer: float = TURN_SECONDS
var consecutive_timeouts := [0, 0]
var pass_limit: int = 3                               # match setting: 3 / 5 / INF_PASSES
var passes_left: int = 3

var holder: RigidBody2D = null                        # cap the ball is stuck to
var _selected_cap: RigidBody2D = null                 # currently selected (highlight)
var _cap_base_pos := Vector2.ZERO                     # cap pos when pull started
var _launcher: RigidBody2D = null                     # cap launched this action
var _ball_in_flight := false                          # true when ball was launched
var _pulling := false
var _aim_start := Vector2.ZERO
var _aim_current := Vector2.ZERO
var _preview: Line2D
var _flight_time := 0.0                 # seconds since launch
const MIN_FLIGHT_TIME := 0.3            # ball can't die before the puck makes contact
var _facing := false                    # holder is swinging behind the ball; input locked
var _facing_swinging := false           # the swing is active (started)
var _facing_stall := 0.0                # seconds of zero swing progress while facing
var _facing_last_target := -1.0         # last distance to the swing target (-1 = unset)
var _facing_badge_rot := 0.0            # badge rotation, moved at FACING_BADGE_RATE
var _facing_settling := false           # swing done — waiting for cap+ball to stop, then release
var _facing_settle_time := 0.0          # seconds spent in settling (timeout guard)
var _facing_rideout_time := 0.0         # seconds the holder has coasted after a shove
var release_enabled := true             # harness hook: tether cases isolate the held phase

signal turn_changed(player: int)
signal match_over(winner: int)

func _ready() -> void:
	_preview = Line2D.new()
	_preview.width = 6.0
	_preview.default_color = Color(Design.SELECT_RING, 0.7)
	_preview.visible = false
	board.add_child(_preview)
	board.ball.body_entered.connect(_on_ball_body_entered)
	_start_match()

func _start_match() -> void:
	active_player = randi() % 2                        # random kickoff
	score = [0, 0]
	consecutive_timeouts = [0, 0]
	passes_left = pass_limit
	_setup_turn(true)
	print("[Match] start — P%d kicks off (pass limit %d)" % [active_player, pass_limit])

func _setup_turn(is_kickoff: bool = false) -> void:
	state = State.TURN_START
	turn_timer = TURN_SECONDS
	passes_left = pass_limit
	_launcher = null
	_ball_in_flight = false
	_facing = false
	_facing_swinging = false
	_facing_settling = false
	_facing_settle_time = 0.0
	_facing_rideout_time = 0.0
	if _selected_cap != null and is_instance_valid(_selected_cap):
		_selected_cap.get_node("Draw").set("selected", false)
	_selected_cap = null
	if is_kickoff:
		# kickoff / after-goal: BOTH teams return to their formation and the ball
		# goes back to the centre spot, FREE. The kicking player picks it up by
		# dragging a cap onto it (pickup mechanic).
		_untether()
		board.reset_formation()
		board.reset_ball(Vector2(board.PITCH.x / 2.0, board.PITCH.y / 2.0))
		holder = null
		board.ball.collision_layer = 1
		board.ball.collision_mask = 1
	else:
		# possession change: ball stays where it stopped, free on the pitch
		_untether()
		holder = null
		board.ball.collision_layer = 1
		board.ball.collision_mask = 1
	turn_changed.emit(active_player)
	_update_team_glow()
	print("[Turn] P%d — ball %s" % [active_player, "with cap %d, %d passes" % [board.caps.find(holder), passes_left] if holder else "free on pitch, %d passes" % passes_left])

func _update_team_glow() -> void:
	# whole active team breathes softly (Plato "your turn" readability);
	# the selected cap additionally gets the gold ring via its Draw node.
	for i in board.caps.size():
		var disc = board.caps[i].get_node_or_null("Disc")
		if disc != null:
			disc.set("team_active", _team_of(i) == active_player)

# --- ball attach / launch ---------------------------------------------------

var _hold_offset := Vector2(0, -34)             # ball's rest position relative to holder

func _attach_ball(cap: RigidBody2D, incoming_vel: Vector2 = Vector2.ZERO) -> void:
	holder = cap
	_ball_in_flight = false              # capture ENDS flight — tether engages
	_launcher = null                     # striker no longer excluded
	# Option A: the ball stays a REAL body while held — it collides with other
	# caps and walls, so any hit swings it around the tether. It only never
	# collides with its own holder (collision exception = the tether).
	board.ball.collision_layer = 1
	board.ball.collision_mask = 1
	board.ball.add_collision_exception_with(cap)
	board.ball.linear_velocity = Vector2.ZERO
	board.ball.angular_velocity = 0.0
	# Graceful stick: ball settles AT the cap's edge (contact distance), on the
	# side it arrived from — no floating gap, no teleport through the cap.
	var rel: Vector2 = board.ball.position - cap.position
	var contact := _contact_dist(cap)
	if rel.length() < ATTACH_MIN_REL or rel.length() > contact + ATTACH_SLOP:
		rel = Vector2(0, -ATTACH_FALLBACK_OFFSET) if active_player == 0 \
				else Vector2(0, ATTACH_FALLBACK_OFFSET)
	_hold_offset = rel.normalized() * contact
	board.ball.position = cap.position + _hold_offset
	# Momentum carry as a REAL impulse (2026-08-11, revised): the ball's
	# momentum has to go somewhere when it sticks — transferring it to the
	# receiver is momentum conservation, applied as an engine-integrated
	# impulse (mass-scaled), NOT the old velocity write. It also opens the
	# gap between the receiver and the still-sliding striker, protecting the
	# catch (pass settle 65.96→56.62 without it). The 0.15 coefficient is
	# feel-tuned above the pure inelastic share (0.032 at 30:1 mass) — the
	# comment in the old code already documented why pure mass ratio is
	# invisible; the impulse form keeps it physical (engine-integrated).
	if incoming_vel.length() > 40.0:
		cap.apply_central_impulse(incoming_vel * MOMENTUM_CARRY * cap.mass)
	# Plato facing: the new holder swings around the ball to sit behind it,
	# facing the goal it attacks (once it has ridden out any shove — see
	# _update_facing). Input stays locked until the swing completes or gives
	# up (wall / stall).
	_facing = true
	_facing_swinging = false
	_facing_stall = 0.0
	_facing_last_target = -1.0
	_facing_settling = false
	_facing_settle_time = 0.0
	_facing_rideout_time = 0.0
	_facing_badge_rot = cap.rotation

func _untether() -> void:
	## Drop the collision exception between ball and holder.
	if holder != null and is_instance_valid(holder):
		board.ball.remove_collision_exception_with(holder)

func _launch_cap(cap: RigidBody2D, pull: Vector2, speed: float) -> void:
	## Slingshot a NON-holder puck (reposition / collect the free ball).
	## Ball isn't launched — it may be collected on contact with this puck.
	_launcher = cap
	_ball_in_flight = false
	var d := pull.normalized()
	cap.apply_central_impulse(d * speed * cap.mass)
	state = State.FLIGHT
	_flight_time = 0.0
	print("[Turn] P%d slingshots cap %d (no ball) dir=%s speed=%.0f" % [active_player, board.caps.find(cap), d, speed])

func _launch_puck(dir: Vector2, speed: float) -> void:
	## HARNESS-ONLY (wall_max / wall_double / pass_chain): direct ball launch
	## for physics-isolation tests. Live play never calls this — after a
	## catch the ball RELEASES (Plato ownership) and every pull slings the
	## cap at the FREE ball via _launch_cap, which physically strikes it.
	## Slingshot the HOLDER PUCK: impulse to the puck, which physically kicks
	## the ball (ball is freed from the holder, placed just ahead of it).
	var ball: RigidBody2D = board.ball
	var d := dir.normalized()
	_launcher = holder
	_ball_in_flight = true
	_untether()                      # ball leaves the holder — drop the exception
	# free the ball and place it at the puck's striking edge — in FRONT of the
	# puck along the launch direction, with a small gap so the puck's motion
	# closes it and kicks the ball (exact-contact spawn makes the solver jitter)
	ball.collision_layer = 1
	ball.collision_mask = 1
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	# body_set_state: a raw position write silently reverts on an AWAKE ball —
	# and the holder's swing leaves the ball moving at launch, so the pass
	# used to spawn the ball nowhere and the puck slid past it.
	PhysicsServer2D.body_set_state(ball.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, board.to_global(
					holder.position + d * (_contact_dist(holder) + LAUNCH_SPAWN_GAP))))
	# impulse to the PUCK (impulse = desired velocity × mass). The puck slides
	# forward, collides with the ball, and the ball flies — like real table soccer.
	holder.apply_central_impulse(d * speed * holder.mass)
	_facing = false               # holder shot — the swing is over
	_facing_swinging = false
	_facing_settling = false
	_facing_settle_time = 0.0
	state = State.FLIGHT
	_flight_time = 0.0
	print("[Turn] P%d slingshots cap %d dir=%s speed=%.0f" % [active_player, board.caps.find(holder), d, speed])

# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MATCH_OVER or state == State.FLIGHT:
		return
	# convert to board-local coords (board is centered in the canvas)
	var pos := board.to_local(event.position)
	if event is InputEventMouseButton:
		_handle_press(pos, event.pressed)
	elif event is InputEventMouseMotion and _pulling:
		_aim_current = pos
		_update_preview()
	elif event is InputEventScreenTouch:
		_handle_press(pos, event.pressed)
	elif event is InputEventScreenDrag and _pulling:
		_aim_current = pos
		_update_preview()

func _handle_press(pos: Vector2, pressed: bool) -> void:
	if _facing:
		return                       # controls locked until the holder faces the goal
	if pressed:
		var cap := _cap_at(pos)
		if cap != null:
			# SELECT: highlight the puck. Selection is free — switch as much
			# as you want; only a pull+release commits.
			_set_selected(cap)
			state = State.TURN_START
			_cap_base_pos = cap.position
			_pulling = true
			_aim_start = pos
			_aim_current = pos
			print("[Turn] P%d selects cap %d" % [active_player, board.caps.find(cap)])
		else:
			_set_selected(null)     # tap empty space = deselect
	else:
		if _pulling and _selected_cap != null:
			_pulling = false
			var pull := _aim_start - _aim_current      # pull-back vector
			_preview.visible = false
			if pull.length() < 20.0:
				# tap, not a pull — stay selected, nothing committed
				_selected_cap.position = _cap_base_pos
				return
			_fire_pull(pull)
			_set_selected(null)          # shot fired — clear highlight
		else:
			_pulling = false

func _fire_pull(pull: Vector2) -> void:
	## Slingshot the SELECTED puck. If it holds the ball → pass or shot.
	## Otherwise the puck slides; if it strikes the free ball the ball is
	## knocked into flight (physics) — it never sticks to the striker.
	if _facing:
		return                       # controls locked until the holder faces the goal
	var cap := _selected_cap
	if cap == null:
		return
	# The player committed an action, so their timeout streak is broken.
	# SRS 02 §4.F counts CONSECUTIVE timeouts; without this reset the counter
	# only ever grows and timeouts spread across a whole match force a forfeit.
	consecutive_timeouts[active_player] = 0
	# NO holder-launch branch: after a catch the ball is RELEASED once the
	# cap and ball settle (_release_held_ball), so every pull slings the cap
	# at a FREE ball — it can only be struck physically, never spawned on
	# the aim line (the backward-kick teleport is structurally impossible).
	_launch_cap(cap, pull, _pull_speed(pull))

func _pull_speed(pull: Vector2) -> float:
	## Linear power curve: full 150px pull = max speed, small pull = gentle slide.
	var t := clampf(pull.length() / MAX_PULL, 0.0, 1.0)
	return lerpf(BALL_SPEED_MIN, BALL_SPEED_MAX, t)

func _set_selected(cap: RigidBody2D) -> void:
	if _selected_cap != null and is_instance_valid(_selected_cap):
		_selected_cap.get_node("Draw").set("selected", false)
	_selected_cap = cap
	if cap != null:
		cap.get_node("Draw").set("selected", true)

# --- turn logic -------------------------------------------------------------

func _process(delta: float) -> void:
	# Plato-style aim: the selected puck does NOT move — only the arrow shows
	# direction/power while pulling. The puck launches from its current spot.
	if _pulling and _selected_cap != null:
		_aim_current = board.to_local(get_viewport().get_mouse_position())
		_update_preview()

	if state == State.TURN_START or state == State.MOVING:
		# the forfeit clock doesn't run while the holder is turning to face
		# the goal — the player can't act during the turn
		if not _facing and get_window().has_focus():   # pause timer while window unfocused
			turn_timer -= delta
			if turn_timer <= 0.0:
				_handle_timeout()


func _update_preview() -> void:
	_preview.visible = true
	_preview.clear_points()
	var cap := _selected_cap
	if cap == null:
		return
	# slingshot: pull-back vector reversed = launch direction (from the puck)
	var dir := _aim_start - _aim_current
	if dir.length() < 20.0:
		return
	# The arrow shows the real launch: pull direction, length = power.
	# No pass indicator, no colour switching — plain white, always.
	_preview.default_color = Color(1, 1, 1, 0.6)
	var speed := _pull_speed(dir)
	_preview.add_point(cap.position)
	_preview.add_point(cap.position + dir.normalized() * (speed * 0.25))

# --- flight / capture -------------------------------------------------------

func _physics_process(delta: float) -> void:
	var ball: RigidBody2D = board.ball
	# No wall-tunnel clamp: the ball runs CCD (continuous_cd = CAST_SHAPE,
	# board.gd) — the ENGINE prevents tunneling at any speed, verified by the
	# wall_max / wall_double harness cases (removed MAX_BALL_SPEED 2026-08-11).
	# TETHER: the held ball is a REAL body that orbits the cap. A custom
	# spring force (F = k·(rest−dist) − c·rel_v along the holder→ball axis)
	# is applied to BOTH bodies every physics frame — the engine integrates
	# it, no position writes, no per-frame projection. The force is purely
	# radial, so tangential velocity is preserved = the orbit emerges. The
	# damping term absorbs shove energy, so a hard ram settles after a few
	# swings instead of rattling. No speed clamp: the damper (c·rel_v) bounds
	# the held ball's speed naturally — at 1500 px/s relative it applies
	# ~54,000 px/s² deceleration (removed HELD_BALL_SPEED 2026-08-11, verified
	# by the ram test).
	if holder != null and not _ball_in_flight:
		var rel: Vector2 = ball.position - holder.position
		var dist := rel.length()
		if dist > 0.01:
			var axis := rel / dist
			var rel_v: Vector2 = ball.linear_velocity - holder.linear_velocity
			var spring_f := TETHER_STIFFNESS * (_contact_dist(holder) - dist)
			var damp_f := TETHER_DAMPING * rel_v.dot(axis)
			var force := axis * (spring_f - damp_f)
			ball.apply_central_force(force)
			holder.apply_central_force(-force)
		ball.angular_velocity = 0.0
		_update_facing(holder, delta)
		# Plato ownership release: once the swing is done (or gave up) and
		# BOTH the cap and the ball have stopped, the tether drops — the
		# ball is FREE on the pitch until any cap physically strikes it
		# again. Input stays locked until release (_facing stays true while
		# settling). Server velocity via body_get_state — the node property
		# lags a frame behind an externally applied impulse.
		if _facing_settling:
			_facing_settle_time += delta
			var cap_v: Vector2 = PhysicsServer2D.body_get_state(holder.get_rid(),
					PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			var ball_v: Vector2 = PhysicsServer2D.body_get_state(ball.get_rid(),
					PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if release_enabled and (_facing_settle_time > FACING_SETTLE_TIMEOUT \
					or (cap_v.length() < STOP_THRESHOLD and ball_v.length() < STOP_THRESHOLD)):
				_release_held_ball()
				return
		# Release rule: an opponent cap touching the HOLDER (or the ball — see
		# _on_ball_body_entered) breaks the tether: possession is lost. While
		# the holder is turning to face the goal it SHOVES caps it touches —
		# that's the holder's own move, so it can't cost possession.
		for i in board.caps.size():
			var cap: RigidBody2D = board.caps[i]
			if cap == holder:
				continue
			var team := _team_of(i)
			if not _facing and team != active_player \
					and cap.position.distance_to(holder.position) \
						< board.cap_radius(cap) + board.cap_radius(holder) + CONTACT_SLOP:
				_lose_possession()
				break
	if state != State.FLIGHT:
		# Goal check outside flight too: with full-restitution caps, a cap
		# from a resolved sling keeps bouncing and can shove the FREE ball
		# across a line during the opponent's turn. Position-based — the
		# ball is a goal whenever it's fully across, no matter who moved it.
		if holder == null:
			var stray_scorer: int = board.detect_goal()
			if stray_scorer != -1:
				_on_goal(stray_scorer)
				return
		return
	_flight_time += delta

	if not _ball_in_flight:
		# cap-only launch (no ball): the puck slides.
		# - If it strikes the FREE ball, the ball is knocked into flight.
		# - If the puck dies without touching a FREE ball, possession is lost.
		# - If the ball is HELD by another cap, the slide is a free reposition:
		#   nothing is lost, the turn continues.
		if _launcher != null and holder == null \
				and _launcher.get_colliding_bodies().has(ball):
			_ball_in_flight = true
			_flight_time = 0.0   # grace restarts: cap still has to close the gap
			print("[Turn] P%d cap %d strikes the ball" % [active_player, board.caps.find(_launcher)])
			return
		if _launcher != null and _flight_time > MIN_FLIGHT_TIME and (
				_launcher.linear_velocity.length() < STOP_THRESHOLD
				or _touching_structure(_launcher)):
			# The sling is spent: the puck stopped, or it hit a wall without
			# touching the ball. With full restitution the puck never "dies" at
			# the wall — it keeps bouncing as free physics, but the shot is over.
			if holder == null:
				_lose_possession()
			else:
				# free reposition — turn continues, ball stays with the holder
				_launcher = null
				state = State.TURN_START
				print("[Turn] P%d repositions cap (ball held)" % active_player)
			return

	# goal?
	var scorer: int = board.detect_goal()
	if scorer != -1:
		_on_goal(scorer)
		return
	# stick ONLY on own-teammate CONTACT (with passes left), EXCEPT the striker
	# (the cap that launched/kicked — ball can't pass to the cap that hit it).
	# Opponent/wall contact is pure physics — the ball bounces and keeps flying.
	# Contact-based, like the release rule and the wall give-up: the ball must
	# actually TOUCH the man to be caught. The old distance check (contact + a
	# 12px slop constant) stuck the ball out of the air — the "magnet" feel.
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		if cap == holder or cap == _launcher:
			continue
		if not cap.get_colliding_bodies().has(ball):
			continue
		var team := _team_of(i)
		if team == active_player and passes_left > 0:
			passes_left -= 1
			_attach_ball(cap, ball.linear_velocity)
			state = State.TURN_START
			turn_timer = TURN_SECONDS
			print("[Turn] P%d pass complete → cap %d (%d passes left)" % [active_player, i, passes_left])
			return
		# opponent (or own cap with no passes left): physics bounce only —
		# keep checking other caps and still reach the die-check below
		continue
	# ball died without being captured → stays where it stopped, turn passes
	# (min flight time: the puck needs a moment to make contact and kick it)
	if _flight_time > MIN_FLIGHT_TIME and ball.linear_velocity.length() < STOP_THRESHOLD:
		_lose_possession()

func _lose_possession() -> void:
	# Ball stays exactly where it stopped — no reset, no teleport, no stick.
	_untether()
	holder = null
	_facing = false
	_facing_swinging = false
	_facing_settling = false
	_facing_settle_time = 0.0
	print("[Turn] P%d lost ball — it rests at %s" % [active_player, board.ball.position])
	_pass_turn()

func _release_held_ball() -> void:
	## Plato ownership: the cap and the ball have both stopped after the
	## catch — the tether drops and the ball is FREE on the pitch until any
	## cap physically strikes it again. The turn continues (the player still
	## owns the move; only the physical bond is gone). Input unlocks.
	_untether()
	holder = null
	_facing = false
	_facing_swinging = false
	_facing_settling = false
	_facing_settle_time = 0.0
	print("[Turn] P%d ball released — free at %s" % [active_player, board.ball.position])

func _on_ball_body_entered(body: Node) -> void:
	## Net contact = GOAL. The net (pocket back wall) sits BALL_RADIUS+2
	## behind the goal line, so the ball can only touch it with its centre
	## already across — this IS the crossing, detected mid-step by the
	## engine. Position sampling (detect_goal, once per frame) can miss a
	## goal-speed ball that crosses, hits the net and rebounds out through
	## the mouth within a single step; body_entered fires at the contact.
	## Deferred: _on_goal resets the formation mid-step, which crashes
	## Godot natively (same rule as the possession loss below).
	if body == board.pocket_nets:
		if state == State.MATCH_OVER:
			return
		var scorer := 0 if board.ball.position.y < board.PITCH.y / 2.0 else 1
		_on_goal.call_deferred(scorer)
		return
	## Release rule: while the ball is HELD, opponent contact with the ball
	## breaks the tether — possession is lost. Teammate/wall contact orbits.
	## body_entered fires MID physics-step; mutating physics from inside the
	## signal (untether, layer changes, turn switch) crashes Godot natively.
	## So the whole possession loss is deferred to the end of the frame.
	if holder == null or _ball_in_flight or _facing:
		return
	if not (body is RigidBody2D):
		return                       # wall / other static body — orbit only
	var idx: int = board.caps.find(body)
	if idx == -1:
		return
	var team := _team_of(idx)
	if team != active_player:
		_lose_possession.call_deferred()

func _on_goal(scorer: int) -> void:
	score[scorer] += 1
	print("[Match] GOAL! P%d scores — %d-%d" % [scorer, score[0], score[1]])
	if score[scorer] >= WIN_GOALS:
		_end_match(scorer, false)
		return
	active_player = 1 - scorer               # conceding player kicks off
	passes_left = pass_limit
	_setup_turn(true)
	print("[Turn] P%d kicks off after goal" % active_player)

func _pass_turn() -> void:
	active_player = 1 - active_player
	_setup_turn()

# --- timeout / forfeit ------------------------------------------------------

func _handle_timeout() -> void:
	consecutive_timeouts[active_player] += 1
	print("[Turn] P%d timeout #%d — shot forfeited" % [active_player, consecutive_timeouts[active_player]])
	if consecutive_timeouts[active_player] >= MAX_TIMEOUTS:
		var winner := 1 - active_player
		# SRS 02 §4.F: an AFK forfeit is a 5-0 TECHNICAL victory. The forfeiting
		# player's real goals are wiped — without this the HUD shows "5-2".
		score[winner] = WIN_GOALS
		score[active_player] = 0
		_end_match(winner, true)
	else:
		_pass_turn()

func _end_match(winner: int, forfeit: bool) -> void:
	state = State.MATCH_OVER
	print("[Match] P%d wins%s — final %d-%d" % [winner, " (forfeit)" if forfeit else "", score[0], score[1]])
	match_over.emit(winner)

# --- helpers ----------------------------------------------------------------

func _update_facing(cap: RigidBody2D, delta: float) -> void:
	## Plato turn: the holder SWINGS AROUND THE BALL to sit behind it, facing
	## the goal it attacks (ball between cap and goal, badge toward the goal).
	## The cap's centre orbits the ball — no self-spin — driven by a velocity
	## write along the chord to the target point on the orbit circle, so caps
	## in the arc get shoved and a wall really stops it (nothing phases). The
	## swing starts only once the cap has ridden out any shove (speed gate);
	## a mid-swing shove freezes it until the cap settles again.
	if not _facing:
		return
	if _facing_settling:
		return                       # swing finished — only the release gate acts now
	var ball: RigidBody2D = board.ball
	if not _facing_swinging:
		# ride-out gate: still coasting from the catch/ram — no swing yet.
		# body_get_state: the node's linear_velocity lags a frame behind an
		# impulse applied outside the step (attach's momentum carry, a ram),
		# so the gate would miss it and the swing would steal the slide.
		# Timeout: with low cap damping (Plato glide), a shoved cap coasts
		# for seconds — the shove is spent after FACING_RIDEOUT_TIMEOUT even
		# if it hasn't stopped; the swing then takes over the motion.
		var v: Vector2 = PhysicsServer2D.body_get_state(cap.get_rid(),
				PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
		if v.length() > FACING_STOP_SPEED and _facing_rideout_time < FACING_RIDEOUT_TIMEOUT:
			_facing_rideout_time += delta
			_facing_stall = 0.0
			_facing_last_target = -1.0
			return
		_facing_rideout_time = 0.0
		_facing_swinging = true
	# swing target: behind the ball, on the ball→goal line, at contact distance
	var goal := Vector2(Design.PITCH.x / 2.0, _target_goal_y(active_player))
	var from_goal := ball.position - goal
	if from_goal.length_squared() < 1.0:
		_facing_swinging = false
		_facing_settling = true
		_facing_settle_time = 0.0
		return
	var target := ball.position + from_goal.normalized() * _contact_dist(cap)
	var to_target := target - cap.position
	var dist := to_target.length()
	# badge turns smoothly toward the orbit angle (capped rate — no snap at
	# the swing start), then tracks it. body_set_state: a direct rotation
	# write on an AWAKE body is reverted by the physics server (same quirk as
	# position writes; the old snap worked only on sleeping bodies, which is
	# why it never showed in live play).
	_facing_badge_rot = rotate_toward(_facing_badge_rot,
			(ball.position - cap.position).angle() + PI / 2.0, FACING_BADGE_RATE * delta)
	PhysicsServer2D.body_set_state(cap.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(_facing_badge_rot, cap.global_position))
	if dist <= FACING_TOLERANCE_PX:
		_facing_swinging = false
		_facing_settling = true        # swing done — release once both stop
		_facing_settle_time = 0.0
		cap.linear_velocity = Vector2.ZERO
		return
	# swing drive: the cap ORBITS the ball on the contact circle — velocity
	# purely TANGENTIAL (perpendicular to the cap→ball axis) toward the target
	# angle, plus a gentle radial pull onto the circle. The old chord pull had
	# a radial component that dragged the ball through the spring, so the pair
	# glided across the table like a car; tangential motion keeps the spring
	# at equilibrium and the ball planted while the cap swings around it.
	var r_vec := cap.position - ball.position
	var r_len := r_vec.length()
	if r_len > 1.0:
		var d_theta := angle_difference(r_vec.angle(), (ball.position - goal).angle())
		var omega := clampf(d_theta * FACING_ORBIT_GAIN,
				-FACING_ORBIT_SPEED / r_len, FACING_ORBIT_SPEED / r_len)
		var radial := clampf((_contact_dist(cap) - r_len) * 2.0, -40.0, 40.0)
		# NOTE: -orthogonal() — Godot's orthogonal() returns (y,-x), the
		# visually-CW perpendicular; negating gives the tangent that moves the
		# cap along the SHORT arc toward the target angle. Without it the cap
		# orbits the long way and never converges (dTh stays ~±PI).
		var v := -r_vec.orthogonal() * omega + r_vec / r_len * radial
		# wall clamp: never push INTO a wall — the cap slides ALONG the face
		# instead of burrowing into it. Without this the swing ground against
		# the wall for seconds (friction-creep read as "progress", so the
		# stall never accumulated and the give-up never fired).
		var inner: float = Design.WALL_THICKNESS / 2.0 + board.cap_radius(cap)
		if cap.position.x < inner and v.x < 0.0:
			v.x = 0.0
		elif cap.position.x > Design.PITCH.x - inner and v.x > 0.0:
			v.x = 0.0
		if cap.position.y < inner and v.y < 0.0:
			v.y = 0.0
		elif cap.position.y > Design.PITCH.y - inner and v.y > 0.0:
			v.y = 0.0
		cap.linear_velocity = v
		# the ball is the pivot: zero its velocity every swing frame so it has
		# no momentum to carry (the ride-out tail + spring drag) — it stays
		# planted while the cap orbits. Position pinning would fight the
		# tether; zeroing keeps the physics intact.
		ball.linear_velocity = Vector2.ZERO
	# stall detection: not closing on the target = physically blocked
	if _facing_last_target < 0.0:
		_facing_last_target = dist
	elif dist < _facing_last_target - 0.05:
		_facing_stall = 0.0
	else:
		_facing_stall += delta
		if _facing_stall >= FACING_GIVE_UP_TIME:
			# pushed a cap for 2s without progress — give up the swing; the
			# ball releases once both settle (no soft-lock, controls return
			# via the release, not by unlocking the holder)
			_facing_swinging = false
			_facing_settling = true
			_facing_settle_time = 0.0
			cap.linear_velocity = Vector2.ZERO
		elif _facing_stall >= FACING_STALL_TIME and _touching_structure(cap):
			# jammed against the wall / goal post — stop trying; same path
			_facing_swinging = false
			_facing_settling = true
			_facing_settle_time = 0.0
			cap.linear_velocity = Vector2.ZERO
	_facing_last_target = dist

func _touching_structure(cap: RigidBody2D) -> bool:
	## Wall / goal-post contact via the real collision system. Caps and the
	## ball are RigidBody2D; everything immovable (walls, posts, pocket
	## backs) is a StaticBody2D — so this is exactly "the turn is blocked by
	## something that won't move".
	for body in cap.get_colliding_bodies():
		if body is StaticBody2D:
			return true
	return false

func _team_of(index: int) -> int:
	## 0 = bottom, 1 = top. Sides are CAPS_PER_TEAM long, GK first.
	return 0 if index < Design.CAPS_PER_TEAM else 1

func _contact_dist(cap: Node) -> float:
	## Distance between cap centre and ball centre at contact. Per-cap, because
	## the goalkeeper's collider is larger than an outfield cap's.
	return board.cap_radius(cap) + Design.BALL_RADIUS

func _target_goal_y(player: int) -> float:
	## The goal `player` attacks: the bottom team (0) shoots at the top goal.
	return 0.0 if player == 0 else Design.PITCH.y

func _cap_at(pos: Vector2) -> RigidBody2D:
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		var team := _team_of(i)
		if team != active_player:
			continue
		if cap.position.distance_to(pos) <= board.cap_radius(cap) + TAP_TOLERANCE:
			return cap
	return null

func _nearest_own_cap(pos: Vector2) -> RigidBody2D:
	var best: RigidBody2D = null
	var best_d := INF
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		var team := _team_of(i)
		if team != active_player:
			continue
		var d := cap.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = cap
	return best
