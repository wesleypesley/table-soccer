extends Node
## Headless physics test suite for TableSoccer.
##
## Protocol: ONE case per FRESH process, so FSM state can never leak between
## cases. The `--headless` engine steps physics normally; only rendering is
## stubbed.
##
## (The protocol originally came from PHYSICS_BRIEF_FOR_CLAUDE.md, removed from
## the repo in 3d96773; the current brief is "How the game should look and
## feel/Design & Gameplay Physics rule.md". Rule references below point at
## Table_Soccer_Documentation_Suite/02_gameplay_turn_system.md, which is live.)
##
##   godot --headless tests/run.tscn -- <case>
##   tests/run_all.sh                          # every case, one process each
##
## Test-setup rules honoured here:
##  - No ball teleports. Possession is always established through the game's own
##    capture path (`turn_manager._attach_ball`), never by writing ball.position.
##  - Caps may be parked for setup; parked caps are kept >= MIN_PARK_GAP apart
##    so they don't shove neighbours, and clear of any coasting cap's path.
##  - Turn timer is pinned high so the FSM can't forfeit mid-case.

const SETTLE_FRAMES := 4
const MIN_PARK_GAP := 100.0            # parked caps shove neighbours if closer
const LONG_TIMER := 99999.0
## Contact distance for an OUTFIELD cap. The GK's is larger; cases that use a
## GK must ask board.cap_radius() rather than assume this.
const OUTFIELD_CONTACT := Design.CAP_RADIUS + Design.BALL_RADIUS
const SPARE_CLEARANCE := 60.0          # margin a parked spare must keep beyond the release radius

# Wall geometry, derived from tokens — never hardcoded.
# Left wall segment is centred on x=0 with thickness WALL_THICKNESS, so its
# inner face sits at +WALL_THICKNESS/2. A ball resting against it has its
# centre at face + BALL_RADIUS.
const WALL_INNER_FACE_X := Design.WALL_THICKNESS / 2.0                    # 10.0
const BALL_MIN_X := WALL_INNER_FACE_X + Design.BALL_RADIUS                # 32.0
## Truly out of the table: past the OUTER face of the wall body, not merely
## overlapping it. Overlap is a solver artefact the ball recovers from;
## clearing the outer face means it is gone for good.
const WALL_OUTER_FACE_X := WALL_INNER_FACE_X - Design.WALL_COLLISION_DEPTH
const BALL_ESCAPED_X := WALL_OUTER_FACE_X - Design.BALL_RADIUS

var main: Node
var board: Node2D
var tm: Node
var _rows: Array[Array] = []

# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var case_name: String = args[0] if args.size() > 0 else "probe"
	await _boot()
	match case_name:
		"probe":        await _case_probe()
		"tether_moving": await _case_tether_moving()
		"wall_max":     await _case_wall_max()
		"wall_double":  await _case_wall_double()
		"tether":       await _case_tether()
		"pass_chain":   await _case_pass_chain()
		"formation":    await _case_formation()
		"gk":           await _case_gk()
		"kickoff":      await _case_kickoff()
		"facing":       await _case_facing()
		"goal":         await _case_goal()
		"forfeit":      await _case_forfeit()
		_:
			push_error("unknown case: %s" % case_name)
			get_tree().quit(1)
			return
	_report(case_name)

func _boot() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# main.gd builds Board/TurnManager/HUD in _ready(); let the world settle.
	await _step(SETTLE_FRAMES)
	board = main.get_node("Board")
	tm = main.get_node("TurnManager")
	tm.turn_timer = LONG_TIMER
	tm.active_player = 0          # kickoff is randi()%2 — pin it for determinism
	tm._update_team_glow()

