class_name AeroGodotAudioBackend
extends "AeroAudioVendorBackend.gd"

const VENDOR_NAME := "godot_audio"
const BACKEND_FAMILY := "godot_builtin_audio"
const SOURCE_KIND_FILE := CoreContract.SOURCE_KIND_FILE
const SOURCE_KIND_PACKAGE := CoreContract.SOURCE_KIND_PACKAGE
const SUPPORTED_SOURCE_KINDS := [SOURCE_KIND_FILE, SOURCE_KIND_PACKAGE]
const VERIFIED_EXTENSIONS := ["ogg", "wav"]
const STREAM_LOOP_MODE_DISABLED := 0
const STREAM_LOOP_MODE_FORWARD := 1

const STATE_IDLE := "idle"
const STATE_ATTACHED := "attached"
const STATE_READY := "ready"
const STATE_PLAYING := "playing"
const STATE_PAUSED := "paused"
const STATE_ERROR := "error"

var _surface: Node = null
var _player: Node = null
var _player_factory: Callable = Callable()
var _stream_resource: Resource = null
var _loaded_source: Dictionary = {}
var _media_info: Dictionary = {}
var _last_error: Dictionary = {}
var _vendor_state: String = STATE_IDLE
var _position_seconds: float = 0.0
var _duration_seconds: float = 0.0
var _volume_db: float = 0.0
var _loop_enabled: bool = false
var _finished_connected: bool = false

func set_player_factory(factory: Callable) -> void:
	_player_factory = factory

func set_player_node(node: Node) -> void:
	_player = node
	_sync_player_binding()
	_sync_player_configuration()
	_connect_finished_signal()

func normalize_source(source: Dictionary) -> Dictionary:
	var normalized := CoreContract.normalize_source(source)
	var original_path := str(normalized.get("path", "")).strip_edges()
	if original_path.to_lower().begins_with("file://"):
		normalized["path"] = _normalize_file_uri(original_path)
	else:
		normalized["path"] = original_path
	normalized["original_path"] = original_path
	normalized["kind"] = SOURCE_KIND_PACKAGE if str(normalized.get("path", "")).begins_with("res://") else SOURCE_KIND_FILE
	normalized["vendor"] = VENDOR_NAME
	normalized["backend_family"] = BACKEND_FAMILY
	normalized["locality"] = _detect_locality(str(normalized.get("path", "")))
	normalized["is_local_file"] = str(normalized.get("locality", "")) != "remote"
	normalized["extension"] = str(normalized.get("path", "")).get_extension().to_lower()
	return normalized

func validate_source(source: Dictionary) -> Dictionary:
	return CoreContract.validate_source(source)

func get_capabilities() -> Dictionary:
	return {
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"supported_source_kinds": SUPPORTED_SOURCE_KINDS.duplicate(),
		"verified_extensions": VERIFIED_EXTENSIONS.duplicate(),
		"remote_sources_supported": false,
		"surface_attach_mode": "direct_or_container_child",
		"surface_types": ["AudioStreamPlayer", "Node"],
		"controls": ["load", "unload", "play", "pause", "resume", "stop", "volume_db", "loop", "seek"],
		"metadata_known_fields": ["path", "kind", "vendor", "backend_family", "extension", "locality", "duration", "position", "surface_attached", "volume_db", "loop"],
	}

func load(source: Dictionary) -> Dictionary:
	var normalized := normalize_source(source)
	var validation_error := validate_source(normalized)
	if not validation_error.is_empty():
		return _fail(
			str(validation_error.get("code", "backend_invalid_source")),
			str(validation_error.get("message", "Invalid source.")),
			validation_error.get("detail", {})
		)

	var stream_resource := _load_stream_resource(str(normalized.get("path", "")))
	if stream_resource == null:
		return _fail(
			"backend_stream_load_failed",
			"Godot could not load the requested audio stream resource.",
			{"path": normalized.get("path", ""), "source": normalized.duplicate(true)}
		)

	_stream_resource = stream_resource
	_loaded_source = normalized.duplicate(true)
	_position_seconds = maxf(0.0, float(_loaded_source.get("start_time", 0.0)))
	_volume_db = float(_loaded_source.get("volume_db", 0.0))
	_loop_enabled = bool(_loaded_source.get("loop", false))
	_duration_seconds = _resolve_duration_seconds(_stream_resource, normalized)
	_media_info = _build_media_info(_loaded_source)
	_sync_player_configuration()
	_last_error = {}
	_vendor_state = STATE_READY
	return _ok({
		"source": _loaded_source.duplicate(true),
		"media_info": _media_info.duplicate(true),
		"vendor_state": _vendor_state,
	})

