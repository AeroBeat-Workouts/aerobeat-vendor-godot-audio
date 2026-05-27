# AeroBeat Vendor Godot Audio

This repo owns the **Godot-specific audio backend/factory layer** for AeroBeat's current local playback needs.

It is intentionally narrow:

- **Formats in this slice:** `.ogg` and `.wav`
- **Path support:** packaged `res://` assets plus arbitrary local absolute file paths outside the project tree
- **Operations:** load, unload, play, pause, resume, stop, volume, loop, and seek
- **Multi-audio stance:** one manager can now own multiple independent audio slots/instances while preserving the original primary-slot API
- **Async ergonomics:** promise-like success/failure callbacks on each manager operation plus state-change listening
- **Collision-safety stance:** this repo must not export a generic `AeroToolManager` global class

## Current package surface

The public package surface centers on explicit Godot-audio entrypoints:

- `src/AeroGodotAudioBackend.gd` — the Godot-native backend built on `AudioStreamPlayer`
- `src/AeroAudioPlaybackManager.gd` — the slot-aware public playback facade for this vendor slice
- `src/AeroGodotAudioBackendFactory.gd` — a convenience factory that creates a backend or a pre-wired manager
- `src/AeroAudioOperation.gd` — promise-like success/failure callback carrier for manager operations

## Behavior covered in this repo

- load packaged `.ogg` / `.wav` assets from `res://...`
- load arbitrary local `.ogg` / `.wav` files from outside the project tree
- attach or create an `AudioStreamPlayer`
- play / pause / resume / stop / unload
- enable or disable loop mode before or after load
- seek and volume updates
- run multiple independent audio slots through a single manager via `slot` names or explicit slot arguments
- state snapshots, active-slot compatibility signals, and per-slot event signals
- failure reporting for unsupported or missing paths

## Multi-audio usage notes

The manager keeps backward compatibility with the original single-slot surface by defaulting to the `primary` slot. New multi-audio helpers include:

- `attach_slot_surface(slot_name, node)`
- `detach_slot_surface(slot_name)`
- `get_state(slot_name)` / `get_media_info(slot_name)` / `get_position(slot_name)`
- `play(slot_name)` / `pause(slot_name)` / `resume(slot_name)` / `stop(slot_name)` / `seek(seconds, slot_name)`
- `set_loop(enabled, slot_name)` / `set_volume_db(volume_db, slot_name)`
- `slot_state_changed`, `slot_position_changed`, `slot_media_loaded`, `slot_playback_finished`, and `slot_error_raised`

Sources may also declare their target slot inline with `{"slot": "left", ...}`.

## Repo-local proving surface

The hidden `.testbed/` workbench includes a real audio proving surface:

- root fixtures: `assets/audio/test-tone.ogg` and `assets/audio/test-tone.wav`
- manual scene: `.testbed/scenes/audio_backend_testbed.tscn`
- manual driver: `.testbed/scripts/audio_backend_testbed.gd`
- automated coverage: `.testbed/tests/test_AeroGodotAudioBackendFactory.gd`

The testbed UI now exposes **two independent audio slots** (`left` and `right`) with their own path selection, load/playback controls, volume sliders, seek sliders, and loop toggles so multi-audio behavior can be verified by hand.

## GodotEnv development flow

This repo uses the AeroBeat GodotEnv package convention.

- Canonical dev/test manifest: `.testbed/addons.jsonc`
- Installed dev/test addons: `.testbed/addons/`
- GodotEnv cache: `.testbed/.addons/`
- Hidden workbench project: `.testbed/project.godot`
- Repo-local unit tests: `.testbed/tests/`

The repo root remains the package/published boundary for downstream consumers. Day-to-day debugging and validation happen from the hidden `.testbed/` workbench using the pinned OpenClaw Godot toolchain.

### Restore dev/test dependencies

From the repo root:

```bash
cd .testbed
godotenv addons install
```

### Open the workbench

From the repo root:

```bash
godot --editor --path .testbed
```

Then open `.testbed/scenes/audio_backend_testbed.tscn`.

### Import smoke check

From the repo root:

```bash
godot --headless --path .testbed --import
```

### Run unit tests

From the repo root:

```bash
godot --headless --path .testbed --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```

## Validation notes

- `.testbed/addons.jsonc` remains the committed dev/test dependency contract.
- Real implementation lives in repo-root `src/`, `assets/`, and `/.testbed/`, not mirrored addon copies.
- External absolute-file coverage is exercised by copying the committed sample assets outside the project tree during tests.
- Loop and multi-slot behavior are covered both in headless tests and in the hidden two-slot proving scene.
