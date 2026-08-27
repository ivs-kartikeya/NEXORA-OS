#include "systembackend.h"

#include <QAbstractSocket>
#include <QDateTime>
#include <QDesktopServices>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QClipboard>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QHostAddress>
#include <QHostInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAddressEntry>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QNetworkInterface>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QSysInfo>
#include <QUrl>
#include <QVariantMap>
#include <algorithm>
#include <utility>
#include <unistd.h>
#include <QTextStream>
#include <QTemporaryFile>
#include <QSocketNotifier>
#include <pty.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>

SystemBackend::SystemBackend(QObject *parent) : QObject(parent)
{
    m_hostname = QHostInfo::localHostName();
    m_kernelVersion = QSysInfo::kernelVersion();
    m_terminalWorkingDirectory = QDir::homePath();
    m_network = new QNetworkAccessManager(this);

    // Nexora OS owns the user-facing taskbar. A tiny KWin script reports
    // third-party windows here over the session bus; native core windows stay
    // in-process and do not pay that IPC cost.
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.registerService(QStringLiteral("org.nexora.Shell"))) {
        bus.registerObject(QStringLiteral("/WindowBridge"), this,
                           QDBusConnection::ExportScriptableSlots);
    }

    // V1: the shell is now a client of Nexora Core. Core owns deterministic
    // system telemetry, audio, power and project primitives and survives shell
    // restarts. Local implementations below remain as a recovery fallback.
    m_core = new QDBusInterface(QStringLiteral("org.nexora.Core"), QStringLiteral("/Core"),
                                QStringLiteral("org.nexora.Core"), bus, this);
    m_core->setTimeout(600);
    bus.connect(QStringLiteral("org.nexora.Core"), QStringLiteral("/Core"),
                QStringLiteral("org.nexora.Core"), QStringLiteral("StatusChanged"),
                this, SLOT(onCoreStatusChanged(QVariantMap)));
    bus.connect(QStringLiteral("org.nexora.Core"), QStringLiteral("/Core"),
                QStringLiteral("org.nexora.Core"), QStringLiteral("AudioChanged"),
                this, SLOT(onCoreAudioChanged(int,bool,bool)));

    connect(&m_statsTimer, &QTimer::timeout, this, &SystemBackend::updateStats);
    connect(&m_clockTimer, &QTimer::timeout, this, &SystemBackend::updateClock);
    connect(&m_audioTimer, &QTimer::timeout, this, &SystemBackend::refreshAudioAsync);
    connect(&m_tonyFallbackTimer, &QTimer::timeout, this, &SystemBackend::refreshTonyStatus);
    connect(&m_voiceTimer, &QTimer::timeout, this, &SystemBackend::refreshVoiceStatus);

    // V1 keeps the shell cheap at idle. Fast /proc reads stay local while
    // file-backed context/Tony state is event-driven through QFileSystemWatcher.
    m_statsTimer.start(3000);
    m_clockTimer.start(1000);
    m_audioTimer.start(20000);
    m_tonyFallbackTimer.start(15000);
    m_voiceTimer.start(3500);

    QDir().mkpath(stateDir());
    m_stateWatcher = new QFileSystemWatcher(this);
    m_stateWatcher->addPath(stateDir());
    connect(m_stateWatcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString &) {
        updateContext();
        refreshTonyStatus();
    });

    // Native Nexora OS session does not start Plasma's convenience
    // services. Bring up the pieces the shell owns explicitly.
    QProcess::startDetached("systemctl", {"--user", "start", "pipewire.service", "pipewire-pulse.service", "wireplumber.service"});
    QProcess::startDetached("systemctl", {"--user", "start", "nexora-core.service", "nexora-tony.service", "nexora-voice.service"});

    // A graphical polkit agent is required for App Center installs. Start it
    // from inside the shell so WAYLAND_DISPLAY is already valid.
    const QStringList polkitAgents = {
        "/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1",
        "/usr/libexec/polkit-kde-authentication-agent-1"
    };
    for (const QString &agent : polkitAgents) {
        if (QFileInfo(agent).isExecutable()) { QProcess::startDetached(agent, {}); break; }
    }

    updateClock();
    updateStats();
    updateContext();
    refreshAudioAsync();
    refreshTonyStatus();
    refreshVoiceStatus();
    QFile note(notesDir() + "/Quick Note.txt");
    if (note.open(QIODevice::ReadOnly | QIODevice::Text)) m_quickNote = QString::fromUtf8(note.readAll());
    QTimer::singleShot(1200, this, [this]() { refreshAudioAsync(); refreshTonyStatus(); refreshVoiceStatus(); });
}

SystemBackend::~SystemBackend()
{
    stopTerminalSession();
}

QString SystemBackend::stateDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/nexora";
}

QString SystemBackend::projectsDir() const
{
    return QDir::homePath() + "/NexoraProjects";
}

QString SystemBackend::notesDir() const
{
    return QDir::homePath() + "/NexoraNotes";
}

QString SystemBackend::homeDirectory() const { return QDir::homePath(); }
QString SystemBackend::projectsDirectory() const { return projectsDir(); }

void SystemBackend::readCpu()
{
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    const QString line = QString::fromUtf8(f.readLine()).simplified();
    const QStringList p = line.split(' ');
    if (p.size() < 8 || p[0] != "cpu") return;

    const qulonglong user = p[1].toULongLong();
    const qulonglong nice = p[2].toULongLong();
    const qulonglong system = p[3].toULongLong();
    const qulonglong idle = p[4].toULongLong();
    const qulonglong iowait = p[5].toULongLong();
    const qulonglong irq = p[6].toULongLong();
    const qulonglong softirq = p[7].toULongLong();
    const qulonglong steal = p.size() > 8 ? p[8].toULongLong() : 0;

    const qulonglong idleAll = idle + iowait;
    const qulonglong total = user + nice + system + idle + iowait + irq + softirq + steal;

    if (m_prevTotal > 0 && total > m_prevTotal) {
        const qulonglong totalDelta = total - m_prevTotal;
        const qulonglong idleDelta = idleAll - m_prevIdle;
        m_cpuUsage = qBound(0.0, (1.0 - (double)idleDelta / (double)totalDelta) * 100.0, 100.0);
    }
    m_prevTotal = total;
    m_prevIdle = idleAll;
}

void SystemBackend::readMemory()
{
    QFile f(QStringLiteral("/proc/meminfo"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;

    qulonglong totalKiB = 0;
    qulonglong availableKiB = 0;
    qulonglong freeKiB = 0;
    qulonglong buffersKiB = 0;
    qulonglong cachedKiB = 0;
    qulonglong reclaimableKiB = 0;
    qulonglong shmemKiB = 0;

    const auto valueKiB = [](const QString &line) -> qulonglong {
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon < 0) return 0;
        const QString value = line.mid(colon + 1).trimmed().section(QLatin1Char(' '), 0, 0);
        bool ok = false;
        const qulonglong parsed = value.toULongLong(&ok);
        return ok ? parsed : 0;
    };

    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine());
        if (line.startsWith(QStringLiteral("MemTotal:"))) totalKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("MemAvailable:"))) availableKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("MemFree:"))) freeKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("Buffers:"))) buffersKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("Cached:"))) cachedKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("SReclaimable:"))) reclaimableKiB = valueKiB(line);
        else if (line.startsWith(QStringLiteral("Shmem:"))) shmemKiB = valueKiB(line);
    }

    if (!totalKiB) return;

    // MemAvailable exists on modern Linux, but keep a conservative fallback so
    // the monitor never turns into 0.0 GiB just because a kernel reports a
    // slightly different meminfo set.
    if (!availableKiB) {
        const qulonglong cacheLike = cachedKiB + reclaimableKiB;
        availableKiB = freeKiB + buffersKiB + (cacheLike > shmemKiB ? cacheLike - shmemKiB : 0);
    }
    availableKiB = qMin(availableKiB, totalKiB);

    const qulonglong usedKiB = totalKiB - availableKiB;
    m_memoryTotalGiB = double(totalKiB) / 1024.0 / 1024.0;
    m_memoryUsedGiB = double(usedKiB) / 1024.0 / 1024.0;
    m_memoryUsage = qBound(0.0, double(usedKiB) / double(totalKiB) * 100.0, 100.0);
}

void SystemBackend::readUptime()
{
    QFile f("/proc/uptime");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    const double seconds = QString::fromUtf8(f.readAll()).split(' ').first().toDouble();
    const int mins = (int)(seconds / 60.0);
    const int hours = mins / 60;
    const int days = hours / 24;
    if (days > 0) m_uptimeText = QString("%1d %2h").arg(days).arg(hours % 24);
    else if (hours > 0) m_uptimeText = QString("%1h %2m").arg(hours).arg(mins % 60);
    else m_uptimeText = QString("%1m").arg(mins);
}

void SystemBackend::readNetwork()
{
    bool connected = false;
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const auto &iface : interfaces) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning) || (flags & QNetworkInterface::IsLoopBack))
            continue;

        for (const auto &entry : iface.addressEntries()) {
            const QHostAddress addr = entry.ip();
            if (addr.protocol() == QAbstractSocket::IPv4Protocol && !addr.isLoopback() && !addr.isNull()) {
                connected = true;
                break;
            }
        }
        if (connected) break;
    }

    if (connected != m_networkConnected) {
        m_networkConnected = connected;
        emit connectivityChanged();
    }
}

