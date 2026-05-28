extends GutTest

const FACTORY_SCRIPT := preload("res://addons/aerobeat-vendor-godot-audio/src/AeroGodotAudioBackendFactory.gd")
const FAKE_PLAYER_SCRIPT := preload("res://tests/helpers/FakeAudioStreamPlayer.gd")
const SAMPLE_OGG_PATH := "res://assets/audio/test-tone.ogg"
const SAMPLE_WAV_PATH := "res://assets/audio/test-tone.wav"

var _factory: AeroGodotAudioBackendFactory
var _backend: AeroGodotAudioBackend
var _manager: AeroAudioPlaybackManager
var _external_tmp_dir: String = ""
var _external_ogg_path: String = ""
var _external_wav_path: String = ""

func _make_fake_player() -> Node:
	return FAKE_PLAYER_SCRIPT.new()

func before_each() -> void:
	_factory = FACTORY_SCRIPT.new()
	_backend = _factory.create_backend(Callable(self, "_make_fake_player"))
	_manager = _factory.create_manager(Callable(self, "_make_fake_player"))
	add_child_autofree(_manager)
	_manager._initialize()
	_prepare_external_samples()

func after_each() -> void:
	for path in [_external_ogg_path, _external_wav_path]:
		if not String(path).is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if not _external_tmp_dir.is_empty() and DirAccess.dir_exists_absolute(_external_tmp_dir):
		DirAccess.remove_absolute(_external_tmp_dir)
	_external_tmp_dir = ""
	_external_ogg_path = ""
	_external_wav_path = ""

func _prepare_external_samples() -> void:
	_external_tmp_dir = OS.get_cache_dir().path_join("aerobeat-vendor-godot-audio-external-%s" % str(Time.get_unix_time_from_system()))
	assert_eq(DirAccess.make_dir_recursive_absolute(_external_tmp_dir), OK, "Should create a temporary directory for external audio coverage")
	_external_ogg_path = _external_tmp_dir.path_join("external-sample.ogg")
	_external_wav_path = _external_tmp_dir.path_join("external-sample.wav")
	assert_eq(DirAccess.copy_absolute(ProjectSettings.globalize_path(SAMPLE_OGG_PATH), _external_ogg_path), OK, "Should copy the OGG sample outside the project tree")
	assert_eq(DirAccess.copy_absolute(ProjectSettings.globalize_path(SAMPLE_WAV_PATH), _external_wav_path), OK, "Should copy the WAV sample outside the project tree")

func _global_class_names() -> Array[String]:
	var names: Array[String] = []
	for class_info in ProjectSettings.get_global_class_list():
		names.append(str(class_info.get("class", "")))
	return names

func test_public_surface_is_vendor_specific_and_collision_safe() -> void:
	var class_names := _global_class_names()
	assert_false(class_names.has("AeroToolManager"), "Repo should not export a generic AeroToolManager global class")
	assert_true(class_names.has("AeroGodotAudioBackend"), "Repo should export the vendor-specific backend class")
	assert_true(class_names.has("AeroAudioPlaybackManager"), "Repo should export the playback manager class")
	assert_true(class_names.has("AeroGodotAudioBackendFactory"), "Repo should export the vendor-specific factory class")
	assert_eq(AeroGodotAudioBackendFactory.VERSION, "0.3.0", "Factory version should reflect the multi-slot + loop slice")

func test_factory_can_create_a_prewired_audio_manager() -> void:
	assert_true(_manager is AeroAudioPlaybackManager, "Factory should create the public audio manager")
	assert_true(_manager.get_backend() is AeroGodotAudioBackend, "Factory-created manager should be wired to the Godot backend")
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_IDLE, "Fresh manager should begin idle")
	assert_eq(_manager.get_active_slot(), AeroAudioPlaybackManager.DEFAULT_SLOT, "Fresh manager should start on the primary slot")

func test_backend_loads_packaged_ogg_and_reports_verified_media() -> void:
	var surface := Node.new()
	surface.name = "AudioSurface"
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container")

	var result: Dictionary = _backend.load({
		"path": SAMPLE_OGG_PATH,
		"metadata": {"source": "vendor_testbed", "fixture": "ogg"},
	})
	assert_true(bool(result.get("success", false)), "Backend should load the packaged OGG sample")
	var media_info: Dictionary = _backend.get_media_info()
	assert_eq(str(media_info.get("path", "")), SAMPLE_OGG_PATH, "Media info should retain the sample path")
	assert_eq(str(media_info.get("format_status", "")), "verified", "OGG should remain a verified format")
	assert_eq(str(media_info.get("vendor", "")), AeroGodotAudioBackend.VENDOR_NAME, "Media info should identify the Godot vendor")
	assert_true(float(media_info.get("duration", 0.0)) > 0.0, "Media info should report a real duration")
	assert_eq(str(_backend.get_state().get("vendor_state", "")), AeroGodotAudioBackend.STATE_READY, "Successful load should leave the backend ready")

