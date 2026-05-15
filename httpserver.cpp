#include "httpserver.h"

#include <QTcpSocket>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHostAddress>
#include <QDebug>
#include <QMutexLocker>
#include <QPointer>

#ifdef ACL_OPENCV_ENABLED
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#endif

namespace {
    const QStringList ACTIVE_POSES = { "center", "left", "right", "up", "down" };

    // ── Validation visage (copie de faceworker.cpp::isValidFace) ───────────
    // On accepte des critères plus larges pour l'upload (photos déjà choisies
    // par l'admin) : pas d'aspect ratio strict, mais on garde la cohérence
    // landmarks pour rejeter les faux positifs flagrants.
#ifdef ACL_OPENCV_ENABLED
    bool isValidUploadFace(const cv::Mat &face)
    {
        float w = face.at<float>(0, 2);
        float h = face.at<float>(0, 3);
        if (w <= 0 || h <= 0) return false;

        float rex = face.at<float>(0, 4),  rey = face.at<float>(0, 5);
        float lex = face.at<float>(0, 6),  ley = face.at<float>(0, 7);
        float rmy = face.at<float>(0, 11), lmy = face.at<float>(0, 13);

        float eye_cy   = (rey + ley) / 2.0f;
        float mouth_cy = (rmy + lmy) / 2.0f;
        return eye_cy < mouth_cy;
    }

    int bestFaceIdx(const cv::Mat &faces)
    {
        int   idx  = -1;
        float best = 0;
        for (int i = 0; i < faces.rows; i++) {
            if (!isValidUploadFace(faces.row(i))) continue;
            float area = faces.at<float>(i, 2) * faces.at<float>(i, 3);
            if (area > best) { best = area; idx = i; }
        }
        return idx;
    }
#endif
}

// ═══════════════════════════════════════════════════════════════════════════
// HttpServer
// ═══════════════════════════════════════════════════════════════════════════

HttpServer::HttpServer(const QString &modelsDir,
                       const QString &controllerUrl,
                       QObject *parent)
    : QTcpServer(parent),
      m_modelsDir(modelsDir),
      m_controllerUrl(controllerUrl)
{
    m_nam = new QNetworkAccessManager(this);
}

HttpServer::~HttpServer() = default;

bool HttpServer::start(quint16 port)
{
    if (!listen(QHostAddress::Any, port)) {
        qWarning() << "[HttpServer] listen failed on port" << port
                   << ":" << errorString();
        return false;
    }
    qDebug() << "[HttpServer] listening on 0.0.0.0:" << port
             << "controllerUrl=" << m_controllerUrl;
    return true;
}

void HttpServer::incomingConnection(qintptr socketDescriptor)
{
    new HttpConnection(socketDescriptor, this);
}

bool HttpServer::loadModels()
{
#ifdef ACL_OPENCV_ENABLED
    if (m_modelsLoaded) return true;
    QMutexLocker l(&m_cvMutex);
    if (m_modelsLoaded) return true;

    const std::string yunet =
        (m_modelsDir + "/face_detection_yunet_2022mar.onnx").toStdString();
    const std::string sface =
        (m_modelsDir + "/face_recognition_sface_2021dec.onnx").toStdString();

    try {
        // Note : pour l'upload on accepte des images de taille variable. On
        // ajuste setInputSize() par image dans le handler.
        m_detector = cv::FaceDetectorYN::create(yunet, "",
            {640, 480}, 0.60f /*score*/, 0.30f /*nms*/, 50);
        m_recognizer = cv::FaceRecognizerSF::create(sface, "");
        m_modelsLoaded = true;
        qDebug() << "[HttpServer] modèles OpenCV chargés (YuNet + SFace)";
        return true;
    } catch (const cv::Exception &e) {
        qWarning() << "[HttpServer] modèles KO :" << e.what();
        return false;
    }
#else
    Q_UNUSED(this)
    return false;
#endif
}

// ═══════════════════════════════════════════════════════════════════════════
// HttpConnection
// ═══════════════════════════════════════════════════════════════════════════

HttpConnection::HttpConnection(qintptr socketDescriptor, HttpServer *server)
    : QObject(server), m_server(server)
{
    m_socket = new QTcpSocket(this);
    if (!m_socket->setSocketDescriptor(socketDescriptor)) {
        qWarning() << "[HttpConnection] setSocketDescriptor failed";
        deleteLater();
        return;
    }
    connect(m_socket, &QTcpSocket::readyRead,
            this,     &HttpConnection::onReadyRead);
    connect(m_socket, &QTcpSocket::disconnected,
            this,     &HttpConnection::onDisconnected);
}

void HttpConnection::onDisconnected()
{
    deleteLater();
}

