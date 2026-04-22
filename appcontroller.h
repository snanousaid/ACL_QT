#pragma once
#include <QObject>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include "socketioclient.h"

class AppController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool badgeConnected READ badgeConnected NOTIFY badgeConnectedChanged)
    Q_PROPERTY(bool faceConnected  READ faceConnected  NOTIFY faceConnectedChanged)
    Q_PROPERTY(QString mjpegUrl    READ mjpegUrl       CONSTANT)

public:
    explicit AppController(QObject *parent = nullptr);

    bool    badgeConnected() const { return m_badgeConnected; }
    bool    faceConnected()  const { return m_faceConnected;  }
    QString mjpegUrl()       const { return m_mjpegUrl;       }

    Q_INVOKABLE void pauseRecognition();
    Q_INVOKABLE void resumeRecognition();

signals:
    void badgeConnectedChanged();
    void faceConnectedChanged();
    void accessEvent(bool granted, const QString &name, const QString &source,
                     double score, const QString &door, const QString &time);

private slots:
    void onBadgeEvent(const QString &evName, const QJsonObject &data);
    void onFaceEvent (const QString &evName, const QJsonObject &data);

private:
    void handleEvent(const QJsonObject &data, const QString &source);

    // ── URLs — modifier ici pour changer la config ──────────────────────────
    const QString m_badgeSocketUrl = QStringLiteral("http://localhost:5000");
    const QString m_faceSocketUrl  = QStringLiteral("http://localhost:5001");
    const QString m_faceApiUrl     = QStringLiteral("http://localhost:5050");
    const QString m_mjpegUrl       = QStringLiteral("http://localhost:5050/video_feed");
    // ────────────────────────────────────────────────────────────────────────

    bool m_badgeConnected = false;
    bool m_faceConnected  = false;

    SocketIoClient        *m_badgeSocket;
    SocketIoClient        *m_faceSocket;
    QNetworkAccessManager *m_nam;
};
