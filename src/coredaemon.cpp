#include "coredaemon.h"

#include <QAbstractSocket>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QtMath>

CoreDaemon::CoreDaemon(QObject *parent) : QObject(parent)
{
    connect(&m_fastTimer, &QTimer::timeout, this, &CoreDaemon::refreshFast);
    connect(&m_slowTimer, &QTimer::timeout, this, &CoreDaemon::refreshSlow);
    connect(&m_audioTimer, &QTimer::timeout, this, &CoreDaemon::refreshAudio);

    // Resource budget: deterministic telemetry is cheap, but it does not need
    // animation-frame cadence. This keeps Nexora Core nearly invisible at idle.
    m_fastTimer.start(3000);
    m_slowTimer.start(12000);
    m_audioTimer.start(15000);

    refreshFast();
    refreshSlow();
    refreshAudio();
}

QString CoreDaemon::Ping() const { return QStringLiteral("nexora-core/1.0.1-beta.1"); }

QString CoreDaemon::projectsDir() const
{
    return QDir::homePath() + QStringLiteral("/NexoraProjects");
}

void CoreDaemon::readCpu()
{
    QFile f(QStringLiteral("/proc/stat"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    const QStringList p = QString::fromUtf8(f.readLine()).simplified().split(' ');
    if (p.size() < 8 || p[0] != QStringLiteral("cpu")) return;
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
        m_cpu = qBound(0.0, (1.0 - double(idleDelta) / double(totalDelta)) * 100.0, 100.0);
    }
    m_prevTotal = total;
    m_prevIdle = idleAll;
}

void CoreDaemon::readMemory()
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
    if (!availableKiB) {
        const qulonglong cacheLike = cachedKiB + reclaimableKiB;
        availableKiB = freeKiB + buffersKiB + (cacheLike > shmemKiB ? cacheLike - shmemKiB : 0);
    }
    availableKiB = qMin(availableKiB, totalKiB);

    const qulonglong usedKiB = totalKiB - availableKiB;
    m_memoryTotalGiB = double(totalKiB) / 1024.0 / 1024.0;
    m_memoryUsedGiB = double(usedKiB) / 1024.0 / 1024.0;
    m_memory = qBound(0.0, double(usedKiB) / double(totalKiB) * 100.0, 100.0);
}

void CoreDaemon::readUptime()
{
    QFile f(QStringLiteral("/proc/uptime"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return;
    const double seconds = QString::fromUtf8(f.readAll()).split(' ').first().toDouble();
    const int mins = int(seconds / 60.0);
    const int hours = mins / 60;
    const int days = hours / 24;
    if (days > 0) m_uptime = QStringLiteral("%1d %2h").arg(days).arg(hours % 24);
    else if (hours > 0) m_uptime = QStringLiteral("%1h %2m").arg(hours).arg(mins % 60);
    else m_uptime = QStringLiteral("%1m").arg(mins);
}

void CoreDaemon::readNetwork()
{
    bool connected = false;
    for (const auto &iface : QNetworkInterface::allInterfaces()) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning) || (flags & QNetworkInterface::IsLoopBack)) continue;
        for (const auto &entry : iface.addressEntries()) {
            const QHostAddress addr = entry.ip();
            if (addr.protocol() == QAbstractSocket::IPv4Protocol && !addr.isLoopback() && !addr.isNull()) {
                connected = true; break;
            }
        }
        if (connected) break;
    }
    m_network = connected;
}

void CoreDaemon::readBattery()
{
    bool present = false; int percent = -1; bool charging = false;
    QDir d(QStringLiteral("/sys/class/power_supply"));
    for (const QString &name : d.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (!name.startsWith(QStringLiteral("BAT"), Qt::CaseInsensitive)) continue;
        const QString base = d.absoluteFilePath(name);
        QFile cap(base + QStringLiteral("/capacity"));
        QFile status(base + QStringLiteral("/status"));
        if (cap.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool ok = false; const int p = QString::fromUtf8(cap.readAll()).trimmed().toInt(&ok);
            if (ok) { present = true; percent = qBound(0, p, 100); }
        }
        if (status.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString s = QString::fromUtf8(status.readAll()).trimmed().toLower();
            charging = s.contains(QStringLiteral("charging")) || s.contains(QStringLiteral("full"));
        }
        if (present) break;
    }
    m_batteryPresent = present; m_batteryPercent = percent; m_batteryCharging = charging;
}


