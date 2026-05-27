class_name AeroAudioPlaybackManager
extends Node

const AeroAudioPlaybackContract := preload("AeroAudioPlaybackContract.gd")
const AeroAudioOperationScript := preload("AeroAudioOperation.gd")
const BackendInterfaceScript := preload("AeroAudioVendorBackend.gd")
const DefaultBackendScript := preload("AeroGodotAudioBackend.gd")

signal initialized
signal state_changed(state: String, detail: Dictionary)
signal position_changed(seconds: float, normalized: float)
signal media_loaded(info: Dictionary)
signal playback_finished
signal error_raised(error_info: Dictionary)

const VERSION: String = "0.2.0"

enum PlaybackState {
	IDLE,
	LOADING,
	READY,
	PLAYING,
	PAUSED,
	STOPPING,
	ERROR,
}

const STATE_IDLE := AeroAudioPlaybackContract.STATE_IDLE
const STATE_LOADING := AeroAudioPlaybackContract.STATE_LOADING
const STATE_READY := AeroAudioPlaybackContract.STATE_READY
const STATE_PLAYING := AeroAudioPlaybackContract.STATE_PLAYING
const STATE_PAUSED := AeroAudioPlaybackContract.STATE_PAUSED
const STATE_STOPPING := AeroAudioPlaybackContract.STATE_STOPPING
const STATE_ERROR := AeroAudioPlaybackContract.STATE_ERROR
const STATE_NAMES := {
	PlaybackState.IDLE: STATE_IDLE,
	PlaybackState.LOADING: STATE_LOADING,
	PlaybackState.READY: STATE_READY,
	PlaybackState.PLAYING: STATE_PLAYING,
	PlaybackState.PAUSED: STATE_PAUSED,
	PlaybackState.STOPPING: STATE_STOPPING,
	PlaybackState.ERROR: STATE_ERROR,
}

@export var is_active: bool = true

var _is_initialized: bool = false
var _backend: AeroAudioVendorBackend
var _backend_name: String = ""
var _state_name: String = STATE_IDLE
var _state_code: int = PlaybackState.IDLE
var _loaded_source: Dictionary = {}
var _media_info: Dictionary = {}
var _last_error: Dictionary = {}
var _has_loaded_media: bool = false
var _surface: Node = null

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	if _is_initialized:
		return
	if _backend == null:
		set_backend(DefaultBackendScript.new())
	_is_initialized = true
	initialized.emit()

func set_backend(backend: AeroAudioVendorBackend) -> void:
	if backend == null:
		backend = DefaultBackendScript.new()
	_backend = backend
	_backend_name = backend.get_script().resource_path.get_file().trim_suffix(".gd") if backend.get_script() != null else "custom_backend"
	if _surface != null and _backend.has_method("attach_surface"):
		_backend.attach_surface(_surface)

func get_backend() -> AeroAudioVendorBackend:
	_initialize()
	return _backend

func create_default_backend() -> AeroAudioVendorBackend:
	return DefaultBackendScript.new()

func get_default_source_config() -> Dictionary:
	return AeroAudioPlaybackContract.get_default_source_config()

func normalize_source(source: Dictionary) -> Dictionary:
	if _backend != null and _backend.has_method("normalize_source"):
		return _backend.call("normalize_source", source)
	return AeroAudioPlaybackContract.normalize_source(source)

func can_load_source(source: Dictionary) -> bool:
	return _validate_source(normalize_source(source)).is_empty()

