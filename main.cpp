#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "mjpegitem.h"
#include "appcontroller.h"

int main(int argc, char *argv[])
{
#if QT_VERSION >= QT_VERSION_CHECK(5, 6, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif

    QGuiApplication app(argc, argv);

    qmlRegisterType<MjpegItem>     ("ACL", 1, 0, "MjpegItem");
    qmlRegisterType<AppController> ("ACL", 1, 0, "AppControllerType");

    QQmlApplicationEngine engine;
    engine.load(QUrl(QStringLiteral("qrc:/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
