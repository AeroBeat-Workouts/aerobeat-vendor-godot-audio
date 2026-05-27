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
signal slot_state_changed(slot_name: String, state: String, detail: Dictionary)
signal slot_position_changed(slot_name: String, seconds: float, normalized: float)
signal slot_media_loaded(slot_name: String, info: Dictionary)
signal slot_playback_finished(slot_name: String)
signal slot_error_raised(slot_name: String, error_info: Dictionary)

const VERSION: String = "0.3.0"
const DEFAULT_SLOT := "primary"

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
var _backend_factory: Callable = Callable()
var _active_slot: String = DEFAULT_SLOT
var _slots: Dictionary = {}

func _ready() -> void:
	_initialize()

func _initialize() -> void:
	if _is_initialized:
		return
	_ensure_slot(DEFAULT_SLOT)
	_is_initialized = true
	initialized.emit()

func set_backend(backend: AeroAudioVendorBackend) -> void:
	_initialize()
	var slot_name := DEFAULT_SLOT
	if backend == null:
		backend = create_default_backend()
	var session := _ensure_slot(slot_name)
	session["backend"] = backend
	session["backend_name"] = _resolve_backend_name(backend)
	_slots[slot_name] = session
	var surface: Node = session.get("surface", null)
	if surface != null and backend.has_method("attach_surface"):
		backend.attach_surface(surface)

func set_backend_factory(factory: Callable) -> void:
	_backend_factory = factory

func get_backend(slot_name: String = DEFAULT_SLOT) -> AeroAudioVendorBackend:
	_initialize()
	var session := _ensure_slot(slot_name)
	return session.get("backend", null)

func create_default_backend() -> AeroAudioVendorBackend:
	if _backend_factory.is_valid():
		var created: Variant = _backend_factory.call()
		if created is AeroAudioVendorBackend:
			return created
	return DefaultBackendScript.new()

func get_default_source_config() -> Dictionary:
	var config := AeroAudioPlaybackContract.get_default_source_config()
	config["slot"] = DEFAULT_SLOT
	return config

func normalize_source(source: Dictionary) -> Dictionary:
	var working_source := source.duplicate(true)
	working_source["slot"] = _resolve_slot_from_source(source)
	var slot_name := str(working_source.get("slot", DEFAULT_SLOT))
	var session := _ensure_slot(slot_name)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var normalized: Dictionary = backend.call("normalize_source", working_source) if backend != null and backend.has_method("normalize_source") else AeroAudioPlaybackContract.normalize_source(working_source)
	normalized["slot"] = slot_name
	return normalized

func can_load_source(source: Dictionary) -> bool:
	return _validate_source(normalize_source(source)).is_empty()

func set_active_slot(slot_name: String) -> Dictionary:
	_initialize()
	_active_slot = _normalize_slot_name(slot_name)
	_ensure_slot(_active_slot)
	return {"slot": _active_slot}

func get_active_slot() -> String:
	_initialize()
	return _active_slot

func get_slot_names() -> PackedStringArray:
	_initialize()
	var slot_names: Array[String] = []
	for slot_name in _slots.keys():
		slot_names.append(str(slot_name))
	slot_names.sort()
	return PackedStringArray(slot_names)

func attach_slot_surface(slot_name: String, node: Node) -> AeroAudioOperation:
	return attach_surface(node, slot_name)

func detach_slot_surface(slot_name: String = "") -> AeroAudioOperation:
	return detach_surface(slot_name)

