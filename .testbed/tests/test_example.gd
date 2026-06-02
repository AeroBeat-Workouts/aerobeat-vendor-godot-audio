extends GutTest

const README_PATH := "../README.md"
const PLUGIN_CFG_PATH := "../plugin.cfg"
const ADDONS_MANIFEST_PATH := "addons.jsonc"
const EXPECTED_PLUGIN_DESCRIPTION := "Collision-safe Godot audio backend/factory layer for local .ogg/.wav playback with callbacks and testbed coverage."

func _read_repo_file(relative_path: String) -> String:
	var absolute_path := ProjectSettings.globalize_path("res://%s" % relative_path)
	assert_true(FileAccess.file_exists(absolute_path), "Expected repo file to exist: %s" % absolute_path)
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	assert_true(file != null, "Expected repo file to open: %s" % absolute_path)
	return file.get_as_text()

func test_readme_states_the_real_audio_scope() -> void:
	var readme_text := _read_repo_file(README_PATH)
	assert_true(readme_text.contains("Godot-specific audio backend/factory layer"), "README should describe the real repo scope")
	assert_true(readme_text.contains(".ogg"), "README should mention OGG support")
	assert_true(readme_text.contains(".wav"), "README should mention WAV support")
	assert_true(readme_text.contains("arbitrary local absolute file paths"), "README should mention absolute local file support")
	assert_true(readme_text.contains("promise-like success/failure callbacks"), "README should mention the callback contract")
	assert_true(readme_text.contains("audio_backend_testbed.tscn"), "README should mention the hidden proving scene")

func test_plugin_cfg_description_matches_audio_backend_truth() -> void:
	var config := ConfigFile.new()
	var error := config.load(ProjectSettings.globalize_path("res://%s" % PLUGIN_CFG_PATH))
	assert_eq(error, OK, "plugin.cfg should parse cleanly")
	assert_eq(config.get_value("plugin", "name", ""), "AeroBeat Vendor Godot Audio", "plugin.cfg name should stay stable")
	assert_eq(config.get_value("plugin", "description", ""), EXPECTED_PLUGIN_DESCRIPTION, "plugin.cfg description should match the real repo behavior")

func test_addons_manifest_keeps_expected_dependencies_only() -> void:
	var manifest_text := _read_repo_file(ADDONS_MANIFEST_PATH)
	assert_true(manifest_text.contains('"aerobeat-tool-core"'), "addons manifest should still pin aerobeat-tool-core")
	assert_true(manifest_text.contains('"aerobeat-vendor-godot-unit-test"'), "addons manifest should still pin the vendor unit-test addon for repo-local tests")
	assert_false(manifest_text.contains('"aerobeat-tool-video-player"'), "audio vendor repo should not depend on the video-player package")
