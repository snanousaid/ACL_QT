#include "appcontroller.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QHttpMultiPart>
#include <QUrlQuery>
#include <QDateTime>
#include <QTime>
#include <QUrl>

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_nam = new QNetworkAccessManager(this);

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

    m_faceSocket = new SocketIoClient(m_faceSocketUrl, this);
    connect(m_faceSocket, &SocketIoClient::connected, this, [this] {
        m_faceConnected = true;
        emit faceConnectedChanged();
    });
    connect(m_faceSocket, &SocketIoClient::disconnected, this, [this] {
        m_faceConnected = false;
        emit faceConnectedChanged();
    });
    connect(m_faceSocket, &SocketIoClient::eventReceived,
            this, &AppController::onFaceEvent);
}

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

void AppController::handleEvent(const QJsonObject &data, const QString &source)
{
    const bool granted = data.value(QStringLiteral("status")).toBool() ||
                         data.value(QStringLiteral("eventType")).toString()
                             == QStringLiteral("ACCESS_GRANTED");

    const QJsonObject user = data.value(QStringLiteral("user")).toObject();
    QString fn = user.value(QStringLiteral("first_name")).toString().trimmed();
    QString ln = user.value(QStringLiteral("last_name")).toString().trimmed();
    QString name = (fn + ' ' + ln).trimmed();
    if (name.isEmpty()) name = QStringLiteral("Anonyme");

    QString door = data.value(QStringLiteral("doorName")).toString();
    if (door.isEmpty()) door = data.value(QStringLiteral("reader_")).toString();

    const double score = data.value(QStringLiteral("score")).toDouble(0.0);
    const QString time = isoToTime(data.value(QStringLiteral("createdAt")).toString());

    emit accessEvent(granted, name, source, score, door, time);
}

void AppController::onBadgeEvent(const QString &evName, const QJsonObject &data)
{
    if (evName == QStringLiteral("event"))
        handleEvent(data, QStringLiteral("badge"));
}

void AppController::onFaceEvent(const QString &evName, const QJsonObject &data)
{
    if (evName == QStringLiteral("event"))
        handleEvent(data, QStringLiteral("face"));
}

void AppController::pauseRecognition()
{
    QUrl url(m_faceApiUrl + QStringLiteral("/recognition/pause"));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    m_nam->post(req, QByteArray());
}

void AppController::resumeRecognition()
{
    QUrl url(m_faceApiUrl + QStringLiteral("/recognition/resume"));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    m_nam->post(req, QByteArray());
}

// ── Face users management ──────────────────────────────────────────────────
void AppController::listFaceUsers()
{
    QNetworkRequest req(QUrl(m_faceApiUrl + QStringLiteral("/api/users")));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit faceApiError(QStringLiteral("list"), reply->errorString());
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isArray()) {
            emit faceApiError(QStringLiteral("list"), QStringLiteral("Réponse invalide"));
            return;
        }
        QVariantList users;
        for (const QJsonValue &v : doc.array())
            users.append(v.toObject().toVariantMap());
        emit faceUsersLoaded(users);
    });
}

void AppController::toggleFaceUser(const QString &name)
{
    const QUrl url(m_faceApiUrl + QStringLiteral("/api/users/") + name + QStringLiteral("/toggle"));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam->post(req, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply, name] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit faceApiError(QStringLiteral("toggle"), reply->errorString());
            return;
        }
        emit faceUserMutated(QStringLiteral("toggle"), name);
    });
}

void AppController::deleteFaceUser(const QString &name)
{
    const QUrl url(m_faceApiUrl + QStringLiteral("/api/users/") + name);
    QNetworkRequest req(url);
    QNetworkReply *reply = m_nam->deleteResource(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, name] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit faceApiError(QStringLiteral("delete"), reply->errorString());
            return;
        }
        emit faceUserMutated(QStringLiteral("delete"), name);
    });
}

// ── Enrôlement live ────────────────────────────────────────────────────────
static QByteArray formEncode(const QList<QPair<QString, QString>> &pairs)
{
    QUrlQuery q;
    for (const auto &p : pairs) q.addQueryItem(p.first, p.second);
    return q.toString(QUrl::FullyEncoded).toUtf8();
}

static void parseOkMsg(QNetworkReply *reply, bool *ok, QString *msg)
{
    *ok = false;
    *msg = QString();
    const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (doc.isObject()) {
        const QJsonObject o = doc.object();
        *ok  = o.value(QStringLiteral("ok")).toBool();
        *msg = o.value(QStringLiteral("msg")).toString();
    }
}

void AppController::startEnroll(const QString &name, const QString &role, int samplesPerPose)
{
    QNetworkRequest req(QUrl(m_faceApiUrl + QStringLiteral("/enroll_live/start")));
    req.setHeader(QNetworkRequest::ContentTypeHeader,
                  QStringLiteral("application/x-www-form-urlencoded"));
    const QByteArray body = formEncode({
        {QStringLiteral("name"), name},
        {QStringLiteral("role"), role},
        {QStringLiteral("samples_per_pose"), QString::number(samplesPerPose)},
    });
    QNetworkReply *reply = m_nam->post(req, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit enrollResult(QStringLiteral("start"), false, reply->errorString());
            return;
        }
        bool ok; QString msg;
        parseOkMsg(reply, &ok, &msg);
        emit enrollResult(QStringLiteral("start"), ok, msg);
    });
}

void AppController::finalizeEnroll()
{
    QNetworkRequest req(QUrl(m_faceApiUrl + QStringLiteral("/enroll_live/finalize")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam->post(req, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit enrollResult(QStringLiteral("finalize"), false, reply->errorString());
            return;
        }
        bool ok; QString msg;
        parseOkMsg(reply, &ok, &msg);
        emit enrollResult(QStringLiteral("finalize"), ok, msg);
    });
}

void AppController::cancelEnroll()
{
    QNetworkRequest req(QUrl(m_faceApiUrl + QStringLiteral("/enroll_live/cancel")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_nam->post(req, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        bool ok = (reply->error() == QNetworkReply::NoError);
        QString msg = ok ? QStringLiteral("annulé") : reply->errorString();
        emit enrollResult(QStringLiteral("cancel"), ok, msg);
    });
}

void AppController::pollEnrollStatus()
{
    QNetworkRequest req(QUrl(m_faceApiUrl + QStringLiteral("/status.json")));
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) return;  // silent — poll récurrent
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isObject())
            emit enrollStatus(doc.object().toVariantMap());
    });
}

// ── Config réseau ──────────────────────────────────────────────────────────
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
        const QJsonObject o = doc.object();
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
