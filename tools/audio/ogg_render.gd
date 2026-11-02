extends Node
## Plays one sound file through the Master bus for Godot's Movie Maker. It is how
## tools/encode_ogg.py encodes Vorbis without ffmpeg, oggenc or soundfile (the
## OGV writer does the encoding), and how it checks an encode (played back into an
## AVI with PCM audio). Not part of the game.
##
## encode_ogg.py runs it inside a throwaway project it writes to build/audio/render/
## (so none of the game's autoloads start), with:
##   Godot_v4.7.2-stable_win64_console.exe --path build/audio/render
##     --write-movie <out>.ogv|.avi --fixed-fps 50 --resolution 64x64
##     res://tools/audio/ogg_render.tscn -- --wav=<abs path> | --ogg=<abs path>
##     [--frames=<n> | --seconds=<s> [--tail-frames=<n>]] [--loop-offset=<s>]
## 50 fps divides 44100 evenly (882 samples a frame). It plays from _ready and
## quits after exactly --frames frames (or the length plus a few spare frames).
## --loop-offset plays an .ogg looped from that point, for checking the seam.

const FPS := 50

var _frames_left := 0
var _player: AudioStreamPlayer


func _ready() -> void:
	var args := _user_args()
	var stream: AudioStream = null
	var path := ""
	if args.has("ogg"):
		path = String(args["ogg"])
		if FileAccess.file_exists(path):
			var ogg := AudioStreamOggVorbis.load_from_file(path)
			if ogg != null and args.has("loop-offset"):
				ogg.loop = true
				ogg.loop_offset = float(args["loop-offset"])
			stream = ogg
	elif args.has("wav"):
		path = String(args["wav"])
		if FileAccess.file_exists(path):
			stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		printerr("[OggRender] could not load '%s'" % path)
		get_tree().quit(2)
		return
	var seconds := float(args.get("seconds", "0"))
	if seconds <= 0.0:
		seconds = stream.get_length()
	_frames_left = int(ceil(seconds * FPS)) + int(args.get("tail-frames", "10"))
	if args.has("frames"):
		_frames_left = int(args["frames"])
	print("[OggRender] length %.6f %s" % [stream.get_length(), stream.get_class()])
	print("[OggRender] %s  render %.3f s  mix %d Hz  %d frames" % [path.get_file(), seconds, AudioServer.get_mix_rate(), _frames_left])
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = &"Master"
	add_child(_player)
	_player.play()


func _process(_delta: float) -> void:
	if _frames_left <= 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		# Don't stop the player: this frame's audio is mixed after _process.
		get_tree().quit()


func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return out
