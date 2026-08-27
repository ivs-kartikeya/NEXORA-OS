#pragma once

#include <QObject>
#include <QTimer>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QByteArray>
#include <QHash>

class QNetworkAccessManager;
class QNetworkReply;
class QFileSystemWatcher;
class QProcess;
class QDBusInterface;
class QJsonObject;
class QSocketNotifier;

class SystemBackend : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nexora.WindowBridge")
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY statsChanged)
    Q_PROPERTY(double memoryUsage READ memoryUsage NOTIFY statsChanged)
    Q_PROPERTY(double memoryUsedGiB READ memoryUsedGiB NOTIFY statsChanged)
    Q_PROPERTY(double memoryTotalGiB READ memoryTotalGiB NOTIFY statsChanged)
    Q_PROPERTY(QString currentTime READ currentTime NOTIFY timeChanged)
    Q_PROPERTY(QString currentDate READ currentDate NOTIFY timeChanged)
    Q_PROPERTY(QString hostname READ hostname CONSTANT)
    Q_PROPERTY(QString uptimeText READ uptimeText NOTIFY statsChanged)
    Q_PROPERTY(QString contextSummary READ contextSummary NOTIFY contextChanged)
    Q_PROPERTY(QStringList recentEvents READ recentEvents NOTIFY contextChanged)
    Q_PROPERTY(QStringList engineeringApps READ engineeringApps NOTIFY contextChanged)
    Q_PROPERTY(bool privateMode READ privateMode NOTIFY privateModeChanged)
    Q_PROPERTY(QString aiStatus READ aiStatus NOTIFY contextChanged)
    Q_PROPERTY(QString terminalWorkingDirectory READ terminalWorkingDirectory NOTIFY terminalWorkingDirectoryChanged)
    Q_PROPERTY(QString homeDirectory READ homeDirectory CONSTANT)
    Q_PROPERTY(QString projectsDirectory READ projectsDirectory CONSTANT)

    Q_PROPERTY(QString osVersion READ osVersion CONSTANT)
    Q_PROPERTY(QString kernelVersion READ kernelVersion CONSTANT)
    Q_PROPERTY(bool networkConnected READ networkConnected NOTIFY connectivityChanged)
    Q_PROPERTY(int volumeLevel READ volumeLevel NOTIFY audioChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY audioChanged)
    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY batteryChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY batteryChanged)
    Q_PROPERTY(bool batteryCharging READ batteryCharging NOTIFY batteryChanged)
    Q_PROPERTY(bool audioAvailable READ audioAvailable NOTIFY audioChanged)
    Q_PROPERTY(QString appJobStatus READ appJobStatus NOTIFY appJobChanged)
    Q_PROPERTY(bool appJobBusy READ appJobBusy NOTIFY appJobChanged)
    Q_PROPERTY(QVariantList appSearchResults READ appSearchResults NOTIFY appSearchChanged)
    Q_PROPERTY(bool appSearchBusy READ appSearchBusy NOTIFY appSearchChanged)
    Q_PROPERTY(QVariantList externalWindows READ externalWindows NOTIFY externalWindowsChanged)
    Q_PROPERTY(bool coreOnline READ coreOnline NOTIFY coreChanged)
    Q_PROPERTY(QString coreStatus READ coreStatus NOTIFY coreChanged)
    Q_PROPERTY(bool wifiAvailable READ wifiAvailable NOTIFY deviceControlChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY deviceControlChanged)
    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY deviceControlChanged)
    Q_PROPERTY(int brightnessLevel READ brightnessLevel NOTIFY deviceControlChanged)

    // Nexora OS V1 — on-demand local speech. No hot microphone by default.
    Q_PROPERTY(bool voiceOnline READ voiceOnline NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceListening READ voiceListening NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceTranscribing READ voiceTranscribing NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceSpeaking READ voiceSpeaking NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceSttReady READ voiceSttReady NOTIFY voiceChanged)
    Q_PROPERTY(QString voiceStatus READ voiceStatus NOTIFY voiceChanged)
    Q_PROPERTY(QString voiceTranscript READ voiceTranscript NOTIFY voiceChanged)
    Q_PROPERTY(QString voiceTtsBackend READ voiceTtsBackend NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceSpeakReplies READ voiceSpeakReplies NOTIFY voiceChanged)
    Q_PROPERTY(bool voiceRequestBusy READ voiceRequestBusy NOTIFY voiceChanged)
    Q_PROPERTY(bool terminalSessionReady READ terminalSessionReady NOTIFY terminalSessionChanged)

    // Nexora OS V1 — Tony local intelligence.
    Q_PROPERTY(bool tonyOnline READ tonyOnline NOTIFY tonyChanged)
    Q_PROPERTY(bool tonyModelOnline READ tonyModelOnline NOTIFY tonyChanged)
    Q_PROPERTY(bool tonyBusy READ tonyBusy NOTIFY tonyChanged)
    Q_PROPERTY(QString tonyStatus READ tonyStatus NOTIFY tonyChanged)
    Q_PROPERTY(QString tonyReply READ tonyReply NOTIFY tonyChanged)
    Q_PROPERTY(bool tonyApprovalPending READ tonyApprovalPending NOTIFY tonyChanged)
    Q_PROPERTY(QString tonyApprovalText READ tonyApprovalText NOTIFY tonyChanged)
    Q_PROPERTY(QString tonyModelPolicy READ tonyModelPolicy NOTIFY tonyChanged)
    Q_PROPERTY(QString quickNote READ quickNote NOTIFY noteChanged)

