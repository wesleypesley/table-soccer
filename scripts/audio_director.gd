extends Node
## Crowd audio (brief item 6): an ambient murmur under play, and a cheer when a
## goal goes in.
##
## Two independent channels, because the reference's in-game menu offers
## "Toggle Sound" and "Toggle Ambient" as SEPARATE items:
##   - ambient  : the looping crowd bed
##   - sound    : one-shot event audio (the goal cheer)
## Muting one leaves the other alone.
##
## Beds are synthesised by tools/gen_audio.py — the project ships no external
## assets, so the audio is generated in code like everything else.

const AMBIENT_PATH := "res://audio/crowd_ambient.wav"
const CHEER_PATH := "res://audio/crowd_cheer.wav"

const AMBIENT_DB := -18.0        # sits under play, never competes with events
const CHEER_DB := -6.0

var turn_manager: Node

var ambient_enabled := true:
	set(v):
		ambient_enabled = v
		_apply_ambient()
var sound_enabled := true

var _ambient: AudioStreamPlayer
var _cheer: AudioStreamPlayer

func _ready() -> void:
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	_ambient.stream = _load_looping(AMBIENT_PATH, true)
	_ambient.volume_db = AMBIENT_DB
	add_child(_ambient)

	_cheer = AudioStreamPlayer.new()
	_cheer.name = "Cheer"
	_cheer.stream = _load_looping(CHEER_PATH, false)
	_cheer.volume_db = CHEER_DB
	add_child(_cheer)

	if turn_manager != null:
		if turn_manager.has_signal("goal_scored"):
			turn_manager.goal_scored.connect(_on_goal_scored)
		if turn_manager.has_signal("match_over"):
			turn_manager.match_over.connect(_on_match_over)
	_apply_ambient()

func _load_looping(path: String, loop: bool) -> AudioStream:
	## The WAV importer does not mark these as looping, so the flag is set on
	## the resource here. The ambient bed is generated with a cross-faded seam
	## precisely so LOOP_FORWARD is clickless.
	# CACHE_MODE_IGNORE: a plain load() leaves the WAV in the resource cache,
	# which outlives tree teardown and makes Godot report "resources still in
	# use at exit". These beds have exactly one owner, so skip the cache.
	var stream: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / 2      # 16-bit mono: 2 bytes per frame
	return stream

func _apply_ambient() -> void:
	if _ambient == null:
		return
	if ambient_enabled and not _ambient.playing:
		_ambient.play()
	elif not ambient_enabled and _ambient.playing:
		_ambient.stop()

# --- events ------------------------------------------------------------------

func _on_goal_scored(_scorer: int) -> void:
	play_cheer()

func _on_match_over(_winner: int) -> void:
	play_cheer()

func play_cheer() -> void:
	if not sound_enabled or _cheer == null:
		return
	_cheer.play()

func _exit_tree() -> void:
	## Release the streams explicitly. Without this, Godot reports "resources
	## still in use at exit" — the players outlive the tree teardown and keep a
	## reference to the WAVs.
	for pl in [_ambient, _cheer]:
		if pl != null:
			if pl.playing:
				pl.stop()
			pl.stream = null

# --- menu hooks --------------------------------------------------------------

func toggle_ambient() -> bool:
	ambient_enabled = not ambient_enabled
	return ambient_enabled

func toggle_sound() -> bool:
	sound_enabled = not sound_enabled
	if not sound_enabled and _cheer != null and _cheer.playing:
		_cheer.stop()
	return sound_enabled
