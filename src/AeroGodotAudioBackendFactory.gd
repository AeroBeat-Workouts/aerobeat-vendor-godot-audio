class_name AeroGodotAudioBackendFactory
extends RefCounted

const VERSION: String = "0.2.0"
const BACKEND_SCRIPT := preload("AeroGodotAudioBackend.gd")
const MANAGER_SCRIPT := preload("AeroAudioPlaybackManager.gd")

func create_backend(player_factory: Callable = Callable()) -> AeroGodotAudioBackend:
	var backend := BACKEND_SCRIPT.new()
	if player_factory.is_valid():
		backend.set_player_factory(player_factory)
	return backend

func create_manager(player_factory: Callable = Callable()) -> AeroAudioPlaybackManager:
	var manager := MANAGER_SCRIPT.new()
	manager.set_backend(create_backend(player_factory))
	return manager
