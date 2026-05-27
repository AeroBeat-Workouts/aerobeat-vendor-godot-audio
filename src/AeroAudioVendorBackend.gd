class_name AeroAudioVendorBackend
extends RefCounted

const CoreContract := preload("AeroAudioPlaybackContract.gd")

func load(_source: Dictionary) -> Dictionary:
	return _unsupported("load")

func unload() -> Dictionary:
	return _unsupported("unload")

func play() -> Dictionary:
	return _unsupported("play")

func pause() -> Dictionary:
	return _unsupported("pause")

func resume() -> Dictionary:
	return play()

func stop() -> Dictionary:
	return _unsupported("stop")

func set_volume_db(_volume_db: float) -> Dictionary:
	return _unsupported("set_volume_db")

func set_loop(_enabled: bool) -> Dictionary:
	return _unsupported("set_loop")

func seek(_seconds: float) -> Dictionary:
	return _unsupported("seek")

func get_state() -> Dictionary:
	return CoreContract.build_state_snapshot()

func get_position() -> float:
	return float(get_state().get("position", 0.0))

func get_duration() -> float:
	return float(get_state().get("duration", 0.0))

func get_media_info() -> Dictionary:
	return {}

func attach_surface(_node: Node) -> Dictionary:
	return _unsupported("attach_surface")

func detach_surface() -> Dictionary:
	return _unsupported("detach_surface")

func get_last_error() -> Dictionary:
	return {}

func _unsupported(method_name: String) -> Dictionary:
	return CoreContract.fail(
		"backend_method_unimplemented",
		"%s is not implemented on this backend." % method_name,
		{"method": method_name}
	)