void SystemBackend::readBattery()
{
    bool present = false;
    int percent = -1;
    bool charging = false;

    QDir powerDir("/sys/class/power_supply");
    const QStringList entries = powerDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &name : entries) {
        if (!name.startsWith("BAT", Qt::CaseInsensitive)) continue;
        const QString base = powerDir.absoluteFilePath(name);
        QFile cap(base + "/capacity");
        QFile status(base + "/status");
        if (cap.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool ok = false;
            const int p = QString::fromUtf8(cap.readAll()).trimmed().toInt(&ok);
            if (ok) {
                present = true;
                percent = qBound(0, p, 100);
            }
        }
        if (status.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString state = QString::fromUtf8(status.readAll()).trimmed().toLower();
            charging = state.contains("charging") || state.contains("full");
        }
        if (present) break;
    }

    if (present != m_batteryPresent || percent != m_batteryPercent || charging != m_batteryCharging) {
        m_batteryPresent = present;
        m_batteryPercent = percent;
        m_batteryCharging = charging;
        emit batteryChanged();
    }
}

void SystemBackend::startAudioProbe(const QString &program, const QStringList &args, bool pactlMode)
{
    if (m_audioProbeBusy) return;
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        if (!pactlMode && !QStandardPaths::findExecutable("pactl").isEmpty())
            startAudioProbe("pactl", {"get-sink-volume", "@DEFAULT_SINK@"}, true);
        else {
            const bool changed = m_audioAvailable;
            m_audioAvailable = false;
            if (changed) emit audioChanged();
        }
        return;
    }

    m_audioProbeBusy = true;
    QProcess *probe = new QProcess(this);
    probe->setProcessChannelMode(QProcess::MergedChannels);
    connect(probe, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
            [this, probe, pactlMode](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromLocal8Bit(probe->readAll()).trimmed();
        probe->deleteLater();
        m_audioProbeBusy = false;

        bool parsed = false;
        int volume = m_volumeLevel;
        bool muted = m_muted;
        if (status == QProcess::NormalExit && code == 0) {
            if (!pactlMode) {
                const auto match = QRegularExpression("Volume:\\s*([0-9.]+)(.*)").match(out);
                if (match.hasMatch()) {
                    bool ok = false;
                    const double raw = match.captured(1).toDouble(&ok);
                    if (ok) {
                        volume = qBound(0, (int)qRound(raw * 100.0), 100);
                        muted = match.captured(2).contains("MUTED", Qt::CaseInsensitive);
                        parsed = true;
                    }
                }
            } else {
                const auto match = QRegularExpression("([0-9]{1,3})%").match(out);
                if (match.hasMatch()) {
                    volume = qBound(0, match.captured(1).toInt(), 100);
                    parsed = true;
                }
            }
        }

        if (!parsed && !pactlMode && !QStandardPaths::findExecutable("pactl").isEmpty()) {
            startAudioProbe("pactl", {"get-sink-volume", "@DEFAULT_SINK@"}, true);
            return;
        }

        const bool changed = volume != m_volumeLevel || muted != m_muted || parsed != m_audioAvailable;
        m_volumeLevel = volume;
        m_muted = muted;
        m_audioAvailable = parsed;
        if (changed) emit audioChanged();

        if (parsed && pactlMode && !QStandardPaths::findExecutable("pactl").isEmpty()) {
            QProcess *muteProbe = new QProcess(this);
            connect(muteProbe, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
                    [this, muteProbe](int, QProcess::ExitStatus) {
                const bool muted = QString::fromLocal8Bit(muteProbe->readAllStandardOutput()).contains("yes", Qt::CaseInsensitive);
                muteProbe->deleteLater();
                if (muted != m_muted) { m_muted = muted; emit audioChanged(); }
            });
            muteProbe->start("pactl", {"get-sink-mute", "@DEFAULT_SINK@"});
        }
    });
    connect(probe, &QProcess::errorOccurred, this, [this, probe, pactlMode](QProcess::ProcessError err) {
        if (err != QProcess::FailedToStart) return;
        probe->deleteLater();
        m_audioProbeBusy = false;
        if (!pactlMode && !QStandardPaths::findExecutable("pactl").isEmpty())
            startAudioProbe("pactl", {"get-sink-volume", "@DEFAULT_SINK@"}, true);
        else if (m_audioAvailable) { m_audioAvailable = false; emit audioChanged(); }
    });
    probe->start(program, args);
}

void SystemBackend::refreshAudioAsync()
{
    // Core publishes AudioChanged itself. The shell probes audio only in
    // recovery mode; this avoids duplicate wpctl/pactl work at idle.
    if (m_coreOnline) return;
    if (m_audioProbeBusy) return;
    startAudioProbe("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"}, false);
}

void SystemBackend::onCoreAudioChanged(int volume, bool muted, bool available)
{
    const bool changed = volume != m_volumeLevel || muted != m_muted || available != m_audioAvailable;
    m_volumeLevel = qBound(0, volume, 100);
    m_muted = muted;
    m_audioAvailable = available;
    if (changed) emit audioChanged();
}

void SystemBackend::onCoreStatusChanged(const QVariantMap &status)
{
    const bool wasOnline = m_coreOnline;
    m_coreOnline = true;
    m_coreStatus = QStringLiteral("Nexora Core online");

    const bool networkChanged = m_networkConnected != status.value(QStringLiteral("networkConnected")).toBool();
    const bool batteryChangedNow = m_batteryPresent != status.value(QStringLiteral("batteryPresent")).toBool() ||
        m_batteryPercent != status.value(QStringLiteral("batteryPercent"), -1).toInt() ||
        m_batteryCharging != status.value(QStringLiteral("batteryCharging")).toBool();

    m_cpuUsage = status.value(QStringLiteral("cpuUsage"), m_cpuUsage).toDouble();
    m_memoryUsage = status.value(QStringLiteral("memoryUsage"), m_memoryUsage).toDouble();
    m_memoryUsedGiB = status.value(QStringLiteral("memoryUsedGiB"), m_memoryUsedGiB).toDouble();
    m_memoryTotalGiB = status.value(QStringLiteral("memoryTotalGiB"), m_memoryTotalGiB).toDouble();
    m_uptimeText = status.value(QStringLiteral("uptimeText"), m_uptimeText).toString();
    m_networkConnected = status.value(QStringLiteral("networkConnected"), m_networkConnected).toBool();
    m_batteryPresent = status.value(QStringLiteral("batteryPresent"), m_batteryPresent).toBool();
    m_batteryPercent = status.value(QStringLiteral("batteryPercent"), m_batteryPercent).toInt();
    m_batteryCharging = status.value(QStringLiteral("batteryCharging"), m_batteryCharging).toBool();
    const bool deviceChanged = m_wifiAvailable != status.value(QStringLiteral("wifiAvailable"), m_wifiAvailable).toBool() ||
        m_wifiEnabled != status.value(QStringLiteral("wifiEnabled"), m_wifiEnabled).toBool() ||
        m_brightnessAvailable != status.value(QStringLiteral("brightnessAvailable"), m_brightnessAvailable).toBool() ||
        m_brightnessLevel != status.value(QStringLiteral("brightnessLevel"), m_brightnessLevel).toInt();
    m_wifiAvailable = status.value(QStringLiteral("wifiAvailable"), m_wifiAvailable).toBool();
    m_wifiEnabled = status.value(QStringLiteral("wifiEnabled"), m_wifiEnabled).toBool();
    m_brightnessAvailable = status.value(QStringLiteral("brightnessAvailable"), m_brightnessAvailable).toBool();
    m_brightnessLevel = status.value(QStringLiteral("brightnessLevel"), m_brightnessLevel).toInt();
    onCoreAudioChanged(status.value(QStringLiteral("volumeLevel"), m_volumeLevel).toInt(),
                       status.value(QStringLiteral("muted"), m_muted).toBool(),
                       status.value(QStringLiteral("audioAvailable"), m_audioAvailable).toBool());
    emit statsChanged();
    if (networkChanged) emit connectivityChanged();
    if (batteryChangedNow) emit batteryChanged();
    if (deviceChanged) emit deviceControlChanged();
    if (!wasOnline) emit coreChanged();
}

void SystemBackend::refreshCoreStatus()
{
    if (m_coreQueryBusy) return;
    if (!m_core || !m_core->isValid()) {
        if (m_core) m_core->deleteLater();
        m_core = new QDBusInterface(QStringLiteral("org.nexora.Core"), QStringLiteral("/Core"),
                                    QStringLiteral("org.nexora.Core"), QDBusConnection::sessionBus(), this);
        m_core->setTimeout(600);
    }
    if (!m_core->isValid()) {
        const bool changed = m_coreOnline;
        m_coreOnline = false;
        m_coreStatus = QStringLiteral("Nexora Core unavailable — shell fallback active");
        if (changed) emit coreChanged();
        return;
    }
    m_coreQueryBusy = true;
    auto *watcher = new QDBusPendingCallWatcher(m_core->asyncCall(QStringLiteral("GetStatus")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        QDBusPendingReply<QVariantMap> reply = *watcher;
        watcher->deleteLater();
        m_coreQueryBusy = false;
        if (reply.isError()) {
            const bool changed = m_coreOnline;
            m_coreOnline = false;
            m_coreStatus = QStringLiteral("Nexora Core not responding — shell fallback active");
            if (changed) emit coreChanged();
            return;
        }
        onCoreStatusChanged(reply.value());
    });
}