func load(source: Dictionary) -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not is_active:
		return operation.settle_failure(_raise_error(AeroAudioPlaybackContract.ERROR_NOT_READY, "AeroAudioPlaybackManager is inactive.", {"source": source.duplicate(true)}, true))
	var normalized := normalize_source(source)
	var validation_error := _validate_source(normalized)
	if not validation_error.is_empty():
		return operation.settle_failure(_raise_error(AeroAudioPlaybackContract.ERROR_INVALID_SOURCE, validation_error.get("message", "Invalid audio source."), validation_error, true))
	_transition_state(PlaybackState.LOADING, {"source": normalized.duplicate(true)})
	var result := _backend.load(normalized)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to load media."))
	_loaded_source = normalized.duplicate(true)
	_media_info = _backend.get_media_info()
	_has_loaded_media = true
	_transition_state(PlaybackState.READY, {
		"source": _loaded_source.duplicate(true),
		"media_info": _media_info.duplicate(true),
	})
	media_loaded.emit(_media_info.duplicate(true))
	if float(_loaded_source.get("start_time", 0.0)) > 0.0:
		seek(float(_loaded_source.get("start_time", 0.0)))
	_emit_position_changed(_backend.get_position(), _backend.get_duration())
	if bool(_loaded_source.get("autoplay", false)):
		play()
	return operation.settle_success({
		"source": _loaded_source.duplicate(true),
		"media_info": _media_info.duplicate(true),
		"state": _state_name,
	})

func unload() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var result := _backend.unload()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to unload media."))
	_loaded_source = {}
	_media_info = {}
	_last_error = {}
	_has_loaded_media = false
	_transition_state(PlaybackState.IDLE)
	_emit_position_changed(0.0, 0.0)
	return operation.settle_success({"state": _state_name})

func play() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not _ensure_loaded("Cannot play before media has been loaded.", operation):
		return operation
	var result := _backend.play()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to start playback."))
	_transition_state(PlaybackState.PLAYING, {"source": _loaded_source.duplicate(true)})
	return operation.settle_success({"state": _state_name})

func pause() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not _ensure_loaded("Cannot pause before media has been loaded.", operation):
		return operation
	var result := _backend.pause()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to pause playback."))
	_transition_state(PlaybackState.PAUSED, {"source": _loaded_source.duplicate(true)})
	_emit_position_changed(_backend.get_position(), _backend.get_duration())
	return operation.settle_success({"state": _state_name, "position": _backend.get_position()})

func resume() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not _ensure_loaded("Cannot resume before media has been loaded.", operation):
		return operation
	var result := _backend.resume()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to resume playback."))
	_transition_state(PlaybackState.PLAYING, {"source": _loaded_source.duplicate(true)})
	return operation.settle_success({"state": _state_name, "position": _backend.get_position()})

func stop() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not _ensure_loaded("Cannot stop before media has been loaded.", operation):
		return operation
	_transition_state(PlaybackState.STOPPING, {"source": _loaded_source.duplicate(true)})
	var result := _backend.stop()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to stop playback."))
	_transition_state(PlaybackState.READY, {"source": _loaded_source.duplicate(true)})
	_emit_position_changed(_backend.get_position(), _backend.get_duration())
	return operation.settle_success({"state": _state_name, "position": _backend.get_position()})

func seek(seconds: float) -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not _ensure_loaded("Cannot seek before media has been loaded.", operation):
		return operation
	var result := _backend.seek(seconds)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to seek playback."))
	_emit_position_changed(_backend.get_position(), _backend.get_duration())
	return operation.settle_success({"state": _state_name, "position": _backend.get_position()})

func set_volume_db(volume_db: float) -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var result := _backend.set_volume_db(volume_db)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to update volume."))
	var detail := get_state()
	detail["volume_db"] = volume_db
	state_changed.emit(_state_name, detail)
	return operation.settle_success({"state": _state_name, "volume_db": volume_db})

func get_state() -> Dictionary:
	_initialize()
	var backend_state: Dictionary = _backend.get_state() if _backend != null else {}
	return AeroAudioPlaybackContract.build_state_snapshot({
		"state": _state_name,
		"state_code": _state_code,
		"source": _loaded_source.duplicate(true),
		"media_info": _media_info.duplicate(true),
		"position": get_position(),
		"duration": get_duration(),
		"volume_db": float(backend_state.get("volume_db", _loaded_source.get("volume_db", 0.0))),
		"surface_attached": bool(backend_state.get("surface_attached", _surface != null)),
		"backend": _backend_name,
		"last_error": _last_error.duplicate(true),
		"media_loaded": _has_loaded_media,
	})

