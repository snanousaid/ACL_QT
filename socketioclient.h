#pragma once
#include <QObject>
#include <QWebSocket>
#include <QTimer>
#include <QJsonObject>

class SocketIoClient : public QObject
{
    Q_OBJECT
public:
    explicit SocketIoClient(const QString &url, QObject *parent = nullptr);
    ~SocketIoClient() override;

    bool isConnected() const { return m_connected; }

signals:
    void connected();
    void disconnected();
    void eventReceived(const QString &name, const QJsonObject &data);

private slots:
    void onWsConnected();
    void onWsDisconnected();
    void onTextMessage(const QString &msg);
    void reconnect();
    void sendPing();

private:
    QWebSocket m_ws;
    QString    m_url;
    bool       m_connected   = false;
    int        m_pingInterval = 25000;
    QTimer     m_pingTimer;
    QTimer     m_reconnectTimer;
};
