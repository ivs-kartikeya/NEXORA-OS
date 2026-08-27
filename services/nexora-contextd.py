#!/usr/bin/env python3
"""Nexora OS V1.0.1-beta.1 context daemon.

Always-on awareness is intentionally cheap and event-driven. It never runs an
LLM and does not capture screenshots, microphone, camera, browser history or
credential stores. V1 keeps expensive sensors event-driven and avoids walking /proc at
high frequency: expensive sensors are cached and project changes wake the loop.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path

HOME = Path.home()
PROJECTS = HOME / "NexoraProjects"
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "nexora"
CONTEXT = STATE / "context.json"
PRIVATE = STATE / "private_mode"
EVENTS = deque(maxlen=16)
EVENT_LOCK = threading.Lock()
DIRTY = threading.Event()

KNOWN_APPS = {
    "freecad": "FreeCAD", "FreeCAD": "FreeCAD",
    "kicad": "KiCad", "pcbnew": "KiCad PCB Editor", "eeschema": "KiCad Schematic Editor",
    "gmsh": "Gmsh", "paraview": "ParaView",
    "simpleFoam": "OpenFOAM", "pisoFoam": "OpenFOAM", "icoFoam": "OpenFOAM",
    "code": "VS Code", "codium": "VSCodium", "blender": "Blender",
    "octave": "Octave", "calculix": "CalculiX",
}


def ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def add_event(message: str) -> None:
    with EVENT_LOCK:
        EVENTS.appendleft(f"{ts()}  {message}")
    DIRTY.set()


def private_mode() -> bool:
    try:
        return PRIVATE.read_text().strip() == "1"
    except OSError:
        return False


def scan_user_processes() -> tuple[list[str], list[dict]]:
    """One /proc walk supplies both engineering-app and top-process context."""
    known: set[str] = set()
    items: list[tuple[int, int, str]] = []
    uid = os.getuid()
    try:
        entries = list(Path("/proc").iterdir())
    except OSError:
        return [], []

    for p in entries:
        if not p.name.isdigit():
            continue
        try:
            if p.stat().st_uid != uid:
                continue
            name = (p / "comm").read_text(errors="ignore").strip()
            if name in KNOWN_APPS:
                known.add(KNOWN_APPS[name])
            status = (p / "status").read_text(errors="ignore")
            rss = 0
            for line in status.splitlines():
                if line.startswith("VmRSS:"):
                    rss = int(line.split()[1])
                    break
            if name and name not in {"nexora-contextd.py", "tonyd.py"}:
                items.append((rss, int(p.name), name))
        except (OSError, PermissionError, ValueError):
            continue

    items.sort(reverse=True)
    top = [{"pid": pid, "name": name, "rss_mib": round(rss / 1024, 1)} for rss, pid, name in items[:8]]
    return sorted(known), top


def read_mem() -> tuple[float, float]:
    vals: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, val = line.split(":", 1)
            vals[key] = int(val.strip().split()[0])
        total = vals.get("MemTotal", 0) / 1024 / 1024
        avail = vals.get("MemAvailable", 0) / 1024 / 1024
        return round(total - avail, 2), round(total, 2)
    except Exception:
        return 0.0, 0.0


def network_online() -> bool:
    try:
        for iface in Path("/sys/class/net").iterdir():
            if iface.name == "lo":
                continue
            try:
                if (iface / "operstate").read_text().strip() == "up":
                    return True
            except OSError:
                pass
    except OSError:
        pass
    return False


def recent_project() -> str:
    PROJECTS.mkdir(parents=True, exist_ok=True)
    newest: tuple[float, str] | None = None
    try:
        for p in PROJECTS.iterdir():
            if not p.is_dir():
                continue
            try:
                latest = p.stat().st_mtime
                # One level is enough for a cheap recency hint. inotify provides
                # the precise event stream separately.
                for child in p.iterdir():
                    try:
                        latest = max(latest, child.stat().st_mtime)
                    except OSError:
                        pass
                item = (latest, p.name)
                if newest is None or item > newest:
                    newest = item
            except OSError:
                pass
    except OSError:
        pass
    return newest[1] if newest else ""


def snapshot_payload(pm: bool, apps: list[str], top: list[dict], used: float, total: float,
                     online: bool, project: str) -> dict:
    if pm:
        summary = "Private mode · awareness paused by user"
    elif apps:
        summary = "Engineering activity detected · " + ", ".join(apps)
    elif project:
        summary = f"System aware · recent project {project}"
    else:
        summary = "System aware · workspace idle"

    with EVENT_LOCK:
        events = list(EVENTS)
    return {
        "version": 4,
        "hostname": socket.gethostname(),
        "private_mode": pm,
        "network_online": online,
        "engineering_apps": [] if pm else apps,
        "current_project": "" if pm else project,
        "top_processes": [] if pm else top,
        "memory_used_gib": used,
        "memory_total_gib": total,
        "summary": summary,
        "recent_events": ["Observation paused in Private Mode"] if pm else events,
    }


def atomic_write(payload: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    out = dict(payload)
    out["timestamp"] = datetime.now().isoformat(timespec="seconds")
    tmp = CONTEXT.with_suffix(".tmp")
    tmp.write_text(json.dumps(out, indent=2))
    tmp.replace(CONTEXT)


def watch_projects() -> None:
    PROJECTS.mkdir(parents=True, exist_ok=True)
    cmd = [
        "inotifywait", "-m", "-r", "-q",
        "-e", "create,modify,move,delete,close_write",
        "--format", "%e|%w%f", str(PROJECTS),
    ]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, bufsize=1)
    except FileNotFoundError:
        add_event("inotifywait unavailable; project event awareness disabled")
        return

    assert proc.stdout
    for line in proc.stdout:
        if private_mode():
            continue
        try:
            event, path = line.rstrip().split("|", 1)
            rel = os.path.relpath(path, PROJECTS)
            if "/.nexora/" in f"/{rel}/" or rel.startswith(".nexora/"):
                continue
            add_event(f"{event.split(',')[0]} · {rel}")
        except Exception:
            continue


def main() -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    PROJECTS.mkdir(parents=True, exist_ok=True)
    if not PRIVATE.exists():
        PRIVATE.write_text("0\n")

    add_event("Context service online")
    threading.Thread(target=watch_projects, daemon=True, name="nexora-project-watch").start()

    apps: list[str] = []
    top: list[dict] = []
    used = total = 0.0
    online = False
    project = ""
    previous_apps: set[str] = set()
    previous_payload: dict | None = None
    last_proc = last_mem = last_net = last_project = last_write = 0.0

    while True:
        now = time.monotonic()
        pm = private_mode()

        if not pm and (now - last_proc >= 4.0 or DIRTY.is_set()):
            apps, top = scan_user_processes()
            current = set(apps)
            for app in current - previous_apps:
                add_event(f"Application active · {app}")
            for app in previous_apps - current:
                add_event(f"Application closed · {app}")
            previous_apps = current
            last_proc = now
        elif pm:
            apps, top, previous_apps = [], [], set()

        if now - last_mem >= 6.0:
            used, total = read_mem(); last_mem = now
        if now - last_net >= 12.0:
            online = network_online(); last_net = now
        if not pm and (now - last_project >= 8.0 or DIRTY.is_set()):
            project = recent_project(); last_project = now
        elif pm:
            project = ""

        payload = snapshot_payload(pm, apps, top, used, total, online, project)
        if payload != previous_payload or now - last_write >= 15.0:
            atomic_write(payload)
            previous_payload = payload
            last_write = now

        DIRTY.clear()
        DIRTY.wait(timeout=2.5)


if __name__ == "__main__":
    main()
