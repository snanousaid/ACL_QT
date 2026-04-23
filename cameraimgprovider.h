#pragma once
#include <QQuickImageProvider>
#include <QImage>
#include <QMutex>

class CameraImgProvider : public QQuickImageProvider
{
public:
    CameraImgProvider();
    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override;
    void updateFrame(const QImage &img);

private:
    QImage m_frame;
    QMutex m_mutex;
};