void HttpConnection::onReadyRead()
{
    m_buffer += m_socket->readAll();

    if (m_state == State::ReadingHeaders) {
        const int hdrEnd = m_buffer.indexOf("\r\n\r\n");
        if (hdrEnd < 0) {
            if (m_buffer.size() > MAX_HEADERS_BYTES) {
                writeJsonError(431, "Request headers too large");
            }
            return;
        }

        const QByteArray headersBlock = m_buffer.left(hdrEnd);
        m_buffer.remove(0, hdrEnd + 4);

        const QList<QByteArray> lines = headersBlock.split('\n');
        if (lines.isEmpty()) {
            writeJsonError(400, "Empty request");
            return;
        }
        if (!parseRequestLine(lines.first().trimmed())) {
            writeJsonError(400, "Invalid request line");
            return;
        }
        for (int i = 1; i < lines.size(); i++) {
            parseHeaderLine(lines[i]);
        }

        if (m_method == "POST" && m_contentLength <= 0) {
            writeJsonError(411, "Content-Length required");
            return;
        }
        if (m_contentLength > MAX_BODY_BYTES) {
            writeJsonError(413, "Body too large");
            return;
        }
        m_state = State::ReadingBody;
    }

    if (m_state == State::ReadingBody) {
        if (m_method == "GET" || m_contentLength == 0) {
            m_state = State::Done;
            route();
            return;
        }
        if (m_buffer.size() < m_contentLength) {
            return; // wait for more
        }
        m_body = m_buffer.left(m_contentLength);
        m_buffer.remove(0, m_contentLength);
        m_state = State::Done;
        route();
    }
}

bool HttpConnection::parseRequestLine(const QByteArray &line)
{
    const QList<QByteArray> parts = line.split(' ');
    if (parts.size() < 3) return false;
    m_method = QString::fromLatin1(parts[0]);
    m_path   = QString::fromLatin1(parts[1]);
    return true;
}

void HttpConnection::parseHeaderLine(const QByteArray &line)
{
    const int colon = line.indexOf(':');
    if (colon <= 0) return;
    const QByteArray key = line.left(colon).trimmed().toLower();
    const QByteArray val = line.mid(colon + 1).trimmed();
    if (key == "content-length") {
        m_contentLength = val.toInt();
    } else if (key == "content-type") {
        m_contentType = val;
    }
}

QByteArray HttpConnection::extractAuthHeader() const
{
    // Pas exposé dans MVP : la front n'envoie pas de token, le backend laisse
    // /face/enroll passer (admin LAN). Stub pour évolution future.
    return {};
}

void HttpConnection::route()
{
    qDebug() << "[HttpServer]" << m_method << m_path
             << "body=" << m_body.size() << "octets";

    if (m_method == "GET" && m_path == "/health") {
        handleHealth();
        return;
    }
    if (m_method == "POST" && m_path == "/enroll-from-images") {
        handleEnrollFromImages();
        return;
    }
    writeJsonError(404, "Not found");
}

void HttpConnection::handleHealth()
{
    writeResponse(200, "{\"status\":\"ok\"}");
}

// ── Multipart parser minimaliste ────────────────────────────────────────────
// Pour chaque part, retourne (name, filename, contentType, dataPtr, dataLen).
// On utilise QByteArray::indexOf — donc une seule passe linéaire sur le body.

namespace {

struct Part {
    QByteArray name;
    QByteArray filename;
    QByteArray contentType;
    QByteArray data;
};

QByteArray extractParam(const QByteArray &headers, const QByteArray &key)
{
    // ex: extractParam("Content-Disposition: form-data; name=\"foo\"", "name")
    const QByteArray needle = key + "=\"";
    int p = headers.indexOf(needle);
    if (p < 0) return {};
    p += needle.size();
    const int q = headers.indexOf('"', p);
    if (q < 0) return {};
    return headers.mid(p, q - p);
}

QList<Part> parseMultipart(const QByteArray &body, const QByteArray &boundary)
{
    QList<Part> parts;
    const QByteArray sep = QByteArray("--") + boundary;
    int pos = body.indexOf(sep);
    if (pos < 0) return parts;
    pos += sep.size();

    while (pos < body.size()) {
        // Après chaque sep : soit "--" (fin) soit "\r\n" + part
        if (body.mid(pos, 2) == "--") break;
        if (body.mid(pos, 2) == "\r\n") pos += 2;

        const int hdrEnd = body.indexOf("\r\n\r\n", pos);
        if (hdrEnd < 0) break;
        const QByteArray hdrs = body.mid(pos, hdrEnd - pos);
        const int dataStart = hdrEnd + 4;

        // Le boundary suivant marque la fin du data. On précède "\r\n--<boundary>".
        const QByteArray nextSep = QByteArray("\r\n--") + boundary;
        const int dataEnd = body.indexOf(nextSep, dataStart);
        if (dataEnd < 0) break;

        Part p;
        p.name        = extractParam(hdrs, "name");
        p.filename    = extractParam(hdrs, "filename");
        // Content-Type optionnel
        const int ctPos = hdrs.indexOf("Content-Type:");
        if (ctPos >= 0) {
            const int eol = hdrs.indexOf("\r\n", ctPos);
            p.contentType = hdrs.mid(ctPos + 13,
                (eol > 0 ? eol : hdrs.size()) - (ctPos + 13)).trimmed();
        }
        p.data = body.mid(dataStart, dataEnd - dataStart);
        parts.append(p);

        pos = dataEnd + nextSep.size();
    }
    return parts;
}

} // namespace

