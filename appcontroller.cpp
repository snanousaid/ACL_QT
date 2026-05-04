#include "appcontroller.h"
#include "framequeue.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QUrlQuery>
#include <QDateTime>
#include <QTime>
#include <QTimer>
#include <QUrl>

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_nam = new QNetworkAccessManager(this);

    // ── Badge socket ──────────────────────────────────────────────────────────
    m_badgeSocket = new SocketIoClient(m_badgeSocketUrl, this);
    connect(m_badgeSocket, &SocketIoClient::connected, this, [this] {
        m_badgeConnected = true;
        emit badgeConnectedChanged();
    });
    connect(m_badgeSocket, &SocketIoClient::disconnected, this, [this] {
        m_badgeConnected = false;
        emit badgeConnectedChanged();
    });
    connect(m_badgeSocket, &SocketIoClient::eventReceived,
            this, &AppController::onBadgeEvent);

    // ── Pipeline caméra : Camera (capture) → FrameQueue → Face (detect+recog) ─
#ifdef ACL_OPENCV_ENABLED
    m_frameQueue = new FrameQueue();
#else
    m_frameQueue = nullptr;
#endif

    m_camera = new CameraWorker(m_frameQueue, this);
    connect(m_camera, &CameraWorker::frameReady,
            this,     &AppController::frameReady);
    m_camera->start();

    m_face = new FaceWorker(m_frameQueue,
                            QStringLiteral("/opt/ACL_qt/embeddings/known_faces.json"),
                            QStringLiteral("/opt/ACL_qt/models"),
                            this);
    connect(m_face, &FaceWorker::faceStatusChanged,
            this,   &AppController::onCamFaceStatus);
    connect(m_face, &FaceWorker::accessGranted,
            this,   &AppController::onCamAccessGranted);
    connect(m_face, &FaceWorker::accessDenied,
            this,   &AppController::onCamAccessDenied);
    connect(m_face, &FaceWorker::enrollProgress,
            this,   &AppController::onCamEnrollProgress);
    connect(m_face, &FaceWorker::enrollFinished,
            this,   &AppController::onCamEnrollFinished);
    m_face->start();

    // ── Timer reset faceAccess (3 s après granted/denied) ────────────────────
    m_accessResetTimer = new QTimer(this);
    m_accessResetTimer->setSingleShot(true);
    m_accessResetTimer->setInterval(3000);
    connect(m_accessResetTimer, &QTimer::timeout,
            this, &AppController::resetFaceAccess);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

static QString isoToTime(const QString &iso)
{
    if (!iso.isEmpty()) {
        QDateTime dt = QDateTime::fromString(iso, Qt::ISODate);
        if (!dt.isValid())
            dt = QDateTime::fromString(iso, QStringLiteral("yyyy-MM-ddThh:mm:ss.zzzZ"));
        if (dt.isValid())
            return dt.time().toString(QStringLiteral("hh:mm:ss"));
    }
    return QTime::currentTime().toString(QStringLiteral("hh:mm:ss"));
}

// ── Badge events ──────────────────────────────────────────────────────────────

void AppController::handleEvent(const QJsonObject &data, const QString &source)
{
    bool granted = data.value(QStringLiteral("status")).toBool();
    if (!granted) {
        const QString evType  = data.value(QStringLiteral("eventType")).toString();
        const QString evType2 = data.value(QStringLiteral("event_type")).toString();
        const QString status  = data.value(QStringLiteral("status")).toString().toUpper();
        granted = evType  == QStringLiteral("ACCESS_GRANTED") ||
                  evType2 == QStringLiteral("ACCESS_GRANTED") ||
                  status  == QStringLiteral("ACCESS_GRANTED") ||
                  status  == QStringLiteral("GRANTED");
    }

    const QJsonObject user = data.value(QStringLiteral("user")).toObject();
    QString name;

    {
        QString fn = user.value(QStringLiteral("first_name")).toString().trimmed();
        QString ln = user.value(QStringLiteral("last_name")).toString().trimmed();
        name = (fn + ' ' + ln).trimmed();
    }
    if (name.isEmpty()) {
        QString fn = user.value(QStringLiteral("firstName")).toString().trimmed();
        QString ln = user.value(QStringLiteral("lastName")).toString().trimmed();
        name = (fn + ' ' + ln).trimmed();
    }
    if (name.isEmpty()) name = user.value(QStringLiteral("name")).toString().trimmed();
    if (name.isEmpty()) name = user.value(QStringLiteral("fullName")).toString().trimmed();
    if (name.isEmpty()) name = user.value(QStringLiteral("full_name")).toString().trimmed();
    if (name.isEmpty()) {
        QString fn = data.value(QStringLiteral("first_name")).toString().trimmed();
        QString ln = data.value(QStringLiteral("last_name")).toString().trimmed();
        name = (fn + ' ' + ln).trimmed();
    }
    if (name.isEmpty()) name = data.value(QStringLiteral("name")).toString().trimmed();
    if (name.isEmpty()) name = QStringLiteral("Anonyme");

    QString userId = data.value(QStringLiteral("userId")).toString();
    if (userId.isEmpty()) userId = user.value(QStringLiteral("id")).toString();
    if (!user.isEmpty() && user.value(QStringLiteral("image")).isNull())
        userId.clear();

    QString door = data.value(QStringLiteral("doorName")).toString();
    if (door.isEmpty()) door = data.value(QStringLiteral("readerName")).toString();
    if (door.isEmpty()) door = data.value(QStringLiteral("reader_")).toString();

    const double  score = data.value(QStringLiteral("score")).toDouble(0.0);
    const QString time  = isoToTime(data.value(QStringLiteral("createdAt")).toString());

    emit accessEvent(granted, name, source, score, door, time, userId);
}