func _step(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _row(label: String, value: Variant) -> void:
	_rows.append([label, value])

func _report(case_name: String) -> void:
	var bar := "=".repeat(58)
	print("\n%s\nCASE: %s\n%s" % [bar, case_name, bar])
	for r in _rows:
		print("  %-26s %s" % [r[0], r[1]])
	print("%s\n" % bar)
	get_tree().quit()

# --- shared helpers ----------------------------------------------------------

func _park(cap: RigidBody2D, pos: Vector2) -> void:
	## Park a test cap for setup, zeroing velocity so it never carries stale
	## momentum into the case. `pos` is board-local.
	##
	## Goes through PhysicsServer2D, not `cap.position = ...`: for an AWAKE
	## RigidBody2D the server owns the transform and silently discards a direct
	## write. That is invisible on a freshly spawned (sleeping) board but breaks
	## any case that parks a second time — the cap stays where it was and the
	## case measures nonsense. body_set_state takes a GLOBAL transform, hence
	## board.to_global().
	var rid := cap.get_rid()
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM,
			Transform2D(0.0, board.to_global(pos)))
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)

func _park_others_away(keep: Array) -> void:
	## Move every cap not in `keep` into a tight cluster in the TOP-LEFT corner,
	## clear of the mid-pitch and bottom-half action every case uses.
	##
	## This used to be a column at x=PITCH.x-48, which sat directly in the drift
	## path of a receiver shoved by MOMENTUM_CARRY: the receiver coasted into a
	## parked OPPONENT, the release rule fired, and pass_chain reported a
	## completed pass whose possession had already been lost. Park spares where
	## nothing coasts into them. Spacing >= MIN_PARK_GAP.
	## 3 columns, so all 9 spares fit inside the corner instead of the last one
	## spilling down the left edge into a holder parked at mid-pitch.
	var slot := 0
	for i in board.caps.size():
		var cap: RigidBody2D = board.caps[i]
		if keep.has(cap):
			continue
		var col := 60.0 + float(slot % 3) * (MIN_PARK_GAP + 10.0)
		var row := 60.0 + float(slot / 3) * (MIN_PARK_GAP + 10.0)
		_park(cap, Vector2(col, row))
		slot += 1
	# Node transforms sync from the server on the next step; read-back before
	# that is stale, so step once before checking clearances.
	await _step(1)
	_assert_spares_clear(keep)

func _assert_spares_clear(keep: Array) -> void:
	## A spare parked too near a kept cap silently ruins a case: an opponent
	## within CAP_RADIUS*2 + CONTACT_SLOP of the holder trips the release rule
	## and possession is gone before the case even starts. Fail loudly instead.
	var release_dist := Design.CAP_RADIUS * 2.0 + 6.0
	var worst := INF
	for i in board.caps.size():
		var spare: RigidBody2D = board.caps[i]
		if keep.has(spare):
			continue
		for k in keep:
			var kept: RigidBody2D = k
			worst = minf(worst, spare.position.distance_to(kept.position))
	if worst < release_dist + SPARE_CLEARANCE:
		push_error("BAD SETUP: a parked spare is %.1fpx from a kept cap (need > %.1f)"
				% [worst, release_dist + SPARE_CLEARANCE])
	_row("setup_min_spare_gap", "%.1f px (release at %.1f)" % [worst, release_dist])

func _capture_with(cap: RigidBody2D) -> void:
	## Establish possession through the REAL capture path. _attach_ball is the
	## same function a completed pass calls; it places the ball on the contact
	## circle itself, so no ball teleport happens in test code.
	tm._attach_ball(cap, Vector2.ZERO)

# --- cases -------------------------------------------------------------------

func _case_probe() -> void:
	## Environment probe: does physics step headless, driven by the real input
	## path? Launches a cap at the free ball via turn_manager._launch_cap.
	var ball: RigidBody2D = board.ball
	var cap: RigidBody2D = board.caps[4]
	var cap_start := cap.position
	var ball_start := ball.position

	tm._launch_cap(cap, ball_start - cap_start, 1000.0)

	var ball_peak := 0.0
	var min_gap := INF
	for i in 240:
		await _step(1)
		ball_peak = maxf(ball_peak, ball.linear_velocity.length())
		min_gap = minf(min_gap, cap.position.distance_to(ball.position))

	_row("initial_gap", "%.1f px" % cap_start.distance_to(ball_start))
	_row("cap_moved", "%.1f px" % cap_start.distance_to(cap.position))
	_row("ball_moved", "%.1f px" % ball_start.distance_to(ball.position))
	_row("ball_peak_speed", "%.1f px/s" % ball_peak)
	_row("min_cap_ball_gap", "%.1f px (contact %.1f)" % [min_gap, OUTFIELD_CONTACT])
	_row("cap_ball_overlap", "%.1f px" % maxf(0.0, OUTFIELD_CONTACT - min_gap))
	_row("PHYSICS_STEPS", "YES" if cap_start.distance_to(cap.position) > 1.0 else "NO")