void HttpConnection::handleEnrollFromImages()
{
#ifndef ACL_OPENCV_ENABLED
    writeJsonError(501, "OpenCV non disponible sur ce build");
    return;
#else
    // ── Boundary multipart ────────────────────────────────────────────────
    const QByteArray boundaryKey = "boundary=";
    const int bpos = m_contentType.indexOf(boundaryKey);
    if (bpos < 0) {
        writeJsonError(400, "Content-Type sans boundary");
        return;
    }
    QByteArray boundary = m_contentType.mid(bpos + boundaryKey.size());
    if (boundary.startsWith('"') && boundary.endsWith('"'))
        boundary = boundary.mid(1, boundary.size() - 2);

    const QList<Part> parts = parseMultipart(m_body, boundary);
    if (parts.isEmpty()) {
        writeJsonError(400, "Multipart vide ou mal forme");
        return;
    }

    // ── Lookup userId + collecte images par pose ──────────────────────────
    QString userId;
    QMap<QString, QList<QByteArray>> imagesByPose;
    for (const Part &p : parts) {
        const QString name = QString::fromLatin1(p.name);
        if (name == "userId") {
            userId = QString::fromUtf8(p.data).trimmed();
        } else if (name.startsWith("images_")) {
            const QString pose = name.mid(7);
            if (ACTIVE_POSES.contains(pose)) {
                imagesByPose[pose].append(p.data);
            }
        }
    }
    if (userId.isEmpty()) {
        writeJsonError(400, "userId manquant");
        return;
    }
    if (imagesByPose.isEmpty()) {
        writeJsonError(400, "Aucune image fournie");
        return;
    }

    // ── Charge modeles si pas encore fait ─────────────────────────────────
    if (!m_server->loadModels()) {
        writeJsonError(500, "Echec chargement modeles OpenCV");
        return;
    }

    // ── Extraction par image, moyenne par pose ────────────────────────────
    QJsonObject embeddings;
    QJsonObject poseCounts;
    int totalValid = 0;

    {
        QMutexLocker l(&m_server->m_cvMutex);
        cv::Mat aligned, feat;

        for (auto it = imagesByPose.constBegin(); it != imagesByPose.constEnd(); ++it) {
            const QString &pose = it.key();
            const QList<QByteArray> &imgs = it.value();

            QVector<QVector<float>> embsForPose;
            for (const QByteArray &raw : imgs) {
                std::vector<uchar> buf(reinterpret_cast<const uchar*>(raw.constData()),
                                       reinterpret_cast<const uchar*>(raw.constData()) + raw.size());
                cv::Mat img;
                try {
                    img = cv::imdecode(buf, cv::IMREAD_COLOR);
                } catch (const cv::Exception &e) {
                    qWarning() << "[enroll-from-images] imdecode KO" << pose << ":" << e.what();
                    continue;
                }
                if (img.empty()) {
                    qWarning() << "[enroll-from-images] image vide / format inconnu, pose=" << pose;
                    continue;
                }

                cv::Mat faces;
                try {
                    m_server->m_detector->setInputSize({img.cols, img.rows});
                    m_server->m_detector->detect(img, faces);
                } catch (const cv::Exception &e) {
                    qWarning() << "[enroll-from-images] detect KO" << pose << ":" << e.what();
                    continue;
                }
                if (faces.empty() || faces.rows == 0) {
                    qDebug() << "[enroll-from-images] aucun visage detecte, pose=" << pose;
                    continue;
                }
                const int idx = bestFaceIdx(faces);
                if (idx < 0) {
                    qDebug() << "[enroll-from-images] aucun visage valide, pose=" << pose;
                    continue;
                }
                try {
                    m_server->m_recognizer->alignCrop(img, faces.row(idx), aligned);
                    m_server->m_recognizer->feature(aligned, feat);
                } catch (const cv::Exception &e) {
                    qWarning() << "[enroll-from-images] feature KO" << pose << ":" << e.what();
                    continue;
                }

                QVector<float> emb(static_cast<int>(feat.total()));
                for (int i = 0; i < emb.size(); i++) emb[i] = feat.at<float>(i);
                embsForPose.append(emb);
            }

            if (embsForPose.isEmpty()) continue;

            // Moyenne + normalisation L2
            const int dim = embsForPose[0].size();
            QVector<float> mean(dim, 0.0f);
            for (const auto &v : embsForPose)
                for (int i = 0; i < dim; i++) mean[i] += v[i];
            for (float &x : mean) x /= embsForPose.size();
            double norm = 0;
            for (float x : mean) norm += x * x;
            norm = std::sqrt(norm);
            if (norm > 1e-9) for (float &x : mean) x /= static_cast<float>(norm);

            QJsonArray arr;
            for (float x : mean) arr.append(static_cast<double>(x));
            embeddings[pose] = arr;
            poseCounts[pose] = embsForPose.size();
            totalValid += embsForPose.size();
        }
    }

    if (embeddings.isEmpty()) {
        writeJsonError(422, "Aucun visage extrait des images fournies");
        return;
    }
    qDebug() << "[enroll-from-images] userId=" << userId
             << "poses=" << embeddings.keys()
             << "samples valides=" << totalValid;

    // ── POST vers acl_controller /face/enroll ─────────────────────────────
    QJsonObject body;
    body["userId"]     = userId;
    body["embeddings"] = embeddings;

    QNetworkRequest req(QUrl(m_server->m_controllerUrl + QStringLiteral("/face/enroll")));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    const QByteArray authHeader = extractAuthHeader();
    if (!authHeader.isEmpty())
        req.setRawHeader("Authorization", authHeader);

    QNetworkReply *reply = m_server->m_nam->post(req,
        QJsonDocument(body).toJson(QJsonDocument::Compact));

    QPointer<HttpConnection> self(this);
    connect(reply, &QNetworkReply::finished, this, [self, reply, poseCounts] {
        const QByteArray respBody = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString netErr = reply->errorString();
        const auto netError = reply->error();
        reply->deleteLater();

        if (!self) return;

        if (netError != QNetworkReply::NoError || http >= 400) {
            QString msg = netErr;
            const auto doc = QJsonDocument::fromJson(respBody);
            const auto m = doc.object().value("message").toString();
            if (!m.isEmpty()) msg = m;
            qWarning() << "[enroll-from-images] backend FAIL http=" << http
                       << "msg=" << msg;
            self->writeJsonError(502, QStringLiteral("Backend: %1").arg(msg));
            return;
        }

        const auto root = QJsonDocument::fromJson(respBody).object();
        QJsonObject out;
        out["profileId"] = root.value("profileId");
        out["isUpdate"] = root.value("isUpdate");
        out["poses"]    = poseCounts;
        self->writeResponse(200, QJsonDocument(out).toJson(QJsonDocument::Compact));
    });
#endif
}