public:
    explicit SystemBackend(QObject *parent = nullptr);
    ~SystemBackend() override;

    double cpuUsage() const { return m_cpuUsage; }
    double memoryUsage() const { return m_memoryUsage; }
    double memoryUsedGiB() const { return m_memoryUsedGiB; }
    double memoryTotalGiB() const { return m_memoryTotalGiB; }
    QString currentTime() const { return m_currentTime; }
    QString currentDate() const { return m_currentDate; }
    QString hostname() const { return m_hostname; }
    QString uptimeText() const { return m_uptimeText; }
    QString contextSummary() const { return m_contextSummary; }
    QStringList recentEvents() const { return m_recentEvents; }
    QStringList engineeringApps() const { return m_engineeringApps; }
    bool privateMode() const { return m_privateMode; }
    QString aiStatus() const { return m_aiStatus; }
    QString terminalWorkingDirectory() const { return m_terminalWorkingDirectory; }
    QString homeDirectory() const;
    QString projectsDirectory() const;

    QString osVersion() const { return QStringLiteral("1.0.1-beta.1"); }
    QString kernelVersion() const { return m_kernelVersion; }
    bool networkConnected() const { return m_networkConnected; }
    int volumeLevel() const { return m_volumeLevel; }
    bool muted() const { return m_muted; }
    bool batteryPresent() const { return m_batteryPresent; }
    int batteryPercent() const { return m_batteryPercent; }
    bool batteryCharging() const { return m_batteryCharging; }
    bool audioAvailable() const { return m_audioAvailable; }
    QString appJobStatus() const { return m_appJobStatus; }
    bool appJobBusy() const { return m_appJobBusy; }
    QVariantList appSearchResults() const { return m_appSearchResults; }
    bool appSearchBusy() const { return m_appSearchBusy; }
    QVariantList externalWindows() const { return m_externalWindows; }
    bool coreOnline() const { return m_coreOnline; }
    QString coreStatus() const { return m_coreStatus; }
    bool wifiAvailable() const { return m_wifiAvailable; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    bool brightnessAvailable() const { return m_brightnessAvailable; }
    int brightnessLevel() const { return m_brightnessLevel; }

    bool voiceOnline() const { return m_voiceOnline; }
    bool voiceListening() const { return m_voiceListening; }
    bool voiceTranscribing() const { return m_voiceTranscribing; }
    bool voiceSpeaking() const { return m_voiceSpeaking; }
    bool voiceSttReady() const { return m_voiceSttReady; }
    QString voiceStatus() const { return m_voiceStatus; }
    QString voiceTranscript() const { return m_voiceTranscript; }
    QString voiceTtsBackend() const { return m_voiceTtsBackend; }
    bool voiceSpeakReplies() const { return m_voiceSpeakReplies; }
    bool voiceRequestBusy() const { return m_voiceRequestBusy; }
    bool terminalSessionReady() const { return m_terminalSessionReady; }

    bool tonyOnline() const { return m_tonyOnline; }
    bool tonyModelOnline() const { return m_tonyModelOnline; }
    bool tonyBusy() const { return m_tonyBusy; }
    QString tonyStatus() const { return m_tonyStatus; }
    QString tonyReply() const { return m_tonyReply; }
    bool tonyApprovalPending() const { return !m_tonyApprovalId.isEmpty(); }
    QString tonyApprovalText() const { return m_tonyApprovalText; }
    QString tonyModelPolicy() const { return m_tonyModelPolicy; }
    QString quickNote() const { return m_quickNote; }

    Q_INVOKABLE QString executeIntent(const QString &text);
    Q_INVOKABLE void launchApp(const QString &app);
    Q_INVOKABLE QStringList listProjects() const;
    Q_INVOKABLE void setPrivateMode(bool enabled);
    Q_INVOKABLE void refreshNow();

    // Nexora OS-native core app APIs.
    Q_INVOKABLE QVariantList listDirectory(const QString &path) const;
    Q_INVOKABLE QString parentDirectory(const QString &path) const;
    Q_INVOKABLE QString normalizePath(const QString &path) const;
    Q_INVOKABLE bool createFolder(const QString &parent, const QString &name);
    Q_INVOKABLE bool openFile(const QString &path);
    Q_INVOKABLE void runTerminalCommand(const QString &command);
    Q_INVOKABLE void terminalInterrupt();
    Q_INVOKABLE void terminalRestart();
    Q_INVOKABLE void terminalResize(int columns, int rows);
    Q_INVOKABLE QVariantList topProcesses() const;
    Q_INVOKABLE void saveQuickNote(const QString &text);

    // Control Center.
    Q_INVOKABLE void setVolume(int percent);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void powerAction(const QString &action);
    Q_INVOKABLE void setBrightness(int percent);
    Q_INVOKABLE void setWifiEnabled(bool enabled);

    // App Center.
    Q_INVOKABLE QVariantList appCatalog() const;
    Q_INVOKABLE void searchDebianPackagesAsync(const QString &query);
    Q_INVOKABLE void installCatalogApp(const QString &source, const QString &id);
    Q_INVOKABLE void removeCatalogApp(const QString &source, const QString &id);
    Q_INVOKABLE void launchCatalogApp(const QString &source, const QString &id, const QString &launch);
    Q_INVOKABLE void installLocalPackage(const QString &urlOrPath);
    Q_INVOKABLE void refreshAppSources();

    // Tony — asynchronous local AI. The shell remains responsive while the
    // language model plans. Sensitive actions are surfaced for explicit approval.
    Q_INVOKABLE void askTony(const QString &text);
    Q_INVOKABLE void approveTonyAction();
    Q_INVOKABLE void denyTonyAction();
    Q_INVOKABLE void refreshTonyStatus();
    Q_INVOKABLE void setTonyModelPolicy(const QString &policy);
    Q_INVOKABLE void loadTonyModel();
    Q_INVOKABLE void unloadTonyModel();

    // Tony Voice — push-to-talk, local STT, local speech.
    Q_INVOKABLE void toggleVoiceListening();
    Q_INVOKABLE void refreshVoiceStatus();
    Q_INVOKABLE void speakText(const QString &text);
    Q_INVOKABLE void stopSpeaking();
    Q_INVOKABLE void setVoiceSpeakReplies(bool enabled);
    Q_INVOKABLE void setVoiceTtsBackend(const QString &backend);

    // Window/taskbar bridge. Native Nexora OS windows are managed directly
    // in QML; third-party Wayland/XWayland windows are reported by a tiny KWin
    // script so the taskbar can minimize/restore/activate them too.
    Q_INVOKABLE void windowAction(const QString &id, const QString &action);
    Q_INVOKABLE void showDesktop();
    Q_INVOKABLE void restoreDesktop();

public slots:
    Q_SCRIPTABLE void reportWindow(const QString &id, const QString &caption, const QString &desktopFile,
                                   qlonglong pid, bool minimized, bool active, bool demandsAttention);
    Q_SCRIPTABLE void removeWindow(const QString &id);

signals:
    void statsChanged();
    void timeChanged();
    void contextChanged();
    void privateModeChanged();
    void connectivityChanged();
    void audioChanged();
    void batteryChanged();
    void appJobChanged();
    void appSearchChanged();
    void externalWindowsChanged();
    void coreChanged();
    void deviceControlChanged();
    void voiceChanged();
    void tonyChanged();
    void noteChanged();
    void assistantMessage(const QString &message);
    void sessionExitRequested();
    void appRequested(const QString &app);
    void terminalOutput(const QString &text);
    void terminalWorkingDirectoryChanged();
    void terminalSessionChanged();

private slots:
    void updateStats();
    void updateClock();
    void updateContext();
    void refreshCoreStatus();
    void onCoreStatusChanged(const QVariantMap &status);
    void onCoreAudioChanged(int volume, bool muted, bool available);

private:
    void readMemory();
    void readCpu();
    void readUptime();
    void readNetwork();
    void readBattery();
    void refreshAudioAsync();
    void startAudioProbe(const QString &program, const QStringList &args, bool pactlMode = false);
    bool isDebInstalled(const QString &package) const;
    bool isFlatpakInstalled(const QString &appId) const;
    void runPackageJob(const QString &program, const QStringList &args, const QString &startMessage, const QString &successMessage);
    QString createProject(const QString &name);
    bool startDetached(const QString &program, const QStringList &args = {});
    QString stateDir() const;
    QString projectsDir() const;
    QString notesDir() const;
    void postTony(const QString &path, const QByteArray &body);
    void handleTonyReply(QNetworkReply *reply);
    void runTonyClientAction(const QString &tool, const QVariantMap &args);
    void postVoice(const QString &path, const QByteArray &body);
    void applyVoiceStatus(const QJsonObject &o);
    void runKWinActionScript(const QString &javascript);
    void rebuildExternalWindows();
    bool startTerminalSession();
    void stopTerminalSession();
    QString sanitizeTerminalOutput(const QByteArray &data);

    QTimer m_statsTimer;
    QTimer m_clockTimer;
    QTimer m_audioTimer;
    QTimer m_tonyFallbackTimer;
    QTimer m_voiceTimer;
    QFileSystemWatcher *m_stateWatcher = nullptr;
    QNetworkAccessManager *m_network = nullptr;
    QProcess *m_appSearchProcess = nullptr;
    QDBusInterface *m_core = nullptr;
    bool m_coreQueryBusy = false;
    int m_coreHealthTick = 0;

    double m_cpuUsage = 0.0;
    double m_memoryUsage = 0.0;
    double m_memoryUsedGiB = 0.0;
    double m_memoryTotalGiB = 0.0;
    qulonglong m_prevIdle = 0;
    qulonglong m_prevTotal = 0;
    int m_slowStatsTick = 0;

    QString m_currentTime;
    QString m_currentDate;
    QString m_hostname;
    QString m_kernelVersion;
    QString m_uptimeText;
    QString m_contextSummary = "Context service starting…";
    QStringList m_recentEvents;
    QStringList m_engineeringApps;
    bool m_privateMode = false;
    QString m_aiStatus = "Tony starting";
    QString m_terminalWorkingDirectory;

    bool m_networkConnected = false;
    int m_volumeLevel = 50;
    bool m_muted = false;
    bool m_batteryPresent = false;
    int m_batteryPercent = -1;
    bool m_batteryCharging = false;
    bool m_audioAvailable = false;
    bool m_audioProbeBusy = false;
    QString m_appJobStatus = "Ready";
    bool m_appJobBusy = false;
    QVariantList m_appSearchResults;
    bool m_appSearchBusy = false;
    QVariantList m_externalWindows;
    QHash<QString, QVariantMap> m_externalWindowMap;
    QStringList m_externalWindowOrder;
    QStringList m_desktopRestoreWindowIds;
    bool m_coreOnline = false;
    QString m_coreStatus = "Nexora Core starting…";
    bool m_wifiAvailable = false;
    bool m_wifiEnabled = false;
    bool m_brightnessAvailable = false;
    int m_brightnessLevel = 50;

    bool m_voiceOnline = false;
    bool m_voiceListening = false;
    bool m_voiceTranscribing = false;
    bool m_voiceSpeaking = false;
    bool m_voiceSttReady = false;
    QString m_voiceStatus = "Voice service starting…";
    QString m_voiceTranscript;
    QString m_voiceTtsBackend = "Unavailable";
    bool m_voiceSpeakReplies = true;
    bool m_voiceAutoSpeakNext = false;
    bool m_voiceRequestBusy = false;

    int m_ptyFd = -1;
    qint64 m_ptyPid = -1;
    QSocketNotifier *m_ptyNotifier = nullptr;
    bool m_terminalSessionReady = false;
    QByteArray m_terminalEscapeBuffer;

    bool m_tonyOnline = false;
    bool m_tonyModelOnline = false;
    bool m_tonyBusy = false;
    QString m_tonyStatus = "Starting local intelligence…";
    QString m_tonyReply = "Tony is getting ready.";
    QString m_tonyApprovalId;
    QString m_tonyApprovalText;
    QString m_tonyModelPolicy = "balanced";
    QString m_quickNote;
};
