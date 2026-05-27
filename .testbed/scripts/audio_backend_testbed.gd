extends Control

const FACTORY_SCRIPT := preload("res://src/AeroGodotAudioBackendFactory.gd")
const SAMPLE_OGG_PATH := "res://assets/audio/test-tone.ogg"
const SAMPLE_WAV_PATH := "res://assets/audio/test-tone.wav"
const SLOT_LEFT := "left"
const SLOT_RIGHT := "right"

@onready var global_result_label: Label = %GlobalResultLabel
@onready var left_path_label: Label = %LeftPathLabel
@onready var left_status_label: Label = %LeftStatusLabel
@onready var left_detail_label: Label = %LeftDetailLabel
@onready var left_result_label: Label = %LeftResultLabel
@onready var left_slider_label: Label = %LeftSliderLabel
@onready var left_player_host: Node = %LeftPlayerHost
@onready var left_picker: FileDialog = %LeftFileDialog
@onready var left_seek_slider: HSlider = %LeftSeekSlider
@onready var left_volume_slider: HSlider = %LeftVolumeSlider
@onready var left_loop_check_box: CheckBox = %LeftLoopCheckBox

@onready var right_path_label: Label = %RightPathLabel
@onready var right_status_label: Label = %RightStatusLabel
@onready var right_detail_label: Label = %RightDetailLabel
@onready var right_result_label: Label = %RightResultLabel
@onready var right_slider_label: Label = %RightSliderLabel
@onready var right_player_host: Node = %RightPlayerHost
@onready var right_picker: FileDialog = %RightFileDialog
@onready var right_seek_slider: HSlider = %RightSeekSlider
@onready var right_volume_slider: HSlider = %RightVolumeSlider
@onready var right_loop_check_box: CheckBox = %RightLoopCheckBox

var _factory: AeroGodotAudioBackendFactory
var _manager: AeroAudioPlaybackManager
var _slot_state := {
	SLOT_LEFT: {
		"selected_path": SAMPLE_OGG_PATH,
		"result_label": null,
		"status_label": null,
		"detail_label": null,
		"path_label": null,
		"slider_label": null,
		"seek_slider": null,
		"volume_slider": null,
		"loop_check_box": null,
		"picker": null,
		"host": null,
		"suspend_seek_updates": false,
	},
	SLOT_RIGHT: {
		"selected_path": SAMPLE_WAV_PATH,
		"result_label": null,
		"status_label": null,
		"detail_label": null,
		"path_label": null,
		"slider_label": null,
		"seek_slider": null,
		"volume_slider": null,
		"loop_check_box": null,
		"picker": null,
		"host": null,
		"suspend_seek_updates": false,
	},
}

func _ready() -> void:
	_slot_state[SLOT_LEFT]["result_label"] = left_result_label
	_slot_state[SLOT_LEFT]["status_label"] = left_status_label
	_slot_state[SLOT_LEFT]["detail_label"] = left_detail_label
	_slot_state[SLOT_LEFT]["path_label"] = left_path_label
	_slot_state[SLOT_LEFT]["slider_label"] = left_slider_label
	_slot_state[SLOT_LEFT]["seek_slider"] = left_seek_slider
	_slot_state[SLOT_LEFT]["volume_slider"] = left_volume_slider
	_slot_state[SLOT_LEFT]["loop_check_box"] = left_loop_check_box
	_slot_state[SLOT_LEFT]["picker"] = left_picker
	_slot_state[SLOT_LEFT]["host"] = left_player_host
	_slot_state[SLOT_RIGHT]["result_label"] = right_result_label
	_slot_state[SLOT_RIGHT]["status_label"] = right_status_label
	_slot_state[SLOT_RIGHT]["detail_label"] = right_detail_label
	_slot_state[SLOT_RIGHT]["path_label"] = right_path_label
	_slot_state[SLOT_RIGHT]["slider_label"] = right_slider_label
	_slot_state[SLOT_RIGHT]["seek_slider"] = right_seek_slider
	_slot_state[SLOT_RIGHT]["volume_slider"] = right_volume_slider
	_slot_state[SLOT_RIGHT]["loop_check_box"] = right_loop_check_box
	_slot_state[SLOT_RIGHT]["picker"] = right_picker
	_slot_state[SLOT_RIGHT]["host"] = right_player_host

	_factory = FACTORY_SCRIPT.new()
	_manager = _factory.create_manager()
	add_child(_manager)
	_manager.slot_state_changed.connect(_on_slot_state_changed)
	_manager.slot_media_loaded.connect(_on_slot_media_loaded)
	_manager.slot_error_raised.connect(_on_slot_error_raised)
	_manager.slot_position_changed.connect(_on_slot_position_changed)
	_manager.slot_playback_finished.connect(_on_slot_playback_finished)

	_configure_slot(SLOT_LEFT)
	_configure_slot(SLOT_RIGHT)
	set_process(true)
	_refresh_all_labels()
	global_result_label.text = "Load/play each slot independently. Left starts OGG, right starts WAV."