func _case_wall_max() -> void:
	## P1: maximum-power REAL shot straight at the left wall, with a long runway
	## so the FIRST wall impact is clean (isolated from any later double-hit).
	## Holder is parked on the right side; the puck is slingshot at
	## BALL_SPEED_MAX and physically kicks the ball across the pitch.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	await _park_others_away([holder])
	_park(holder, Vector2(Design.PITCH.x - 160.0, Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(holder)
	await _step(2)

	_row("holder_pos", holder.position)
	_row("ball_pos_after_capture", ball.position)
	tm._launch_puck(Vector2.LEFT, tm.BALL_SPEED_MAX)
	_row("ball_pos_after_launch", ball.position)

	var min_x := INF
	var peak := 0.0
	var speed_at_min := 0.0
	var first_min_x := INF          # min x before the first rebound
	var bounced := false
	var escaped := false
	var trace: Array[String] = []
	var prev_vx := 0.0

	for i in 300:
		await _step(1)
		var x := ball.position.x
		var vx := ball.linear_velocity.x
		var spd := ball.linear_velocity.length()
		peak = maxf(peak, spd)
		if not bounced:
			first_min_x = minf(first_min_x, x)
			if prev_vx < -1.0 and vx > 1.0:
				bounced = true
		prev_vx = vx
		if x < min_x:
			min_x = x
			speed_at_min = spd
		if x < BALL_ESCAPED_X:
			escaped = true
		if x < 120.0 and trace.size() < 10:
			trace.append("f%d x=%.1f vx=%.0f sleep=%s" % [i, x, vx, ball.sleeping])

	_row("launch_speed", "%.1f px/s" % tm.BALL_SPEED_MAX)
	_row("ball_peak_speed", "%.1f px/s" % peak)
	_row("speed_cap", "none (CCD, MAX_BALL_SPEED removed 2026-08-11)")
	_row("first_impact_min_x", "%.2f px" % first_min_x)
	_row("overall_min_x", "%.2f px" % min_x)
	_row("expected_min_x", "%.2f px" % BALL_MIN_X)
	_row("first_impact_penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - first_min_x))
	_row("overall_penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - min_x))
	_row("speed_at_min_x", "%.1f px/s" % speed_at_min)
	_row("px_per_frame_at_min", "%.1f" % (speed_at_min / 60.0))
	_row("ESCAPED_PITCH", "YES" if escaped else "NO")
	_row("final_ball_pos", ball.position)
	for t in trace:
		_row("  trace", t)

func _case_wall_double() -> void:
	## P1: the double-hit the MAX_BALL_SPEED comment warns about — the ball
	## rebounds off the wall into the still-advancing puck and is re-kicked.
	## Holder is parked close to the wall so the rebound meets the puck.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	await _park_others_away([holder])
	# Close to the wall: puck centre one cap-radius + margin off the face.
	_park(holder, Vector2(WALL_INNER_FACE_X + Design.CAP_RADIUS + OUTFIELD_CONTACT + 20.0,
			Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(holder)
	await _step(2)

	tm._launch_puck(Vector2.LEFT, tm.BALL_SPEED_MAX)

	var min_x := INF
	var peak := 0.0
	var hits := 0
	var prev_vx := 0.0
	var escaped := false
	var escape_frame := -1
	var escape_pos := Vector2.ZERO
	var peak_frame := -1
	var trace: Array[String] = []

	for i in 300:
		await _step(1)
		var vx := ball.linear_velocity.x
		var spd := ball.linear_velocity.length()
		# sign flip from left-going to right-going = a wall bounce
		if prev_vx < -1.0 and vx > 1.0:
			hits += 1
		prev_vx = vx
		if spd > peak:
			peak = spd
			peak_frame = i
		min_x = minf(min_x, ball.position.x)
		if not escaped and ball.position.x < BALL_ESCAPED_X:
			escaped = true
			escape_frame = i
			escape_pos = ball.position
		if trace.size() < 12 and (ball.position.x < 140.0 or escaped):
			trace.append("f%d x=%.1f vx=%.0f spd=%.0f" % [i, ball.position.x, vx, spd])

	_row("ball_peak_speed", "%.1f px/s" % peak)
	_row("peak_at_frame", peak_frame)
	_row("speed_cap", "none (CCD, MAX_BALL_SPEED removed 2026-08-11)")
	_row("peak_EXCEEDS_cap", "NO — no cap exists; CCD prevents tunnel")
	_row("wall_bounces", hits)
	_row("min_ball_x", "%.2f px" % min_x)
	_row("expected_min_x", "%.2f px" % BALL_MIN_X)
	_row("penetration", "%.2f px" % maxf(0.0, BALL_MIN_X - min_x))
	_row("wall_outer_face_x", "%.2f px" % WALL_OUTER_FACE_X)
	_row("ESCAPED_TABLE", "YES" if escaped else "NO")
	_row("escape_frame", escape_frame)
	_row("escape_pos", escape_pos)
	_row("final_ball_pos", ball.position)
	var in_play: bool = ball.position.x > 0.0 and ball.position.x < Design.PITCH.x \
			and ball.position.y > 0.0 and ball.position.y < Design.PITCH.y
	_row("RECOVERED_INTO_PLAY", "YES" if in_play else "NO")
	for t in trace:
		_row("  trace", t)

func _case_tether() -> void:
	## Regression guard for the core mechanic: the held ball orbits at exactly
	## CAPTURE_DIST and never phases through a blocking cap.
	## An opponent cap is rammed at the holder to stress the sweep.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	var mate: RigidBody2D = board.caps[4]           # OWN team, so no release rule
	await _park_others_away([holder, mate])
	# Holder is parked clear of the ball spawn: parking a cap ON the ball makes
	# the solver eject it and every measurement after that is noise.
	_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 160.0))
	_park(mate, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 - 200.0))
	await _step(2)
	_capture_with(holder)
	await _step(6)                                  # let the orbit settle

	var d1_settled := ball.position.distance_to(holder.position)
	var d1_min := INF
	var d1_max := 0.0
	var d2_min := INF
	var held_all := true
	var lost_at := -1
	# Teammate ram, tangential (dead-radial hits slam the ball into
	# the holder). A teammate can't trigger the release rule, so this isolates
	# the tether's blocking/sweep behaviour from possession loss.
	mate.apply_central_impulse(Vector2(0.35, 1.0).normalized() * 1100.0 * mate.mass)

	for i in 150:
		await _step(1)
		if tm.holder == null:
			held_all = false
			lost_at = i
			break
		var d1 := ball.position.distance_to(holder.position)
		d1_min = minf(d1_min, d1)
		d1_max = maxf(d1_max, d1)
		d2_min = minf(d2_min, ball.position.distance_to(mate.position))

	_row("orbit_radius_target", "%.1f px" % OUTFIELD_CONTACT)
	_row("d1_after_settle", "%.2f px" % d1_settled)
	_row("d1_min", "%.2f px" % d1_min)
	_row("d1_max", "%.2f px" % d1_max)
	_row("d1_max_deviation", "%.2f px" % maxf(absf(d1_max - OUTFIELD_CONTACT), absf(d1_min - OUTFIELD_CONTACT)))
	_row("d2_min_vs_mate", "%.2f px" % d2_min)
	_row("phase_through", "YES" if d2_min < OUTFIELD_CONTACT - 1.0 else "NO")
	_row("held_every_frame", "YES" if held_all else "NO (lost at frame %d)" % lost_at)

func _case_tether_moving() -> void:
	## Isolates the pass_chain anomaly: same tether, same clear circle, but the
	## HOLDER is gliding instead of parked. Nothing else differs from _case_tether.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	await _park_others_away([holder])
	_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 160.0))
	await _step(2)
	_capture_with(holder)
	await _step(6)

	var r_parked := ball.position.distance_to(holder.position)

	# Push the holder along +x. No collision involved — pure glide.
	holder.apply_central_impulse(Vector2.RIGHT * 600.0 * holder.mass)

	var trace: Array[String] = []
	var r_max := 0.0
	for i in 30:
		await _step(1)
		var r := ball.position.distance_to(holder.position)
		r_max = maxf(r_max, r)
		if i % 3 == 0:
			trace.append("f%d r=%.2f v_hold=%.0f" % [i, r, holder.linear_velocity.length()])

	_row("orbit_target", "%.2f px" % OUTFIELD_CONTACT)
	_row("radius_holder_parked", "%.2f px" % r_parked)
	_row("radius_max_while_moving", "%.2f px" % r_max)
	_row("radius_final", "%.2f px" % ball.position.distance_to(holder.position))
	_row("DEGRADES_WHEN_MOVING", "YES" if r_max > OUTFIELD_CONTACT + 1.0 else "NO")
	for t in trace:
		_row("  trace", t)

func _case_pass_chain() -> void:
	## Regression guard: a real pass completes, decrements passes_left, and the
	## receiver becomes holder at the correct orbit radius.
	var ball: RigidBody2D = board.ball
	var passer: RigidBody2D = board.caps[3]
	var receiver: RigidBody2D = board.caps[4]
	await _park_others_away([passer, receiver])
	_park(passer, Vector2(200.0, Design.PITCH.y / 2.0))
	_park(receiver, Vector2(200.0 + 320.0, Design.PITCH.y / 2.0))
	await _step(2)
	_capture_with(passer)
	await _step(2)

	var passes_before: int = tm.passes_left
	tm._launch_puck(receiver.position - passer.position, 900.0)

	var caught := false
	var caught_at := -1
	for i in 240:
		await _step(1)
		if tm.holder == receiver:
			caught = true
			caught_at = i
			break

	var radius_at_catch := 0.0
	var radius_settled := 0.0
	var radius_min_after := INF
	var crushed_at := -1
	var trace: Array[String] = []
	if caught:
		radius_at_catch = ball.position.distance_to(receiver.position)
		for i in 20:                    # watch the tether pull it onto the circle
			await _step(1)
			var r_now := ball.position.distance_to(receiver.position)
			radius_min_after = minf(radius_min_after, r_now)
			# Inside the holder's own collider = the ball has been pushed into
			# the cap it is attached to. The ball/holder collision exception
			# means nothing physically stops this.
			if crushed_at == -1 and r_now < Design.CAP_RADIUS:
				crushed_at = i
			trace.append("f%d r=%.2f v_hold=%.0f d_passer=%.0f" % [
				i,
				ball.position.distance_to(receiver.position),
				receiver.linear_velocity.length(),
				passer.position.distance_to(receiver.position)])
		radius_settled = ball.position.distance_to(receiver.position)

	_row("passes_before", passes_before)
	_row("passes_after", tm.passes_left)
	_row("pass_completed", "YES" if caught else "NO")
	_row("caught_at_frame", caught_at)
	_row("holder_is_receiver", "YES" if tm.holder == receiver else "NO")
	_row("orbit_target", "%.2f px" % OUTFIELD_CONTACT)
	_row("radius_at_catch", "%.2f px" % radius_at_catch)
	_row("radius_after_settle", "%.2f px" % radius_settled)
	_row("radius_min_after_catch", "%.2f px" % radius_min_after)
	_row("BALL_INSIDE_HOLDER", "NO" if crushed_at == -1 \
			else "YES (frame %d, cap radius %.0f)" % [crushed_at, Design.CAP_RADIUS])
	_row("fsm_state", tm.state)
	for t in trace:
		_row("  trace", t)

func _case_goal() -> void:
	## Is a goal actually reachable with a real shot? Standing regression guard:
	## a shot from mid-pitch must cross the opponent goal line.
	var ball: RigidBody2D = board.ball
	var holder: RigidBody2D = board.caps[3]
	await _park_others_away([holder])
	# Mid-pitch, shooting at the TOP goal (P0 scores when ball.y < 0).
	_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 160.0))
	await _step(2)
	_capture_with(holder)
	await _step(4)

	var start_y := ball.position.y
	var score_before: int = tm.score[0]
	# Optional 2nd CLI arg: shot power, for probing the scoring threshold.
	var cli := OS.get_cmdline_user_args()
	var power: float = cli[1].to_float() if cli.size() > 1 else tm.BALL_SPEED_MAX
	tm._launch_puck(Vector2.UP, power)
	_row("shot_power", "%.0f px/s" % power)

	var min_y := INF
	var peak := 0.0
	var scored_at := -1
	for i in 300:
		await _step(1)
		peak = maxf(peak, ball.linear_velocity.length())
		min_y = minf(min_y, ball.position.y)
		if scored_at == -1 and tm.score[0] > score_before:
			scored_at = i
			break

	_row("shot_from_y", "%.1f px" % start_y)
	_row("distance_to_goal_line", "%.1f px" % start_y)
	_row("ball_peak_speed", "%.1f px/s" % peak)
	_row("min_ball_y", "%.2f px" % min_y)
	# Clear depth behind the goal line, and where a ball resting on the pocket
	# back wall ends up. detect_goal() needs the CENTRE to reach y < 0.
	var pocket_clear_depth := 36.0 - Design.WALL_THICKNESS
	_row("pocket_clear_depth", "%.1f px (ball radius %.1f)" % [pocket_clear_depth, Design.BALL_RADIUS])
	_row("ball_rest_y_in_pocket", "%.1f px" % (Design.BALL_RADIUS - pocket_clear_depth))
	_row("GOAL_SCORED", "YES" if scored_at != -1 else "NO")
	_row("scored_at_frame", scored_at)
	_row("score", tm.score)

