#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDebug>
#include <QVector>
#include <QMetaType>
#include "mjpegitem.h"
#include "appcontroller.h"
#include "cameraimgprovider.h"
#include "opencvtest.h"
#include "tapdetector.h"

int main(int argc, char *argv[])
{
#if QT_VERSION >= QT_VERSION_CHECK(5, 6, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
    QCoreApplication::setAttribute(Qt::AA_SynthesizeMouseForUnhandledTouchEvents, true);
    QCoreApplication::setAttribute(Qt::AA_SynthesizeTouchForUnhandledMouseEvents, false);
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));

    QGuiApplication app(argc, argv);

    // Enregistrement metatypes pour signaux cross-thread
    // (FaceWorker emit faceMatchRequest(QVector<float>) -> AppController main thread)
    qRegisterMetaType<QVector<float>>("QVector<float>");

    // ── Test OpenCV (retirer après validation) ────────────────────────────────
    QString cvResult = runOpenCvTest(QStringLiteral("/opt/ACL_qt/models"));
    qDebug() << "[OpenCV TEST]" << cvResult;
    // ─────────────────────────────────────────────────────────────────────────

    // ── Backend ───────────────────────────────────────────────────────────────
    AppController *ctrl = new AppController(&app);

    // ── Détecteur de tap global (event filter app-level) ─────────────────────
    // Contournement bug A133 evdev : MultiPointTouchArea capturait les touches
    // sans recevoir les releases. On observe ici les MouseButtonPress / TouchBegin
    // sans les consommer → propagation normale vers QML, mais on émet
    // controller.screenTapped() pour le détecteur de double-tap.
    TapDetector *tapDetector = new TapDetector(&app);
    app.installEventFilter(tapDetector);
    QObject::connect(tapDetector, &TapDetector::tapped,
                     ctrl,        &AppController::screenTapped);

    // ── Image provider caméra C++ ─────────────────────────────────────────────
    CameraImgProvider *imgProvider = new CameraImgProvider();
    // CameraImgProvider n'est pas un QObject — connexion via lambda (thread-safe via mutex interne)
    QObject::connect(ctrl, &AppController::frameReady, ctrl,
                     [imgProvider](const QImage &img) {
                         imgProvider->updateFrame(img);
                     },
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
