#pragma once
#include <QObject>
#include <QTcpServer>
#include <QMutex>

#ifdef ACL_OPENCV_ENABLED
#include <opencv2/core.hpp>
#include <opencv2/objdetect.hpp>
#endif

class QTcpSocket;
class QNetworkAccessManager;
class QNetworkReply;

// ─────────────────────────────────────────────────────────────────────────────
// HttpServer — mini-serveur HTTP intégré au process Qt, pour permettre au
// dashboard web ACL_133_FRONT d'enrôler des visages via upload d'images.
//
// Endpoints (v1) :
//   GET  /health
//   POST /enroll-from-images  multipart/form-data : userId + images_<pose>[]
//
// Le serveur charge ses PROPRES instances YuNet + SFace (pas de partage avec
// FaceWorker pour éviter mutex/contention sur le pipeline live). Les modèles
// sont chargés à la première requête nécessitant détection.
//
// Après extraction, POST /face/enroll directement vers acl_controller.
// ─────────────────────────────────────────────────────────────────────────────
class HttpServer : public QTcpServer
{
    Q_OBJECT
public:
    explicit HttpServer(const QString &modelsDir,
                        const QString &controllerUrl,
                        QObject *parent = nullptr);
    ~HttpServer() override;

    bool start(quint16 port);

protected:
    void incomingConnection(qintptr socketDescriptor) override;

private:
    QString m_modelsDir;
    QString m_controllerUrl;
    QNetworkAccessManager *m_nam;

    QMutex m_cvMutex;
#ifdef ACL_OPENCV_ENABLED
    cv::Ptr<cv::FaceDetectorYN>   m_detector;
    cv::Ptr<cv::FaceRecognizerSF> m_recognizer;
#endif
    bool m_modelsLoaded = false;
    bool loadModels();

    friend class HttpConnection;
};

// Une instance par socket entrant. S'autodétruit à la fin du traitement.
class HttpConnection : public QObject
{
    Q_OBJECT
public:
    HttpConnection(qintptr socketDescriptor, HttpServer *server);

private slots:
    void onReadyRead();
    void onDisconnected();

private:
    HttpServer *m_server;
    QTcpSocket *m_socket;
    QByteArray  m_buffer;

    enum class State { ReadingHeaders, ReadingBody, Done };
    State    m_state = State::ReadingHeaders;
    QString  m_method;
    QString  m_path;
    QByteArray m_contentType;
    int      m_contentLength = 0;
    QByteArray m_body;

    static constexpr int MAX_HEADERS_BYTES = 16 * 1024;
    static constexpr int MAX_BODY_BYTES    = 100 * 1024 * 1024; // 100 Mo (5 × 20 imgs)

    bool parseRequestLine(const QByteArray &line);
    void parseHeaderLine(const QByteArray &line);
    void route();

    void writeResponse(int status, const QByteArray &body,
                       const QByteArray &contentType = "application/json");
    void writeJsonError(int status, const QString &message);

    void handleHealth();
    void handleEnrollFromImages();

    QByteArray extractAuthHeader() const;
};
