#include "cameraimgprovider.h"
#include <QMutexLocker>

CameraImgProvider::CameraImgProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{}

QImage CameraImgProvider::requestImage(const QString &, QSize *size,
                                        const QSize &requestedSize)
{
    QMutexLocker lock(&m_mutex);
    QImage frame = m_frame.isNull()
        ? QImage(640, 480, QImage::Format_RGB888)
        : m_frame;

    if (!requestedSize.isEmpty())
        frame = frame.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    if (size) *size = frame.size();
    return frame;
}

void CameraImgProvider::updateFrame(const QImage &img)
{
    QMutexLocker lock(&m_mutex);
    m_frame = img;
}