void SystemBackend::updateStats()
{
    // /proc/meminfo is tiny and effectively free to read. Keep a shell-side
    // memory sample even when Nexora Core is online so the UI never loses RAM
    // telemetry because of a stale/missed D-Bus update. Core remains the main
    // source for the rest of the deterministic telemetry.
    readMemory();

    if (m_coreOnline) {
        // Core pushes status every few seconds. Only perform a low-frequency
        // health query so a vanished service is detected without duplicating
        // telemetry work over D-Bus.
        if ((m_coreHealthTick++ % 5) == 0) refreshCoreStatus();
        emit statsChanged();
        return;
    }

    refreshCoreStatus();
    // Recovery fallback: if Core is down, the shell can still provide basic
    // telemetry and controls instead of collapsing with the service.
    readCpu(); readMemory(); readUptime();
    if ((m_slowStatsTick++ % 3) == 0) { readNetwork(); readBattery(); }
    emit statsChanged();
}

void SystemBackend::updateClock()
{
    const auto now = QDateTime::currentDateTime();
    m_currentTime = now.toString("HH:mm");
    m_currentDate = now.toString("ddd, dd MMM");
    emit timeChanged();
}

void SystemBackend::updateContext()
{
    QFile f(stateDir() + "/context.json");
    if (!f.open(QIODevice::ReadOnly)) {
        m_contextSummary = "Local context service is starting";
        m_engineeringApps.clear();
        m_aiStatus = m_tonyStatus;
        emit contextChanged();
        return;
    }

    const auto doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject()) return;
    const QJsonObject o = doc.object();
    // private_mode is the user's control file and is authoritative. context.json
    // is written asynchronously by the awareness daemon and can lag for a
    // couple of seconds; trusting only that snapshot made the toggle flicker
    // back to its old state immediately after a click.
    bool newPrivateMode = o.value("private_mode").toBool(false);
    QFile privateFile(stateDir() + "/private_mode");
    if (privateFile.open(QIODevice::ReadOnly | QIODevice::Text))
        newPrivateMode = QString::fromUtf8(privateFile.readAll()).trimmed() == "1";
    const bool privateChanged = newPrivateMode != m_privateMode;
    m_privateMode = newPrivateMode;
    m_contextSummary = o.value("summary").toString("System context available");

    m_recentEvents.clear();
    for (const auto &v : o.value("recent_events").toArray()) m_recentEvents << v.toString();

    m_engineeringApps.clear();
    for (const auto &v : o.value("engineering_apps").toArray()) m_engineeringApps << v.toString();

    m_aiStatus = m_tonyStatus;
    if (privateChanged) emit privateModeChanged();
    emit contextChanged();
}

bool SystemBackend::startDetached(const QString &program, const QStringList &args)
{
    return QProcess::startDetached(program, args);
}

void SystemBackend::launchApp(const QString &app)
{
    const QString a = app.toLower();

    if (a == "terminal" || a == "files" || a == "settings" || a == "projects" || a == "appcenter" ||
        a == "notes" || a == "monitor" || a == "tony" || a == "ai" || a == "command") {
        const QString target = (a == "ai" || a == "command") ? "tony" : a;
        emit appRequested(target);
        return;
    }

    // Third-party applications remain external. Nexora OS owns the shell
    // and core apps but does not pretend to reimplement every engineering tool.
    if (a == "browser") {
        if (isDebInstalled("firefox-esr")) startDetached("firefox-esr");
        else { emit appRequested("appcenter"); m_appJobStatus = "Install a browser from App Center."; emit appJobChanged(); }
    }
    else if (a == "freecad") startDetached("freecad");
    else if (a == "kicad") startDetached("kicad");
    else if (a == "blender") startDetached("blender");
    else if (a == "gmsh") startDetached("gmsh");
    else if (a == "paraview") startDetached("paraview");
    else if (a == "openscad") startDetached("openscad");
    else if (a == "octave") startDetached("octave", {"--gui"});
    else if (a == "libreoffice") startDetached("libreoffice");
    else if (a == "gimp") startDetached("gimp");
    else if (a == "inkscape") startDetached("inkscape");
    else if (a == "vlc") startDetached("vlc");
    else if (a == "vscodium" || a == "codium") {
        if (!QStandardPaths::findExecutable("codium").isEmpty()) startDetached("codium");
        else startDetached("flatpak", {"run", "com.vscodium.codium"});
    }
    else if (a == "konsole") startDetached("konsole", {"--separate"});
    else if (a == "dolphin") startDetached("dolphin", {"--new-window"});
}

QStringList SystemBackend::listProjects() const
{
    if (m_coreOnline && m_core && m_core->isValid()) {
        QDBusReply<QStringList> reply = m_core->call(QStringLiteral("ListProjects"));
        if (reply.isValid()) return reply.value();
    }
    QDir d(projectsDir());
    if (!d.exists()) return {};
    return d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
}

QString SystemBackend::createProject(const QString &name)
{
    if (m_coreOnline && m_core && m_core->isValid()) {
        QDBusReply<QString> reply = m_core->call(QStringLiteral("CreateProject"), name);
        if (reply.isValid()) return reply.value();
    }

    // Recovery fallback used only if Nexora Core is unavailable.
    QString clean = name.trimmed();
    clean.replace(QRegularExpression("[^A-Za-z0-9._ -]"), "");
    if (clean.isEmpty()) return "Give the project a name.";
    const QString root = projectsDir() + "/" + clean;
    const bool existed = QFileInfo::exists(root);
    QDir().mkpath(root);
    for (const QString &sub : {"mechanical", "electronics", "simulation", "software", "documents", ".nexora"})
        QDir().mkpath(root + "/" + sub);
    const QString metaPath = root + "/.nexora/project.json";
    if (!QFileInfo::exists(metaPath)) {
        QFile meta(metaPath);
        if (meta.open(QIODevice::WriteOnly)) {
            QJsonObject o;
            o["name"] = clean;
            o["created"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
            o["version"] = 2;
            o["units"] = "SI";
            o["platform"] = "Nexora OS";
            meta.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        }
    }
    return existed ? QString("Project %1 already exists.").arg(clean)
                   : QString("Created %1.").arg(clean);
}

void SystemBackend::setPrivateMode(bool enabled)
{
    QDir().mkpath(stateDir());
    QFile f(stateDir() + "/private_mode");
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) f.write(enabled ? "1\n" : "0\n");
    m_privateMode = enabled;
    emit privateModeChanged();
}

QVariantList SystemBackend::listDirectory(const QString &path) const
{
    QVariantList result;
    const QString normalized = normalizePath(path);
    QDir d(normalized);
    if (!d.exists()) return result;

    const QFileInfoList entries = d.entryInfoList(
        QDir::AllEntries | QDir::NoDotAndDotDot,
        QDir::DirsFirst | QDir::IgnoreCase | QDir::Name);

    for (const QFileInfo &info : entries) {
        QVariantMap item;
        item["name"] = info.fileName();
        item["path"] = info.absoluteFilePath();
        item["isDir"] = info.isDir();
        item["size"] = info.isDir() ? QString() : QString::number(info.size());
        item["modified"] = info.lastModified().toString("dd MMM HH:mm");
        result.push_back(item);
    }
    return result;
}

QString SystemBackend::normalizePath(const QString &path) const
{
    QString p = path.trimmed();
    if (p.isEmpty() || p == "~") return QDir::homePath();
    if (p.startsWith("~/")) p = QDir::homePath() + p.mid(1);
    return QDir::cleanPath(QFileInfo(p).absoluteFilePath());
}

QString SystemBackend::parentDirectory(const QString &path) const
{
    QDir d(normalizePath(path));
    d.cdUp();
    return d.absolutePath();
}

bool SystemBackend::createFolder(const QString &parent, const QString &name)
{
    QString clean = name.trimmed();
    clean.remove('/');
    if (clean.isEmpty()) return false;
    QDir d(normalizePath(parent));
    return d.mkdir(clean);
}

bool SystemBackend::openFile(const QString &path)
{
    const QString normalized = normalizePath(path);
    const QFileInfo info(normalized);
    if (!info.exists()) return false;
    if (info.isDir()) {
        emit appRequested("files:" + normalized);
        return true;
    }
    return QDesktopServices::openUrl(QUrl::fromLocalFile(normalized));
}

void SystemBackend::runTerminalCommand(const QString &command)
{
    const QString cmd = command.trimmed();
    if (cmd.isEmpty()) return;
    if (!m_terminalSessionReady && !startTerminalSession()) {
        emit terminalOutput(QStringLiteral("<span style='color:#FF9C9C'>Unable to start the Nexora console session.</span>"));
        return;
    }
    if (cmd == QStringLiteral("clear")) emit terminalOutput(QStringLiteral("__CLEAR__"));
    QByteArray line = command.toUtf8();
    line.append('\n');
    if (m_ptyFd >= 0) ::write(m_ptyFd, line.constData(), static_cast<size_t>(line.size()));
}

