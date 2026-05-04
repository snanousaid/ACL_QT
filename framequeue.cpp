#include "framequeue.h"
#ifdef ACL_OPENCV_ENABLED

#include <QMutexLocker>

void FrameQueue::push(const cv::Mat &frame)
{
    QMutexLocker l(&m_mutex);
    m_frame    = frame.clone(); // copie pour rester thread-safe
    m_hasFrame = true;
    m_cond.wakeOne();
}

bool FrameQueue::pop(cv::Mat &frame, int timeoutMs)
{
    QMutexLocker l(&m_mutex);
    if (!m_hasFrame && !m_stopped) {
        m_cond.wait(&m_mutex, static_cast<unsigned long>(timeoutMs));
    }
    if (m_stopped || !m_hasFrame) return false;
    frame = m_frame;
    m_hasFrame = false;
    return true;
}

void FrameQueue::stop()
{
    QMutexLocker l(&m_mutex);
    m_stopped = true;
    m_cond.wakeAll();
}

#endif // ACL_OPENCV_ENABLED
