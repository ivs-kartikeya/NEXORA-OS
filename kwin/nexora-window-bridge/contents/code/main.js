// Nexora OS 1.0.1-beta.1 window bridge.
// KWin remains the compositor/window manager; Nexora OS owns the taskbar.
// This script only emits metadata about normal application windows. It never
// reads window contents, screenshots, keyboard input, or document data.

const SERVICE = "org.nexora.Shell";
const PATH = "/WindowBridge";
const IFACE = "org.nexora.WindowBridge";
const hooked = {};

function windowId(w) {
    return String(w.internalId);
}

function visibleInTaskbar(w) {
    return !!w && w.managed && !w.specialWindow && !w.skipTaskbar && !w.deleted;
}

function remove(w) {
    if (!w) return;
    callDBus(SERVICE, PATH, IFACE, "removeWindow", windowId(w));
}

function report(w) {
    if (!w) return;
    if (!visibleInTaskbar(w)) {
        remove(w);
        return;
    }
    callDBus(
        SERVICE,
        PATH,
        IFACE,
        "reportWindow",
        windowId(w),
        String(w.caption || "Application"),
        String(w.desktopFileName || ""),
        Number(w.pid || 0),
        !!w.minimized,
        !!w.active,
        !!w.demandsAttention
    );
}

function hook(w) {
    if (!w) return;
    const id = windowId(w);
    if (hooked[id]) {
        report(w);
        return;
    }
    hooked[id] = true;

    w.captionChanged.connect(function() { report(w); });
    w.desktopFileNameChanged.connect(function() { report(w); });
    w.minimizedChanged.connect(function() { report(w); });
    w.activeChanged.connect(function() { report(w); });
    w.demandsAttentionChanged.connect(function() { report(w); });
    w.skipTaskbarChanged.connect(function() { report(w); });
    report(w);
}

const initial = workspace.stackingOrder;
for (let i = 0; i < initial.length; ++i) hook(initial[i]);

workspace.windowAdded.connect(function(w) { hook(w); });
workspace.windowRemoved.connect(function(w) {
    if (!w) return;
    const id = windowId(w);
    delete hooked[id];
    remove(w);
});
workspace.windowActivated.connect(function(w) {
    if (w) report(w);
});
