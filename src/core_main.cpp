#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include "coredaemon.h"

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Nexora Core"));
    app.setOrganizationName(QStringLiteral("Nexora"));

    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QStringLiteral("org.nexora.Core"))) {
        qCritical() << "Could not register org.nexora.Core:" << bus.lastError().message();
        return 2;
    }

    CoreDaemon core;
    if (!bus.registerObject(QStringLiteral("/Core"), &core,
                            QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportAllSignals)) {
        qCritical() << "Could not register /Core:" << bus.lastError().message();
        return 3;
    }
    return app.exec();
}
