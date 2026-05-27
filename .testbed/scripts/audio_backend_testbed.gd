extends Control

const FACTORY_SCRIPT := preload("res://src/AeroGodotAudioBackendFactory.gd")
const SAMPLE_OGG_PATH := "res://assets/audio/test-tone.ogg"
const SAMPLE_WAV_PATH := "res://assets/audio/test-tone.wav"

@onready var path_label: Label = %PathLabel
@onready var status_label: Label = %StatusLabel
@onready var detail_label: Label = %DetailLabel
@onready var result_label: Label = %ResultLabel
@onready var slider_label: Label = %SliderLabel
@onready var player_host: Node = %PlayerHost
@onready var picker: FileDialog = %FileDialog
@onready var seek_slider: HSlider = %SeekSlider
@onready var volume_slider: HSlider = %VolumeSlider

var _factory: AeroGodotAudioBackendFactory
var _manager: AeroAudioPlaybackManager
var _selected_path: String = SAMPLE_OGG_PATH
var _suspend_seek_updates: bool = false

func _ready() -> void:
	path_label.text = _selected_path
	_factory = FACTORY_SCRIPT.new()
	_manager = _factory.create_manager()
	add_child(_manager)
	_manager.state_changed.connect(_on_state_changed)
	_manager.media_loaded.connect(_on_media_loaded)
	_manager.error_raised.connect(_on_error_raised)
	_manager.position_changed.connect(_on_position_changed)
	_manager.playback_finished.connect(_on_playback_finished)
	_manager.attach_surface(player_host)
	picker.filters = PackedStringArray(["*.ogg ; Ogg Vorbis", "*.wav ; Waveform Audio"])
	volume_slider.value = 0.0
	set_process(true)
	_refresh_labels()

func _process(_delta: float) -> void:
	_refresh_labels()

func _refresh_labels() -> void:
	if _manager == null:
		return
	var state: Dictionary = _manager.get_state()
	var media_info: Dictionary = _manager.get_media_info()
	var duration := float(state.get("duration", 0.0))
	var position := float(state.get("position", 0.0))
	status_label.text = "State: %s" % str(state.get("state", "idle"))
	detail_label.text = "Position: %.2f / %.2f | Volume: %.1f dB | Format: %s | Path type: %s" % [
		position,
		duration,
		float(state.get("volume_db", 0.0)),
		str(media_info.get("extension", "")),
		str(media_info.get("locality", "")),
	]
	slider_label.text = "Seek %.2fs | Volume %.1f dB" % [seek_slider.value, volume_slider.value]
	if not _suspend_seek_updates:
		seek_slider.max_value = maxf(duration, 0.01)
		seek_slider.value = clampf(position, 0.0, seek_slider.max_value)

func _choose_path(path: String) -> void:
	_selected_path = path
	path_label.text = _selected_path
	result_label.text = "Selected %s" % _selected_path

func _load_selected_path() -> void:
	if _selected_path.is_empty():
		result_label.text = "Pick an .ogg or .wav file first."
		return
	var source := {
		"path": _selected_path,
		"volume_db": volume_slider.value,
		"metadata": {"source": "audio_backend_testbed"},
	}
	_manager.load(source).on_success(func(result: Dictionary) -> void:
		result_label.text = "Loaded %s" % str(result.get("media_info", {}).get("path", _selected_path))
	).on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Load failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_state_changed(_state: String, _detail: Dictionary) -> void:
	_refresh_labels()

func _on_media_loaded(info: Dictionary) -> void:
	result_label.text = "Loaded %s" % str(info.get("path", ""))
	_refresh_labels()

func _on_error_raised(error_info: Dictionary) -> void:
	result_label.text = "Error: %s" % str(error_info.get("message", "Unknown error"))
	_refresh_labels()

func _on_position_changed(_seconds: float, _normalized: float) -> void:
	_refresh_labels()

func _on_playback_finished() -> void:
	result_label.text = "Playback finished"
	_refresh_labels()

func _on_choose_file_button_pressed() -> void:
	picker.popup_centered_ratio(0.8)

func _on_file_dialog_file_selected(path: String) -> void:
	_choose_path(path)

func _on_use_sample_ogg_button_pressed() -> void:
	_choose_path(SAMPLE_OGG_PATH)

func _on_use_sample_wav_button_pressed() -> void:
	_choose_path(SAMPLE_WAV_PATH)

func _on_load_button_pressed() -> void:
	_load_selected_path()

func _on_play_button_pressed() -> void:
	_manager.play().on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Play failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_pause_button_pressed() -> void:
	_manager.pause().on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Pause failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_resume_button_pressed() -> void:
	_manager.resume().on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Resume failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_stop_button_pressed() -> void:
	_manager.stop().on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Stop failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_unload_button_pressed() -> void:
	_manager.unload().on_success(func(_result: Dictionary) -> void:
		result_label.text = "Unloaded"
	)

func _on_seek_slider_drag_started() -> void:
	_suspend_seek_updates = true

func _on_seek_slider_drag_ended(_value_changed: bool) -> void:
	_suspend_seek_updates = false
	_manager.seek(seek_slider.value).on_failure(func(error_info: Dictionary) -> void:
		result_label.text = "Seek failed: %s" % str(error_info.get("message", "Unknown error"))
	)

func _on_volume_slider_value_changed(value: float) -> void:
	_manager.set_volume_db(value)
	_refresh_labels()
