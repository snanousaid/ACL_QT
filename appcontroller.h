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

    // ── Face users management (REST → m_faceApiUrl) ─────────────────────────
    Q_INVOKABLE void listFaceUsers();
    Q_INVOKABLE void toggleFaceUser(const QString &name);
    Q_INVOKABLE void deleteFaceUser(const QString &name);

    // ── Enrôlement live ─────────────────────────────────────────────────────
    Q_INVOKABLE void startEnroll(const QString &name, const QString &role,
                                 int samplesPerPose);
    Q_INVOKABLE void finalizeEnroll();
    Q_INVOKABLE void cancelEnroll();
    Q_INVOKABLE void pollEnrollStatus();

signals:
    void badgeConnectedChanged();
    void faceConnectedChanged();
    void accessEvent(bool granted, const QString &name, const QString &source,
                     double score, const QString &door, const QString &time);
    // Liste reçue : QVariantList de {name, role, created_at, active, dim}
    void faceUsersLoaded(const QVariantList &users);
    // Erreur (réseau ou HTTP non-2xx). msg = description courte.
    void faceApiError(const QString &op, const QString &msg);
    // Mutation réussie (toggle/delete) → la modal recharge la liste.
    void faceUserMutated(const QString &op, const QString &name);
    // Statut de l'enrôlement (poll), payload = QVariantMap aplati de status.json.
    void enrollStatus(const QVariantMap &status);
    // Réponse start/finalize/cancel : ok + msg backend.
    void enrollResult(const QString &op, bool ok, const QString &msg);

private slots:
    void onBadgeEvent(const QString &evName, const QJsonObject &data);
    void onFaceEvent (const QString &evName, const QJsonObject &data);

private:
    void handleEvent(const QJsonObject &data, const QString &source);

    // ── URLs — modifier ici pour changer la config ──────────────────────────
    const QString m_badgeSocketUrl = QStringLiteral("http://192.168.10.132:5000");
    const QString m_faceSocketUrl  = QStringLiteral("http://192.168.10.132:5001");
    const QString m_faceApiUrl     = QStringLiteral("http://192.168.10.132:5050");
    const QString m_mjpegUrl       = QStringLiteral("http://192.168.10.132:5050/video_feed");
    // ────────────────────────────────────────────────────────────────────────

    bool m_badgeConnected = false;
    bool m_faceConnected  = false;

    SocketIoClient        *m_badgeSocket;
    SocketIoClient        *m_faceSocket;
    QNetworkAccessManager *m_nam;
};