func load(source: Dictionary, slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if not is_active:
		return operation.settle_failure(_raise_error_for_slot(_resolve_slot_name(slot_name, source), AeroAudioPlaybackContract.ERROR_NOT_READY, "AeroAudioPlaybackManager is inactive.", {"source": source.duplicate(true)}, true))
	var resolved_slot := _resolve_slot_name(slot_name, source)
	var session := _ensure_slot(resolved_slot)
	var normalized := normalize_source(_with_slot(source, resolved_slot))
	var validation_error := _validate_source(normalized)
	if not validation_error.is_empty():
		return operation.settle_failure(_raise_error_for_slot(resolved_slot, AeroAudioPlaybackContract.ERROR_INVALID_SOURCE, validation_error.get("message", "Invalid audio source."), validation_error, true))
	_transition_state_for_slot(resolved_slot, PlaybackState.LOADING, {"source": normalized.duplicate(true)})
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.load(normalized)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to load media."))
	session["loaded_source"] = normalized.duplicate(true)
	session["media_info"] = backend.get_media_info()
	session["has_loaded_media"] = true
	session["last_error"] = {}
	_slots[resolved_slot] = session
	_apply_result_for_slot(resolved_slot, backend.set_loop(bool(normalized.get("loop", false))), AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to update loop mode.")
	if _slot_state_name(resolved_slot) == STATE_ERROR:
		return operation.settle_failure(get_last_error(resolved_slot))
	_transition_state_for_slot(resolved_slot, PlaybackState.READY, {
		"source": session.get("loaded_source", {}).duplicate(true),
		"media_info": session.get("media_info", {}).duplicate(true),
	})
	var loaded_info: Dictionary = session.get("media_info", {}).duplicate(true)
	loaded_info["slot"] = resolved_slot
	if resolved_slot == _active_slot:
		media_loaded.emit(loaded_info.duplicate(true))
	slot_media_loaded.emit(resolved_slot, loaded_info.duplicate(true))
	if float(normalized.get("start_time", 0.0)) > 0.0:
		seek(float(normalized.get("start_time", 0.0)), resolved_slot)
	else:
		_emit_position_changed_for_slot(resolved_slot, backend.get_position(), backend.get_duration())
	if bool(normalized.get("autoplay", false)):
		play(resolved_slot)
	return operation.settle_success({
		"slot": resolved_slot,
		"source": session.get("loaded_source", {}).duplicate(true),
		"media_info": session.get("media_info", {}).duplicate(true),
		"state": _slot_state_name(resolved_slot),
	})

func unload(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.unload()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to unload media."))
	session["loaded_source"] = {}
	session["media_info"] = {}
	session["last_error"] = {}
	session["has_loaded_media"] = false
	_slots[resolved_slot] = session
	_transition_state_for_slot(resolved_slot, PlaybackState.IDLE)
	_emit_position_changed_for_slot(resolved_slot, 0.0, 0.0)
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot)})

func play(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	if not _ensure_loaded_for_slot(resolved_slot, "Cannot play before media has been loaded.", operation):
		return operation
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.play()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to start playback."))
	_transition_state_for_slot(resolved_slot, PlaybackState.PLAYING, {"source": session.get("loaded_source", {}).duplicate(true)})
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot)})

func pause(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	if not _ensure_loaded_for_slot(resolved_slot, "Cannot pause before media has been loaded.", operation):
		return operation
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.pause()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to pause playback."))
	_transition_state_for_slot(resolved_slot, PlaybackState.PAUSED, {"source": session.get("loaded_source", {}).duplicate(true)})
	_emit_position_changed_for_slot(resolved_slot, backend.get_position(), backend.get_duration())
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "position": backend.get_position()})

func resume(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	if not _ensure_loaded_for_slot(resolved_slot, "Cannot resume before media has been loaded.", operation):
		return operation
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.resume()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to resume playback."))
	_transition_state_for_slot(resolved_slot, PlaybackState.PLAYING, {"source": session.get("loaded_source", {}).duplicate(true)})
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "position": backend.get_position()})

func stop(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	if not _ensure_loaded_for_slot(resolved_slot, "Cannot stop before media has been loaded.", operation):
		return operation
	var session := _ensure_slot(resolved_slot)
	_transition_state_for_slot(resolved_slot, PlaybackState.STOPPING, {"source": session.get("loaded_source", {}).duplicate(true)})
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.stop()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to stop playback."))
	_transition_state_for_slot(resolved_slot, PlaybackState.READY, {"source": session.get("loaded_source", {}).duplicate(true)})
	_emit_position_changed_for_slot(resolved_slot, backend.get_position(), backend.get_duration())
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "position": backend.get_position()})

