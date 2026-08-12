extends Node
## Screenshot harness — renders the real game and writes a PNG.
##
## Needs a framebuffer, so it is NOT a --headless tool. Run it under Xvfb:
##
##   tests/shoot.sh                      # default: kickoff formation
##   tests/shoot.sh 120 shot_late.png    # wait 120 frames, custom name
##
## Waits for real presented frames before grabbing, because the first frames
## after boot are the clear colour, not the scene.

const DEFAULT_WAIT := 45

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var wait_frames: int = int(args[0]) if args.size() > 0 else DEFAULT_WAIT
	var out_name: String = args[1] if args.size() > 1 else "shot.png"

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	# Let the scene build, physics settle, and the renderer actually present.
	for i in wait_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var path := "user://%s" % out_name
	var err := img.save_png(path)
	print("[shot] %s -> %s (%dx%d) err=%d"
			% [out_name, ProjectSettings.globalize_path(path), img.get_width(), img.get_height(), err])
	get_tree().quit()
