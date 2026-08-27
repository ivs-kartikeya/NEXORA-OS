#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include "systembackend.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Nexora OS"));
    app.setOrganizationName(QStringLiteral("Nexora"));
    app.setDesktopFileName(QStringLiteral("nexora-shell"));

    SystemBackend backend;
    QObject::connect(&backend, &SystemBackend::sessionExitRequested,
                     &app, &QCoreApplication::quit);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("systemBackend"), &backend);

    const QUrl mainUrl(QStringLiteral("qrc:/Nexora/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app,
                     [mainUrl](QObject *obj, const QUrl &objUrl) {
                         if (!obj && objUrl == mainUrl) QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);
    engine.load(mainUrl);
    if (engine.rootObjects().isEmpty()) return -1;
    return app.exec();
}