func unload() -> Dictionary:
	if not _loaded_source.is_empty() and _player != null and _player.has_method("stop"):
		_player.call("stop")
	_stream_resource = null
	_loaded_source = {}
	_media_info = {}
	_last_error = {}
	_position_seconds = 0.0
	_duration_seconds = 0.0
	_loop_enabled = false
	_vendor_state = STATE_ATTACHED if _surface != null else STATE_IDLE
	if _player != null:
		_set_player_property("stream", null)
		_set_player_property("stream_paused", false)
		_set_player_property("volume_db", _volume_db)
	return _ok({"vendor_state": _vendor_state})

func play() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot start playback before a source is loaded.")
	var player_result := _ensure_player()
	if not bool(player_result.get("success", false)):
		return player_result
	_sync_player_configuration()
	if _player.has_method("play"):
		_player.call("play", _position_seconds)
	_set_player_property("stream_paused", false)
	_vendor_state = STATE_PLAYING
	_last_error = {}
	return _ok({"vendor_state": _vendor_state})

func pause() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot pause playback before a source is loaded.")
	var current_position := get_position()
	_position_seconds = current_position
	if _player != null:
		_set_player_property("stream_paused", true)
	_vendor_state = STATE_PAUSED
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func resume() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot resume playback before a source is loaded.")
	if _player != null:
		_set_player_property("stream_paused", false)
		if _player.has_method("play") and not _is_player_playing():
			_player.call("play", _position_seconds)
	_vendor_state = STATE_PLAYING
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func stop() -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot stop playback before a source is loaded.")
	_position_seconds = 0.0
	if _player != null:
		if _player.has_method("stop"):
			_player.call("stop")
		_set_player_property("stream_paused", false)
	_vendor_state = STATE_READY
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func set_volume_db(volume_db: float) -> Dictionary:
	_volume_db = volume_db
	var applied_to_player := _set_player_property("volume_db", _volume_db)
	_last_error = {}
	return _ok({"volume_db": _volume_db, "applied_to_player": applied_to_player})

func set_loop(enabled: bool) -> Dictionary:
	_loop_enabled = enabled
	if not _loaded_source.is_empty():
		_loaded_source["loop"] = enabled
	_sync_stream_loop_configuration()
	_last_error = {}
	return _ok({"loop": _loop_enabled})

func seek(seconds: float) -> Dictionary:
	if _loaded_source.is_empty():
		return _fail("backend_not_loaded", "Cannot seek before a source is loaded.")
	var max_position := maxf(0.0, seconds)
	if _duration_seconds > 0.0:
		max_position = _duration_seconds
	_position_seconds = clampf(seconds, 0.0, max_position)
	if _player != null and _player.has_method("seek"):
		_player.call("seek", _position_seconds)
	_last_error = {}
	return _ok({"vendor_state": _vendor_state, "position": _position_seconds})

func get_state() -> Dictionary:
	return translate_backend_state(_snapshot_player_state())

func get_position() -> float:
	var state := get_state()
	return float(state.get("position", _position_seconds))

func get_duration() -> float:
	return _duration_seconds

func get_media_info() -> Dictionary:
	var info := _media_info.duplicate(true)
	if info.is_empty() and not _loaded_source.is_empty():
		info = _build_media_info(_loaded_source)
	return info

func attach_surface(node: Node) -> Dictionary:
	if node == null:
		return _fail("backend_invalid_surface", "Cannot attach a null audio surface.")
	_surface = node
	var player_result := _ensure_player()
	if not bool(player_result.get("success", false)):
		return player_result
	_sync_player_binding()
	_sync_player_configuration()
	_connect_finished_signal()
	_last_error = {}
	if _loaded_source.is_empty():
		_vendor_state = STATE_ATTACHED
	return _ok({
		"surface_attached": true,
		"surface_path": str(node.get_path()) if node.is_inside_tree() else node.name,
		"player_present": _player != null,
	})

func detach_surface() -> Dictionary:
	if _player != null and _surface != null and _player != _surface and _player.get_parent() == _surface:
		_surface.remove_child(_player)
		if _player.has_method("queue_free"):
			_player.call("queue_free")
		_player = null
		_finished_connected = false
	_surface = null
	if _loaded_source.is_empty():
		_vendor_state = STATE_IDLE
	_last_error = {}
	return _ok({"surface_attached": false})

func get_last_error() -> Dictionary:
	return _last_error.duplicate(true)

