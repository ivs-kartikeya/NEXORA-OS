#!/usr/bin/env python3
"""Nexora OS V1.0.1-beta.1 local voice service.

Goals for the stabilization build:
- recording/transcription/TTS are completely local
- heavy speech engines are process-on-demand, not resident
- capture always follows the user's default PipeWire/Pulse source when possible
- recorded speech is normalized/trimmed before Whisper sees it
- Whisper writes a clean transcript file (we no longer scrape its console logs)
- every TTS backend creates a WAV and playback is routed through PipeWire/ALSA
"""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "nexora" / "voice"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "nexora"
STATUS_FILE = STATE_DIR / "voice.json"
CONFIG_FILE = DATA / "config.json"
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = int(os.environ.get("NEXORA_VOICE_PORT", "8767"))
WHISPER_DIR = DATA / "whisper.cpp"
WHISPER_BIN = WHISPER_DIR / "build" / "bin" / "whisper-cli"
WHISPER_MODEL = DATA / "models" / "ggml-base.en.bin"
PIPER_VENV = DATA / "piper-venv"
PIPER_PYTHON = PIPER_VENV / "bin" / "python"
PIPER_VOICE_DIR = DATA / "piper-voices"
PIPER_VOICE = PIPER_VOICE_DIR / "en_US-lessac-medium.onnx"
RECORDING_RAW = DATA / "capture-raw.wav"
RECORDING_CLEAN = DATA / "capture-clean.wav"
TRANSCRIPT_PREFIX = DATA / "transcript"
TRANSCRIPT_FILE = Path(str(TRANSCRIPT_PREFIX) + ".txt")
SPEECH_FILE = DATA / "speech.wav"

LOCK = threading.RLock()
RECORDER: subprocess.Popen | None = None
SPEAKER: subprocess.Popen | None = None
RECORDING_STARTED = 0.0
STATE = "ready"
LAST_TRANSCRIPT = ""
LAST_ERROR = ""
LAST_CAPTURE_SECONDS = 0.0
LAST_STT_SECONDS = 0.0
LAST_TTS_BACKEND = ""


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_config() -> dict:
    default = {
        "speak_replies": True,
        "tts_backend": "natural",
        "voice": "en_US-lessac-medium",
        "max_record_seconds": 18,
        "minimum_record_seconds": 0.55,
        "speech_rate": 1.0,
    }
    try:
        raw = json.loads(CONFIG_FILE.read_text())
        if isinstance(raw, dict):
            default.update(raw)
    except Exception:
        pass
    return default


