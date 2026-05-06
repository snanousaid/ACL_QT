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

    // Pause UI : skip emit + push, capture continue à 5 FPS keepalive.
    void setPaused(bool paused);
    // Idle stream : 15 FPS au lieu de 30 quand aucun visage depuis longtemps.
    void setIdleStream(bool idle);

signals:
    void frameReady(const QImage &image);

protected:
    void run() override;

private:
    static const int CAM_W       = 640;
    static const int CAM_H       = 480;
    static const int CAM_FPS     = 30;
    static const int SLEEP_ACTIVE = 33;   // ~30 FPS
    static const int SLEEP_IDLE   = 66;   // ~15 FPS
    static const int SLEEP_PAUSED = 200;  // ~5 FPS keepalive (drain V4L2)

    QAtomicInt   m_running{0};
    QAtomicInt   m_paused{0};
    QAtomicInt   m_idleStream{0};
    FrameQueue  *m_queue;     // partagée avec FaceWorker (non-owned)
};