func _case_formation() -> void:
	## Spawn integrity for the 6-a-side formation: no cap may overlap another
	## cap, a wall, or the kickoff ball. Cheap to check and catches a bad
	## formation table immediately, which is otherwise a subtle physics mess.
	var per: int = Design.CAPS_PER_TEAM
	var worst_pair := INF
	var worst_pair_name := ""
	var worst_wall := INF
	var ball_gap := INF

	for i in board.caps.size():
		var a: RigidBody2D = board.caps[i]
		var ra: float = board.cap_radius(a)
		# cap vs cap
		for j in range(i + 1, board.caps.size()):
			var b: RigidBody2D = board.caps[j]
			var clearance: float = a.position.distance_to(b.position) - ra - board.cap_radius(b)
			if clearance < worst_pair:
				worst_pair = clearance
				worst_pair_name = "%d-%d" % [i, j]
		# cap vs wall (inner faces)
		var half_t := Design.WALL_THICKNESS / 2.0
		worst_wall = minf(worst_wall, a.position.x - half_t - ra)
		worst_wall = minf(worst_wall, (Design.PITCH.x - half_t) - a.position.x - ra)
		worst_wall = minf(worst_wall, a.position.y - half_t - ra)
		worst_wall = minf(worst_wall, (Design.PITCH.y - half_t) - a.position.y - ra)
		ball_gap = minf(ball_gap, a.position.distance_to(board.ball.position) - ra - Design.BALL_RADIUS)

	_row("caps_total", board.caps.size())
	_row("caps_per_team", per)
	_row("min_cap_cap_clearance", "%.1f px (pair %s)" % [worst_pair, worst_pair_name])
	_row("min_cap_wall_clearance", "%.1f px" % worst_wall)
	_row("min_cap_ball_clearance", "%.1f px" % ball_gap)
	_row("NO_CAP_OVERLAP", "YES" if worst_pair > 0.0 else "NO")
	_row("ALL_INSIDE_WALLS", "YES" if worst_wall > 0.0 else "NO")
	_row("BALL_SPAWN_CLEAR", "YES" if ball_gap > 0.0 else "NO")

