#include "appcontroller.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
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