void CoreDaemon::readDeviceControls()
{
    m_brightnessAvailable = false;
    QDir backlights(QStringLiteral("/sys/class/backlight"));
    const QStringList entries = backlights.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!entries.isEmpty()) {
        const QString base = backlights.absoluteFilePath(entries.first());
        QFile current(base + QStringLiteral("/brightness"));
        QFile maximum(base + QStringLiteral("/max_brightness"));
        if (current.open(QIODevice::ReadOnly | QIODevice::Text) && maximum.open(QIODevice::ReadOnly | QIODevice::Text)) {
            bool ok1 = false, ok2 = false;
            const int cur = QString::fromUtf8(current.readAll()).trimmed().toInt(&ok1);
            const int max = QString::fromUtf8(maximum.readAll()).trimmed().toInt(&ok2);
            if (ok1 && ok2 && max > 0) {
                m_brightnessAvailable = true;
                m_brightness = qBound(0, int(qRound(double(cur) / double(max) * 100.0)), 100);
            }
        }
    }

    m_wifiAvailable = false;
    QDir net(QStringLiteral("/sys/class/net"));
    for (const QString &name : net.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        if (QFileInfo::exists(net.absoluteFilePath(name) + QStringLiteral("/wireless"))) {
            m_wifiAvailable = true;
            break;
        }
    }
    if (m_wifiAvailable && !QStandardPaths::findExecutable(QStringLiteral("nmcli")).isEmpty()) {
        QProcess proc;
        proc.start(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi")});
        if (proc.waitForFinished(700)) {
            const QString out = QString::fromLocal8Bit(proc.readAllStandardOutput()).trimmed().toLower();
            m_wifiEnabled = out == QStringLiteral("enabled");
        }
    }
}

QVariantMap CoreDaemon::buildStatus() const
{
    return {
        {QStringLiteral("cpuUsage"), m_cpu},
        {QStringLiteral("memoryUsage"), m_memory},
        {QStringLiteral("memoryUsedGiB"), m_memoryUsedGiB},
        {QStringLiteral("memoryTotalGiB"), m_memoryTotalGiB},
        {QStringLiteral("uptimeText"), m_uptime},
        {QStringLiteral("networkConnected"), m_network},
        {QStringLiteral("batteryPresent"), m_batteryPresent},
        {QStringLiteral("batteryPercent"), m_batteryPercent},
        {QStringLiteral("batteryCharging"), m_batteryCharging},
        {QStringLiteral("volumeLevel"), m_volume},
        {QStringLiteral("muted"), m_muted},
        {QStringLiteral("audioAvailable"), m_audioAvailable},
        {QStringLiteral("wifiAvailable"), m_wifiAvailable},
        {QStringLiteral("wifiEnabled"), m_wifiEnabled},
        {QStringLiteral("brightnessAvailable"), m_brightnessAvailable},
        {QStringLiteral("brightnessLevel"), m_brightness},
        {QStringLiteral("version"), QStringLiteral("1.0.1-beta.1")}
    };
}

QVariantMap CoreDaemon::GetStatus() const { return buildStatus(); }

void CoreDaemon::refreshFast()
{
    readCpu(); readMemory(); readUptime();
    emit StatusChanged(buildStatus());
}

void CoreDaemon::refreshSlow()
{
    readNetwork(); readBattery(); readDeviceControls();
    emit StatusChanged(buildStatus());
}

