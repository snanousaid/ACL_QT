#pragma once
#include <QObject>
#include <QTcpServer>
#include <QMutex>
#include <QPointer>
#include <QImage>

#ifdef ACL_OPENCV_ENABLED
#include <opencv2/core.hpp>
#include <opencv2/objdetect.hpp>
#endif

class QTcpSocket;
class QNetworkAccessManager;
class QNetworkReply;
class AppController;

// ─────────────────────────────────────────────────────────────────────────────
// HttpServer — mini-serveur HTTP intégré au process Qt, pour permettre au
// dashboard web ACL_133_FRONT d'enrôler des visages.
//
// Endpoints :
//   GET  /health
//   POST /enroll-from-images  multipart/form-data : userId + images[]
//
//   ── Mode live (v2) ──
//   GET  /stream                  multipart MJPEG (camera)
//   POST /enroll/start            JSON {userId, samplesPerPose}
//   GET  /enroll/status           JSON {status, result}
//   POST /enroll/finalize         (vide)
//   POST /enroll/cancel           (vide)
//
// Pour l'upload, le serveur charge ses propres instances YuNet+SFace.
// Pour le live, il drive le FaceWorker existant via AppController.
// ─────────────────────────────────────────────────────────────────────────────
class HttpServer : public QTcpServer
{
    Q_OBJECT
public:
    explicit HttpServer(const QString &modelsDir,
                        const QString &controllerUrl,
                        AppController *controller,
                        QObject *parent = nullptr);
    ~HttpServer() override;

    bool start(quint16 port);

protected:
    void incomingConnection(qintptr socketDescriptor) override;

private slots:
    // Diffusion d'une nouvelle frame caméra à tous les clients /stream connectés.
    void onFrameReady(const QImage &img);

private:
    QString m_modelsDir;
    QString m_controllerUrl;
    QPointer<AppController> m_controller;
    QNetworkAccessManager *m_nam;

    QMutex m_cvMutex;
#ifdef ACL_OPENCV_ENABLED
    cv::Ptr<cv::FaceDetectorYN>   m_detector;
    cv::Ptr<cv::FaceRecognizerSF> m_recognizer;
#endif
    bool m_modelsLoaded = false;
    bool loadModels();

    // Liste des sockets en streaming MJPEG (long-poll).
    // QPointer pour gestion auto si client deconnecte.
    QList<QPointer<QTcpSocket>> m_streamClients;
    QByteArray m_lastFrameJpeg;
    qint64     m_lastFrameMs = 0;

    void registerStreamClient(QTcpSocket *sock);

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
    void handleStream();
    void handleEnrollStart();
    void handleEnrollStatus();
    void handleEnrollFinalize();
    void handleEnrollCancel();

    QByteArray extractAuthHeader() const;
};