func _process(_delta: float) -> void:
	_refresh_all_labels()

func _configure_slot(slot_name: String) -> void:
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	var picker: FileDialog = slot_info.get("picker", null)
	var volume_slider: HSlider = slot_info.get("volume_slider", null)
	var host: Node = slot_info.get("host", null)
	var path_label: Label = slot_info.get("path_label", null)
	if picker != null:
		picker.filters = PackedStringArray(["*.ogg ; Ogg Vorbis", "*.wav ; Waveform Audio"])
	if volume_slider != null:
		volume_slider.value = 0.0
	if path_label != null:
		path_label.text = str(slot_info.get("selected_path", ""))
	if host != null:
		_manager.attach_slot_surface(slot_name, host)

func _refresh_all_labels() -> void:
	_refresh_labels_for_slot(SLOT_LEFT)
	_refresh_labels_for_slot(SLOT_RIGHT)

func _refresh_labels_for_slot(slot_name: String) -> void:
	if _manager == null:
		return
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	var state: Dictionary = _manager.get_state(slot_name)
	var media_info: Dictionary = _manager.get_media_info(slot_name)
	var duration := float(state.get("duration", 0.0))
	var position := float(state.get("position", 0.0))
	var status_label: Label = slot_info.get("status_label", null)
	var detail_label: Label = slot_info.get("detail_label", null)
	var slider_label: Label = slot_info.get("slider_label", null)
	var seek_slider: HSlider = slot_info.get("seek_slider", null)
	var volume_slider: HSlider = slot_info.get("volume_slider", null)
	var loop_check_box: CheckBox = slot_info.get("loop_check_box", null)
	if status_label != null:
		status_label.text = "%s state: %s" % [slot_name.capitalize(), str(state.get("state", "idle"))]
	if detail_label != null:
		detail_label.text = "Position: %.2f / %.2f | Volume: %.1f dB | Loop: %s | Format: %s | Path type: %s" % [
			position,
			duration,
			float(state.get("volume_db", 0.0)),
			"on" if bool(state.get("loop", false)) else "off",
			str(media_info.get("extension", "")),
			str(media_info.get("locality", "")),
		]
	if slider_label != null and seek_slider != null and volume_slider != null:
		slider_label.text = "Seek %.2fs | Volume %.1f dB | Loop %s" % [seek_slider.value, volume_slider.value, "on" if loop_check_box != null and loop_check_box.button_pressed else "off"]
	if seek_slider != null and not bool(slot_info.get("suspend_seek_updates", false)):
		seek_slider.max_value = maxf(duration, 0.01)
		seek_slider.value = clampf(position, 0.0, seek_slider.max_value)
	if loop_check_box != null and loop_check_box.button_pressed != bool(state.get("loop", false)):
		loop_check_box.button_pressed = bool(state.get("loop", false))

func _choose_path(slot_name: String, path: String) -> void:
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	slot_info["selected_path"] = path
	_slot_state[slot_name] = slot_info
	var path_label: Label = slot_info.get("path_label", null)
	var result_label: Label = slot_info.get("result_label", null)
	if path_label != null:
		path_label.text = path
	if result_label != null:
		result_label.text = "Selected %s" % path