def save_config(update: dict) -> dict:
    DATA.mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    for key in (
        "speak_replies", "tts_backend", "voice", "max_record_seconds",
        "minimum_record_seconds", "speech_rate",
    ):
        if key in update:
            cfg[key] = update[key]
    if cfg.get("tts_backend") not in {"natural", "system"}:
        cfg["tts_backend"] = "natural"
    try:
        cfg["max_record_seconds"] = max(3, min(45, int(cfg.get("max_record_seconds", 18))))
    except Exception:
        cfg["max_record_seconds"] = 18
    try:
        cfg["minimum_record_seconds"] = max(0.25, min(2.0, float(cfg.get("minimum_record_seconds", 0.55))))
    except Exception:
        cfg["minimum_record_seconds"] = 0.55
    try:
        cfg["speech_rate"] = max(0.75, min(1.35, float(cfg.get("speech_rate", 1.0))))
    except Exception:
        cfg["speech_rate"] = 1.0
    tmp = CONFIG_FILE.with_name(f".{CONFIG_FILE.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(cfg, indent=2))
    tmp.replace(CONFIG_FILE)
    return cfg


def microphone_backend() -> str:
    if shutil.which("parec"):
        return "PipeWire/Pulse"
    if shutil.which("pw-record"):
        return "PipeWire"
    if shutil.which("arecord"):
        return "ALSA"
    return ""


def playback_backend() -> str:
    if shutil.which("pw-play"):
        return "PipeWire"
    if shutil.which("paplay"):
        return "PipeWire/Pulse"
    if shutil.which("aplay"):
        return "ALSA"
    return ""


def piper_ready() -> bool:
    return PIPER_PYTHON.exists() and PIPER_VOICE.exists()


def tts_backend() -> str:
    cfg = load_config()
    if cfg.get("tts_backend") == "natural" and piper_ready():
        return "Piper · natural"
    if shutil.which("espeak-ng"):
        return "eSpeak NG · lightweight"
    return "Unavailable"


def stt_ready() -> bool:
    return WHISPER_BIN.exists() and WHISPER_MODEL.exists()


def write_status() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    with LOCK:
        payload = {
            "version": "1.0.1-beta.1",
            "timestamp": now_iso(),
            "state": STATE,
            "listening": STATE == "listening",
            "transcribing": STATE == "transcribing",
            "speaking": STATE == "speaking",
            "stt_ready": stt_ready(),
            "tts_ready": tts_backend() != "Unavailable",
            "microphone_backend": microphone_backend(),
            "playback_backend": playback_backend(),
            "tts_backend": tts_backend(),
            "last_tts_backend": LAST_TTS_BACKEND,
            "last_transcript": LAST_TRANSCRIPT,
            "last_error": LAST_ERROR,
            "last_capture_seconds": round(LAST_CAPTURE_SECONDS, 2),
            "last_stt_seconds": round(LAST_STT_SECONDS, 2),
            "config": load_config(),
        }
    tmp = STATUS_FILE.with_name(f".{STATUS_FILE.name}.{os.getpid()}.{threading.get_ident()}.tmp")
    try:
        tmp.write_text(json.dumps(payload, indent=2))
        tmp.replace(STATUS_FILE)
    finally:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass


def set_state(state: str, error: str = "") -> None:
    global STATE, LAST_ERROR
    with LOCK:
        STATE = state
        if error:
            LAST_ERROR = error[:800]
        elif state != "error":
            LAST_ERROR = ""
    write_status()


def stop_process(proc: subprocess.Popen | None, timeout: float = 1.5) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.send_signal(signal.SIGINT)
        proc.wait(timeout=timeout)
    except Exception:
        try:
            proc.terminate()
            proc.wait(timeout=0.8)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


def recorder_command() -> list[str] | None:
    """Prefer the Pulse compatibility layer because @DEFAULT_SOURCE@ is stable.

    On Nexora, Pulse is provided by pipewire-pulse, so this still stays entirely
    inside PipeWire while selecting exactly the same default mic the UI uses.
    """
    if shutil.which("parec"):
        return [
            "parec", "--device=@DEFAULT_SOURCE@", "--file-format=wav",
            "--rate=16000", "--channels=1", "--format=s16le", str(RECORDING_RAW),
        ]
    if shutil.which("pw-record"):
        return ["pw-record", "--rate=16000", "--channels=1", "--format=s16", str(RECORDING_RAW)]
    if shutil.which("arecord"):
        return ["arecord", "-q", "-f", "S16_LE", "-r", "16000", "-c", "1", str(RECORDING_RAW)]
    return None


def start_listening() -> dict:
    global RECORDER, RECORDING_STARTED
    with LOCK:
        if RECORDER and RECORDER.poll() is None:
            return {"ok": True, "state": "listening", "message": "Already listening."}
        stop_speaking()
        DATA.mkdir(parents=True, exist_ok=True)
        for path in (RECORDING_RAW, RECORDING_CLEAN, TRANSCRIPT_FILE):
            try:
                path.unlink(missing_ok=True)
            except Exception:
                pass
        cmd = recorder_command()
        if not cmd:
            set_state("error", "No microphone backend. Install pulseaudio-utils, pipewire-bin or alsa-utils.")
            return {"ok": False, "error": LAST_ERROR}
        try:
            RECORDER = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.08)
            if RECORDER.poll() is not None:
                raise RuntimeError("the selected microphone source could not be opened")
            RECORDING_STARTED = time.monotonic()
            set_state("listening")
            return {"ok": True, "state": "listening", "message": "Listening locally."}
        except Exception as exc:
            RECORDER = None
            set_state("error", f"Could not start microphone: {exc}")
            return {"ok": False, "error": LAST_ERROR}


def preprocess_recording() -> Path:
    """Normalize speech before Whisper.

    VM microphones are frequently quiet/noisy. ffmpeg gives us a cheap, short
    post-recording pass without keeping DSP running in the background.
    """
    if not RECORDING_RAW.exists():
        return RECORDING_RAW
    if not shutil.which("ffmpeg"):
        return RECORDING_RAW
    # Conservative filters: remove rumble, trim obvious silence, normalize gain.
    filters = (
        "highpass=f=80,lowpass=f=7600,"
        "silenceremove=start_periods=1:start_duration=0.08:start_threshold=-48dB:"
        "stop_periods=-1:stop_duration=0.28:stop_threshold=-48dB,"
        "dynaudnorm=f=150:g=12"
    )
    cmd = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(RECORDING_RAW), "-ac", "1", "-ar", "16000", "-af", filters,
        str(RECORDING_CLEAN),
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=12)
        if proc.returncode == 0 and RECORDING_CLEAN.exists() and RECORDING_CLEAN.stat().st_size > 1200:
            return RECORDING_CLEAN
    except Exception:
        pass
    return RECORDING_RAW