func get_duration() -> float:
	_initialize()
	if not _has_loaded_media:
		return 0.0
	return _backend.get_duration() if _backend != null else 0.0

func get_position() -> float:
	_initialize()
	if not _has_loaded_media:
		return 0.0
	return _backend.get_position() if _backend != null else 0.0

func get_media_info() -> Dictionary:
	_initialize()
	return _media_info.duplicate(true)

func attach_surface(node: Node) -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if node == null:
		return operation.settle_failure(_raise_error(AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Cannot attach a null output surface.", {}, true))
	_surface = node
	var result := _backend.attach_surface(node)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Backend rejected the output surface."))
	var detail := get_state()
	detail["surface_path"] = str(node.get_path()) if node.is_inside_tree() else node.name
	state_changed.emit(_state_name, detail)
	return operation.settle_success(detail)

func detach_surface() -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	_surface = null
	var result := _backend.detach_surface()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result(result, AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Backend failed to detach the output surface."))
	var detail := get_state()
	detail["surface_path"] = ""
	state_changed.emit(_state_name, detail)
	return operation.settle_success(detail)

func get_last_error() -> Dictionary:
	return _last_error.duplicate(true)

func listen_for_state(callback: Callable, emit_immediately: bool = true) -> void:
	if callback.is_valid() and not state_changed.is_connected(callback):
		state_changed.connect(callback)
	if emit_immediately and callback.is_valid():
		callback.call(_state_name, get_state())

func stop_listening_for_state(callback: Callable) -> void:
	if callback.is_valid() and state_changed.is_connected(callback):
		state_changed.disconnect(callback)

func _validate_source(source: Dictionary) -> Dictionary:
	if _backend != null and _backend.has_method("validate_source"):
		return _backend.call("validate_source", source)
	return AeroAudioPlaybackContract.validate_source(source)

func _ensure_loaded(message: String, operation: AeroAudioOperation) -> bool:
	if not _has_loaded_media:
		operation.settle_failure(_raise_error(AeroAudioPlaybackContract.ERROR_NOT_READY, message, {}, true))
		return false
	return true

func _transition_state(state_code: int, detail: Dictionary = {}) -> void:
	_state_code = state_code
	_state_name = STATE_NAMES.get(state_code, STATE_IDLE)
	var payload := detail.duplicate(true)
	payload["state"] = _state_name
	state_changed.emit(_state_name, payload)
	if _state_name == STATE_READY and _has_loaded_media and get_duration() > 0.0 and is_equal_approx(get_position(), get_duration()):
		playback_finished.emit()

func _emit_position_changed(seconds: float, duration: float) -> void:
	var normalized := 0.0
	if duration > 0.0:
		normalized = clampf(seconds / duration, 0.0, 1.0)
	position_changed.emit(seconds, normalized)

func _apply_result(result: Dictionary, fallback_code: String, fallback_message: String) -> Dictionary:
	if bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		_last_error = {}
		return {}
	return _raise_error(
		String(result.get(AeroAudioPlaybackContract.RESULT_CODE, fallback_code)),
		String(result.get(AeroAudioPlaybackContract.RESULT_MESSAGE, fallback_message)),
		result.get(AeroAudioPlaybackContract.RESULT_DETAIL, {}),
		true
	)

func _raise_error(code: String, message: String, detail: Variant = {}, transition_to_error: bool = true) -> Dictionary:
	var safe_detail: Dictionary = detail if typeof(detail) == TYPE_DICTIONARY else {"value": detail}
	_last_error = {
		"code": code,
		"message": message,
		"detail": safe_detail.duplicate(true),
		"state": _state_name,
	}
	if transition_to_error:
		_transition_state(PlaybackState.ERROR, _last_error.duplicate(true))
	error_raised.emit(_last_error.duplicate(true))
	return _last_error.duplicate(true)
