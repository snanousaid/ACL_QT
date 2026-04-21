#pragma once
#include <QQuickPaintedItem>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QByteArray>

class MjpegItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)

public:
    explicit MjpegItem(QQuickItem *parent = nullptr);
    ~MjpegItem() override;

    void paint(QPainter *painter) override;

    QString source() const { return m_source; }
    void setSource(const QString &url);

    bool active() const { return m_active; }
    void setActive(bool a);

signals:
    void sourceChanged();
    void activeChanged();

private slots:
    void onReadyRead();
    void onError();
    void startStream();

private:
    void stopStream();
    void parseBuffer();

    QString                m_source;
    bool                   m_active = true;
    QNetworkAccessManager *m_nam;
    QNetworkReply         *m_reply = nullptr;
    QByteArray             m_buf;
    QImage                 m_frame;
};