func _case_gk() -> void:
	## The goalkeeper's size must be REAL physics, not a visual trick: bigger
	## collider, bigger contact ring, and enough mass that an outfield cap
	## charging it does not shove it around like a peer.
	var gk: RigidBody2D = board.caps[Design.GK_INDEX]
	var outfield: RigidBody2D = board.caps[Design.GK_INDEX + 1]
	var gk_r: float = board.cap_radius(gk)
	var out_r: float = board.cap_radius(outfield)

	_row("gk_index", Design.GK_INDEX)
	_row("gk_radius", "%.1f px" % gk_r)
	_row("outfield_radius", "%.1f px" % out_r)
	_row("GK_IS_BIGGER", "YES" if gk_r > out_r else "NO")
	_row("gk_mass", "%.1f" % gk.mass)
	_row("outfield_mass", "%.1f" % outfield.mass)
	_row("GK_IS_HEAVIER", "YES" if gk.mass > outfield.mass else "NO")

	# The collider really is bigger, not just the metadata: ask the shape.
	var shape: CircleShape2D = gk.get_node("CollisionShape2D").shape as CircleShape2D \
			if gk.get_node_or_null("CollisionShape2D") != null else null
	if shape == null:
		for c in gk.get_children():
			if c is CollisionShape2D:
				shape = (c as CollisionShape2D).shape as CircleShape2D
				break
	_row("gk_collider_radius", "%.1f px" % (shape.radius if shape != null else -1.0))
	_row("COLLIDER_MATCHES", "YES" if shape != null and is_equal_approx(shape.radius, gk_r) else "NO")

	# Contact ring: the ball sticks to the GK further out than to an outfield cap.
	_row("gk_contact_dist", "%.1f px" % tm._contact_dist(gk))
	_row("outfield_contact_dist", "%.1f px" % tm._contact_dist(outfield))

	# Ram the GK with an outfield cap and record how far it gets shoved --
	# reported, not asserted: the right value is a feel call, not a fact.
	await _park_others_away([gk, outfield])
	_park(gk, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0))
	_park(outfield, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0 + 300.0))
	await _step(2)
	var gk_start := gk.position
	outfield.apply_central_impulse(Vector2.UP * 1200.0 * outfield.mass)
	for i in 90:
		await _step(1)
	_row("gk_shoved_by", "%.1f px" % gk_start.distance_to(gk.position))