func translate_backend_error(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	var category := "runtime"
	match code:
		"audio_source_missing_path", "audio_source_not_local", "audio_source_extension_unsupported", "backend_stream_load_failed":
			category = "source"
		"backend_invalid_surface", "backend_player_unavailable":
			category = "surface"
		"backend_not_loaded":
			category = "state"
		_:
			category = "runtime"
	return {
		"code": code,
		"message": message,
		"category": category,
		"recoverable": code != "backend_player_unavailable",
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"detail": detail.duplicate(true),
	}

func translate_backend_state(raw_state: Dictionary = {}) -> Dictionary:
	var translated := {
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"vendor_state": _vendor_state,
		"surface_attached": _surface != null,
		"player_present": _player != null,
		"media_loaded": not _loaded_source.is_empty(),
		"position": _position_seconds,
		"duration": _duration_seconds,
		"volume_db": _volume_db,
		"loop": _loop_enabled,
		"last_error": _last_error.duplicate(true),
		"source": _loaded_source.duplicate(true),
		"raw": raw_state.duplicate(true),
	}
	for key in raw_state.keys():
		translated[key] = raw_state[key]
	if bool(raw_state.get("playing", false)):
		translated["vendor_state"] = STATE_PLAYING
	elif translated["media_loaded"] and bool(raw_state.get("paused", false)):
		translated["vendor_state"] = STATE_PAUSED
	elif translated["media_loaded"] and translated["vendor_state"] == STATE_ATTACHED:
		translated["vendor_state"] = STATE_READY
	if not _last_error.is_empty():
		translated["vendor_state"] = STATE_ERROR
	return translated

func _normalize_file_uri(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed.to_lower().begins_with("file://localhost/"):
		return "/%s" % trimmed.substr(17)
	if trimmed.to_lower().begins_with("file:///"):
		return "/%s" % trimmed.substr(8)
	if trimmed.to_lower().begins_with("file://"):
		return trimmed.substr(7)
	return trimmed

func _detect_locality(path: String) -> String:
	if path.begins_with("res://"):
		return "project_resource"
	if path.begins_with("user://"):
		return "user_data"
	if path.begins_with("/"):
		return "absolute_path"
	if path.to_lower().begins_with("http://") or path.to_lower().begins_with("https://"):
		return "remote"
	return "relative_path"

func _build_media_info(source: Dictionary) -> Dictionary:
	return {
		"path": str(source.get("path", "")),
		"kind": str(source.get("kind", SOURCE_KIND_FILE)),
		"vendor": VENDOR_NAME,
		"backend_family": BACKEND_FAMILY,
		"locality": str(source.get("locality", "")),
		"extension": str(source.get("extension", "")).to_lower(),
		"format_status": "verified",
		"duration": _duration_seconds,
		"position": _position_seconds,
		"surface_attached": _surface != null,
		"volume_db": _volume_db,
		"loop": _loop_enabled,
		"metadata": source.get("metadata", {}).duplicate(true),
	}

func _load_stream_resource(path: String) -> Resource:
	var candidate_path := path
	if path.begins_with("/"):
		var localized := ProjectSettings.localize_path(path)
		if localized.begins_with("res://") or localized.begins_with("user://"):
			candidate_path = localized
		else:
			return _load_external_stream_resource(path)
	if not (candidate_path.begins_with("res://") or candidate_path.begins_with("user://")):
		return null
	if not ResourceLoader.exists(candidate_path):
		return null
	var loaded := ResourceLoader.load(candidate_path)
	return loaded as Resource

func _load_external_stream_resource(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	var extension := path.get_extension().to_lower()
	if extension == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if extension == "wav":
		return AudioStreamWAV.load_from_file(path)
	return null

func _resolve_duration_seconds(stream_resource: Resource, normalized: Dictionary) -> float:
	if stream_resource == null:
		return maxf(0.0, float(normalized.get("duration_hint", 0.0)))
	if _object_supports_property(stream_resource, "length"):
		return maxf(0.0, float(stream_resource.get("length")))
	if stream_resource.has_method("get_length"):
		return maxf(0.0, float(stream_resource.call("get_length")))
	return maxf(0.0, float(normalized.get("duration_hint", 0.0)))

func _ensure_player() -> Dictionary:
	if _player != null:
		return _ok({"player_present": true})
	if _surface is AudioStreamPlayer:
		_player = _surface
	elif _player_factory.is_valid():
		_player = _player_factory.call()
	elif ClassDB.can_instantiate("AudioStreamPlayer"):
		_player = ClassDB.instantiate("AudioStreamPlayer")
	if _player == null:
		return _fail("backend_player_unavailable", "Unable to create a Godot audio player node for the attached surface.")
	if str(_player.name).is_empty():
		_player.name = "AeroGodotAudioPlayer"
	return _ok({"player_present": true})

func _sync_player_binding() -> void:
	if _surface == null or _player == null:
		return
	if _player == _surface:
		return
	if _player.get_parent() != _surface:
		if _player.get_parent() != null:
			_player.get_parent().remove_child(_player)
		_surface.add_child(_player)

func _sync_player_configuration() -> void:
	if _player == null:
		return
	if _stream_resource != null:
		_set_player_property("stream", _stream_resource)
	_sync_stream_loop_configuration()
	_set_player_property("volume_db", _volume_db)
	_set_player_property("stream_paused", _vendor_state == STATE_PAUSED)
	if _player.has_method("set") and _loaded_source.has("autoplay"):
		_set_player_property("autoplay", bool(_loaded_source.get("autoplay", false)))

func _sync_stream_loop_configuration() -> void:
	if _stream_resource == null:
		return
	if _object_supports_property(_stream_resource, "loop"):
		_stream_resource.set("loop", _loop_enabled)
	if _object_supports_property(_stream_resource, "loop_mode"):
		_stream_resource.set("loop_mode", STREAM_LOOP_MODE_FORWARD if _loop_enabled else STREAM_LOOP_MODE_DISABLED)
	if _stream_resource is AudioStreamWAV and _loop_enabled:
		var loop_begin := int(_stream_resource.get("loop_begin")) if _object_supports_property(_stream_resource, "loop_begin") else 0
		var loop_end := int(_stream_resource.get("loop_end")) if _object_supports_property(_stream_resource, "loop_end") else 0
		if loop_end <= loop_begin:
			_stream_resource.set("loop_end", _resolve_wav_loop_end_frame(loop_begin))

func _resolve_wav_loop_end_frame(loop_begin: int) -> int:
	var mix_rate := int(_stream_resource.get("mix_rate")) if _object_supports_property(_stream_resource, "mix_rate") else 0
	var estimated_frame := int(ceili(maxf(0.0, _duration_seconds) * float(mix_rate)))
	return maxi(loop_begin + 1, estimated_frame)

func _connect_finished_signal() -> void:
	if _player == null or _finished_connected:
		return
	if _player.has_signal("finished"):
		_player.connect("finished", Callable(self, "_on_player_finished"))
		_finished_connected = true

func _snapshot_player_state() -> Dictionary:
	var raw := {
		"surface_attached": _surface != null,
		"player_present": _player != null,
		"position": _position_seconds,
		"duration": _duration_seconds,
		"volume_db": _volume_db,
		"loop": _loop_enabled,
	}
	if _player != null:
		if _player.has_method("get_playback_position"):
			raw["position"] = float(_player.call("get_playback_position"))
		if _player_supports_property("volume_db"):
			raw["volume_db"] = float(_player.get("volume_db"))
		if _player_supports_property("stream_paused"):
			raw["paused"] = bool(_player.get("stream_paused"))
		raw["playing"] = _is_player_playing()
		raw["player_name"] = str(_player.name)
	return raw

func _player_supports_property(property_name: String) -> bool:
	return _object_supports_property(_player, property_name)

func _object_supports_property(target: Variant, property_name: String) -> bool:
	if target == null or not (target is Object):
		return false
	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false

func _set_player_property(property_name: String, value: Variant) -> bool:
	if _player == null or not _player_supports_property(property_name):
		return false
	_player.set(property_name, value)
	return true

func _is_player_playing() -> bool:
	if _player == null:
		return false
	if _player.has_method("playing"):
		return bool(_player.call("playing"))
	if _player.has_method("is_playing"):
		return bool(_player.call("is_playing"))
	if _player_supports_property("stream_paused"):
		return not bool(_player.get("stream_paused")) and _vendor_state == STATE_PLAYING
	return _vendor_state == STATE_PLAYING

func _on_player_finished() -> void:
	if _loop_enabled and not _loaded_source.is_empty():
		_position_seconds = 0.0
		_vendor_state = STATE_PLAYING
		if _player != null and _player.has_method("play"):
			_player.call("play", 0.0)
		_set_player_property("stream_paused", false)
		return
	_position_seconds = _duration_seconds
	_vendor_state = STATE_READY

func _ok(detail: Dictionary = {}) -> Dictionary:
	return CoreContract.ok(detail)

func _fail(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	_last_error = translate_backend_error(code, message, detail)
	_vendor_state = STATE_ERROR
	return CoreContract.fail(code, message, detail)