void AppController::onBadgeEvent(const QString &evName, const QJsonObject &data)
{
    if (evName == QStringLiteral("event")         ||
        evName == QStringLiteral("access")        ||
        evName == QStringLiteral("access_event")  ||
        evName == QStringLiteral("badge_event"))
        handleEvent(data, QStringLiteral("badge"));
}

void AppController::onFaceEvent(const QString &evName, const QJsonObject &data)
{
    if (evName == QStringLiteral("event"))
        handleEvent(data, QStringLiteral("face"));
}

// ── Camera slots ──────────────────────────────────────────────────────────────

void AppController::onCamFaceStatus(bool face, bool inRoi, bool recognized)
{
    Q_UNUSED(recognized)
    if (m_faceInFrame != face || m_faceInRoi != inRoi) {
        m_faceInFrame = face;
        m_faceInRoi   = inRoi;
        emit faceStatusChanged();
    }
}

void AppController::onCamAccessGranted(const QString &name, float score)
{
    m_faceAccess = QStringLiteral("granted");
    emit faceStatusChanged();
    m_accessResetTimer->start();

    const QString time = QTime::currentTime().toString(QStringLiteral("hh:mm:ss"));
    emit accessEvent(true, name, QStringLiteral("face"),
                     static_cast<double>(score), QString(), time, QString());
}

void AppController::onCamAccessDenied(const QString &reason, float score)
{
    m_faceAccess = QStringLiteral("denied");
    emit faceStatusChanged();
    m_accessResetTimer->start();

    const QString time = QTime::currentTime().toString(QStringLiteral("hh:mm:ss"));
    emit accessEvent(false, reason, QStringLiteral("face"),
                     static_cast<double>(score), QString(), time, QString());
}

void AppController::onCamEnrollProgress(const QVariantMap &status)
{
    m_lastEnrollStatus = status;
    emit enrollStatus(status);
}

void AppController::onCamEnrollFinished(bool ok, const QString &msg)
{
    m_lastEnrollStatus.clear();
    emit enrollResult(QStringLiteral("finalize"), ok, msg);
    if (ok) emit faceUserMutated(QStringLiteral("enroll"), QString());
}

void AppController::resetFaceAccess()
{
    m_faceAccess.clear();
    emit faceStatusChanged();
}

// ── Recognition pause/resume ──────────────────────────────────────────────────

void AppController::pauseRecognition()
{
    m_face->pause();
}

void AppController::resumeRecognition()
{
    m_face->resume();
}

// ── Face users (FaceWorker/FaceDb) ───────────────────────────────────────────

void AppController::listFaceUsers()
{
    emit faceUsersLoaded(m_face->listUsers());
}

void AppController::toggleFaceUser(const QString &name)
{
    m_face->toggleUser(name);
    emit faceUserMutated(QStringLiteral("toggle"), name);
}

void AppController::deleteFaceUser(const QString &name)
{
    m_face->deleteUser(name);
    emit faceUserMutated(QStringLiteral("delete"), name);
}

// ── Enrôlement live ───────────────────────────────────────────────────────────

void AppController::startEnroll(const QString &name, const QString &role, int samplesPerPose)
{
    m_face->startEnroll(name, role, samplesPerPose);
    emit enrollResult(QStringLiteral("start"), true, QStringLiteral("Enrôlement démarré"));
}

void AppController::finalizeEnroll()
{
    m_face->finalizeEnroll();
}

void AppController::cancelEnroll()
{
    m_face->cancelEnroll();
    emit enrollResult(QStringLiteral("cancel"), true, QStringLiteral("annulé"));
}

