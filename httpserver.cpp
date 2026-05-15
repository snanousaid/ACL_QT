#include "httpserver.h"
#include "appcontroller.h"

#include <QTcpSocket>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QHostAddress>
#include <QDebug>
#include <QMutexLocker>
#include <QPointer>
#include <QBuffer>
#include <QDateTime>

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

    // Auto-classification pose depuis landmarks YuNet — meme logique que
    // faceworker.cpp::estimatePose(). Utilisee pour l'upload web : le front
    // n'envoie qu'un seul lot d'images, Qt repartit par pose.
    // Retourne "center" pour les images transitionnelles ou ambigues (au lieu
    // de "transition") puisque pour l'upload on veut toujours garder l'image.
    QString classifyPose(const cv::Mat &face)
    {
        float rex = face.at<float>(0, 4),  rey = face.at<float>(0, 5);
        float lex = face.at<float>(0, 6),  ley = face.at<float>(0, 7);
        float nx  = face.at<float>(0, 8),  ny  = face.at<float>(0, 9);
        float rmy = face.at<float>(0, 11), lmy = face.at<float>(0, 13);

        float eye_cx    = (rex + lex) / 2.0f;
        float eye_cy    = (rey + ley) / 2.0f;
        float mouth_cy  = (rmy + lmy) / 2.0f;
        float inter_eye = std::max(std::abs(lex - rex), 1.0f);

        float yaw   = (nx - eye_cx) / inter_eye;
        float em    = mouth_cy - eye_cy;
        float pitch = (em > 1.0f) ? ((ny - eye_cy) / em - 0.5f) : 0.0f;

        if (yaw   < -0.30f && std::abs(pitch) < 0.20f) return QStringLiteral("left");
        if (yaw   >  0.30f && std::abs(pitch) < 0.20f) return QStringLiteral("right");
        if (pitch < -0.06f && std::abs(yaw)   < 0.30f) return QStringLiteral("up");
        if (pitch >  0.08f && std::abs(yaw)   < 0.30f) return QStringLiteral("down");
        // center par defaut (englobe "transition" pour l'upload)
        return QStringLiteral("center");
    }
#endif
}

// ═══════════════════════════════════════════════════════════════════════════
// HttpServer
// ═══════════════════════════════════════════════════════════════════════════