func seek(seconds: float, slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	if not _ensure_loaded_for_slot(resolved_slot, "Cannot seek before media has been loaded.", operation):
		return operation
	var backend: AeroAudioVendorBackend = get_backend(resolved_slot)
	var result := backend.seek(seconds)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to seek playback."))
	_emit_position_changed_for_slot(resolved_slot, backend.get_position(), backend.get_duration())
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "position": backend.get_position()})

func set_volume_db(volume_db: float, slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.set_volume_db(volume_db)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to update volume."))
	var source: Dictionary = session.get("loaded_source", {}).duplicate(true)
	source["volume_db"] = volume_db
	session["loaded_source"] = source
	_slots[resolved_slot] = session
	var detail := get_state(resolved_slot)
	_state_changed_for_slot(resolved_slot, detail)
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "volume_db": volume_db})

func set_loop(enabled: bool, slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	var source: Dictionary = session.get("loaded_source", {}).duplicate(true)
	if source.is_empty():
		source = get_default_source_config()
		source["slot"] = resolved_slot
	source["loop"] = enabled
	session["loaded_source"] = source
	_slots[resolved_slot] = session
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.set_loop(enabled)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_BACKEND_REJECTED, "Backend failed to update loop mode."))
	var detail := get_state(resolved_slot)
	_state_changed_for_slot(resolved_slot, detail)
	return operation.settle_success({"slot": resolved_slot, "state": _slot_state_name(resolved_slot), "loop": enabled})

func get_state(slot_name: String = "") -> Dictionary:
	_initialize()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var backend_state: Dictionary = backend.get_state() if backend != null else {}
	return AeroAudioPlaybackContract.build_state_snapshot({
		"slot": resolved_slot,
		"active_slot": _active_slot,
		"slot_names": get_slot_names(),
		"state": _slot_state_name(resolved_slot),
		"state_code": int(session.get("state_code", PlaybackState.IDLE)),
		"source": session.get("loaded_source", {}).duplicate(true),
		"media_info": session.get("media_info", {}).duplicate(true),
		"position": get_position(resolved_slot),
		"duration": get_duration(resolved_slot),
		"loop": bool(backend_state.get("loop", session.get("loaded_source", {}).get("loop", false))),
		"volume_db": float(backend_state.get("volume_db", session.get("loaded_source", {}).get("volume_db", 0.0))),
		"surface_attached": bool(backend_state.get("surface_attached", session.get("surface", null) != null)),
		"backend": str(session.get("backend_name", "")),
		"last_error": session.get("last_error", {}).duplicate(true),
		"media_loaded": bool(session.get("has_loaded_media", false)),
	})

func get_slot_state(slot_name: String) -> Dictionary:
	return get_state(slot_name)

func get_duration(slot_name: String = "") -> float:
	_initialize()
	var session := _ensure_slot(_resolve_slot_name(slot_name))
	if not bool(session.get("has_loaded_media", false)):
		return 0.0
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	return backend.get_duration() if backend != null else 0.0

func get_position(slot_name: String = "") -> float:
	_initialize()
	var session := _ensure_slot(_resolve_slot_name(slot_name))
	if not bool(session.get("has_loaded_media", false)):
		return 0.0
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	return backend.get_position() if backend != null else 0.0

func get_media_info(slot_name: String = "") -> Dictionary:
	_initialize()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	var info: Dictionary = session.get("media_info", {}).duplicate(true)
	info["slot"] = resolved_slot
	return info