func _case_kickoff() -> void:
	## After a goal: both teams return to formation, the ball resets to the
	## centre spot, and the CONCEDING side kicks off.
	var ball: RigidBody2D = board.ball
	# Scatter the pitch so a reset is unmistakable.
	for i in board.caps.size():
		_park(board.caps[i], Vector2(80.0 + float(i % 4) * 60.0, 300.0 + float(i / 4) * 60.0))
	await _step(2)
	var scattered_err := 0.0
	for i in board.caps.size():
		scattered_err = maxf(scattered_err, board.caps[i].position.distance_to(board.formation_for(i)))
	var scorer := 0                      # bottom team scores
	tm.score = [0, 0]
	tm._on_goal(scorer)
	await _step(4)

	var worst := 0.0
	var worst_i := -1
	for i in board.caps.size():
		var e: float = board.caps[i].position.distance_to(board.formation_for(i))
		if e > worst:
			worst = e
			worst_i = i
	_row("worst_cap", worst_i)
	var centre := Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0)

	_row("scatter_before_reset", "%.1f px" % scattered_err)
	_row("worst_formation_error", "%.1f px" % worst)
	_row("FORMATION_RESTORED", "YES" if worst < 1.0 else "NO")
	_row("ball_pos", ball.position)
	_row("BALL_AT_CENTRE_SPOT", "YES" if ball.position.distance_to(centre) < 1.0 else "NO")
	_row("scorer", "P%d" % scorer)
	_row("kicks_off", "P%d" % tm.active_player)
	_row("CONCEDER_KICKS_OFF", "YES" if tm.active_player == 1 - scorer else "NO")
	_row("score", tm.score)
	_row("win_goals", tm.WIN_GOALS)

