#pragma once
#include <QThread>
#include <QImage>
#include <QAtomicInt>

class FrameQueue;

// ─────────────────────────────────────────────────────────────────────────────
// CameraWorker — Capture pure (V4L2 → QImage @ 30 fps).
//   • emit frameReady(QImage)            → flux UI (CameraImgProvider)
//   • push BGR cv::Mat dans FrameQueue   → consommé par FaceWorker
// ─────────────────────────────────────────────────────────────────────────────
class CameraWorker : public QThread
{
    Q_OBJECT
public:
    // queue peut être nullptr si on ne veut pas alimenter FaceWorker.
    explicit CameraWorker(FrameQueue *queue = nullptr, QObject *parent = nullptr);
    ~CameraWorker() override;

    void stop();

signals:
    void frameReady(const QImage &image);

protected:
    void run() override;

private:
    static const int CAM_W   = 640;
    static const int CAM_H   = 480;
    static const int CAM_FPS = 30;

    QAtomicInt   m_running{0};
    FrameQueue  *m_queue;     // partagée avec FaceWorker (non-owned)
};