HttpServer::HttpServer(const QString &modelsDir,
                       const QString &controllerUrl,
                       AppController *controller,
                       QObject *parent)
    : QTcpServer(parent),
      m_modelsDir(modelsDir),
      m_controllerUrl(controllerUrl),
      m_controller(controller)
{
    m_nam = new QNetworkAccessManager(this);
    if (m_controller) {
        // Branche le stream MJPEG sur les frames de la camera.
        // QueuedConnection : la frame est forwardee depuis le thread camera,
        // on veut traiter l'encodage JPEG dans le main thread.
        connect(m_controller, &AppController::frameReady,
                this,         &HttpServer::onFrameReady,
                Qt::QueuedConnection);
    }
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

void HttpServer::registerStreamClient(QTcpSocket *sock)
{
    if (!sock) return;
    m_streamClients.append(QPointer<QTcpSocket>(sock));

    // Si on a une frame en cache, envoie tout de suite pour eviter un ecran
    // noir le temps de la prochaine frame.
    if (!m_lastFrameJpeg.isEmpty() && sock->state() == QAbstractSocket::ConnectedState) {
        QByteArray part;
        part += "--frame\r\n";
        part += "Content-Type: image/jpeg\r\n";
        part += "Content-Length: " + QByteArray::number(m_lastFrameJpeg.size()) + "\r\n\r\n";
        sock->write(part);
        sock->write(m_lastFrameJpeg);
        sock->write("\r\n");
        sock->flush();
    }

    qDebug() << "[HttpServer] stream client connecte —"
             << m_streamClients.size() << "clients actifs";

    // Cleanup auto a la deconnexion
    connect(sock, &QTcpSocket::disconnected, this, [this, sock] {
        for (int i = m_streamClients.size() - 1; i >= 0; --i) {
            if (m_streamClients[i].isNull() || m_streamClients[i].data() == sock)
                m_streamClients.removeAt(i);
        }
        sock->deleteLater();
        qDebug() << "[HttpServer] stream client deconnecte —"
                 << m_streamClients.size() << "clients restants";
    });
}

void HttpServer::onFrameReady(const QImage &img)
{
    if (img.isNull()) return;

    // Rate-limit : on n'envoie pas plus vite que ~15 FPS aux clients web pour
    // economiser bande passante (le live enrollment n'a pas besoin de 30 FPS).
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (nowMs - m_lastFrameMs < 66) return;  // ~15 FPS max
    m_lastFrameMs = nowMs;

    if (m_streamClients.isEmpty()) return;

    // Encode JPEG (qualité 75 — compromis taille/qualité pour LAN web)
    QByteArray jpeg;
    {
        QBuffer buf(&jpeg);
        buf.open(QIODevice::WriteOnly);
        img.save(&buf, "JPEG", 75);
    }
    if (jpeg.isEmpty()) return;
    m_lastFrameJpeg = jpeg;

    QByteArray head;
    head += "--frame\r\n";
    head += "Content-Type: image/jpeg\r\n";
    head += "Content-Length: " + QByteArray::number(jpeg.size()) + "\r\n\r\n";

    for (int i = m_streamClients.size() - 1; i >= 0; --i) {
        QPointer<QTcpSocket> &sp = m_streamClients[i];
        if (sp.isNull()) {
            m_streamClients.removeAt(i);
            continue;
        }
        QTcpSocket *s = sp.data();
        if (s->state() != QAbstractSocket::ConnectedState) {
            m_streamClients.removeAt(i);
            s->deleteLater();
            continue;
        }
        s->write(head);
        s->write(jpeg);
        s->write("\r\n");
        // Pas de flush ici : Qt batchera automatiquement, evite syscalls
    }
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

    if (m_method == "GET"  && m_path == "/health")              { handleHealth(); return; }
    if (m_method == "POST" && m_path == "/enroll-from-images")  { handleEnrollFromImages(); return; }
    if (m_method == "GET"  && m_path == "/stream")              { handleStream(); return; }
    if (m_method == "POST" && m_path == "/enroll/start")        { handleEnrollStart(); return; }
    if (m_method == "GET"  && m_path == "/enroll/status")       { handleEnrollStatus(); return; }
    if (m_method == "POST" && m_path == "/enroll/finalize")     { handleEnrollFinalize(); return; }
    if (m_method == "POST" && m_path == "/enroll/cancel")       { handleEnrollCancel(); return; }
    writeJsonError(404, "Not found");
}

void HttpConnection::handleHealth()
{
    writeResponse(200, "{\"status\":\"ok\"}");
}

// ── Stream MJPEG ───────────────────────────────────────────────────────────
// Le socket reste ouvert ; HttpServer pousse chaque nouvelle frame en y
// ecrivant un nouveau "part" multipart. On transfere le socket au server
// (la HttpConnection s'auto-detruit, le socket lui survit).
void HttpConnection::handleStream()
{
    if (!m_socket || m_socket->state() != QAbstractSocket::ConnectedState) {
        deleteLater();
        return;
    }
    QByteArray head;
    head += "HTTP/1.1 200 OK\r\n";
    head += "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n";
    head += "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n";
    head += "Pragma: no-cache\r\n";
    head += "Access-Control-Allow-Origin: *\r\n";
    head += "Connection: close\r\n\r\n";
    m_socket->write(head);
    m_socket->flush();

    // Detache le socket de la connection : on coupe les signaux readyRead /
    // disconnected pour eviter que ce HttpConnection traite encore quelque
    // chose, et on confie le socket a HttpServer.
    disconnect(m_socket, nullptr, this, nullptr);
    QTcpSocket *sock = m_socket;
    m_socket = nullptr;
    sock->setParent(m_server);
    m_server->registerStreamClient(sock);

    deleteLater();
}

// ── Enroll control (proxy vers AppController) ──────────────────────────────
void HttpConnection::handleEnrollStart()
{
    if (!m_server->m_controller) {
        writeJsonError(500, "AppController non disponible");
        return;
    }
    const auto doc = QJsonDocument::fromJson(m_body);
    if (!doc.isObject()) {
        writeJsonError(400, "JSON body invalide");
        return;
    }
    const QString userId = doc.object().value("userId").toString().trimmed();
    int samples = doc.object().value("samplesPerPose").toInt(10);
    if (userId.isEmpty()) {
        writeJsonError(400, "userId manquant");
        return;
    }
    if (samples < 1)  samples = 1;
    if (samples > 30) samples = 30;

    // Invocation cross-thread safe (AppController est sur le main thread,
    // on est aussi sur le main thread donc direct call OK).
    QMetaObject::invokeMethod(m_server->m_controller.data(), "startEnroll",
                              Qt::QueuedConnection,
                              Q_ARG(QString, userId),
                              Q_ARG(int, samples));

    QJsonObject out{
        {"started", true},
        {"userId", userId},
        {"samplesPerPose", samples},
    };
    writeResponse(200, QJsonDocument(out).toJson(QJsonDocument::Compact));
}

void HttpConnection::handleEnrollStatus()
{
    QJsonObject out;
    if (m_server->m_controller) {
        const QVariantMap status = m_server->m_controller->lastEnrollStatus();
        const QVariantMap result = m_server->m_controller->lastEnrollResult();
        out["status"] = QJsonValue::fromVariant(status);
        out["result"] = QJsonValue::fromVariant(result);
    } else {
        out["status"] = QJsonObject{};
        out["result"] = QJsonObject{};
    }
    writeResponse(200, QJsonDocument(out).toJson(QJsonDocument::Compact));
}

void HttpConnection::handleEnrollFinalize()
{
    if (!m_server->m_controller) {
        writeJsonError(500, "AppController non disponible");
        return;
    }
    QMetaObject::invokeMethod(m_server->m_controller.data(), "finalizeEnroll",
                              Qt::QueuedConnection);
    writeResponse(200, "{\"finalize\":\"requested\"}");
}

void HttpConnection::handleEnrollCancel()
{
    if (!m_server->m_controller) {
        writeJsonError(500, "AppController non disponible");
        return;
    }
    QMetaObject::invokeMethod(m_server->m_controller.data(), "cancelEnroll",
                              Qt::QueuedConnection);
    writeResponse(200, "{\"cancel\":\"requested\"}");
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

    // ── Lookup userId + collecte images (single field 'images') ───────────
    // Le front n'envoie pas la pose : Qt auto-classifie via landmarks YuNet
    // (cf. classifyPose() ci-dessus). On accepte aussi les anciens champs
    // 'images_<pose>' au cas ou (compat live future v2).
    QString userId;
    QList<QByteArray> allImages;
    QMap<QString, QList<QByteArray>> imagesByPose;  // si client fournit pose explicite
    for (const Part &p : parts) {
        const QString name = QString::fromLatin1(p.name);
        if (name == "userId") {
            userId = QString::fromUtf8(p.data).trimmed();
        } else if (name == "images") {
            allImages.append(p.data);
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
    if (allImages.isEmpty() && imagesByPose.isEmpty()) {
        writeJsonError(400, "Aucune image fournie");
        return;
    }
    if (allImages.size() > 20) {
        writeJsonError(413, "Max 20 images par enrolement");
        return;
    }

    // ── Charge modeles si pas encore fait ─────────────────────────────────
    if (!m_server->loadModels()) {
        writeJsonError(500, "Echec chargement modeles OpenCV");
        return;
    }

    // ── Extraction par image + auto-classification par pose ──────────────
    // Si le client a fourni 'images' (champ unique), on auto-classifie via
    // landmarks YuNet. Si le client a fourni 'images_<pose>' (mode legacy /
    // future v2 live), on respecte la pose fournie.
    QMap<QString, QVector<QVector<float>>> binsByPose;
    int totalValid = 0;
    int totalRejected = 0;

    auto processImage = [&](const QByteArray &raw, const QString &forcedPose) {
        std::vector<uchar> buf(reinterpret_cast<const uchar*>(raw.constData()),
                               reinterpret_cast<const uchar*>(raw.constData()) + raw.size());
        cv::Mat img;
        try {
            img = cv::imdecode(buf, cv::IMREAD_COLOR);
        } catch (const cv::Exception &e) {
            qWarning() << "[enroll-from-images] imdecode KO :" << e.what();
            totalRejected++;
            return;
        }
        if (img.empty()) {
            qWarning() << "[enroll-from-images] image vide / format inconnu";
            totalRejected++;
            return;
        }

        cv::Mat faces;
        try {
            m_server->m_detector->setInputSize({img.cols, img.rows});
            m_server->m_detector->detect(img, faces);
        } catch (const cv::Exception &e) {
            qWarning() << "[enroll-from-images] detect KO :" << e.what();
            totalRejected++;
            return;
        }
        if (faces.empty() || faces.rows == 0) {
            qDebug() << "[enroll-from-images] aucun visage detecte";
            totalRejected++;
            return;
        }
        const int idx = bestFaceIdx(faces);
        if (idx < 0) {
            qDebug() << "[enroll-from-images] aucun visage valide";
            totalRejected++;
            return;
        }

        const cv::Mat best = faces.row(idx);
        const QString pose = forcedPose.isEmpty() ? classifyPose(best) : forcedPose;

        cv::Mat aligned, feat;
        try {
            m_server->m_recognizer->alignCrop(img, best, aligned);
            m_server->m_recognizer->feature(aligned, feat);
        } catch (const cv::Exception &e) {
            qWarning() << "[enroll-from-images] feature KO :" << e.what();
            totalRejected++;
            return;
        }

        QVector<float> emb(static_cast<int>(feat.total()));
        for (int i = 0; i < emb.size(); i++) emb[i] = feat.at<float>(i);
        binsByPose[pose].append(emb);
        totalValid++;
    };

    {
        QMutexLocker l(&m_server->m_cvMutex);
        // Mode upload (champ 'images') : auto-classification
        for (const QByteArray &raw : allImages) processImage(raw, QString());
        // Mode legacy / v2 live (champ 'images_<pose>') : pose forcee
        for (auto it = imagesByPose.constBegin(); it != imagesByPose.constEnd(); ++it) {
            for (const QByteArray &raw : it.value()) processImage(raw, it.key());
        }
    }

    // ── Moyenne + normalisation L2 par pose ───────────────────────────────
    QJsonObject embeddings;
    QJsonObject poseCounts;
    for (auto it = binsByPose.constBegin(); it != binsByPose.constEnd(); ++it) {
        const auto &samples = it.value();
        if (samples.isEmpty()) continue;
        const int dim = samples[0].size();
        QVector<float> mean(dim, 0.0f);
        for (const auto &v : samples)
            for (int i = 0; i < dim; i++) mean[i] += v[i];
        for (float &x : mean) x /= samples.size();
        double norm = 0;
        for (float x : mean) norm += x * x;
        norm = std::sqrt(norm);
        if (norm > 1e-9) for (float &x : mean) x /= static_cast<float>(norm);

        QJsonArray arr;
        for (float x : mean) arr.append(static_cast<double>(x));
        embeddings[it.key()] = arr;
        poseCounts[it.key()] = samples.size();
    }

    if (embeddings.isEmpty()) {
        writeJsonError(422, "Aucun visage extrait des images fournies");
        return;
    }
    qDebug() << "[enroll-from-images] userId=" << userId
             << "poses=" << embeddings.keys()
             << "valides=" << totalValid
             << "rejetees=" << totalRejected;

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
