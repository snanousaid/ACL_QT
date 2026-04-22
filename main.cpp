#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "mjpegitem.h"
#include "appcontroller.h"

int main(int argc, char *argv[])
{
    // Force rotation before display init — env var in shell profile not always picked up
    qputenv("QT_QPA_EGLFS_ROTATION", "90");

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