void CoreDaemon::startAudioProbe(const QString &program, const QStringList &args, bool pactlMode)
{
    if (m_audioProbeBusy) return;
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        if (!pactlMode && !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty())
            startAudioProbe(QStringLiteral("pactl"), {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")}, true);
        else {
            m_audioAvailable = false;
            emit AudioChanged(m_volume, m_muted, false);
            emit StatusChanged(buildStatus());
        }
        return;
    }

    m_audioProbeBusy = true;
    auto *probe = new QProcess(this);
    probe->setProcessChannelMode(QProcess::MergedChannels);
    connect(probe, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
            [this, probe, pactlMode](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromLocal8Bit(probe->readAll()).trimmed();
        probe->deleteLater(); m_audioProbeBusy = false;
        bool parsed = false; int volume = m_volume; bool muted = m_muted;
        if (status == QProcess::NormalExit && code == 0) {
            if (!pactlMode) {
                const auto m = QRegularExpression(QStringLiteral("Volume:\\s*([0-9.]+)(.*)")).match(out);
                if (m.hasMatch()) {
                    bool ok = false; const double raw = m.captured(1).toDouble(&ok);
                    if (ok) { volume = qBound(0, int(qRound(raw * 100.0)), 100); muted = m.captured(2).contains(QStringLiteral("MUTED"), Qt::CaseInsensitive); parsed = true; }
                }
            } else {
                const auto m = QRegularExpression(QStringLiteral("([0-9]{1,3})%")).match(out);
                if (m.hasMatch()) { volume = qBound(0, m.captured(1).toInt(), 100); parsed = true; }
            }
        }
        if (!parsed && !pactlMode && !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty()) {
            startAudioProbe(QStringLiteral("pactl"), {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")}, true); return;
        }
        m_volume = volume; m_muted = muted; m_audioAvailable = parsed;
        emit AudioChanged(m_volume, m_muted, m_audioAvailable);
        emit StatusChanged(buildStatus());
        if (parsed && pactlMode) {
            auto *muteProbe = new QProcess(this);
            connect(muteProbe, qOverload<int,QProcess::ExitStatus>(&QProcess::finished), this,
                    [this, muteProbe](int, QProcess::ExitStatus) {
                const bool mute = QString::fromLocal8Bit(muteProbe->readAllStandardOutput()).contains(QStringLiteral("yes"), Qt::CaseInsensitive);
                muteProbe->deleteLater(); m_muted = mute;
                emit AudioChanged(m_volume, m_muted, m_audioAvailable);
                emit StatusChanged(buildStatus());
            });
            muteProbe->start(QStringLiteral("pactl"), {QStringLiteral("get-sink-mute"), QStringLiteral("@DEFAULT_SINK@")});
        }
    });
    connect(probe, &QProcess::errorOccurred, this, [this, probe, pactlMode](QProcess::ProcessError err) {
        if (err != QProcess::FailedToStart) return;
        probe->deleteLater(); m_audioProbeBusy = false;
        if (!pactlMode && !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty())
            startAudioProbe(QStringLiteral("pactl"), {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")}, true);
        else { m_audioAvailable = false; emit AudioChanged(m_volume, m_muted, false); }
    });
    probe->start(program, args);
}

void CoreDaemon::refreshAudio()
{
    if (!m_audioProbeBusy) startAudioProbe(QStringLiteral("wpctl"), {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}, false);
}

void CoreDaemon::SetVolume(int percent)
{
    percent = qBound(0, percent, 100); m_volume = percent;
    emit AudioChanged(m_volume, m_muted, m_audioAvailable);
    const QString pct = QString::number(percent) + QStringLiteral("%");
    bool started = false;
    if (!QStandardPaths::findExecutable(QStringLiteral("wpctl")).isEmpty())
        started = QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), pct});
    if (!started && !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty())
        started = QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"), pct});
    if (!started && !QStandardPaths::findExecutable(QStringLiteral("amixer")).isEmpty())
        QProcess::startDetached(QStringLiteral("amixer"), {QStringLiteral("-q"), QStringLiteral("sset"), QStringLiteral("Master"), pct});
    QTimer::singleShot(250, this, &CoreDaemon::refreshAudio);
}

void CoreDaemon::SetMuted(bool muted)
{
    m_muted = muted; emit AudioChanged(m_volume, m_muted, m_audioAvailable);
    bool started = false;
    if (!QStandardPaths::findExecutable(QStringLiteral("wpctl")).isEmpty())
        started = QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), muted ? QStringLiteral("1") : QStringLiteral("0")});
    if (!started && !QStandardPaths::findExecutable(QStringLiteral("pactl")).isEmpty())
        started = QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-mute"), QStringLiteral("@DEFAULT_SINK@"), muted ? QStringLiteral("1") : QStringLiteral("0")});
    if (!started && !QStandardPaths::findExecutable(QStringLiteral("amixer")).isEmpty())
        QProcess::startDetached(QStringLiteral("amixer"), {QStringLiteral("-q"), QStringLiteral("sset"), QStringLiteral("Master"), muted ? QStringLiteral("mute") : QStringLiteral("unmute")});
    QTimer::singleShot(250, this, &CoreDaemon::refreshAudio);
}