def transcribe_recording() -> tuple[bool, str]:
    global LAST_TRANSCRIPT, LAST_STT_SECONDS
    if not stt_ready():
        return False, "Whisper is not ready. Run the V1.0.1-beta.1 voice repair script."
    source = preprocess_recording()
    if not source.exists() or source.stat().st_size < 1200:
        return False, "No usable microphone audio was captured."

    try:
        TRANSCRIPT_FILE.unlink(missing_ok=True)
    except Exception:
        pass

    prompt = "Tony, Nexora OS, FreeCAD, KiCad, OpenFOAM, CAD, CFD, FEA, Python, Git, terminal, project."
    threads = str(max(2, min(6, (os.cpu_count() or 4) // 2)))
    cmd = [
        str(WHISPER_BIN), "-m", str(WHISPER_MODEL), "-f", str(source),
        "-l", "en", "-t", threads, "-nt", "-np", "-sns",
        "--prompt", prompt, "-otxt", "-of", str(TRANSCRIPT_PREFIX),
    ]
    started = time.monotonic()
    try:
        proc = subprocess.run(cmd, text=True, stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, timeout=55)
        LAST_STT_SECONDS = time.monotonic() - started
        if proc.returncode != 0:
            err = (proc.stderr or "").strip().splitlines()[-1:] or ["unknown Whisper error"]
            return False, "Speech transcription failed: " + err[0][:300]
        text = ""
        if TRANSCRIPT_FILE.exists():
            text = TRANSCRIPT_FILE.read_text(errors="replace").strip()
        text = re.sub(r"\s+", " ", text).strip()
        # Whisper sometimes emits these for near-silence; don't send them to Tony.
        if text.lower().strip(" .[]") in {"", "music", "silence", "blank audio", "inaudible"}:
            text = ""
        if not text:
            return False, "I couldn't make out speech clearly. Try speaking a little closer to the microphone."
        LAST_TRANSCRIPT = text[:6000]
        return True, LAST_TRANSCRIPT
    except subprocess.TimeoutExpired:
        LAST_STT_SECONDS = time.monotonic() - started
        return False, "Speech transcription timed out."
    except Exception as exc:
        LAST_STT_SECONDS = time.monotonic() - started
        return False, f"Speech transcription failed: {exc}"


def stop_listening() -> dict:
    global RECORDER, LAST_CAPTURE_SECONDS
    with LOCK:
        if not RECORDER or RECORDER.poll() is not None:
            RECORDER = None
            set_state("ready")
            return {"ok": False, "error": "Tony was not listening."}
        LAST_CAPTURE_SECONDS = max(0.0, time.monotonic() - RECORDING_STARTED)
        stop_process(RECORDER)
        RECORDER = None
        cfg = load_config()
        if LAST_CAPTURE_SECONDS < float(cfg.get("minimum_record_seconds", 0.55)):
            set_state("error", "That recording was too short. Hold the mic for at least half a second.")
            return {"ok": False, "state": "error", "error": LAST_ERROR}
        set_state("transcribing")
    ok, text = transcribe_recording()
    if ok:
        set_state("ready")
        return {"ok": True, "state": "ready", "transcript": text}
    set_state("error", text)
    return {"ok": False, "state": "error", "error": text}


def stop_speaking() -> dict:
    global SPEAKER
    with LOCK:
        stop_process(SPEAKER, timeout=0.8)
        SPEAKER = None
        if STATE == "speaking":
            set_state("ready")
    return {"ok": True}


def synthesize_piper(text: str) -> bool:
    if not piper_ready():
        return False
    try:
        SPEECH_FILE.unlink(missing_ok=True)
    except Exception:
        pass
    cfg = load_config()
    length_scale = max(0.75, min(1.35, 1.0 / float(cfg.get("speech_rate", 1.0))))
    cmd = [
        str(PIPER_PYTHON), "-m", "piper", "-m", str(PIPER_VOICE),
        "-f", str(SPEECH_FILE), "--length-scale", f"{length_scale:.3f}", "--", text,
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                              timeout=30, text=True)
        return proc.returncode == 0 and SPEECH_FILE.exists() and SPEECH_FILE.stat().st_size > 1000
    except Exception:
        return False


def synthesize_espeak(text: str) -> bool:
    """Generate a WAV instead of letting eSpeak pick an ALSA device itself."""
    if not shutil.which("espeak-ng"):
        return False
    try:
        SPEECH_FILE.unlink(missing_ok=True)
    except Exception:
        pass
    cfg = load_config()
    speed = int(168 * float(cfg.get("speech_rate", 1.0)))
    cmd = ["espeak-ng", "-s", str(max(120, min(230, speed))), "-p", "38", "-w", str(SPEECH_FILE), text]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=20)
        return proc.returncode == 0 and SPEECH_FILE.exists() and SPEECH_FILE.stat().st_size > 1000
    except Exception:
        return False


def play_wav(path: Path) -> subprocess.Popen | None:
    if shutil.which("pw-play"):
        return subprocess.Popen(["pw-play", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which("paplay"):
        return subprocess.Popen(["paplay", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which("aplay"):
        return subprocess.Popen(["aplay", "-q", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return None


def speak(text: str) -> dict:
    global SPEAKER, LAST_TTS_BACKEND
    text = re.sub(r"\s+", " ", str(text)).strip()[:1800]
    if not text:
        return {"ok": False, "error": "Nothing to speak."}
    stop_speaking()
    cfg = load_config()
    set_state("speaking")
    try:
        rendered = False
        backend = ""
        if cfg.get("tts_backend") == "natural":
            rendered = synthesize_piper(text)
            if rendered:
                backend = "Piper"
        if not rendered:
            rendered = synthesize_espeak(text)
            if rendered:
                backend = "eSpeak NG"
        if not rendered:
            set_state("error", "No working text-to-speech renderer is available.")
            return {"ok": False, "error": LAST_ERROR}
        SPEAKER = play_wav(SPEECH_FILE)
        if SPEAKER is None:
            set_state("error", "Speech was generated, but no audio playback backend is available.")
            return {"ok": False, "error": LAST_ERROR}
        LAST_TTS_BACKEND = backend

        def waiter(proc: subprocess.Popen) -> None:
            global SPEAKER
            try:
                proc.wait(timeout=90)
            except Exception:
                stop_process(proc)
            with LOCK:
                if SPEAKER is proc:
                    SPEAKER = None
                    if STATE == "speaking":
                        set_state("ready")

        threading.Thread(target=waiter, args=(SPEAKER,), daemon=True).start()
        return {"ok": True, "state": "speaking", "backend": backend}
    except Exception as exc:
        SPEAKER = None
        set_state("error", f"Speech failed: {exc}")
        return {"ok": False, "error": LAST_ERROR}


def health_payload() -> dict:
    write_status()
    try:
        return json.loads(STATUS_FILE.read_text())
    except Exception:
        return {"version": "1.0.1-beta.1", "state": STATE, "stt_ready": stt_ready(), "tts_backend": tts_backend()}


def watchdog() -> None:
    global RECORDER
    while True:
        try:
            cfg = load_config()
            with LOCK:
                if RECORDER and RECORDER.poll() is None and RECORDING_STARTED > 0:
                    if time.monotonic() - RECORDING_STARTED > int(cfg.get("max_record_seconds", 18)):
                        stop_process(RECORDER)
                        RECORDER = None
                        set_state("error", "Listening stopped after the safety limit. Press the mic and try again.")
        except Exception:
            pass
        time.sleep(0.5)


class Handler(BaseHTTPRequestHandler):
    server_version = "Nexora-Voice/1.0.1-beta.1"

    def log_message(self, fmt: str, *args) -> None:
        if self.path != "/health":
            super().log_message(fmt, *args)

    def send_json(self, obj: dict, status: int = 200) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict:
        size = min(int(self.headers.get("Content-Length", "0") or 0), 100_000)
        try:
            return json.loads(self.rfile.read(size).decode("utf-8", "replace") or "{}")
        except Exception:
            return {}

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_json(health_payload())
            return
        self.send_json({"ok": False, "error": "not found"}, 404)

    def do_POST(self) -> None:
        obj = self.read_json()
        if self.path == "/listen/start":
            self.send_json(start_listening())
            return
        if self.path == "/listen/stop":
            self.send_json(stop_listening())
            return
        if self.path == "/speak":
            self.send_json(speak(str(obj.get("text", ""))))
            return
        if self.path == "/speak/stop":
            self.send_json(stop_speaking())
            return
        if self.path == "/config":
            self.send_json({"ok": True, "config": save_config(obj)})
            write_status()
            return
        self.send_json({"ok": False, "error": "not found"}, 404)


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "models").mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        save_config({})
    set_state("ready")
    threading.Thread(target=watchdog, daemon=True, name="voice-watchdog").start()
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    server.daemon_threads = True
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        stop_process(RECORDER)
        stop_process(SPEAKER)


if __name__ == "__main__":
    main()
