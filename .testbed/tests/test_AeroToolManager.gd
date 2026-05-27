extends GutTest

const MANAGER_SCRIPT := preload("res://src/AeroAudioPlaybackManager.gd")
const OPERATION_SCRIPT := preload("res://src/AeroAudioOperation.gd")

func test_public_repo_no_longer_exports_template_tool_manager_shape() -> void:
	var class_names: Array[String] = []
	for class_info in ProjectSettings.get_global_class_list():
		class_names.append(str(class_info.get("class", "")))
	assert_false(class_names.has("AeroToolManager"), "Template AeroToolManager global class should be gone")
	assert_true(class_names.has("AeroAudioPlaybackManager"), "Audio playback manager should be exported instead")
	assert_eq(AeroAudioPlaybackManager.VERSION, "0.3.0", "Audio manager version should reflect the real implementation slice")

func test_operation_callbacks_can_settle_immediately_and_late_subscribers_still_fire() -> void:
	var operation: AeroAudioOperation = OPERATION_SCRIPT.new()
	var callback_state := {"success_message": ""}
	operation.settle_success({"message": "loaded"})
	operation.on_success(func(result: Dictionary) -> void:
		callback_state["success_message"] = str(result.get("message", ""))
	)
	assert_eq(str(callback_state.get("success_message", "")), "loaded", "Success callbacks should still fire after immediate settlement")

func test_manager_can_register_and_remove_state_listeners() -> void:
	var manager: AeroAudioPlaybackManager = MANAGER_SCRIPT.new()
	add_child_autofree(manager)
	manager._initialize()
	var callback_state := {"calls": 0}
	var listener := func(_state: String, _detail: Dictionary) -> void:
		callback_state["calls"] = int(callback_state.get("calls", 0)) + 1
	manager.listen_for_state(listener)
	assert_true(int(callback_state.get("calls", 0)) >= 1, "listen_for_state should optionally emit the current state immediately")
	manager.stop_listening_for_state(listener)
	manager.get_state()
	assert_true(manager.state_changed.is_connected(listener) == false, "stop_listening_for_state should disconnect the callback")
