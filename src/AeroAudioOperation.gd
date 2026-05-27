class_name AeroAudioOperation
extends RefCounted

signal succeeded(result: Dictionary)
signal failed(error_info: Dictionary)

var _is_settled: bool = false
var _did_succeed: bool = false
var _payload: Dictionary = {}

func on_success(callback: Callable) -> AeroAudioOperation:
	if not callback.is_valid():
		return self
	if _is_settled and _did_succeed:
		callback.call(_payload.duplicate(true))
		return self
	succeeded.connect(func(result: Dictionary) -> void:
		callback.call(result.duplicate(true)), CONNECT_ONE_SHOT)
	return self

func on_failure(callback: Callable) -> AeroAudioOperation:
	if not callback.is_valid():
		return self
	if _is_settled and not _did_succeed:
		callback.call(_payload.duplicate(true))
		return self
	failed.connect(func(error_info: Dictionary) -> void:
		callback.call(error_info.duplicate(true)), CONNECT_ONE_SHOT)
	return self

func settle_success(result: Dictionary) -> AeroAudioOperation:
	if _is_settled:
		return self
	_is_settled = true
	_did_succeed = true
	_payload = result.duplicate(true)
	succeeded.emit(_payload.duplicate(true))
	return self

func settle_failure(error_info: Dictionary) -> AeroAudioOperation:
	if _is_settled:
		return self
	_is_settled = true
	_did_succeed = false
	_payload = error_info.duplicate(true)
	failed.emit(_payload.duplicate(true))
	return self

func is_settled() -> bool:
	return _is_settled

func did_succeed() -> bool:
	return _is_settled and _did_succeed

func get_payload() -> Dictionary:
	return _payload.duplicate(true)
