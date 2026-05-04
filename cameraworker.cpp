#include "cameraworker.h"
#include <QDebug>
#include <QMutexLocker>
#include <QThread>

// ─────────────────────────────────────────────────────────────────────────────
// CameraWorker — Étape 1 : CAPTURE PURE (pas de détection / reconnaissance).
// La détection + reconnaissance sera ajoutée dans FaceWorker à l'étape 2.
// ─────────────────────────────────────────────────────────────────────────────

#ifndef ACL_OPENCV_ENABLED
// ── Stub Windows / sans OpenCV ────────────────────────────────────────────────

CameraWorker::CameraWorker(QObject *parent) : QThread(parent) {}
CameraWorker::~CameraWorker() { stop(); wait(); }
void CameraWorker::stop()    { m_running.store(0); }
void CameraWorker::pause()   { QMutexLocker l(&m_mutex); m_mode = Paused; }
void CameraWorker::resume()  { QMutexLocker l(&m_mutex); m_mode = Detecting; }

void CameraWorker::startEnroll(const QString &, const QString &, int) {}
void CameraWorker::finalizeEnroll() {}
void CameraWorker::cancelEnroll()   {}
void CameraWorker::reloadDb()       {}
QVariantList CameraWorker::listUsers() const { return {}; }
void CameraWorker::toggleUser(const QString &) {}
void CameraWorker::deleteUser(const QString &) {}

void CameraWorker::run()
{
    qDebug() << "[CameraWorker] OpenCV désactivé (build non-Linux)";
}

#else
// ── Implémentation Linux + OpenCV ─────────────────────────────────────────────
#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/imgproc.hpp>

CameraWorker::CameraWorker(QObject *parent) : QThread(parent) {}
CameraWorker::~CameraWorker() { stop(); wait(); }

void CameraWorker::stop()   { m_running.store(0); }
void CameraWorker::pause()  { QMutexLocker l(&m_mutex); m_mode = Paused; }
void CameraWorker::resume() { QMutexLocker l(&m_mutex); m_mode = Detecting; }

// ── Stubs étape 1 — déplacés vers FaceWorker à l'étape 2 ─────────────────────
void CameraWorker::startEnroll(const QString &, const QString &, int) {}
void CameraWorker::finalizeEnroll() {}
void CameraWorker::cancelEnroll()   {}
void CameraWorker::reloadDb()       {}
QVariantList CameraWorker::listUsers() const { return {}; }
void CameraWorker::toggleUser(const QString &) {}
void CameraWorker::deleteUser(const QString &) {}

// ── Boucle de capture pure ────────────────────────────────────────────────────
void CameraWorker::run()
{
    qDebug() << "[CameraWorker] démarrage — capture pure (étape 1)";

    cv::VideoCapture cap(0, cv::CAP_V4L2);
    if (!cap.isOpened()) cap.open(0, cv::CAP_ANY);
    if (!cap.isOpened()) {
        qDebug() << "[CameraWorker] ERREUR : impossible d'ouvrir la caméra";
        return;
    }
    cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M','J','P','G'));
    cap.set(cv::CAP_PROP_FRAME_WIDTH,  CAM_W);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, CAM_H);
    cap.set(cv::CAP_PROP_FPS,          CAM_FPS);
    cap.set(cv::CAP_PROP_BUFFERSIZE,   1);
    qDebug() << "[CameraWorker] caméra ouverte —"
             << CAM_W << "x" << CAM_H << "@" << CAM_FPS << "fps";

    m_running.store(1);

    cv::Mat frame, rgb;

    while (m_running.load()) {
        Mode currentMode;
        { QMutexLocker l(&m_mutex); currentMode = m_mode; }

        cap >> frame;
        if (frame.empty()) { QThread::msleep(10); continue; }

        cv::cvtColor(frame, rgb, cv::COLOR_BGR2RGB);
        emit frameReady(QImage(rgb.data, rgb.cols, rgb.rows,
                               static_cast<int>(rgb.step),
                               QImage::Format_RGB888).copy());

        // 33 ms = ~30 fps en mode normal, 66 ms = ~15 fps en pause
        QThread::msleep(currentMode == Paused ? 66 : 33);
    }

    cap.release();
    qDebug() << "[CameraWorker] arrêté";
}

#endif // ACL_OPENCV_ENABLED
