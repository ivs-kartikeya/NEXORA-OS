# Nexora OS V1 Public Beta test checklist

## Session
- Nexora logs in without Plasma underneath.
- Shell crash supervisor restarts the shell rather than ending the session.
- Files / Projects / Settings / App Center open and close normally.

## Taskbar / windows
- Native windows minimize and restore from the taskbar.
- Third-party windows appear and restore.
- Show Desktop hides windows but never hides the desktop shell.

## Shortcuts
- Ctrl+Space toggles Tony.
- Ctrl+Shift+Space starts/stops listening.
- Ctrl+Alt+T opens Nexora Console.
- Ctrl+Alt+F opens Files.
- Ctrl+Alt+D toggles Show Desktop.

## Console
- `pwd`, `cd`, `ls`, `git`, `python3 --version` work.
- Current directory persists between commands.
- `Break` interrupts a running command.
- `Restart` restarts the PTY shell session.

## Tony / Voice
- Fast deterministic Tony actions work with LLM sleeping.
- A natural-language request wakes the model.
- Listen button reaches Listening state.
- Stopping Listen produces a transcript.
- Tony can speak a reply.
- Voice failure does not crash the desktop.

## Audio / Control Center
- Volume slider changes real output volume.
- Mute toggles.
- Control Center toggles closed when its top button is clicked again.

## Public ISO
- `./iso/build-iso.sh` completes.
- SHA-256 file is produced.
- ISO boots in a brand-new VM.
- Live user lands in Nexora OS.
- Tony text tools work.
- Voice service starts (microphone availability depends on VM device configuration).