bool SystemBackend::startTerminalSession()
{
    if (m_terminalSessionReady && m_ptyFd >= 0) return true;
    stopTerminalSession();

    struct winsize ws {};
    ws.ws_col = 110;
    ws.ws_row = 32;
    const pid_t pid = forkpty(&m_ptyFd, nullptr, nullptr, &ws);
    if (pid < 0) {
        m_ptyFd = -1;
        m_terminalSessionReady = false;
        emit terminalSessionChanged();
        return false;
    }
    if (pid == 0) {
        ::setenv("TERM", "xterm-256color", 1);
        ::setenv("COLORTERM", "truecolor", 1);
        ::setenv("PS1", "PS \\w> ", 1);
        ::setenv("PROMPT_COMMAND", "printf '\\033]7;file://%s%s\\007' \"$HOSTNAME\" \"$PWD\"", 1);
        ::execl("/bin/bash", "bash", "--noprofile", "--norc", "-i", static_cast<char*>(nullptr));
        _exit(127);
    }

    m_ptyPid = pid;
    const int flags = fcntl(m_ptyFd, F_GETFL, 0);
    if (flags >= 0) fcntl(m_ptyFd, F_SETFL, flags | O_NONBLOCK);
    m_ptyNotifier = new QSocketNotifier(m_ptyFd, QSocketNotifier::Read, this);
    connect(m_ptyNotifier, &QSocketNotifier::activated, this, [this](QSocketDescriptor, QSocketNotifier::Type) {
        char buf[8192];
        QByteArray all;
        while (m_ptyFd >= 0) {
            const ssize_t n = ::read(m_ptyFd, buf, sizeof(buf));
            if (n > 0) all.append(buf, static_cast<int>(n));
            else break;
        }
        if (!all.isEmpty()) {
            const QString clean = sanitizeTerminalOutput(all);
            if (!clean.isEmpty()) emit terminalOutput(clean);
        }
        int status = 0;
        if (m_ptyPid > 0 && waitpid(static_cast<pid_t>(m_ptyPid), &status, WNOHANG) == m_ptyPid) {
            stopTerminalSession();
            emit terminalOutput(QStringLiteral("<br><span style='color:#9AA8B6'>Console session ended. Press Restart in the title bar to reopen it.</span>"));
        }
    });
    m_terminalSessionReady = true;
    emit terminalSessionChanged();
    return true;
}

void SystemBackend::stopTerminalSession()
{
    if (m_ptyNotifier) {
        m_ptyNotifier->setEnabled(false);
        m_ptyNotifier->deleteLater();
        m_ptyNotifier = nullptr;
    }
    if (m_ptyPid > 0) {
        ::kill(static_cast<pid_t>(m_ptyPid), SIGHUP);
        int status = 0;
        waitpid(static_cast<pid_t>(m_ptyPid), &status, WNOHANG);
    }
    if (m_ptyFd >= 0) ::close(m_ptyFd);
    m_ptyFd = -1;
    m_ptyPid = -1;
    if (m_terminalSessionReady) {
        m_terminalSessionReady = false;
        emit terminalSessionChanged();
    }
}

QString SystemBackend::sanitizeTerminalOutput(const QByteArray &data)
{
    QString text = QString::fromUtf8(data);
    // Track the shell's OSC-7 working-directory report before removing OSC sequences.
    const QRegularExpression cwdRe(QStringLiteral("\\x1B\\]7;file://[^/]*(/[^\\x07\\x1B]*)[\\x07]"));
    auto cwdMatch = cwdRe.match(text);
    if (cwdMatch.hasMatch()) {
        const QString cwd = QUrl::fromPercentEncoding(cwdMatch.captured(1).toUtf8());
        if (!cwd.isEmpty() && cwd != m_terminalWorkingDirectory) {
            m_terminalWorkingDirectory = cwd;
            emit terminalWorkingDirectoryChanged();
        }
    }
    text.remove(QRegularExpression(QStringLiteral("\\x1B\\][^\\x07]*(?:\\x07|\\x1B\\\\)")));
    text.remove(QRegularExpression(QStringLiteral("\\x1B\\[[0-?]*[ -/]*[@-~]")));
    text.remove(QChar::CarriageReturn);
    text.remove(QChar(0x08));
    text.remove(QChar(0x07));
    if (text.isEmpty()) return {};
    return text.toHtmlEscaped().replace(QStringLiteral("\n"), QStringLiteral("<br>"));
}

void SystemBackend::terminalInterrupt()
{
    if (m_ptyFd >= 0) {
        const char c = 0x03;
        ::write(m_ptyFd, &c, 1);
    }
}

void SystemBackend::terminalRestart()
{
    stopTerminalSession();
    emit terminalOutput(QStringLiteral("__CLEAR__"));
    startTerminalSession();
}

void SystemBackend::terminalResize(int columns, int rows)
{
    if (m_ptyFd < 0) return;
    struct winsize ws {};
    ws.ws_col = static_cast<unsigned short>(qBound(40, columns, 300));
    ws.ws_row = static_cast<unsigned short>(qBound(10, rows, 120));
    ioctl(m_ptyFd, TIOCSWINSZ, &ws);
}

void SystemBackend::setVolume(int percent)
{
    percent = qBound(0, percent, 100);
    m_volumeLevel = percent;
    emit audioChanged();

    if (m_coreOnline && m_core && m_core->isValid()) {
        m_core->asyncCall(QStringLiteral("SetVolume"), percent);
        QTimer::singleShot(250, this, &SystemBackend::refreshCoreStatus);
        return;
    }

    // Recovery fallback if Core is unavailable.
    const QString pct = QString::number(percent) + "%";
    bool started = false;
    if (!QStandardPaths::findExecutable("wpctl").isEmpty())
        started = QProcess::startDetached("wpctl", {"set-volume", "@DEFAULT_AUDIO_SINK@", pct});
    if (!started && !QStandardPaths::findExecutable("pactl").isEmpty())
        started = QProcess::startDetached("pactl", {"set-sink-volume", "@DEFAULT_SINK@", pct});
    if (!started && !QStandardPaths::findExecutable("amixer").isEmpty())
        QProcess::startDetached("amixer", {"-q", "sset", "Master", pct});
    QTimer::singleShot(250, this, &SystemBackend::refreshAudioAsync);
}

void SystemBackend::setMuted(bool muted)
{
    m_muted = muted;
    emit audioChanged();

    if (m_coreOnline && m_core && m_core->isValid()) {
        m_core->asyncCall(QStringLiteral("SetMuted"), muted);
        QTimer::singleShot(250, this, &SystemBackend::refreshCoreStatus);
        return;
    }

    bool started = false;
    if (!QStandardPaths::findExecutable("wpctl").isEmpty())
        started = QProcess::startDetached("wpctl", {"set-mute", "@DEFAULT_AUDIO_SINK@", muted ? "1" : "0"});
    if (!started && !QStandardPaths::findExecutable("pactl").isEmpty())
        started = QProcess::startDetached("pactl", {"set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"});
    if (!started && !QStandardPaths::findExecutable("amixer").isEmpty())
        QProcess::startDetached("amixer", {"-q", "sset", "Master", muted ? "mute" : "unmute"});
    QTimer::singleShot(250, this, &SystemBackend::refreshAudioAsync);
}


void SystemBackend::setBrightness(int percent)
{
    percent = qBound(1, percent, 100);
    m_brightnessLevel = percent;
    emit deviceControlChanged();
    if (m_coreOnline && m_core && m_core->isValid()) {
        m_core->asyncCall(QStringLiteral("SetBrightness"), percent);
        return;
    }
    if (!QStandardPaths::findExecutable(QStringLiteral("brightnessctl")).isEmpty())
        QProcess::startDetached(QStringLiteral("brightnessctl"), {QStringLiteral("set"), QString::number(percent) + QStringLiteral("%")});
}

void SystemBackend::setWifiEnabled(bool enabled)
{
    m_wifiEnabled = enabled;
    emit deviceControlChanged();
    if (m_coreOnline && m_core && m_core->isValid()) {
        m_core->asyncCall(QStringLiteral("SetWifiEnabled"), enabled);
        return;
    }
    if (!QStandardPaths::findExecutable(QStringLiteral("nmcli")).isEmpty())
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), enabled ? QStringLiteral("on") : QStringLiteral("off")});
}

void SystemBackend::powerAction(const QString &action)
{
    const QString a = action.trimmed().toLower();
    if (a == "logout") {
        emit sessionExitRequested();
        return;
    }
    if ((a == "reboot" || a == "restart" || a == "poweroff" || a == "shutdown") && m_coreOnline && m_core && m_core->isValid()) {
        m_core->asyncCall(QStringLiteral("PowerAction"), a);
        return;
    }
    if (a == "reboot" || a == "restart") startDetached("systemctl", {"reboot"});
    else if (a == "poweroff" || a == "shutdown") startDetached("systemctl", {"poweroff"});
}

