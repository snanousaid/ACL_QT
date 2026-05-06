#pragma once
#include <QObject>
#include <QJsonObject>
#include <QImage>
#include <QNetworkAccessManager>
#include "socketioclient.h"
#include "cameraworker.h"
#include "faceworker.h"

class FrameQueue;

class AppController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool    badgeConnected READ badgeConnected  NOTIFY badgeConnectedChanged)
    Q_PROPERTY(bool    faceConnected  READ faceConnected   NOTIFY faceConnectedChanged)
    Q_PROPERTY(QString mjpegUrl       READ mjpegUrl        CONSTANT)
    Q_PROPERTY(QString controllerUrl  READ controllerUrl   CONSTANT)
    // ── État visage (remplace le polling /status.json) ──────────────────────
    Q_PROPERTY(bool    faceInFrame  READ faceInFrame  NOTIFY faceStatusChanged)
    Q_PROPERTY(bool    faceInRoi    READ faceInRoi    NOTIFY faceStatusChanged)
    Q_PROPERTY(QString faceAccess   READ faceAccess   NOTIFY faceStatusChanged)

public:
    explicit AppController(QObject *parent = nullptr);

    bool    badgeConnected() const { return m_badgeConnected; }
    bool    faceConnected()  const { return m_faceConnected;  }
    QString mjpegUrl()       const { return m_mjpegUrl;       }
    QString controllerUrl()  const { return m_controllerUrl;  }
    bool    faceInFrame()    const { return m_faceInFrame;    }
    bool    faceInRoi()      const { return m_faceInRoi;      }
    QString faceAccess()     const { return m_faceAccess;     }

    Q_INVOKABLE void pauseRecognition();
    Q_INVOKABLE void resumeRecognition();
    // Pause/resume du flux vidéo UI seul (CameraWorker).
    // Permet de couper le flux quand l'admin est ouvert SANS impacter
    // l'enrôlement qui doit garder la caméra active.
    Q_INVOKABLE void setStreamPaused(bool paused);

    // ── Face users (C++ — FaceDb via CameraWorker) ──────────────────────────
    Q_INVOKABLE void listFaceUsers();
    Q_INVOKABLE void toggleFaceUser(const QString &name);
    Q_INVOKABLE void deleteFaceUser(const QString &name);

    // ── Enrôlement live (C++) ───────────────────────────────────────────────
    Q_INVOKABLE void startEnroll(const QString &name, const QString &role,
                                 int samplesPerPose);
    Q_INVOKABLE void finalizeEnroll();
    Q_INVOKABLE void cancelEnroll();
    Q_INVOKABLE void pollEnrollStatus();

    // ── Config réseau (REST → m_controllerUrl) ──────────────────────────────
    Q_INVOKABLE void getNetworkInfo();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password,
                                 const QString &mode,
                                 const QString &ip, const QString &prefix,
                                 const QString &gateway, const QString &dns);
    Q_INVOKABLE void setEthernet(const QString &mode,
                                 const QString &ip, const QString &prefix,
                                 const QString &gateway, const QString &dns);

signals:
    void badgeConnectedChanged();
    void faceConnectedChanged();
    void faceStatusChanged();
    void frameReady(const QImage &img);
    void accessEvent(bool granted, const QString &name, const QString &source,
                     double score, const QString &door, const QString &time,
                     const QString &userId);
    void faceUsersLoaded(const QVariantList &users);
    void faceApiError(const QString &op, const QString &msg);
    void faceUserMutated(const QString &op, const QString &name);
    void enrollStatus(const QVariantMap &status);
    void enrollResult(const QString &op, bool ok, const QString &msg);
    void networkInfoLoaded(const QVariantMap &info);
    void wifiNetworksLoaded(const QVariantList &networks);
    void wifiConnectResult(bool ok, const QString &msg);
    void ethernetResult(bool ok, const QString &msg);
    void networkApiError(const QString &op, const QString &msg);

private slots:
    void onBadgeEvent(const QString &evName, const QJsonObject &data);
    void onFaceEvent (const QString &evName, const QJsonObject &data);
    void onCamFaceStatus(bool face, bool inRoi, bool recognized);
    void onCamAccessGranted(const QString &name, float score);
    void onCamAccessDenied(const QString &reason, float score);
    void onCamEnrollProgress(const QVariantMap &status);
    void onCamEnrollFinished(bool ok, const QString &msg);
    void resetFaceAccess();

private:
    void handleEvent(const QJsonObject &data, const QString &source);

    // ── URLs ────────────────────────────────────────────────────────────────
    const QString m_badgeSocketUrl = QStringLiteral("http://192.168.10.132:5000");
    const QString m_controllerUrl  = QStringLiteral("http://192.168.10.132:80/api/v2");
    // mjpegUrl vide = mode C++ (CameraWorker fournit les frames)
    const QString m_mjpegUrl       = QStringLiteral("");
    // ────────────────────────────────────────────────────────────────────────

    bool    m_badgeConnected = false;
    bool    m_faceConnected  = true;   // CameraWorker = toujours connecté
    bool    m_faceInFrame    = false;
    bool    m_faceInRoi      = false;
    QString m_faceAccess;              // "" | "granted" | "denied"

    SocketIoClient        *m_badgeSocket;
    QNetworkAccessManager *m_nam;
    FrameQueue            *m_frameQueue;   // partagé Camera ↔ Face
    CameraWorker          *m_camera;
    FaceWorker            *m_face;
    QTimer                *m_accessResetTimer;
    QTimer                *m_idleStreamTimer;   // bascule 30→15 FPS après 5s sans visage

    // Dernier statut enrollment pour pollEnrollStatus()
    QVariantMap m_lastEnrollStatus;
};
