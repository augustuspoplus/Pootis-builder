class_name Tf2Audio
extends Node

## Milestone 10 — Authentic Valve TF2 UI & Gameplay Sound Effects streamed directly
## from tf2_sound_misc_dir.vpk via Tf2Core.read_sound_bytes()!

var core: Object
var muted: bool = false
var _streams: Dictionary = {} # key -> AudioStreamWAV
var _player: AudioStreamPlayer

const SFX_MAP := {
	"click":    "sound/ui/buttonclick.wav",
	"release":  "sound/ui/buttonclickrelease.wav",
	"hover":    "sound/ui/buttonrollover.wav",
	"place":    "sound/buttons/button9.wav",
	"carve":    "sound/buttons/lever7.wav",
	"medkit":   "sound/items/medshot4.wav",
	"success":  "sound/misc/achievement_earned.wav",
	"rocket":   "sound/weapons/rocket_shoot.wav",
	"explode":  "sound/weapons/explode1.wav",
}

func setup(p_core: Object) -> void:
	core = p_core
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.volume_db = -8.0
		add_child(_player)

func play(sfx_key: String, volume_db: float = -8.0) -> void:
	if muted or core == null or _player == null:
		return
	var stream: AudioStreamWAV = _get_stream(sfx_key)
	if stream == null:
		return
	_player.volume_db = volume_db
	_player.stream = stream
	_player.play()

func _get_stream(sfx_key: String) -> AudioStreamWAV:
	if _streams.has(sfx_key):
		return _streams[sfx_key]
	var vpk_path: String = SFX_MAP.get(sfx_key, sfx_key)
	var raw: PackedByteArray = core.read_sound_bytes(vpk_path)
	if raw.size() < 44:
		_streams[sfx_key] = null
		return null
	var wav := _parse_wav(raw)
	_streams[sfx_key] = wav
	return wav

static func _parse_wav(raw: PackedByteArray) -> AudioStreamWAV:
	# Minimal RIFF/WAVE PCM parser (8-bit or 16-bit mono/stereo)
	if raw.size() < 44:
		return null
	if raw.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := 1
	var sample_rate := 22050
	var bits := 16
	var pcm := PackedByteArray()
	var pos := 12
	while pos + 8 <= raw.size():
		var cid := raw.slice(pos, pos + 4).get_string_from_ascii()
		var csz := raw.decode_u32(pos + 4)
		pos += 8
		if cid == "fmt " and pos + 16 <= raw.size():
			var fmt_code := raw.decode_u16(pos)
			channels = raw.decode_u16(pos + 2)
			sample_rate = raw.decode_u32(pos + 4)
			bits = raw.decode_u16(pos + 14)
			if fmt_code != 1:
				return null
		elif cid == "data":
			var end: int = mini(raw.size(), pos + csz)
			pcm = raw.slice(pos, end)
			break
		pos += csz + (csz & 1)
	if pcm.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.data = pcm
	wav.mix_rate = sample_rate
	wav.stereo = (channels >= 2)
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	return wav