void AppController::pollEnrollStatus()
{
    if (!m_lastEnrollStatus.isEmpty())
        emit enrollStatus(m_lastEnrollStatus);
}

// ── Config réseau (REST → m_controllerUrl) ────────────────────────────────────

void AppController::getNetworkInfo()
{
    QNetworkRequest req(QUrl(m_controllerUrl + QStringLiteral("/network/info")));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit networkApiError(QStringLiteral("info"), reply->errorString());
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isObject()) {
            emit networkApiError(QStringLiteral("info"), QStringLiteral("Réponse invalide"));
            return;
        }
        const QJsonObject o    = doc.object();
        const QJsonObject wifi = o.value(QStringLiteral("wifi")).toObject();
        const QJsonObject eth  = o.value(QStringLiteral("ethernet")).toObject();
        QVariantMap info;
        info[QStringLiteral("hostname")] = o.value(QStringLiteral("hostname")).toString();
        info[QStringLiteral("wifiIface")]= wifi.value(QStringLiteral("interface")).toString();
        info[QStringLiteral("wifiIp")]   = wifi.value(QStringLiteral("ip")).toString();
        info[QStringLiteral("wifiMac")]  = wifi.value(QStringLiteral("mac")).toString();
        info[QStringLiteral("wifiSsid")] = wifi.value(QStringLiteral("ssid")).toString();
        info[QStringLiteral("wifiMode")] = wifi.value(QStringLiteral("mode")).toString();
        info[QStringLiteral("ethIface")] = eth.value(QStringLiteral("interface")).toString();
        info[QStringLiteral("ethIp")]    = eth.value(QStringLiteral("ip")).toString();
        info[QStringLiteral("ethMac")]   = eth.value(QStringLiteral("mac")).toString();
        info[QStringLiteral("ethMode")]  = eth.value(QStringLiteral("mode")).toString();
        emit networkInfoLoaded(info);
    });
}

void AppController::scanWifi()
{
    QNetworkRequest req(QUrl(m_controllerUrl + QStringLiteral("/network/scan")));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit networkApiError(QStringLiteral("scan"), reply->errorString());
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isArray()) {
            emit networkApiError(QStringLiteral("scan"), QStringLiteral("Réponse invalide"));
            return;
        }
        QVariantList nets;
        for (const QJsonValue &v : doc.array())
            nets.append(v.toObject().toVariantMap());
        emit wifiNetworksLoaded(nets);
    });
}

static QByteArray jsonBody(const QJsonObject &o)
{
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

void AppController::connectWifi(const QString &ssid, const QString &password,
                                const QString &mode,
                                const QString &ip, const QString &prefix,
                                const QString &gateway, const QString &dns)
{
    QJsonObject body;
    body[QStringLiteral("ssid")]     = ssid;
    body[QStringLiteral("password")] = password;
    if (mode == QStringLiteral("dhcp")) {
        body[QStringLiteral("dhcp")] = true;
    } else {
        body[QStringLiteral("dhcp")]           = false;
        body[QStringLiteral("staticIp")]       = ip;
        body[QStringLiteral("mask")]           = prefix.isEmpty() ? QStringLiteral("24") : prefix;
        body[QStringLiteral("gw")]             = gateway;
        body[QStringLiteral("dnsPrimaryWifi")] = dns;
    }
    QNetworkRequest req(QUrl(m_controllerUrl + QStringLiteral("/network/wifi")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam->post(req, jsonBody(body));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit wifiConnectResult(false, reply->errorString());
            return;
        }
        emit wifiConnectResult(true, QStringLiteral("Connecté."));
    });
}

void AppController::setEthernet(const QString &mode,
                                const QString &ip, const QString &prefix,
                                const QString &gateway, const QString &dns)
{
    QJsonObject body;
    if (mode == QStringLiteral("dhcp")) {
        body[QStringLiteral("dhcp")] = true;
    } else {
        body[QStringLiteral("dhcp")]             = false;
        body[QStringLiteral("staticIpEthern")]   = ip;
        body[QStringLiteral("maskEthern")]       = prefix.isEmpty() ? QStringLiteral("24") : prefix;
        body[QStringLiteral("gwEthern")]         = gateway;
        body[QStringLiteral("dnsPrimaryEthern")] = dns;
    }
    QNetworkRequest req(QUrl(m_controllerUrl + QStringLiteral("/network/ethernet")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam->post(req, jsonBody(body));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit ethernetResult(false, reply->errorString());
            return;
        }
        emit ethernetResult(true, QStringLiteral("Configuration appliquée."));
    });
}
