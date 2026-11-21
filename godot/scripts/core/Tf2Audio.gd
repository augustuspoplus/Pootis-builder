class_name Tf2Audio
extends Node

## Milestone 23 — Clean, Pleasant TF2 UI & Editor Sound Notifications!
## Polyphonic 4-voice AudioStreamPlayer pool with balanced Valve TF2 VPK UI cues
## and soft procedural chime fallbacks (zero loud guitar blares or harsh beeps).

var core: Object
var muted: bool = false
var master_db: float = -8.0
var _streams: Dictionary = {} # key -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _voice_idx: int = 0

const SFX_MAP := {
	"click":    "sound/ui/buttonclick.wav",
	"release":  "sound/ui/buttonclickrelease.wav",
	"hover":    "sound/ui/buttonrollover.wav",
	"place":    "sound/ui/buttonclickrelease.wav",
	"carve":    "sound/ui/cyoa_node_activate.wav",
	"undo":     "sound/ui/panel_close.wav",
	"redo":     "sound/ui/panel_open.wav",
	"delete":   "sound/ui/item_discard.wav",
	"save":     "sound/ui/chat_display_text.wav",
	"notify":   "sound/ui/chat_display_text.wav",
	"warn":     "sound/common/wpn_denyselect.wav",
	"success":  "sound/ui/notification_alert.wav",
	"medkit":   "sound/items/medshot4.wav",
	"rocket":   "sound/weapons/rocket_shoot.wav",
	"explode":  "sound/weapons/explode1.wav",
}

const DEFAULT_DB := {
	"click":   -12.0,
	"hover":   -18.0,
	"place":   -10.0,
	"carve":   -11.0,
	"undo":    -11.0,
	"redo":    -11.0,
	"delete":  -12.0,
	"save":    -10.0,
	"notify":  -12.0,
	"warn":    -11.0,
	"success": -10.0,
}

func setup(p_core: Object) -> void:
	core = p_core
	if _players.is_empty():
		for i in range(4):
			var p := AudioStreamPlayer.new()
			p.volume_db = master_db
			add_child(p)
			_players.append(p)

func set_volume(db: float, is_muted: bool) -> void:
	master_db = clampf(db, -36.0, 0.0)
	muted = is_muted
	for p in _players:
		p.volume_db = master_db

func play(sfx_key: String, volume_db: float = -999.0) -> void:
	if muted or _players.is_empty():
		return
	var stream: AudioStreamWAV = _get_stream(sfx_key)
	if stream == null:
		return
	var target_db: float = float(DEFAULT_DB.get(sfx_key, -10.0)) if volume_db < -100.0 else volume_db
	var p: AudioStreamPlayer = _players[_voice_idx]
	_voice_idx = (_voice_idx + 1) % _players.size()
	p.volume_db = minf(target_db, master_db)
	p.pitch_scale = randf_range(0.97, 1.03) if sfx_key in ["click", "place"] else 1.0
	p.stream = stream
	p.play()

func _get_stream(sfx_key: String) -> AudioStreamWAV:
	if _streams.has(sfx_key):
		return _streams[sfx_key]
	var wav: AudioStreamWAV = null
	if core != null:
		var vpk_path: String = SFX_MAP.get(sfx_key, sfx_key)
		var raw: PackedByteArray = core.read_sound_bytes(vpk_path)
		if raw.size() >= 44:
			wav = _parse_wav(raw)
	# Crisp, pleasant procedural UI tone fallback so undo/redo/save/warn/success ALWAYS sound great!
	if wav == null:
		wav = _make_synth_cue(sfx_key)
	_streams[sfx_key] = wav
	return wav

static func _make_synth_cue(sfx_key: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.11
	var f0 := 520.0
	var f1 := 520.0
	match sfx_key:
		"undo":    dur = 0.12; f0 = 520.0; f1 = 360.0
		"redo":    dur = 0.12; f0 = 380.0; f1 = 560.0
		"save":    dur = 0.15; f0 = 587.0; f1 = 880.0
		"success": dur = 0.22; f0 = 523.0; f1 = 784.0
		"delete":  dur = 0.10; f0 = 300.0; f1 = 170.0
		"warn":    dur = 0.16; f0 = 260.0; f1 = 210.0
		"carve":   dur = 0.09; f0 = 420.0; f1 = 620.0
		"place":   dur = 0.07; f0 = 440.0; f1 = 520.0
		_:         dur = 0.05; f0 = 640.0; f1 = 600.0
	var n := int(float(rate) * dur)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var env := sin(minf(t * 8.0, 1.0) * PI * 0.5) * pow(1.0 - t, 1.8)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(rate)
		var s := sin(phase) * 0.65 + sin(phase * 2.0) * 0.18
		var v := clampi(int(s * env * 12000.0), -32767, 32767)
		pcm.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.data = pcm
	wav.mix_rate = rate
	wav.stereo = false
	wav.format = AudioStreamWAV.FORMAT_16_BITS
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