func test_backend_loads_external_absolute_ogg_and_wav_files() -> void:
	var surface := Node.new()
	surface.name = "ExternalAudioSurface"
	add_child_autofree(surface)
	assert_true(bool(_backend.attach_surface(surface).get("success", false)), "Backend should attach to a surface container for external coverage")

	var ogg_result: Dictionary = _backend.load({"path": _external_ogg_path})
	assert_true(bool(ogg_result.get("success", false)), "Backend should load an absolute OGG path outside the project tree")
	assert_eq(str(_backend.get_media_info().get("locality", "")), "absolute_path", "External OGG fixture should report absolute-path locality")

	var wav_result: Dictionary = _backend.load({"path": _external_wav_path})
	assert_true(bool(wav_result.get("success", false)), "Backend should load an absolute WAV path outside the project tree")
	assert_eq(str(_backend.get_media_info().get("extension", "")), "wav", "External WAV fixture should preserve its extension")

func test_backend_loop_updates_state_and_finished_signal_restarts_playback() -> void:
	var surface := Node.new()
	surface.name = "LoopSurface"
	add_child_autofree(surface)
	_backend.attach_surface(surface)
	assert_true(bool(_backend.load({"path": SAMPLE_OGG_PATH, "loop": true}).get("success", false)), "Backend should load a loop-enabled source")
	assert_true(bool(_backend.set_loop(true).get("success", false)), "Backend should accept loop updates")
	_backend.play()
	var player: Node = _backend._player
	assert_true(player != null, "Backend should create a player for playback")
	player.call("emit_finished")
	assert_eq(str(_backend.get_state().get("vendor_state", "")), AeroGodotAudioBackend.STATE_PLAYING, "Loop-enabled playback should restart instead of ending ready")
	assert_true(bool(_backend.get_state().get("loop", false)), "Backend state should expose loop status")

func test_backend_expands_zero_length_wav_loop_window_when_loop_gets_enabled_after_load() -> void:
	var surface := Node.new()
	surface.name = "WavLoopSurface"
	add_child_autofree(surface)
	_backend.attach_surface(surface)
	assert_true(bool(_backend.load({"path": SAMPLE_WAV_PATH, "loop": false}).get("success", false)), "Backend should load the packaged WAV sample before the UI-style loop toggle")

	var wav_stream := _backend._stream_resource as AudioStreamWAV
	assert_true(wav_stream != null, "WAV fixture should load into an AudioStreamWAV resource")
	assert_eq(int(wav_stream.loop_begin), 0, "Regression fixture should begin with the imported loop start")
	assert_eq(int(wav_stream.loop_end), 0, "Regression fixture should begin with the zero-length imported loop end")

	assert_true(bool(_backend.set_loop(true).get("success", false)), "Enabling loop after load should succeed for WAV streams")
	assert_eq(int(wav_stream.loop_mode), AeroGodotAudioBackend.STREAM_LOOP_MODE_FORWARD, "WAV loop toggle should switch the stream into forward loop mode")
	assert_gt(int(wav_stream.loop_end), int(wav_stream.loop_begin), "WAV loop toggle should expand the loop end beyond the loop start so playback can advance")
	assert_eq(int(wav_stream.loop_end), int(ceili(wav_stream.get_length() * float(wav_stream.mix_rate))), "WAV loop toggle should map an open-ended import to the stream's full duration in sample frames")

func test_manager_path_supports_load_unload_play_pause_resume_stop_volume_seek_and_loop_with_callbacks() -> void:
	var surface := Node.new()
	surface.name = "ManagedSurface"
	add_child_autofree(surface)
	_manager.attach_surface(surface)

	var state_events: Array[String] = []
	_manager.listen_for_state(func(state: String, _detail: Dictionary) -> void:
		state_events.append(state)
	)

	var callback_state := {"load_success": false}
	_manager.load({
		"path": SAMPLE_WAV_PATH,
		"start_time": 0.2,
		"volume_db": -6.0,
		"loop": true,
		"metadata": {"fixture": "wav"},
	}).on_success(func(result: Dictionary) -> void:
		callback_state["load_success"] = str(result.get("media_info", {}).get("path", "")) == SAMPLE_WAV_PATH
	)
	assert_true(bool(callback_state.get("load_success", false)), "Load should resolve through the promise-like success callback")
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_READY, "Manager should become ready after load")
	assert_almost_eq(_manager.get_position(), 0.2, 0.001, "Manager should honor start_time")
	assert_true(bool(_manager.get_state().get("loop", false)), "Manager state should expose loop")

	_manager.play().on_success(func(_result: Dictionary) -> void:
		pass
	)
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_PLAYING, "play should transition into playing")
	_manager.pause()
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_PAUSED, "pause should transition into paused")
	_manager.resume()
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_PLAYING, "resume should transition back into playing")
	_manager.seek(0.7)
	assert_almost_eq(_manager.get_position(), 0.7, 0.001, "seek should update the manager position")
	_manager.set_volume_db(-12.0)
	assert_almost_eq(float(_manager.get_state().get("volume_db", 0.0)), -12.0, 0.001, "set_volume_db should update the manager state")
	_manager.set_loop(false)
	assert_false(bool(_manager.get_state().get("loop", true)), "set_loop should update runtime state after load")
	_manager.stop()
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_READY, "stop should return the manager to ready")
	assert_almost_eq(_manager.get_position(), 0.0, 0.001, "stop should reset playback position")
	_manager.unload()
	assert_eq(str(_manager.get_state().get("state", "")), AeroAudioPlaybackManager.STATE_IDLE, "unload should return the manager to idle")
	assert_true(state_events.has(AeroAudioPlaybackManager.STATE_PLAYING), "State listener should receive playing transitions")
	assert_true(state_events.has(AeroAudioPlaybackManager.STATE_PAUSED), "State listener should receive paused transitions")

