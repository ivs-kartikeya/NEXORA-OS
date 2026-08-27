# Nexora OS V1.0.1 Public Beta

## Resource Monitor stabilization

- Fixed RAM telemetry that could display zero/blank when `/proc/meminfo` whitespace was parsed incorrectly in the shell fallback.
- Added a direct low-cost RAM sample in the shell so a missed Core D-Bus update cannot blank the Memory UI.
- Reworked System Monitor into an OS-style Overview / Processes utility.
- Memory now shows used, total, available, percentage and live usage bar.
- Processes refresh every two seconds and remain sorted by memory use.
- Preserves the V1 PTY Console, Tony, Voice and public ISO pipeline.

This is the first public testing release of Nexora OS. It is still beta software: use it in a VM or on non-critical hardware.

## Highlights

- Nexora desktop/session on Wayland + KWin
- Tony local AI with local memory and system controls
- On-device push-to-talk transcription and speech
- New Ctrl/Alt keyboard shortcuts that work cleanly in VMs
- Fixed Voice service startup/path handling
- More reliable Listen state machine with visible busy/transcribing states
- Redesigned calm blue/teal V1 desktop and taskbar
- Nexora Console: PowerShell-inspired UI backed by a persistent PTY shell
- Core/Context/Tony/Voice service isolation
- App Center, Files, Projects, Notes, Monitor, Control Center
- Live ISO build pipeline for public testing

## Public-beta warning

Nexora OS V1 is not yet the production installer. The provided image is a live test image. Back up important data and test in a VM first.