// ── Réponses HTTP ───────────────────────────────────────────────────────────

void HttpConnection::writeResponse(int status, const QByteArray &body,
                                   const QByteArray &contentType)
{
    if (!m_socket || m_socket->state() != QAbstractSocket::ConnectedState) {
        deleteLater();
        return;
    }
    static const QMap<int, QByteArray> reasons = {
        {200, "OK"}, {400, "Bad Request"}, {404, "Not Found"},
        {411, "Length Required"}, {413, "Payload Too Large"},
        {422, "Unprocessable Entity"}, {431, "Request Header Fields Too Large"},
        {500, "Internal Server Error"}, {501, "Not Implemented"},
        {502, "Bad Gateway"},
    };
    const QByteArray reason = reasons.value(status, "Status");

    QByteArray head;
    head += "HTTP/1.1 " + QByteArray::number(status) + " " + reason + "\r\n";
    head += "Content-Type: " + contentType + "\r\n";
    head += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    // CORS ouvert (LAN privé v1)
    head += "Access-Control-Allow-Origin: *\r\n";
    head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    head += "Access-Control-Allow-Headers: Content-Type, Authorization\r\n";
    head += "Connection: close\r\n\r\n";

    m_socket->write(head);
    m_socket->write(body);
    m_socket->flush();
    m_socket->disconnectFromHost();
}

void HttpConnection::writeJsonError(int status, const QString &message)
{
    QJsonObject obj;
    obj["error"]   = true;
    obj["message"] = message;
    writeResponse(status, QJsonDocument(obj).toJson(QJsonDocument::Compact));
}