func test_manager_supports_multiple_independent_audio_slots() -> void:
	var left_surface := Node.new()
	left_surface.name = "LeftSurface"
	add_child_autofree(left_surface)
	var right_surface := Node.new()
	right_surface.name = "RightSurface"
	add_child_autofree(right_surface)
	_manager.attach_slot_surface("left", left_surface)
	_manager.attach_slot_surface("right", right_surface)

	var slot_events: Array[String] = []
	_manager.slot_state_changed.connect(func(slot_name: String, state: String, _detail: Dictionary) -> void:
		slot_events.append("%s:%s" % [slot_name, state])
	)

	assert_true(_manager.load({
		"path": SAMPLE_OGG_PATH,
		"slot": "left",
		"loop": true,
		"volume_db": -3.0,
		"metadata": {"slot": "left"},
	}).did_succeed(), "Left slot should load independently")
	assert_true(_manager.load({
		"path": SAMPLE_WAV_PATH,
		"slot": "right",
		"loop": false,
		"volume_db": -9.0,
		"metadata": {"slot": "right"},
	}).did_succeed(), "Right slot should load independently")

	assert_true(_manager.play("left").did_succeed(), "Left slot should play")
	assert_true(_manager.play("right").did_succeed(), "Right slot should play")
	assert_eq(str(_manager.get_state("left").get("state", "")), AeroAudioPlaybackManager.STATE_PLAYING, "Left slot should report playing")
	assert_eq(str(_manager.get_state("right").get("state", "")), AeroAudioPlaybackManager.STATE_PLAYING, "Right slot should report playing")
	assert_true(bool(_manager.get_state("left").get("loop", false)), "Left slot should keep its loop flag")
	assert_false(bool(_manager.get_state("right").get("loop", true)), "Right slot should keep its own loop flag")
	assert_eq(str(_manager.get_media_info("left").get("path", "")), SAMPLE_OGG_PATH, "Left slot should retain its own media info")
	assert_eq(str(_manager.get_media_info("right").get("path", "")), SAMPLE_WAV_PATH, "Right slot should retain its own media info")

	_manager.pause("left")
	assert_eq(str(_manager.get_state("left").get("state", "")), AeroAudioPlaybackManager.STATE_PAUSED, "Left slot pause should not affect right")
	assert_eq(str(_manager.get_state("right").get("state", "")), AeroAudioPlaybackManager.STATE_PLAYING, "Right slot should remain playing")
	_manager.seek(0.5, "right")
	assert_almost_eq(_manager.get_position("right"), 0.5, 0.001, "Right slot seek should remain isolated")
	assert_true(slot_events.has("left:paused"), "Slot events should identify left slot transitions")
	assert_true(slot_events.has("right:playing"), "Slot events should identify right slot transitions")
	assert_eq(_manager.get_slot_names(), PackedStringArray(["left", "primary", "right"]), "Manager should expose all slot names after multi-audio setup")

func test_failure_callbacks_surface_honest_errors() -> void:
	var callback_state := {"failure_code": ""}
	_manager.load({"path": "https://example.com/demo.ogg"}).on_failure(func(error_info: Dictionary) -> void:
		callback_state["failure_code"] = str(error_info.get("code", ""))
	)
	assert_eq(str(callback_state.get("failure_code", "")), AeroAudioPlaybackContract.ERROR_INVALID_SOURCE, "Remote URLs should reject through the promise-like failure callback")
	assert_eq(str(_manager.get_last_error().get("code", "")), AeroAudioPlaybackContract.ERROR_INVALID_SOURCE, "Manager should retain the invalid-source error")