func _case_facing() -> void:
	## A cap holding the ball turns to face the goal it is attacking (Plato).
	## Checked for BOTH sides, since they attack opposite ends.
	var results: Array[String] = []
	var ok := true
	for player in [0, 1]:
		# caps 0..5 are the bottom side, 6..11 the top side; index 1 is outfield.
		var holder: RigidBody2D = board.caps[1 if player == 0 else Design.CAPS_PER_TEAM + 1]
		tm.active_player = player
		# Park the HOLDER first: _park_others_away asserts on clearance, and on
		# the second pass this cap is still sitting in the spare cluster from
		# the first, which reads as an opponent on top of it.
		_park(holder, Vector2(Design.PITCH.x / 2.0, Design.PITCH.y / 2.0))
		await _step(1)
		await _park_others_away([holder])
		await _step(2)
		_capture_with(holder)
		await _step(6)

		# The goal this player attacks, and the direction the cap should point.
		var goal := Vector2(Design.PITCH.x / 2.0, 0.0 if player == 0 else Design.PITCH.y)
		var want := (goal - holder.position).angle() + PI / 2.0
		var err := absf(angle_difference(holder.rotation, want))
		if err > 0.01:
			ok = false
		results.append("P%d rot=%.3f want=%.3f err=%.4f" % [player, holder.rotation, want, err])
		tm._lose_possession()
		await _step(2)

	for r in results:
		_row("  ", r)
	_row("FACES_TARGET_GOAL", "YES" if ok else "NO")