bool SystemBackend::isDebInstalled(const QString &package) const
{
    // Reading dpkg's status database is dramatically cheaper than spawning one
    // dpkg-query process per App Center tile/search row.
    static QSet<QString> cache;
    static QDateTime cacheTime;
    const auto now = QDateTime::currentDateTime();
    if (!cacheTime.isValid() || cacheTime.secsTo(now) > 1) {
        cache.clear();
        QFile f("/var/lib/dpkg/status");
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString current;
            bool installed = false;
            while (!f.atEnd()) {
                const QString line = QString::fromUtf8(f.readLine()).trimmed();
                if (line.startsWith("Package:")) current = line.mid(8).trimmed();
                else if (line.startsWith("Status:")) installed = line.contains("install ok installed");
                else if (line.isEmpty()) {
                    if (installed && !current.isEmpty()) cache.insert(current);
                    current.clear(); installed = false;
                }
            }
            if (installed && !current.isEmpty()) cache.insert(current);
        }
        cacheTime = now;
    }
    return cache.contains(package);
}

bool SystemBackend::isFlatpakInstalled(const QString &appId) const
{
    const QString userPath = QDir::homePath() + "/.local/share/flatpak/app/" + appId;
    if (QFileInfo::exists(userPath)) return true;
    return QFileInfo::exists("/var/lib/flatpak/app/" + appId);
}

QVariantList SystemBackend::appCatalog() const
{
    struct App { const char *name; const char *summary; const char *category; const char *source; const char *id; const char *launch; };
    static const App apps[] = {
        {"FreeCAD", "Parametric 3D CAD", "Engineering", "apt", "freecad", "freecad"},
        {"KiCad", "PCB and electronics design", "Engineering", "apt", "kicad", "kicad"},
        {"OpenSCAD", "Programmatic solid CAD", "Engineering", "apt", "openscad", "openscad"},
        {"Gmsh", "Finite-element mesh generation", "Engineering", "apt", "gmsh", "gmsh"},
        {"ParaView", "Scientific data visualization", "Engineering", "apt", "paraview", "paraview"},
        {"GNU Octave", "Numerical engineering computing", "Engineering", "apt", "octave", "octave --gui"},
        {"Blender", "3D creation and visualization", "Creative", "apt", "blender", "blender"},
        {"VSCodium", "Open-source code editor", "Development", "flatpak", "com.vscodium.codium", "com.vscodium.codium"},
        {"Firefox ESR", "Web browser", "General", "apt", "firefox-esr", "firefox-esr"},
        {"LibreOffice", "Documents and spreadsheets", "General", "apt", "libreoffice", "libreoffice"},
        {"GIMP", "Image editing", "Creative", "apt", "gimp", "gimp"},
        {"Inkscape", "Vector graphics", "Creative", "apt", "inkscape", "inkscape"},
        {"VLC", "Media player", "General", "apt", "vlc", "vlc"}
    };

    QVariantList result;
    for (const App &app : apps) {
        QVariantMap m;
        m["name"] = app.name;
        m["summary"] = app.summary;
        m["category"] = app.category;
        m["source"] = app.source;
        m["id"] = app.id;
        m["launch"] = app.launch;
        m["installed"] = QString(app.source) == "apt" ? isDebInstalled(app.id) : isFlatpakInstalled(app.id);
        result.push_back(m);
    }
    return result;
}

// Debian repository search is intentionally async in V1; keeping the
// old synchronous helper around made it too easy to freeze the shell UI.
void SystemBackend::searchDebianPackagesAsync(const QString &query)
{
    const QString q = query.trimmed();
    if (m_appSearchProcess) {
        m_appSearchProcess->kill();
        m_appSearchProcess->deleteLater();
        m_appSearchProcess = nullptr;
    }

    m_appSearchResults.clear();
    if (q.size() < 2) {
        m_appSearchBusy = false;
        emit appSearchChanged();
        return;
    }

    if (QStandardPaths::findExecutable("apt-cache").isEmpty()) {
        m_appSearchBusy = false;
        emit appSearchChanged();
        return;
    }

    m_appSearchBusy = true;
    emit appSearchChanged();
    QProcess *search = new QProcess(this);
    m_appSearchProcess = search;
    search->setProcessChannelMode(QProcess::MergedChannels);

    connect(search, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
            [this, search](int code, QProcess::ExitStatus status) {
        if (m_appSearchProcess != search) { search->deleteLater(); return; }
        QVariantList result;
        if (status == QProcess::NormalExit && code == 0) {
            const QStringList lines = QString::fromLocal8Bit(search->readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
            int count = 0;
            for (const QString &line : lines) {
                if (count >= 40) break;
                const int sep = line.indexOf(" - ");
                if (sep <= 0) continue;
                const QString id = line.left(sep).trimmed();
                QVariantMap m;
                m["name"] = id;
                m["summary"] = line.mid(sep + 3).trimmed();
                m["category"] = "Repository";
                m["source"] = "apt";
                m["id"] = id;
                m["launch"] = "";
                m["installed"] = isDebInstalled(id);
                result.push_back(m);
                ++count;
            }
        }
        m_appSearchResults = result;
        m_appSearchBusy = false;
        m_appSearchProcess = nullptr;
        emit appSearchChanged();
        search->deleteLater();
    });
    connect(search, &QProcess::errorOccurred, this, [this, search](QProcess::ProcessError error) {
        if (m_appSearchProcess != search) return;
        if (error == QProcess::FailedToStart) {
            m_appSearchResults.clear();
            m_appSearchBusy = false;
            m_appSearchProcess = nullptr;
            emit appSearchChanged();
            search->deleteLater();
        }
    });
    search->start("apt-cache", {"search", "--names-only", q});
}

void SystemBackend::runPackageJob(const QString &program, const QStringList &args, const QString &startMessage, const QString &successMessage)
{
    if (m_appJobBusy) {
        m_appJobStatus = "Another app operation is already running.";
        emit appJobChanged();
        return;
    }
    m_appJobBusy = true;
    m_appJobStatus = startMessage;
    emit appJobChanged();

    QProcess *job = new QProcess(this);
    job->setProcessChannelMode(QProcess::MergedChannels);
    connect(job, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
            [this, job, successMessage](int code, QProcess::ExitStatus status) {
        const QString output = QString::fromLocal8Bit(job->readAll()).trimmed();
        m_appJobBusy = false;
        if (status == QProcess::NormalExit && code == 0) m_appJobStatus = successMessage;
        else if (!output.isEmpty()) m_appJobStatus = "Install failed: " + output.right(220).replace('\n', ' ');
        else m_appJobStatus = QString("App operation failed (code %1).").arg(code);
        emit appJobChanged();
        job->deleteLater();
    });
    connect(job, &QProcess::errorOccurred, this, [this, job](QProcess::ProcessError error) {
        // FailedToStart does not reliably produce a useful finished() path on
        // every backend. Other errors (for example Crashed) are finalized by
        // finished(), so do not clear busy state twice.
        if (error != QProcess::FailedToStart) return;
        m_appJobBusy = false;
        m_appJobStatus = "Could not start installer: " + job->errorString();
        emit appJobChanged();
        job->deleteLater();
    });
    job->start(program, args);
}

void SystemBackend::installCatalogApp(const QString &source, const QString &id)
{
    if (source == "apt")
        runPackageJob("pkexec", {"apt-get", "install", "-y", id}, "Waiting for permission to install " + id + "…", id + " installed.");
    else if (source == "flatpak")
        runPackageJob("flatpak", {"install", "--user", "-y", "--noninteractive", "flathub", id}, "Installing " + id + " from Flathub…", id + " installed.");
}

void SystemBackend::removeCatalogApp(const QString &source, const QString &id)
{
    if (source == "apt")
        runPackageJob("pkexec", {"apt-get", "remove", "-y", id}, "Waiting for permission to remove " + id + "…", id + " removed.");
    else if (source == "flatpak")
        runPackageJob("flatpak", {"uninstall", "--user", "-y", id}, "Removing " + id + "…", id + " removed.");
}

void SystemBackend::launchCatalogApp(const QString &source, const QString &id, const QString &launch)
{
    if (source == "flatpak") { startDetached("flatpak", {"run", id}); return; }
    QStringList parts = QProcess::splitCommand(launch.trimmed());
    if (parts.isEmpty()) return;
    const QString program = parts.takeFirst();
    startDetached(program, parts);
}

void SystemBackend::installLocalPackage(const QString &urlOrPath)
{
    QUrl u(urlOrPath);
    QString path = u.isLocalFile() ? u.toLocalFile() : urlOrPath;
    path = normalizePath(path);
    QFileInfo info(path);
    if (!info.exists() || !info.isFile()) {
        m_appJobStatus = "Package file not found.";
        emit appJobChanged();
        return;
    }

    const QString lower = info.fileName().toLower();
    if (lower.endsWith(".deb")) {
        runPackageJob("pkexec", {"apt-get", "install", "-y", path}, "Waiting for permission to install local package…", info.fileName() + " installed.");
        return;
    }
    if (lower.endsWith(".flatpakref") || lower.endsWith(".flatpak")) {
        runPackageJob("flatpak", {"install", "--user", "-y", path}, "Installing local Flatpak…", info.fileName() + " installed.");
        return;
    }
    if (lower.endsWith(".appimage")) {
        const QString appDir = QDir::homePath() + "/.local/opt/nexora/apps";
        QDir().mkpath(appDir);
        QString safeName = info.completeBaseName().toLower();
        safeName.replace(QRegularExpression("[^a-z0-9._-]+"), "-");
        if (safeName.isEmpty()) safeName = "imported-app";
        const QString dest = appDir + "/" + safeName + ".AppImage";
        if (QFileInfo(dest).exists()) QFile::remove(dest);
        if (!QFile::copy(path, dest)) {
            m_appJobStatus = "Could not copy AppImage.";
            emit appJobChanged();
            return;
        }
        QFile::setPermissions(dest, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                   QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                   QFileDevice::ReadOther | QFileDevice::ExeOther);

        // Register imported AppImages as normal desktop applications so the
        // future Nexora OS app index can discover them without special cases.
        const QString desktopDir = QDir::homePath() + "/.local/share/applications";
        QDir().mkpath(desktopDir);
        const QString desktopId = safeName;
        QFile desktop(desktopDir + "/nexora-" + desktopId + ".desktop");
        if (desktop.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            const QString entry = QString("[Desktop Entry]\nType=Application\nName=%1\nExec=%2\nTerminal=false\nCategories=Utility;\n")
                                      .arg(info.completeBaseName(), dest);
            desktop.write(entry.toUtf8());
        }
        m_appJobStatus = info.fileName() + " imported and registered.";
        emit appJobChanged();
        return;
    }

    m_appJobStatus = "Supported local packages: .deb, .AppImage, .flatpakref, .flatpak";
    emit appJobChanged();
}

void SystemBackend::refreshAppSources()
{
    runPackageJob("pkexec", {"apt-get", "update"}, "Refreshing Debian app catalog…", "App sources refreshed.");
}


QVariantList SystemBackend::topProcesses() const
{
    struct ProcItem { qint64 rssKiB; int pid; QString name; };
    QList<ProcItem> items;
    QDir proc("/proc");
    const QStringList entries = proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    const uint uid = getuid();
    for (const QString &entry : entries) {
        bool okPid = false;
        const int pid = entry.toInt(&okPid);
        if (!okPid) continue;
        QFileInfo fi("/proc/" + entry);
        if (fi.ownerId() != uid) continue;
        QFile comm("/proc/" + entry + "/comm");
        QFile status("/proc/" + entry + "/status");
        if (!comm.open(QIODevice::ReadOnly | QIODevice::Text) || !status.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
        const QString name = QString::fromUtf8(comm.readAll()).trimmed();
        qint64 rss = 0;
        while (!status.atEnd()) {
            const QString line = QString::fromUtf8(status.readLine());
            if (line.startsWith("VmRSS:")) {
                const QStringList parts = line.simplified().split(' ');
                if (parts.size() >= 2) rss = parts[1].toLongLong();
                break;
            }
        }
        if (!name.isEmpty()) items.push_back({rss, pid, name});
    }
    std::sort(items.begin(), items.end(), [](const ProcItem &a, const ProcItem &b) { return a.rssKiB > b.rssKiB; });
    QVariantList result;
    const int processCount = qMin(20, static_cast<int>(items.size()));
    for (int i = 0; i < processCount; ++i) {
        QVariantMap m;
        m["pid"] = items[i].pid;
        m["name"] = items[i].name;
        m["memoryMiB"] = items[i].rssKiB / 1024.0;
        result.push_back(m);
    }
    return result;
}

void SystemBackend::saveQuickNote(const QString &text)
{
    QDir().mkpath(notesDir());
    QFile f(notesDir() + "/Quick Note.txt");
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f.write(text.toUtf8());
        m_quickNote = text;
        emit noteChanged();
    }
}

void SystemBackend::refreshTonyStatus()
{
    QFileInfo info(stateDir() + "/tony.json");
    bool online = false;
    bool modelOnline = false;
    if (info.exists() && info.lastModified().secsTo(QDateTime::currentDateTime()) < 12) {
        QFile f(info.filePath());
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
            if (doc.isObject()) {
                const QJsonObject o = doc.object();
                online = o.value("service").toString() == "online";
                modelOnline = o.value("model_online").toBool(false);
                const QString policy = o.value("model_policy").toString();
                if (!policy.isEmpty()) m_tonyModelPolicy = policy;
            }
        }
    }
    const QString oldStatus = m_tonyStatus;
    const bool changed = online != m_tonyOnline || modelOnline != m_tonyModelOnline;
    m_tonyOnline = online;
    m_tonyModelOnline = modelOnline;
    m_tonyStatus = !online ? "Tony service offline" : (modelOnline ? "Tony · local model ready" : "Tony · model sleeping");
    m_aiStatus = m_tonyStatus;
    if (changed || oldStatus != m_tonyStatus) emit tonyChanged();
}


