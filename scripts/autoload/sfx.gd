extends Node
## Autoload "Sfx": tiny sound manager with separate SFX/Music buses, a pool
## of players, and per-sound rate limiting so a busy factory never turns
## into a wall of noise.

const SOUNDS := {
	"click": preload("res://assets/audio/click.wav"),
	"sale": preload("res://assets/audio/sale.wav"),
	"buy": preload("res://assets/audio/buy.wav"),
	"deny": preload("res://assets/audio/deny.wav"),
	"fanfare": preload("res://assets/audio/fanfare.wav"),
	"thunk": preload("res://assets/audio/thunk.wav"),
	"blip": preload("res://assets/audio/blip.wav"),
}
const MUSIC := preload("res://assets/audio/music.ogg")
const MIN_INTERVAL := {"click": 0.04, "sale": 0.12, "thunk": 0.1}
const POOL_SIZE := 10

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _music: AudioStreamPlayer


func _ready() -> void:
	for bus_name: String in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	var stream: AudioStreamOggVorbis = MUSIC
	stream.loop = true
	_music.stream = stream
	_music.volume_db = -8.0
	add_child(_music)
	apply_settings()
	_music.play()


func apply_settings() -> void:
	var settings: Dictionary = Game.session.state.settings
	_set_bus("SFX", float(settings.get("sfx_volume", 0.8)))
	_set_bus("Music", float(settings.get("music_volume", 0.4)))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(idx, linear <= 0.005)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.005, 1.0)))


func play(sound: String, pitch_variation: float = 0.0, volume_db: float = 0.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -10.0)) < float(MIN_INTERVAL.get(sound, 0.0)):
		return
	_last_played[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = SOUNDS[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.volume_db = volume_db
	p.play()


func _exit_tree() -> void:
	_music.stop()
	_music.stream = null