func _case_forfeit() -> void:
	## P7: 3-strike forfeit final score. The turn timer is driven by _process,
	## which gates on get_window().has_focus() — unreliable headless — so the
	## timeout handler is called directly. That IS the real handler; only the
	## clock is bypassed.
	# Turns alternate on every timeout, so P0 (who starts) reaches MAX_TIMEOUTS
	# first and is the forfeiting LOSER. Give the loser real goals — that is
	# exactly the "5-x" case the brief asks about.
	tm.score = [2, 0]
	var loser := 0

	# Sub-check: is `consecutive_timeouts` actually consecutive? Time out once,
	# then complete a normal turn, and see whether the counter clears.
	tm._handle_timeout()
	var after_one: Array = (tm.consecutive_timeouts as Array).duplicate()
	# Now the same player actually takes their shot — that must clear the streak.
	tm.active_player = loser
	tm.state = tm.State.TURN_START
	tm._set_selected(board.caps[1])
	tm._fire_pull(Vector2(0.0, -60.0))
	var after_normal_turn: Array = (tm.consecutive_timeouts as Array).duplicate()

	tm.consecutive_timeouts = [0, 0]       # reset for the clean forfeit run
	tm.active_player = loser
	tm.state = tm.State.TURN_START

	var timeouts := 0
	var guard := 0
	while tm.state != tm.State.MATCH_OVER and guard < 20:
		tm._handle_timeout()
		timeouts += 1
		guard += 1
		await _step(1)

	_row("loser", "P%d" % loser)
	_row("loser_goals_before", 2)
	_row("timeouts_to_forfeit", timeouts)
	_row("consecutive_timeouts", tm.consecutive_timeouts)
	_row("final_score", tm.score)
	_row("expected_result", "%d-0 (loser zeroed)" % tm.WIN_GOALS)
	_row("LOSER_ZEROED", "YES" if tm.score[loser] == 0 else "NO (shows %d-%d)" % [tm.WIN_GOALS, tm.score[loser]])
	_row("state_is_MATCH_OVER", "YES" if tm.state == tm.State.MATCH_OVER else "NO")
	_row("--- consecutive check ---", "")
	_row("after_one_timeout", after_one)
	_row("after_player_acted", after_normal_turn)
	_row("COUNTER_RESETS", "YES" if after_normal_turn[loser] == 0 else "NO (stays %d)" % after_normal_turn[loser])