void SystemBackend::setTonyModelPolicy(const QString &policy)
{
    const QString p = policy.trimmed().toLower();
    if (p != "eco" && p != "balanced" && p != "always") return;
    m_tonyModelPolicy = p;
    emit tonyChanged();
    QJsonObject payload; payload["policy"] = p;
    postTony("/model-policy", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::loadTonyModel()
{
    QJsonObject payload; payload["action"] = "load";
    postTony("/model-control", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::unloadTonyModel()
{
    QJsonObject payload; payload["action"] = "unload";
    postTony("/model-control", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::postTony(const QString &path, const QByteArray &body)
{
    QNetworkRequest req(QUrl("http://127.0.0.1:8766" + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    // Balanced/Eco mode may need to cold-start the local model. Keep the UI
    // asynchronous, but do not let Qt abort a legitimate first request early.
    req.setTransferTimeout(95000);
    QNetworkReply *reply = m_network->post(req, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { handleTonyReply(reply); });
}

void SystemBackend::askTony(const QString &text)
{
    const QString clean = text.trimmed();
    if (clean.isEmpty() || m_tonyBusy) return;
    m_tonyBusy = true;
    m_tonyReply = "Thinking…";
    m_tonyApprovalId.clear();
    m_tonyApprovalText.clear();
    emit tonyChanged();
    QJsonObject payload;
    payload["text"] = clean;
    postTony("/ask", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::approveTonyAction()
{
    if (m_tonyApprovalId.isEmpty() || m_tonyBusy) return;
    m_tonyBusy = true;
    emit tonyChanged();
    QJsonObject payload; payload["id"] = m_tonyApprovalId;
    postTony("/approve", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::denyTonyAction()
{
    if (m_tonyApprovalId.isEmpty() || m_tonyBusy) return;
    m_tonyBusy = true;
    emit tonyChanged();
    QJsonObject payload; payload["id"] = m_tonyApprovalId;
    postTony("/deny", QJsonDocument(payload).toJson(QJsonDocument::Compact));
}


void SystemBackend::applyVoiceStatus(const QJsonObject &o)
{
    m_voiceOnline = true;
    const QString state = o.value(QStringLiteral("state")).toString(QStringLiteral("ready"));
    m_voiceListening = o.value(QStringLiteral("listening")).toBool(state == QStringLiteral("listening"));
    m_voiceTranscribing = o.value(QStringLiteral("transcribing")).toBool(state == QStringLiteral("transcribing"));
    m_voiceSpeaking = o.value(QStringLiteral("speaking")).toBool(state == QStringLiteral("speaking"));
    m_voiceSttReady = o.value(QStringLiteral("stt_ready")).toBool(m_voiceSttReady);
    if (o.contains(QStringLiteral("last_transcript")))
        m_voiceTranscript = o.value(QStringLiteral("last_transcript")).toString(m_voiceTranscript);
    if (o.contains(QStringLiteral("tts_backend")))
        m_voiceTtsBackend = o.value(QStringLiteral("tts_backend")).toString(m_voiceTtsBackend);
    const QJsonObject config = o.value(QStringLiteral("config")).toObject();
    if (!config.isEmpty())
        m_voiceSpeakReplies = config.value(QStringLiteral("speak_replies")).toBool(m_voiceSpeakReplies);

    const QString voiceError = o.value(QStringLiteral("last_error")).toString().trimmed();
    if (m_voiceListening) m_voiceStatus = QStringLiteral("Listening…");
    else if (m_voiceTranscribing) m_voiceStatus = QStringLiteral("Transcribing locally…");
    else if (m_voiceSpeaking) m_voiceStatus = QStringLiteral("Tony is speaking");
    else if (state == QStringLiteral("error") && !voiceError.isEmpty()) m_voiceStatus = voiceError.left(160);
    else if (!m_voiceSttReady) m_voiceStatus = QStringLiteral("Voice input needs setup");
    else m_voiceStatus = QStringLiteral("Voice ready");
    emit voiceChanged();
}

void SystemBackend::refreshVoiceStatus()
{
    QNetworkRequest req(QUrl(QStringLiteral("http://127.0.0.1:8767/health")));
    req.setRawHeader("Cache-Control", "no-cache");
    req.setTransferTimeout(1800);
    QNetworkReply *reply = m_network->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() != QNetworkReply::NoError) {
            const bool changed = m_voiceOnline;
            m_voiceOnline = false;
            m_voiceListening = m_voiceTranscribing = m_voiceSpeaking = false;
            m_voiceStatus = QStringLiteral("Voice service offline");
            reply->deleteLater();
            if (changed) emit voiceChanged();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(raw);
        reply->deleteLater();
        if (doc.isObject()) applyVoiceStatus(doc.object());
    });
}

void SystemBackend::postVoice(const QString &path, const QByteArray &body)
{
    QNetworkRequest req(QUrl(QStringLiteral("http://127.0.0.1:8767") + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(path == QStringLiteral("/speak") ? 35000 : 5000);
    QNetworkReply *reply = m_network->post(req, body.isEmpty() ? QByteArray("{}") : body);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        const QJsonDocument doc = QJsonDocument::fromJson(raw);
        if (reply->error() != QNetworkReply::NoError) {
            m_voiceOnline = false;
            m_voiceStatus = QStringLiteral("Voice service unavailable");
            emit voiceChanged();
        } else if (doc.isObject()) {
            const QJsonObject o = doc.object();
            if (o.contains(QStringLiteral("state")) || o.contains(QStringLiteral("stt_ready")))
                applyVoiceStatus(o);
        }
        reply->deleteLater();
    });
}

void SystemBackend::toggleVoiceListening()
{
    if (m_voiceRequestBusy || m_voiceTranscribing) return;

    if (!m_voiceOnline) {
        m_voiceRequestBusy = true;
        m_voiceStatus = QStringLiteral("Starting voice service…");
        emit voiceChanged();
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("start"), QStringLiteral("nexora-voice.service")});
        QTimer::singleShot(900, this, [this]() {
            m_voiceRequestBusy = false;
            refreshVoiceStatus();
            QTimer::singleShot(300, this, [this]() {
                if (m_voiceOnline) toggleVoiceListening();
                else {
                    m_voiceStatus = QStringLiteral("Voice service unavailable");
                    emit voiceChanged();
                }
            });
        });
        return;
    }

    const bool stopping = m_voiceListening;
    m_voiceRequestBusy = true;
    if (!stopping) {
        m_voiceStatus = QStringLiteral("Opening microphone…");
    } else {
        m_voiceListening = false;
        m_voiceTranscribing = true;
        m_voiceStatus = QStringLiteral("Transcribing locally…");
    }
    emit voiceChanged();

    const QString path = stopping ? QStringLiteral("/listen/stop") : QStringLiteral("/listen/start");
    QNetworkRequest req(QUrl(QStringLiteral("http://127.0.0.1:8767") + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setTransferTimeout(stopping ? 65000 : 6000);
    QNetworkReply *reply = m_network->post(req, QByteArray("{}"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, stopping]() {
        const QByteArray raw = reply->readAll();
        const QJsonDocument doc = QJsonDocument::fromJson(raw);
        const bool networkOk = reply->error() == QNetworkReply::NoError;
        reply->deleteLater();
        m_voiceRequestBusy = false;
        m_voiceOnline = networkOk;
        if (!networkOk || !doc.isObject()) {
            m_voiceListening = m_voiceTranscribing = false;
            m_voiceStatus = QStringLiteral("Voice service unavailable");
            emit voiceChanged();
            return;
        }
        const QJsonObject o = doc.object();
        if (!o.value(QStringLiteral("ok")).toBool(false)) {
            m_voiceListening = m_voiceTranscribing = false;
            m_voiceStatus = o.value(QStringLiteral("error")).toString(QStringLiteral("Voice request failed"));
            emit voiceChanged();
            return;
        }
        if (!stopping) {
            m_voiceListening = true;
            m_voiceTranscribing = false;
            m_voiceStatus = QStringLiteral("Listening… click Listen again when finished");
            emit voiceChanged();
            return;
        }
        m_voiceListening = false;
        m_voiceTranscribing = false;
        m_voiceTranscript = o.value(QStringLiteral("transcript")).toString().trimmed();
        m_voiceStatus = m_voiceTranscript.isEmpty() ? QStringLiteral("I didn't catch that") : QStringLiteral("Heard you");
        emit voiceChanged();
        if (!m_voiceTranscript.isEmpty()) {
            m_voiceAutoSpeakNext = m_voiceSpeakReplies;
            askTony(m_voiceTranscript);
        }
    });
}

void SystemBackend::speakText(const QString &text)
{
    const QString clean = text.trimmed();
    if (clean.isEmpty()) return;
    m_voiceSpeaking = true;
    m_voiceStatus = QStringLiteral("Tony is speaking");
    emit voiceChanged();
    QJsonObject payload; payload[QStringLiteral("text")] = clean.left(2200);
    postVoice(QStringLiteral("/speak"), QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::stopSpeaking()
{
    m_voiceSpeaking = false;
    m_voiceStatus = QStringLiteral("Voice ready");
    emit voiceChanged();
    postVoice(QStringLiteral("/speak/stop"), QByteArray("{}"));
}

void SystemBackend::setVoiceSpeakReplies(bool enabled)
{
    m_voiceSpeakReplies = enabled;
    emit voiceChanged();
    QJsonObject payload; payload[QStringLiteral("speak_replies")] = enabled;
    postVoice(QStringLiteral("/config"), QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void SystemBackend::setVoiceTtsBackend(const QString &backend)
{
    const QString b = backend.trimmed().toLower() == QStringLiteral("system") ? QStringLiteral("system") : QStringLiteral("natural");
    QJsonObject payload; payload[QStringLiteral("tts_backend")] = b;
    postVoice(QStringLiteral("/config"), QJsonDocument(payload).toJson(QJsonDocument::Compact));
    QTimer::singleShot(350, this, &SystemBackend::refreshVoiceStatus);
}

void SystemBackend::runTonyClientAction(const QString &tool, const QVariantMap &args)
{
    if (tool == "open_app") {
        launchApp(args.value("app").toString());
    } else if (tool == "open_path") {
        emit appRequested("files:" + args.value("path").toString());
    } else if (tool == "open_url") {
        QDesktopServices::openUrl(QUrl(args.value("url").toString()));
    } else if (tool == "set_volume") {
        setVolume(args.value("percent").toInt());
    } else if (tool == "set_mute") {
        setMuted(args.value("muted").toBool());
    } else if (tool == "private_mode") {
        setPrivateMode(args.value("enabled").toBool());
    } else if (tool == "set_brightness") {
        setBrightness(args.value("percent").toInt());
    } else if (tool == "set_wifi") {
        setWifiEnabled(args.value("enabled").toBool());
    } else if (tool == "set_clipboard") {
        if (QGuiApplication::clipboard()) QGuiApplication::clipboard()->setText(args.value("text").toString().left(20000));
    } else if (tool == "open_overlay") {
        emit appRequested("overlay:" + args.value("name").toString());
    } else if (tool == "show_desktop") {
        emit appRequested("showdesktop");
    } else if (tool == "speak") {
        speakText(args.value("text").toString());
    } else if (tool == "power_action") {
        powerAction(args.value("action").toString());
    }
}

void SystemBackend::handleTonyReply(QNetworkReply *reply)
{
    m_tonyBusy = false;
    const QByteArray raw = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        const bool speakFailure = m_voiceAutoSpeakNext;
        m_voiceAutoSpeakNext = false;
        m_tonyOnline = false;
        m_tonyReply = "Tony timed out or the local service is unavailable. Basic Nexora controls still work.";
        m_tonyStatus = "Tony service/model unavailable";
        reply->deleteLater();
        emit tonyChanged();
        if (speakFailure && m_voiceSpeakReplies) speakText(m_tonyReply);
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(raw);
    if (!doc.isObject()) {
        const bool speakFailure = m_voiceAutoSpeakNext;
        m_voiceAutoSpeakNext = false;
        m_tonyReply = "Tony returned an invalid local-model response. I reset the request; try again.";
        reply->deleteLater();
        emit tonyChanged();
        if (speakFailure && m_voiceSpeakReplies) speakText(m_tonyReply);
        return;
    }
    const QJsonObject o = doc.object();
    m_tonyOnline = true;
    if (o.contains("model_online")) m_tonyModelOnline = o.value("model_online").toBool(m_tonyModelOnline);
    if (o.contains("model_policy")) {
        const QString policy = o.value("model_policy").toString();
        if (!policy.isEmpty()) m_tonyModelPolicy = policy;
    }
    m_tonyReply = o.value("reply").toString("Done.");
    m_tonyApprovalId.clear();
    m_tonyApprovalText.clear();

    const QJsonArray clientActions = o.value("client_actions").toArray();
    for (const QJsonValue &v : clientActions) {
        const QJsonObject a = v.toObject();
        runTonyClientAction(a.value("tool").toString(), a.value("args").toObject().toVariantMap());
    }

    const QJsonObject pending = o.value("pending").toObject();
    if (!pending.isEmpty()) {
        m_tonyApprovalId = pending.value("id").toString();
        m_tonyApprovalText = pending.value("description").toString("Sensitive action");
    }
    m_tonyStatus = m_tonyModelOnline ? "Tony · local model ready" : "Tony · system tools ready";
    const bool speakReply = m_voiceAutoSpeakNext;
    m_voiceAutoSpeakNext = false;
    reply->deleteLater();
    emit tonyChanged();
    if (speakReply && m_voiceSpeakReplies) speakText(m_tonyReply);
}

QString SystemBackend::executeIntent(const QString &text)
{
    const QString original = text.trimmed();
    const QString q = original.toLower();
    if (q.isEmpty()) return "Type a command, open an app, or jump to a project.";

    if (q == "help" || q.contains("what can you do"))
        return "Tony can listen and speak locally, open apps, manage projects/files, inspect the system, control audio/Wi-Fi/brightness, calculate and convert units, remember context, search the web, and propose approved sensitive actions.";

    if (q.contains("open terminal") || q == "terminal") { launchApp("terminal"); return "Terminal opened."; }
    if (q.contains("open files") || q.contains("file manager") || q == "files") { launchApp("files"); return "Files opened."; }
    if (q.contains("open settings") || q == "settings") { launchApp("settings"); return "Settings opened."; }
    if (q.contains("open apps") || q.contains("app center") || q == "store") { emit appRequested("appcenter"); return "App Center opened."; }
    if (q.contains("open projects") || q == "projects") { launchApp("projects"); return "Projects opened."; }
    if (q.contains("open browser") || q == "browser" || q == "web") { launchApp("browser"); return "Opening browser."; }

    if (q.contains("system status") || q.contains("system stats") || q == "stats")
        return QString("CPU %1% · RAM %2/%3 GiB · uptime %4 · %5")
            .arg(m_cpuUsage, 0, 'f', 0)
            .arg(m_memoryUsedGiB, 0, 'f', 1)
            .arg(m_memoryTotalGiB, 0, 'f', 1)
            .arg(m_uptimeText)
            .arg(m_networkConnected ? "online" : "offline");

    if (q.startsWith("create project ")) return createProject(original.mid(QString("create project ").size()));

    if (q == "list projects" || q.contains("show projects")) {
        const auto p = listProjects();
        return p.isEmpty() ? "No projects yet." : "Projects: " + p.join(", ");
    }

    if (q == "private mode on" || q == "enable private mode") {
        setPrivateMode(true);
        return "Context monitoring paused.";
    }
    if (q == "private mode off" || q == "disable private mode") {
        setPrivateMode(false);
        return "Local context monitoring resumed.";
    }

    if (q == "logout" || q == "log out" || q == "exit session") {
        emit sessionExitRequested();
        return "Ending session.";
    }

    return "Ask Tony naturally — the local AI will interpret this request.";
}

void SystemBackend::refreshNow()
{
    refreshCoreStatus();
    updateContext();
    if (!m_coreOnline) {
        readNetwork();
        readBattery();
        refreshAudioAsync();
    }
    refreshTonyStatus();
}

void SystemBackend::rebuildExternalWindows()
{
    QVariantList next;
    QStringList cleaned;
    for (const QString &id : std::as_const(m_externalWindowOrder)) {
        if (!m_externalWindowMap.contains(id)) continue;
        next.push_back(m_externalWindowMap.value(id));
        cleaned.push_back(id);
    }
    m_externalWindowOrder = cleaned;
    m_externalWindows = next;
    emit externalWindowsChanged();
}

void SystemBackend::reportWindow(const QString &id, const QString &caption, const QString &desktopFile,
                                 qlonglong pid, bool minimized, bool active, bool demandsAttention)
{
    const QString cleanId = id.trimmed();
    if (cleanId.isEmpty()) return;

    // All Nexora OS-native windows share this process and already have a
    // richer in-process lifecycle model; suppress them to avoid duplicate tabs.
    if (pid == static_cast<qlonglong>(QCoreApplication::applicationPid())) return;

    QVariantMap m;
    m["id"] = cleanId;
    m["title"] = caption.trimmed().isEmpty() ? QStringLiteral("Application") : caption.trimmed();
    m["app"] = desktopFile.trimmed();
    m["minimized"] = minimized;
    m["active"] = active;
    m["attention"] = demandsAttention;

    const bool existed = m_externalWindowMap.contains(cleanId);
    if (!existed) m_externalWindowOrder.push_back(cleanId);
    if (existed && m_externalWindowMap.value(cleanId) == m) return;
    m_externalWindowMap.insert(cleanId, m);
    rebuildExternalWindows();
}

void SystemBackend::removeWindow(const QString &id)
{
    const QString cleanId = id.trimmed();
    if (!m_externalWindowMap.remove(cleanId)) return;
    m_externalWindowOrder.removeAll(cleanId);
    m_desktopRestoreWindowIds.removeAll(cleanId);
    rebuildExternalWindows();
}

void SystemBackend::runKWinActionScript(const QString &javascript)
{
    QTemporaryFile *file = new QTemporaryFile(QDir::tempPath() + "/nexora-kwin-action-XXXXXX.js", this);
    file->setAutoRemove(false);
    if (!file->open()) { file->deleteLater(); return; }
    file->write(javascript.toUtf8());
    const QString path = file->fileName();
    file->close();

    const QString plugin = QString("nexora-action-%1").arg(QDateTime::currentMSecsSinceEpoch());
    QDBusInterface scripting("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", QDBusConnection::sessionBus());
    if (!scripting.isValid()) { QFile::remove(path); file->deleteLater(); return; }

    QDBusReply<int> loaded = scripting.call("loadScript", path, plugin);
    if (!loaded.isValid() || loaded.value() < 0) { QFile::remove(path); file->deleteLater(); return; }

    const int scriptId = loaded.value();
    QDBusInterface script("org.kde.KWin", QString("/Scripting/Script%1").arg(scriptId),
                          "org.kde.kwin.Script", QDBusConnection::sessionBus());
    if (script.isValid()) script.call("run");

    QTimer::singleShot(700, this, [plugin, path, file]() {
        QDBusInterface scripting2("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", QDBusConnection::sessionBus());
        if (scripting2.isValid()) scripting2.call("unloadScript", plugin);
        QFile::remove(path);
        file->deleteLater();
    });
}

void SystemBackend::windowAction(const QString &id, const QString &action)
{
    QString cleanId = id.trimmed();
    QString cleanAction = action.trimmed().toLower();
    if (cleanId.isEmpty()) return;
    if (cleanAction != "toggle" && cleanAction != "activate" && cleanAction != "minimize" && cleanAction != "close")
        return;

    cleanId.replace('\\', "\\\\").replace('"', "\\\"");
    cleanAction.replace('\\', "\\\\").replace('"', "\\\"");
    const QString js = QString::fromLatin1(R"JS(
const targetId = "%1";
const action = "%2";
const windows = workspace.stackingOrder;
for (let i = 0; i < windows.length; ++i) {
    const w = windows[i];
    if (String(w.internalId) !== targetId) continue;
    if (action === "close") {
        if (w.closeable) w.closeWindow();
    } else if (action === "minimize") {
        if (w.minimizable) w.minimized = true;
    } else if (action === "activate") {
        if (w.minimized) w.minimized = false;
        workspace.raiseWindow(w);
        workspace.activeWindow = w;
        if (w.demandsAttention) w.demandsAttention = false;
    } else {
        if (w.minimized) {
            w.minimized = false;
            workspace.raiseWindow(w);
            workspace.activeWindow = w;
        } else if (w.active && w.minimizable) {
            w.minimized = true;
        } else {
            workspace.raiseWindow(w);
            workspace.activeWindow = w;
        }
        if (!w.minimized && w.demandsAttention) w.demandsAttention = false;
    }
    break;
}
)JS").arg(cleanId, cleanAction);
    runKWinActionScript(js);
}

static QString jsStringArray(const QStringList &values)
{
    QStringList escaped;
    escaped.reserve(values.size());
    for (QString value : values) {
        value.replace('\\', "\\\\").replace('"', "\\\"");
        escaped.push_back(QStringLiteral("\"") + value + QStringLiteral("\""));
    }
    return QStringLiteral("[") + escaped.join(',') + QStringLiteral("]");
}

void SystemBackend::showDesktop()
{
    // Critical V1 stability inheritance: never sweep KWin's whole stacking order. The
    // Nexora OS desktop itself is a normal managed window and the prototype could
    // minimize it, producing a black screen. Only minimize windows that the
    // taskbar bridge has explicitly identified as third-party application
    // tasks; native Nexora OS windows are handled in QML.
    m_desktopRestoreWindowIds.clear();
    for (const QString &id : std::as_const(m_externalWindowOrder)) {
        const QVariantMap state = m_externalWindowMap.value(id);
        if (state.isEmpty() || state.value("minimized").toBool()) continue;
        m_desktopRestoreWindowIds.push_back(id);
    }
    if (m_desktopRestoreWindowIds.isEmpty()) return;

    const QString ids = jsStringArray(m_desktopRestoreWindowIds);
    const QString js = QString::fromLatin1(R"JS(
const ids = %1;
const windows = workspace.stackingOrder;
for (let i = 0; i < windows.length; ++i) {
    const w = windows[i];
    if (ids.indexOf(String(w.internalId)) < 0) continue;
    if (w.minimizable && !w.minimized) w.minimized = true;
}
)JS").arg(ids);
    runKWinActionScript(js);
}

void SystemBackend::restoreDesktop()
{
    const QStringList restore = m_desktopRestoreWindowIds;
    m_desktopRestoreWindowIds.clear();
    if (restore.isEmpty()) return;

    const QString ids = jsStringArray(restore);
    const QString js = QString::fromLatin1(R"JS(
const ids = %1;
const windows = workspace.stackingOrder;
let last = null;
for (let i = 0; i < windows.length; ++i) {
    const w = windows[i];
    if (ids.indexOf(String(w.internalId)) < 0) continue;
    if (w.minimized) w.minimized = false;
    workspace.raiseWindow(w);
    last = w;
}
if (last !== null) workspace.activeWindow = last;
)JS").arg(ids);
    runKWinActionScript(js);
}
