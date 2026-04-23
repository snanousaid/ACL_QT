#pragma once
#include <QObject>
#include <QQuickImageProvider>
#include <QImage>
#include <QMutex>

class CameraImgProvider : public QObject, public QQuickImageProvider
{
    Q_OBJECT
public:
    CameraImgProvider();
    QImage requestImage(const QString &id, QSize *size,
                        const QSize &requestedSize) override;

public slots:
    void updateFrame(const QImage &img);

private:
    QImage m_frame;
    QMutex m_mutex;
};
