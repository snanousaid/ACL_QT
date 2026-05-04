#pragma once
#ifdef ACL_OPENCV_ENABLED

#include <QMutex>
#include <QWaitCondition>
#include <opencv2/core.hpp>

// ─────────────────────────────────────────────────────────────────────────────
// FrameQueue — Queue thread-safe de capacité 1 ("latest wins").
// Producer (CameraWorker) push une frame BGR ; si une ancienne est encore là,
// elle est remplacée. Consumer (FaceWorker) attend la frame suivante, jamais
// de backlog.
// ─────────────────────────────────────────────────────────────────────────────
class FrameQueue
{
public:
    FrameQueue() = default;

    // Remplace la frame courante (ou en pose une si la queue est vide).
    void push(const cv::Mat &frame);

    // Bloque jusqu'à `timeoutMs` ms en attente d'une frame.
    // Retourne true si une frame est disponible, false sinon (timeout / stop).
    bool pop(cv::Mat &frame, int timeoutMs = 200);

    // Réveille tous les consumers en attente, force pop() à retourner false.
    void stop();

private:
    QMutex          m_mutex;
    QWaitCondition  m_cond;
    cv::Mat         m_frame;
    bool            m_hasFrame = false;
    bool            m_stopped  = false;
};

#endif // ACL_OPENCV_ENABLED