func attach_surface(node: Node, slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	if node == null:
		return operation.settle_failure(_raise_error_for_slot(_resolve_slot_name(slot_name), AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Cannot attach a null output surface.", {}, true))
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	session["surface"] = node
	_slots[resolved_slot] = session
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.attach_surface(node)
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Backend rejected the output surface."))
	var detail := get_state(resolved_slot)
	detail["surface_path"] = str(node.get_path()) if node.is_inside_tree() else node.name
	_state_changed_for_slot(resolved_slot, detail)
	return operation.settle_success(detail)

func detach_surface(slot_name: String = "") -> AeroAudioOperation:
	_initialize()
	var operation := AeroAudioOperationScript.new()
	var resolved_slot := _resolve_slot_name(slot_name)
	var session := _ensure_slot(resolved_slot)
	session["surface"] = null
	_slots[resolved_slot] = session
	var backend: AeroAudioVendorBackend = session.get("backend", null)
	var result := backend.detach_surface()
	if not bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		return operation.settle_failure(_apply_result_for_slot(resolved_slot, result, AeroAudioPlaybackContract.ERROR_INVALID_SURFACE, "Backend failed to detach the output surface."))
	var detail := get_state(resolved_slot)
	detail["surface_path"] = ""
	_state_changed_for_slot(resolved_slot, detail)
	return operation.settle_success(detail)

func get_last_error(slot_name: String = "") -> Dictionary:
	var session := _ensure_slot(_resolve_slot_name(slot_name))
	return session.get("last_error", {}).duplicate(true)

func listen_for_state(callback: Callable, emit_immediately: bool = true) -> void:
	if callback.is_valid() and not state_changed.is_connected(callback):
		state_changed.connect(callback)
	if emit_immediately and callback.is_valid():
		callback.call(_slot_state_name(_active_slot), get_state())

func stop_listening_for_state(callback: Callable) -> void:
	if callback.is_valid() and state_changed.is_connected(callback):
		state_changed.disconnect(callback)

func _validate_source(source: Dictionary) -> Dictionary:
	var backend: AeroAudioVendorBackend = get_backend(str(source.get("slot", DEFAULT_SLOT)))
	if backend != null and backend.has_method("validate_source"):
		return backend.call("validate_source", source)
	return AeroAudioPlaybackContract.validate_source(source)

func _ensure_loaded_for_slot(slot_name: String, message: String, operation: AeroAudioOperation) -> bool:
	var session := _ensure_slot(slot_name)
	if not bool(session.get("has_loaded_media", false)):
		operation.settle_failure(_raise_error_for_slot(slot_name, AeroAudioPlaybackContract.ERROR_NOT_READY, message, {}, true))
		return false
	return true

func _transition_state_for_slot(slot_name: String, state_code: int, detail: Dictionary = {}) -> void:
	var session := _ensure_slot(slot_name)
	session["state_code"] = state_code
	session["state_name"] = STATE_NAMES.get(state_code, STATE_IDLE)
	_slots[slot_name] = session
	var payload := detail.duplicate(true)
	payload["slot"] = slot_name
	payload["state"] = str(session.get("state_name", STATE_IDLE))
	_state_changed_for_slot(slot_name, payload)
	if payload["state"] == STATE_READY and bool(session.get("has_loaded_media", false)) and get_duration(slot_name) > 0.0 and is_equal_approx(get_position(slot_name), get_duration(slot_name)) and not bool(get_state(slot_name).get("loop", false)):
		if slot_name == _active_slot:
			playback_finished.emit()
		slot_playback_finished.emit(slot_name)

func _emit_position_changed_for_slot(slot_name: String, seconds: float, duration: float) -> void:
	var normalized := 0.0
	if duration > 0.0:
		normalized = clampf(seconds / duration, 0.0, 1.0)
	if slot_name == _active_slot:
		position_changed.emit(seconds, normalized)
	slot_position_changed.emit(slot_name, seconds, normalized)

func _apply_result_for_slot(slot_name: String, result: Dictionary, fallback_code: String, fallback_message: String) -> Dictionary:
	if bool(result.get(AeroAudioPlaybackContract.RESULT_SUCCESS, false)):
		var session := _ensure_slot(slot_name)
		session["last_error"] = {}
		_slots[slot_name] = session
		return {}
	return _raise_error_for_slot(
		slot_name,
		String(result.get(AeroAudioPlaybackContract.RESULT_CODE, fallback_code)),
		String(result.get(AeroAudioPlaybackContract.RESULT_MESSAGE, fallback_message)),
		result.get(AeroAudioPlaybackContract.RESULT_DETAIL, {}),
		true
	)

func _raise_error_for_slot(slot_name: String, code: String, message: String, detail: Variant = {}, transition_to_error: bool = true) -> Dictionary:
	var session := _ensure_slot(slot_name)
	var safe_detail: Dictionary = detail if typeof(detail) == TYPE_DICTIONARY else {"value": detail}
	session["last_error"] = {
		"code": code,
		"message": message,
		"detail": safe_detail.duplicate(true),
		"state": str(session.get("state_name", STATE_IDLE)),
		"slot": slot_name,
	}
	_slots[slot_name] = session
	if transition_to_error:
		_transition_state_for_slot(slot_name, PlaybackState.ERROR, session.get("last_error", {}).duplicate(true))
	var error_payload: Dictionary = session.get("last_error", {}).duplicate(true)
	if slot_name == _active_slot:
		error_raised.emit(error_payload.duplicate(true))
	slot_error_raised.emit(slot_name, error_payload.duplicate(true))
	return error_payload

func _ensure_slot(slot_name: String) -> Dictionary:
	var normalized_slot := _normalize_slot_name(slot_name)
	if not _slots.has(normalized_slot):
		_slots[normalized_slot] = {
			"backend": create_default_backend(),
			"backend_name": "",
			"state_name": STATE_IDLE,
			"state_code": PlaybackState.IDLE,
			"loaded_source": {},
			"media_info": {},
			"last_error": {},
			"has_loaded_media": false,
			"surface": null,
		}
		var created_backend: AeroAudioVendorBackend = _slots[normalized_slot].get("backend", null) as AeroAudioVendorBackend
		_slots[normalized_slot]["backend_name"] = _resolve_backend_name(created_backend)
	return _slots[normalized_slot]

func _resolve_backend_name(backend: AeroAudioVendorBackend) -> String:
	return backend.get_script().resource_path.get_file().trim_suffix(".gd") if backend != null and backend.get_script() != null else "custom_backend"

func _resolve_slot_from_source(source: Dictionary) -> String:
	var direct_slot := str(source.get("slot", "")).strip_edges()
	if not direct_slot.is_empty():
		return _normalize_slot_name(direct_slot)
	var metadata: Dictionary = source.get("metadata", {}) if typeof(source.get("metadata", {})) == TYPE_DICTIONARY else {}
	if typeof(metadata) == TYPE_DICTIONARY:
		var metadata_slot := str(metadata.get("slot", "")).strip_edges()
		if not metadata_slot.is_empty():
			return _normalize_slot_name(metadata_slot)
	return _active_slot

func _resolve_slot_name(slot_name: String = "", source: Dictionary = {}) -> String:
	var explicit_slot := str(slot_name).strip_edges()
	if not explicit_slot.is_empty():
		return _normalize_slot_name(explicit_slot)
	if not source.is_empty():
		return _resolve_slot_from_source(source)
	return _normalize_slot_name(_active_slot)

func _with_slot(source: Dictionary, slot_name: String) -> Dictionary:
	var normalized_source := source.duplicate(true)
	normalized_source["slot"] = slot_name
	return normalized_source

func _slot_state_name(slot_name: String) -> String:
	var session := _ensure_slot(slot_name)
	return str(session.get("state_name", STATE_IDLE))

func _state_changed_for_slot(slot_name: String, detail: Dictionary) -> void:
	var state_name := str(detail.get("state", _slot_state_name(slot_name)))
	if slot_name == _active_slot:
		state_changed.emit(state_name, detail.duplicate(true))
	slot_state_changed.emit(slot_name, state_name, detail.duplicate(true))

static func _normalize_slot_name(slot_name: String) -> String:
	var normalized := slot_name.strip_edges()
	return normalized if not normalized.is_empty() else DEFAULT_SLOT
