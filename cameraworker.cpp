#include "cameraworker.h"
#include "framequeue.h"
#include <QDebug>
#include <QThread>

#ifndef ACL_OPENCV_ENABLED
// ── Stub Windows / sans OpenCV ────────────────────────────────────────────────

CameraWorker::CameraWorker(FrameQueue *queue, QObject *parent)
    : QThread(parent), m_queue(queue) {}
CameraWorker::~CameraWorker() { stop(); wait(); }
void CameraWorker::stop() { m_running.store(0); }

void CameraWorker::run()
{
    qDebug() << "[CameraWorker] OpenCV désactivé (build non-Linux)";
}

#else
// ── Implémentation Linux + OpenCV ─────────────────────────────────────────────
#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/imgproc.hpp>

CameraWorker::CameraWorker(FrameQueue *queue, QObject *parent)
    : QThread(parent), m_queue(queue) {}
CameraWorker::~CameraWorker() { stop(); wait(); }

void CameraWorker::stop() { m_running.store(0); }

void CameraWorker::run()
{
    qDebug() << "[CameraWorker] démarrage — capture pure";

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
        cap >> frame;
        if (frame.empty()) { QThread::msleep(10); continue; }

        // ── Push BGR vers FaceWorker (latest wins, non-bloquant) ──────────────
        if (m_queue) m_queue->push(frame);

        // ── Conversion + emit pour le stream UI ────────────────────────────────
        cv::cvtColor(frame, rgb, cv::COLOR_BGR2RGB);
        emit frameReady(QImage(rgb.data, rgb.cols, rgb.rows,
                               static_cast<int>(rgb.step),
                               QImage::Format_RGB888).copy());

        QThread::msleep(33); // ~30 fps
    }

    cap.release();
    qDebug() << "[CameraWorker] arrêté";
}

#endif // ACL_OPENCV_ENABLED
