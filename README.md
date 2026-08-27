# Nexora OS V1 Public Beta

Nexora OS is a Linux-based, local-first desktop operating environment built around engineering projects and a system-level AI called **Tony**.

V1 is the first release intended for **public testing**. It is still beta software: test it in VMware/VirtualBox or on non-critical hardware before trusting it with important work.

## V1.0.1 RAM/Monitor stabilization

This public-beta revision fixes RAM telemetry and replaces the first System Monitor UI with a more native Overview / Processes design. Physical memory is read robustly from `/proc/meminfo`, with a shell-side fallback so the UI remains populated even if a Core status signal is missed.


## What changed in V1

### Desktop / UX

- New calmer blue/teal wallpaper with a subtle engineering-grid texture.
- Refined floating taskbar and top system capsule.
- Cleaner Tony, Control Center, launcher, and app surfaces.
- Control Center quick actions for Files, Console and Apps.
- User-facing shortcuts no longer say “Super”. V1 uses normal PC combinations:
  - `Ctrl + Space` — Tony
  - `Ctrl + Shift + Space` — start/stop listening
  - `Ctrl + Alt + T` — Nexora Console
  - `Ctrl + Alt + F` — Files
  - `Ctrl + Alt + A` — App Center
  - `Ctrl + Alt + P` — Projects
  - `Ctrl + Alt + D` — Show Desktop

### Nexora Console

The old line-by-line pseudo terminal has been replaced by a persistent **PTY-backed shell session** with a PowerShell-inspired interface. `cd`, environment state, interactive shell processes and Ctrl-C/Break now operate inside one real Bash session instead of spawning a new Bash process per command.

### Tony Voice

- Canonical Voice service path fixed permanently.
- Listen button has explicit Starting / Listening / Working / Stop states.
- Voice service auto-start/retry if it is temporarily offline.
- Re-entrant listen clicks are blocked while transcription is running.
- Push-to-talk remains local and explicit; no permanently hot microphone.

### Backend

- Nexora Core, Context, Tony and Voice remain isolated services.
- Tony's LLM remains lazy-loaded to protect idle RAM.
- Existing user data, projects, notes and Tony memory survive an in-place V1 upgrade.

### Public ISO

V1 adds a reproducible Debian `live-build` pipeline:

```bash
./iso/build-iso.sh
```

Output:

```text
dist/NexoraOS-1.0.1-beta.5-amd64.iso
```

The V1 image is a **live public-testing ISO**, not the final production disk installer.

## Upgrade from Nexora 0.8.x

Take a VMware snapshot first. Log into the Plasma recovery session, extract this release, then run:

```bash
cd ~/NexoraOS-V1.0-PublicBeta
./scripts/upgrade-v1.sh
```

Do not log out until Doctor says:

```text
READY: Nexora OS V1 Public Beta is safe to test.
```

Then log out and select **Nexora OS**.

## Build the public ISO

After V1 itself passes your local tests:

```bash
./iso/build-iso.sh
```

Boot the generated ISO in a completely new VM. Only publish it after that fresh-boot test passes.

See `GITHUB_RELEASE.md` for release-upload instructions.

## Source layout

```text
src/       Nexora shell/Core C++
qml/       Desktop and core-app UI
services/  Context, Tony and Voice services
session/   Native Wayland session / shell supervisor
kwin/      Third-party window/taskbar bridge
runtime/   Tony local model launcher
iso/       Public live-ISO builder
docs/      Architecture and test documentation
```

## Important beta limitations

- V1 is an amd64 public beta.
- Hardware support has not yet been certified across laptop vendors.
- The ISO is a live testing image; the production installer/update/rollback system comes later.
- Tony can perform many OS actions, but destructive and privileged actions remain permission-gated.
- Do not ship cracked/pirated commercial software inside Nexora images or repositories.
