extends Node

signal finished

var stream: Resource = null
var volume_db: float = 0.0
var stream_paused: bool = false
var autoplay: bool = false
var _position: float = 0.0
var _playing: bool = false

func play(from_position: float = 0.0) -> void:
	_position = maxf(0.0, from_position)
	_playing = true
	stream_paused = false

func stop() -> void:
	_position = 0.0
	_playing = false
	stream_paused = false

func seek(to_position: float) -> void:
	_position = maxf(0.0, to_position)

func get_playback_position() -> float:
	return _position

func is_playing() -> bool:
	return _playing and not stream_paused

func playing() -> bool:
	return is_playing()

func emit_finished() -> void:
	_playing = false
	stream_paused = false
	finished.emit()
