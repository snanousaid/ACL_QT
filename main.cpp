#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include "mjpegitem.h"
#include "appcontroller.h"
#include "cameraimgprovider.h"
#include "opencvtest.h"

int main(int argc, char *argv[])
{
#if QT_VERSION >= QT_VERSION_CHECK(5, 6, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents, true);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents, false);
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));

    QGuiApplication app(argc, argv);

    // ── Test OpenCV (retirer après validation) ────────────────────────────────
    QString cvResult = runOpenCvTest(QStringLiteral("/opt/ACL_qt/models"));
    qDebug() << "[OpenCV TEST]" << cvResult;
    // ─────────────────────────────────────────────────────────────────────────

    // ── Backend ───────────────────────────────────────────────────────────────
    AppController *ctrl = new AppController(&app);

    // ── Image provider caméra C++ ─────────────────────────────────────────────
    CameraImgProvider *imgProvider = new CameraImgProvider();
    QObject::connect(ctrl, &AppController::frameReady,
                     imgProvider, &CameraImgProvider::updateFrame,
                     Qt::QueuedConnection);

    qmlRegisterType<MjpegItem>("ACL", 1, 0, "MjpegItem");

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("camera"), imgProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("controller"), ctrl);
    engine.load(QUrl(QStringLiteral("qrc:/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
