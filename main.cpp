#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "shmreader.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QGuiApplication app(argc, argv);

    // Enregistre VideoItem comme type QML utilisable dans les fichiers .qml
    qmlRegisterType<VideoItem>("ACL", 1, 0, "VideoItem");

    QQmlApplicationEngine engine;
    engine.load(QUrl(QStringLiteral("qrc:/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
