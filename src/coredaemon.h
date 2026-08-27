#pragma once

#include <QObject>
#include <QTimer>
#include <QStringList>
#include <QVariantMap>

class QProcess;

// Nexora Core owns small, deterministic OS primitives that must survive shell
// restarts. The desktop shell is a client of this service over the session bus.
class CoreDaemon : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nexora.Core")
public:
    explicit CoreDaemon(QObject *parent = nullptr);

public slots:
    Q_SCRIPTABLE QString Ping() const;
    Q_SCRIPTABLE QVariantMap GetStatus() const;
    Q_SCRIPTABLE QStringList ListProjects() const;
    Q_SCRIPTABLE QString CreateProject(const QString &name);
    Q_SCRIPTABLE void SetVolume(int percent);
    Q_SCRIPTABLE void SetMuted(bool muted);
    Q_SCRIPTABLE void SetBrightness(int percent);
    Q_SCRIPTABLE void SetWifiEnabled(bool enabled);
    Q_SCRIPTABLE void PowerAction(const QString &action);

signals:
    void StatusChanged(const QVariantMap &status);
    void AudioChanged(int volume, bool muted, bool available);
    void ProjectsChanged();

private slots:
    void refreshFast();
    void refreshSlow();
    void refreshAudio();

private:
    void readCpu();
    void readMemory();
    void readUptime();
    void readNetwork();
    void readBattery();
    void readDeviceControls();
    void startAudioProbe(const QString &program, const QStringList &args, bool pactlMode = false);
    QVariantMap buildStatus() const;
    QString projectsDir() const;

    QTimer m_fastTimer;
    QTimer m_slowTimer;
    QTimer m_audioTimer;
    qulonglong m_prevIdle = 0;
    qulonglong m_prevTotal = 0;
    double m_cpu = 0.0;
    double m_memory = 0.0;
    double m_memoryUsedGiB = 0.0;
    double m_memoryTotalGiB = 0.0;
    QString m_uptime;
    bool m_network = false;
    bool m_batteryPresent = false;
    int m_batteryPercent = -1;
    bool m_batteryCharging = false;
    int m_volume = 50;
    bool m_muted = false;
    bool m_audioAvailable = false;
    bool m_audioProbeBusy = false;
    bool m_wifiAvailable = false;
    bool m_wifiEnabled = false;
    bool m_brightnessAvailable = false;
    int m_brightness = 50;
};