QStringList CoreDaemon::ListProjects() const
{
    QDir d(projectsDir());
    if (!d.exists()) return {};
    return d.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
}

QString CoreDaemon::CreateProject(const QString &name)
{
    QString clean = name.trimmed();
    clean.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9._ -]")), QString());
    if (clean.isEmpty()) return QStringLiteral("Give the project a name.");
    const QString root = projectsDir() + QStringLiteral("/") + clean;
    const bool existed = QFileInfo::exists(root);
    QDir().mkpath(root);
    for (const QString &sub : {QStringLiteral("mechanical"), QStringLiteral("electronics"), QStringLiteral("simulation"), QStringLiteral("software"), QStringLiteral("documents"), QStringLiteral(".nexora")})
        QDir().mkpath(root + QStringLiteral("/") + sub);
    const QString metaPath = root + QStringLiteral("/.nexora/project.json");
    if (!QFileInfo::exists(metaPath)) {
        QFile meta(metaPath);
        if (meta.open(QIODevice::WriteOnly)) {
            QJsonObject o; o[QStringLiteral("name")] = clean; o[QStringLiteral("created")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
            o[QStringLiteral("version")] = 2; o[QStringLiteral("units")] = QStringLiteral("SI"); o[QStringLiteral("platform")] = QStringLiteral("Nexora OS");
            meta.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        }
    }
    emit ProjectsChanged();
    return existed ? QStringLiteral("Project %1 already exists.").arg(clean) : QStringLiteral("Created %1.").arg(clean);
}


void CoreDaemon::SetBrightness(int percent)
{
    percent = qBound(1, percent, 100);
    m_brightness = percent;
    if (!QStandardPaths::findExecutable(QStringLiteral("brightnessctl")).isEmpty()) {
        QProcess::startDetached(QStringLiteral("brightnessctl"), {QStringLiteral("set"), QString::number(percent) + QStringLiteral("%")});
    }
    QTimer::singleShot(300, this, [this]() { readDeviceControls(); emit StatusChanged(buildStatus()); });
}

void CoreDaemon::SetWifiEnabled(bool enabled)
{
    m_wifiEnabled = enabled;
    if (!QStandardPaths::findExecutable(QStringLiteral("nmcli")).isEmpty()) {
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), enabled ? QStringLiteral("on") : QStringLiteral("off")});
    }
    QTimer::singleShot(500, this, [this]() { readNetwork(); readDeviceControls(); emit StatusChanged(buildStatus()); });
}

void CoreDaemon::PowerAction(const QString &action)
{
    const QString a = action.trimmed().toLower();
    if (a == QStringLiteral("reboot") || a == QStringLiteral("restart")) QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
    else if (a == QStringLiteral("poweroff") || a == QStringLiteral("shutdown")) QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
}