func _load_selected_path(slot_name: String) -> void:
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	var selected_path := str(slot_info.get("selected_path", ""))
	var result_label: Label = slot_info.get("result_label", null)
	var volume_slider: HSlider = slot_info.get("volume_slider", null)
	var loop_check_box: CheckBox = slot_info.get("loop_check_box", null)
	if selected_path.is_empty():
		if result_label != null:
			result_label.text = "Pick an .ogg or .wav file first."
		return
	var source := {
		"path": selected_path,
		"slot": slot_name,
		"loop": bool(loop_check_box != null and loop_check_box.button_pressed),
		"volume_db": volume_slider.value if volume_slider != null else 0.0,
		"metadata": {"source": "audio_backend_testbed", "slot": slot_name},
	}
	_manager.load(source, slot_name).on_success(func(result: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Loaded %s" % str(result.get("media_info", {}).get("path", selected_path))
	).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Load failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _play_slot(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.play(slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Play failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _pause_slot(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.pause(slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Pause failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _resume_slot(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.resume(slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Resume failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _stop_slot(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.stop(slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Stop failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _unload_slot(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.unload(slot_name).on_success(func(_result: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Unloaded"
	)

func _set_slot_seek_suspended(slot_name: String, suspended: bool) -> void:
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	slot_info["suspend_seek_updates"] = suspended
	_slot_state[slot_name] = slot_info

func _apply_slot_seek(slot_name: String) -> void:
	var slot_info: Dictionary = _slot_state.get(slot_name, {})
	var seek_slider: HSlider = slot_info.get("seek_slider", null)
	var result_label: Label = slot_info.get("result_label", null)
	if seek_slider == null:
		return
	_manager.seek(seek_slider.value, slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Seek failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _apply_slot_volume(slot_name: String, value: float) -> void:
	_manager.set_volume_db(value, slot_name)
	_refresh_labels_for_slot(slot_name)

func _apply_slot_loop(slot_name: String, enabled: bool) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	_manager.set_loop(enabled, slot_name).on_failure(func(error_info: Dictionary) -> void:
		if result_label != null:
			result_label.text = "Loop failed: %s" % str(error_info.get("message", "Unknown error"))
	)
	_refresh_labels_for_slot(slot_name)

func _on_slot_state_changed(_slot_name: String, _state: String, _detail: Dictionary) -> void:
	_refresh_all_labels()

func _on_slot_media_loaded(slot_name: String, info: Dictionary) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	if result_label != null:
		result_label.text = "Loaded %s" % str(info.get("path", ""))
	global_result_label.text = "Loaded %s in %s" % [str(info.get("path", "")), slot_name]
	_refresh_labels_for_slot(slot_name)

func _on_slot_error_raised(slot_name: String, error_info: Dictionary) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	if result_label != null:
		result_label.text = "Error: %s" % str(error_info.get("message", "Unknown error"))
	global_result_label.text = "%s error: %s" % [slot_name, str(error_info.get("message", "Unknown error"))]
	_refresh_labels_for_slot(slot_name)

func _on_slot_position_changed(slot_name: String, _seconds: float, _normalized: float) -> void:
	_refresh_labels_for_slot(slot_name)

func _on_slot_playback_finished(slot_name: String) -> void:
	var result_label: Label = _slot_state.get(slot_name, {}).get("result_label", null)
	if result_label != null:
		result_label.text = "Playback finished"
	global_result_label.text = "%s playback finished" % slot_name
	_refresh_labels_for_slot(slot_name)

func _on_left_choose_file_button_pressed() -> void:
	left_picker.popup_centered_ratio(0.8)

func _on_left_file_dialog_file_selected(path: String) -> void:
	_choose_path(SLOT_LEFT, path)

func _on_left_use_sample_ogg_button_pressed() -> void:
	_choose_path(SLOT_LEFT, SAMPLE_OGG_PATH)

func _on_left_use_sample_wav_button_pressed() -> void:
	_choose_path(SLOT_LEFT, SAMPLE_WAV_PATH)

func _on_left_load_button_pressed() -> void:
	_load_selected_path(SLOT_LEFT)

func _on_left_play_button_pressed() -> void:
	_play_slot(SLOT_LEFT)

func _on_left_pause_button_pressed() -> void:
	_pause_slot(SLOT_LEFT)

func _on_left_resume_button_pressed() -> void:
	_resume_slot(SLOT_LEFT)

func _on_left_stop_button_pressed() -> void:
	_stop_slot(SLOT_LEFT)

func _on_left_unload_button_pressed() -> void:
	_unload_slot(SLOT_LEFT)

func _on_left_seek_slider_drag_started() -> void:
	_set_slot_seek_suspended(SLOT_LEFT, true)

func _on_left_seek_slider_drag_ended(_value_changed: bool) -> void:
	_set_slot_seek_suspended(SLOT_LEFT, false)
	_apply_slot_seek(SLOT_LEFT)

func _on_left_volume_slider_value_changed(value: float) -> void:
	_apply_slot_volume(SLOT_LEFT, value)

func _on_left_loop_check_box_toggled(toggled_on: bool) -> void:
	_apply_slot_loop(SLOT_LEFT, toggled_on)

func _on_right_choose_file_button_pressed() -> void:
	right_picker.popup_centered_ratio(0.8)

func _on_right_file_dialog_file_selected(path: String) -> void:
	_choose_path(SLOT_RIGHT, path)

func _on_right_use_sample_ogg_button_pressed() -> void:
	_choose_path(SLOT_RIGHT, SAMPLE_OGG_PATH)

func _on_right_use_sample_wav_button_pressed() -> void:
	_choose_path(SLOT_RIGHT, SAMPLE_WAV_PATH)

func _on_right_load_button_pressed() -> void:
	_load_selected_path(SLOT_RIGHT)

func _on_right_play_button_pressed() -> void:
	_play_slot(SLOT_RIGHT)

func _on_right_pause_button_pressed() -> void:
	_pause_slot(SLOT_RIGHT)

func _on_right_resume_button_pressed() -> void:
	_resume_slot(SLOT_RIGHT)

func _on_right_stop_button_pressed() -> void:
	_stop_slot(SLOT_RIGHT)

func _on_right_unload_button_pressed() -> void:
	_unload_slot(SLOT_RIGHT)

func _on_right_seek_slider_drag_started() -> void:
	_set_slot_seek_suspended(SLOT_RIGHT, true)

func _on_right_seek_slider_drag_ended(_value_changed: bool) -> void:
	_set_slot_seek_suspended(SLOT_RIGHT, false)
	_apply_slot_seek(SLOT_RIGHT)

func _on_right_volume_slider_value_changed(value: float) -> void:
	_apply_slot_volume(SLOT_RIGHT, value)

func _on_right_loop_check_box_toggled(toggled_on: bool) -> void:
	_apply_slot_loop(SLOT_RIGHT, toggled_on)
