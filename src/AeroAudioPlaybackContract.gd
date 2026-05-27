class_name AeroAudioPlaybackContract
extends RefCounted

const RESULT_SUCCESS := "success"
const RESULT_CODE := "code"
const RESULT_MESSAGE := "message"
const RESULT_DETAIL := "detail"

const STATE_IDLE := "idle"
const STATE_LOADING := "loading"
const STATE_READY := "ready"
const STATE_PLAYING := "playing"
const STATE_PAUSED := "paused"
const STATE_STOPPING := "stopping"
const STATE_ERROR := "error"

const SOURCE_KIND_FILE := "file"
const SOURCE_KIND_PACKAGE := "package"
const SOURCE_KIND_URL := "url"
const SOURCE_KINDS := [SOURCE_KIND_FILE, SOURCE_KIND_PACKAGE]

const ERROR_INVALID_SOURCE := "invalid_source"
const ERROR_INVALID_SURFACE := "invalid_surface"
const ERROR_BACKEND_REJECTED := "backend_rejected"
const ERROR_NOT_READY := "not_ready"

static func ok(detail: Dictionary = {}) -> Dictionary:
	return {
		RESULT_SUCCESS: true,
		RESULT_CODE: "ok",
		RESULT_MESSAGE: "ok",
		RESULT_DETAIL: detail.duplicate(true),
	}

static func fail(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	return {
		RESULT_SUCCESS: false,
		RESULT_CODE: code,
		RESULT_MESSAGE: message,
		RESULT_DETAIL: detail.duplicate(true),
	}

static func get_default_source_config() -> Dictionary:
	return {
		"path": "",
		"kind": SOURCE_KIND_FILE,
		"loop": false,
		"autoplay": false,
		"start_time": 0.0,
		"volume_db": 0.0,
		"metadata": {},
	}

static func normalize_source(source: Dictionary) -> Dictionary:
	var normalized := get_default_source_config()
	for key in source.keys():
		normalized[key] = source[key]
	var path := String(normalized.get("path", "")).strip_edges()
	normalized["path"] = path
	if String(normalized.get("kind", "")).strip_edges().is_empty():
		normalized["kind"] = SOURCE_KIND_PACKAGE if path.begins_with("res://") else SOURCE_KIND_FILE
	normalized["extension"] = path.get_extension().to_lower()
	return normalized

static func validate_source(source: Dictionary) -> Dictionary:
	var path := String(source.get("path", "")).strip_edges()
	if path.is_empty():
		return {
			"code": "audio_source_missing_path",
			"message": "Audio source path must be a non-empty local file path.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	var extension := String(source.get("extension", path.get_extension())).to_lower()
	if not ["ogg", "wav"].has(extension):
		return {
			"code": "audio_source_extension_unsupported",
			"message": "Godot audio backend currently supports only .ogg and .wav assets.",
			"detail": {"field": "path", "source": source.duplicate(true), "supported_extensions": ["ogg", "wav"]},
		}
	if path.to_lower().begins_with("http://") or path.to_lower().begins_with("https://"):
		return {
			"code": "audio_source_not_local",
			"message": "Godot audio backend only accepts packaged or arbitrary local file paths in this slice.",
			"detail": {"field": "path", "source": source.duplicate(true)},
		}
	return {}

static func build_state_snapshot(detail: Dictionary = {}) -> Dictionary:
	var snapshot := {
		"state": STATE_IDLE,
		"state_code": 0,
		"source": {},
		"media_info": {},
		"position": 0.0,
		"duration": 0.0,
		"loop": false,
		"volume_db": 0.0,
		"surface_attached": false,
		"backend": "",
		"last_error": {},
		"media_loaded": false,
	}
	for key in detail.keys():
		snapshot[key] = detail[key]
	return snapshot
