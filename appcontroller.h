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

    // ── Face profiles (REST → backend acl_controller) ──────────────────────
    Q_INVOKABLE void lookupUserByCin(const QString &cin);
    Q_INVOKABLE void listFaceProfiles();
    Q_INVOKABLE void deleteFaceProfile(const QString &userId);

    // ── Enrôlement live (capture cote Qt, save cote backend) ────────────────
    Q_INVOKABLE void startEnroll(const QString &userId, int samplesPerPose);
    Q_INVOKABLE void finalizeEnroll();
    Q_INVOKABLE void cancelEnroll();
    Q_INVOKABLE void pollEnrollStatus();

    // Accesseurs utilisés par HttpServer (polling enrollment depuis web).
    // Renvoient une copie snapshot — appelables depuis le main thread.
    QVariantMap lastEnrollStatus() const { return m_lastEnrollStatus; }
    QVariantMap lastEnrollResult() const { return m_lastEnrollResult; }

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
    // Émis quand l'event filter (TapDetector) capture un tap au niveau app.
    // Permet à QML de détecter le double-tap sans utiliser MultiPointTouchArea
    // (qui bug sur le driver A133 evdev — releases manquants).
    void screenTapped();
    void frameReady(const QImage &img);
    void accessEvent(bool granted, const QString &name, const QString &source,
                     double score, const QString &door, const QString &time,
                     const QString &userId);
    // ── Face REST signals ────────────────────────────────────────────────
    void userLookupResult(bool found, const QVariantMap &user, const QString &errorMsg);
    void faceProfilesLoaded(const QVariantList &profiles);
    void faceProfileMutated(const QString &op, const QString &userId);
    void faceApiError(const QString &op, const QString &msg);
    void enrollStatus(const QVariantMap &status);
    void enrollResult(const QString &op, bool ok, const QString &msg);
    void networkInfoLoaded(const QVariantMap &info);
    void wifiNetworksLoaded(const QVariantList &networks);
    void wifiConnectResult(bool ok, const QString &msg);
    void ethernetResult(bool ok, const QString &msg);
    void networkApiError(const QString &op, const QString &msg);

    // Anti-spoofing (forward depuis FaceWorker).
    // QML peut afficher un overlay "Tournez la tete" sur livenessChallenge,
    // et le masquer sur livenessResult.
    void livenessChallenge();
    void livenessResult(bool ok);

private slots:
    void onBadgeEvent(const QString &evName, const QJsonObject &data);
    void onFaceEvent (const QString &evName, const QJsonObject &data);
    void onCamFaceStatus(bool face, bool inRoi, bool recognized);
    void onCamEnrollProgress(const QVariantMap &status);
    void onCamEnrollFinished(bool ok, const QString &msg);
    // FaceWorker -> REST bridge
    void onFaceMatchRequest(const QVector<float> &embedding);
    void onEnrollEmbeddingsReady(const QString &userId,
                                 const QVariantMap &embeddings);
    void resetFaceAccess();

private:
    void handleEvent(const QJsonObject &data, const QString &source);

    // ── URLs ────────────────────────────────────────────────────────────────
    const QString m_badgeSocketUrl = QStringLiteral("http://localhost:5000");
    const QString m_controllerUrl  = QStringLiteral("http://localhost:80/api/v2");
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
    // Dernier resultat de finalize/start/cancel pour polling HTTP cote web.
    // Cle 'op' = start|finalize|cancel ; 'ok' = bool ; 'msg' = str ; 'ts' = ms.
    QVariantMap m_lastEnrollResult;
};
