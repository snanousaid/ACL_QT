#include "mjpegitem.h"
#include <QPainter>
#include <QNetworkRequest>
#include <QTimer>

MjpegItem::MjpegItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    m_nam = new QNetworkAccessManager(this);
}

MjpegItem::~MjpegItem()
{
    stopStream();
}

void MjpegItem::setSource(const QString &url)
{
    if (m_source == url) return;
    m_source = url;
    emit sourceChanged();
    if (m_active && !m_source.isEmpty())
        startStream();
}

void MjpegItem::setActive(bool a)
{
    if (m_active == a) return;
    m_active = a;
    emit activeChanged();
    if (m_active && !m_source.isEmpty())
        startStream();
    else
        stopStream();
}

void MjpegItem::startStream()
{
    stopStream();
    if (m_source.isEmpty()) return;

    QNetworkRequest req(QUrl(m_source));
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    m_buf.clear();
    m_reply = m_nam->get(req);
    connect(m_reply, &QNetworkReply::readyRead, this, &MjpegItem::onReadyRead);
    connect(m_reply,
            QOverload<QNetworkReply::NetworkError>::of(&QNetworkReply::error),
            this, &MjpegItem::onError);
}

void MjpegItem::stopStream()
{
    if (!m_reply) return;
    m_reply->abort();
    m_reply->deleteLater();
    m_reply = nullptr;
    m_buf.clear();
}

void MjpegItem::onReadyRead()
{
    m_buf.append(m_reply->readAll());
    parseBuffer();
}

void MjpegItem::parseBuffer()
{
    // Locate JPEG frames by SOI (ff d8) / EOI (ff d9) markers — no header parsing needed.
    while (true) {
        int soi = m_buf.indexOf("\xff\xd8");
        if (soi < 0) {
            if (m_buf.size() > 512)
                m_buf = m_buf.right(512);
            return;
        }
        int eoi = m_buf.indexOf("\xff\xd9", soi + 2);
        if (eoi < 0) return;

        QImage img;
        if (img.loadFromData(
                reinterpret_cast<const uchar *>(m_buf.constData()) + soi,
                eoi - soi + 2, "JPEG")) {
            m_frame = img;
            update();
        }
        m_buf = m_buf.mid(eoi + 2);
    }
}

void MjpegItem::onError()
{
    stopStream();
    QTimer::singleShot(2000, this, &MjpegItem::startStream);
}

void MjpegItem::paint(QPainter *painter)
{
    if (m_frame.isNull()) {
        painter->fillRect(boundingRect(), Qt::black);
        return;
    }
    painter->drawImage(boundingRect(), m_frame);
}
