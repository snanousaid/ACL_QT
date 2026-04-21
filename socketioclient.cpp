#include "socketioclient.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

SocketIoClient::SocketIoClient(const QString &url, QObject *parent)
    : QObject(parent), m_url(url)
{
    connect(&m_ws, &QWebSocket::connected,
            this, &SocketIoClient::onWsConnected);
    connect(&m_ws, &QWebSocket::disconnected,
            this, &SocketIoClient::onWsDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived,
            this, &SocketIoClient::onTextMessage);

    m_pingTimer.setInterval(m_pingInterval);
    connect(&m_pingTimer, &QTimer::timeout, this, &SocketIoClient::sendPing);

    m_reconnectTimer.setSingleShot(true);
    m_reconnectTimer.setInterval(3000);
    connect(&m_reconnectTimer, &QTimer::timeout, this, &SocketIoClient::reconnect);

    reconnect();
}

SocketIoClient::~SocketIoClient()
{
    m_pingTimer.stop();
    m_reconnectTimer.stop();
    m_ws.close();
}

void SocketIoClient::reconnect()
{
    // Engine.IO 4 WebSocket upgrade URL
    QString ws = m_url;
    ws.replace(QStringLiteral("http://"), QStringLiteral("ws://"));
    ws.replace(QStringLiteral("https://"), QStringLiteral("wss://"));
    if (!ws.endsWith('/')) ws += '/';
    ws += QStringLiteral("socket.io/?EIO=4&transport=websocket");
    m_ws.open(QUrl(ws));
}

void SocketIoClient::onWsConnected()
{
    // Engine.IO OPEN packet arrives as first text message; wait for it.
}

void SocketIoClient::onWsDisconnected()
{
    m_connected = false;
    m_pingTimer.stop();
    emit disconnected();
    m_reconnectTimer.start();
}

void SocketIoClient::onTextMessage(const QString &msg)
{
    if (msg.isEmpty()) return;

    const QChar eio = msg[0];

    if (eio == '0') {
        // Engine.IO OPEN — parse pingInterval, then send Socket.IO CONNECT
        QJsonDocument doc = QJsonDocument::fromJson(msg.mid(1).toUtf8());
        if (doc.isObject()) {
            int pi = doc.object().value(QStringLiteral("pingInterval")).toInt(0);
            if (pi > 0) {
                m_pingInterval = pi;
                m_pingTimer.setInterval(pi);
            }
        }
        m_ws.sendTextMessage(QStringLiteral("40"));
        return;
    }

    if (eio == '2') {
        // Engine.IO PING → reply PONG
        m_ws.sendTextMessage(QStringLiteral("3"));
        return;
    }

    if (eio == '4' && msg.length() >= 2) {
        const QChar sio = msg[1];

        if (sio == '0') {
            // Socket.IO CONNECT acknowledged
            m_connected = true;
            m_pingTimer.start();
            emit connected();
            return;
        }

        if (sio == '2') {
            // Socket.IO EVENT: 42["eventName", {...}]
            QJsonDocument doc = QJsonDocument::fromJson(msg.mid(2).toUtf8());
            if (doc.isArray() && doc.array().size() >= 1) {
                const QString name = doc.array()[0].toString();
                QJsonObject data;
                if (doc.array().size() >= 2 && doc.array()[1].isObject())
                    data = doc.array()[1].toObject();
                emit eventReceived(name, data);
            }
            return;
        }
    }
}

void SocketIoClient::sendPing()
{
    if (m_ws.state() == QAbstractSocket::ConnectedState)
        m_ws.sendTextMessage(QStringLiteral("2"));
}
