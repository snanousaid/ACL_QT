#include "cameraworker.h"
#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QMutexLocker>

// ── Stub Windows (sans OpenCV) ────────────────────────────────────────────────
#ifndef ACL_OPENCV_ENABLED

CameraWorker::CameraWorker(QObject *parent) : QThread(parent) {}
CameraWorker::~CameraWorker() { stop(); wait(); }
void CameraWorker::stop()    { m_running.store(0); }
void CameraWorker::pause()   { QMutexLocker l(&m_mutex); m_mode = Paused; }
void CameraWorker::resume()  { QMutexLocker l(&m_mutex); m_mode = Detecting; }
void CameraWorker::startEnroll(const QString &, const QString &, int) {}
void CameraWorker::finalizeEnroll() {}
void CameraWorker::cancelEnroll()   {}
void CameraWorker::reloadDb()       {}

QVariantList CameraWorker::listUsers() const { return {}; }
void CameraWorker::toggleUser(const QString &) {}
void CameraWorker::deleteUser(const QString &) {}

void CameraWorker::run()
{
    qDebug() << "[CameraWorker] OpenCV désactivé (build non-Linux)";
}

#else  // ACL_OPENCV_ENABLED

#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/objdetect.hpp>
#include <opencv2/imgproc.hpp>

// ── Helpers ───────────────────────────────────────────────────────────────────

static float frameBrightness(const cv::Mat &frame)
{
    cv::Mat hsv;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    return static_cast<float>(cv::mean(hsv)[2]);
}

static bool faceInRoi(const cv::Mat &face, int fw, int fh,
                      float rx, float ry, float rw, float rh)
{
    float cx = face.at<float>(0, 0) + face.at<float>(0, 2) * 0.5f;
    float cy = face.at<float>(0, 1) + face.at<float>(0, 3) * 0.5f;
    return cx >= rx * fw && cx <= (rx + rw) * fw
        && cy >= ry * fh && cy <= (ry + rh) * fh;
}

static int bestFaceIdx(const cv::Mat &faces)
{
    int   idx  = 0;
    float best = 0;
    for (int i = 0; i < faces.rows; i++) {
        float area = faces.at<float>(i, 2) * faces.at<float>(i, 3);
        if (area > best) { best = area; idx = i; }
    }
    return idx;
}

static QVector<float> matToVector(const cv::Mat &m)
{
    QVector<float> v(static_cast<int>(m.total()));
    for (int i = 0; i < v.size(); i++)
        v[i] = m.at<float>(i);
    return v;
}

static QVector<float> meanEmbedding(const QVector<QVector<float>> &samples)
{
    if (samples.isEmpty()) return {};
    int dim = samples[0].size();
    QVector<float> mean(dim, 0.0f);
    for (const auto &s : samples)
        for (int i = 0; i < dim; i++) mean[i] += s[i];
    for (float &v : mean) v /= samples.size();
    // L2-normalise
    double norm = 0;
    for (float v : mean) norm += v * v;
    norm = std::sqrt(norm);
    if (norm > 1e-9) for (float &v : mean) v /= static_cast<float>(norm);
    return mean;
}

// ── Constructeur / Destructeur ────────────────────────────────────────────────

CameraWorker::CameraWorker(QObject *parent)
    : QThread(parent)
{
    QDir().mkpath(QStringLiteral("/opt/ACL_qt/embeddings"));
    m_db.load(m_dbPath);
    qDebug() << "[CameraWorker] DB chargée —" << m_db.count() << "utilisateurs";
}

CameraWorker::~CameraWorker()
{
    stop();
    wait();
}

// ── Contrôle (thread-safe) ────────────────────────────────────────────────────

void CameraWorker::stop()   { m_running.store(0); }
void CameraWorker::pause()  { QMutexLocker l(&m_mutex); m_mode = Paused; }
void CameraWorker::resume() { QMutexLocker l(&m_mutex); m_mode = Detecting; }

void CameraWorker::startEnroll(const QString &name, const QString &role, int samplesPerPose)
{
    QMutexLocker l(&m_mutex);
    m_enrollName            = name;
    m_enrollRole            = role;
    m_enrollSamplesTarget   = qMax(1, samplesPerPose);
    m_enrollSamples.clear();
    m_enrollFinalizeRequested = false;
    m_mode = Enrolling;
    qDebug() << "[CameraWorker] enrollment démarré pour" << name;
}

void CameraWorker::finalizeEnroll()
{
    QMutexLocker l(&m_mutex);
    m_enrollFinalizeRequested = true;
}

void CameraWorker::cancelEnroll()
{
    QMutexLocker l(&m_mutex);
    m_enrollSamples.clear();
    m_enrollFinalizeRequested = false;
    m_mode = Detecting;
    qDebug() << "[CameraWorker] enrollment annulé";
}

void CameraWorker::reloadDb()
{
    QMutexLocker l(&m_mutex);
    m_db.load(m_dbPath);
    qDebug() << "[CameraWorker] DB rechargée —" << m_db.count() << "utilisateurs";
}

// ── Gestion DB (QML side) ─────────────────────────────────────────────────────

QVariantList CameraWorker::listUsers() const
{
    QMutexLocker l(&m_mutex);
    QVariantList result;
    for (const auto &pair : m_db.entries()) {
        QVariantMap u;
        u[QStringLiteral("name")]       = pair.first;
        u[QStringLiteral("role")]       = pair.second.role;
        u[QStringLiteral("active")]     = pair.second.active;
        u[QStringLiteral("dim")]        = !pair.second.active;
        u[QStringLiteral("created_at")] = pair.second.createdAt;
        result.append(u);
    }
    return result;
}

void CameraWorker::toggleUser(const QString &name)
{
    QMutexLocker l(&m_mutex);
    for (const auto &pair : m_db.entries()) {
        if (pair.first == name) {
            m_db.setActive(name, !pair.second.active);
            m_db.save(m_dbPath);
            return;
        }
    }
}

void CameraWorker::deleteUser(const QString &name)
{
    QMutexLocker l(&m_mutex);
    m_db.remove(name);
    m_db.save(m_dbPath);
}

// ── Boucle principale ─────────────────────────────────────────────────────────

void CameraWorker::run()
{
    qDebug() << "[CameraWorker] démarrage";

    // ── Caméra ─────────────────────────────────────────────────────────────────
    cv::VideoCapture cap(0, cv::CAP_V4L2);
    if (!cap.isOpened()) cap.open(0, cv::CAP_ANY);
    if (!cap.isOpened()) {
        qDebug() << "[CameraWorker] ERREUR : impossible d'ouvrir la caméra";
        return;
    }
    cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter_fourcc('M','J','P','G'));
    cap.set(cv::CAP_PROP_FRAME_WIDTH,  CAM_W);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, CAM_H);
    cap.set(cv::CAP_PROP_FPS,          CAM_FPS);
    cap.set(cv::CAP_PROP_BUFFERSIZE,   1);

    // ── Modèles ────────────────────────────────────────────────────────────────
    std::string yunet = (m_modelsDir + "/face_detection_yunet_2022mar.onnx").toStdString();
    std::string sface = (m_modelsDir + "/face_recognition_sface_2021dec.onnx").toStdString();

    cv::Ptr<cv::FaceDetectorYN>  detector;
    cv::Ptr<cv::FaceRecognizerSF> recognizer;
    try {
        detector   = cv::FaceDetectorYN::create(yunet, "", {CAM_W, CAM_H},
                                                 SCORE_THRESH, NMS_THRESH, 50);
        recognizer = cv::FaceRecognizerSF::create(sface, "");
    } catch (const cv::Exception &e) {
        qDebug() << "[CameraWorker] ERREUR modèles :" << e.what();
        cap.release();
        return;
    }
    qDebug() << "[CameraWorker] modèles chargés — OK";

    m_running.store(1);

    cv::Mat frame, faces, aligned, feat;
    int    frameCount   = 0;
    qint64 lastEventMs  = 0;
    QString lastEventName;

    while (m_running.load()) {

        cap >> frame;
        if (frame.empty()) { QThread::msleep(10); continue; }
        frameCount++;

        // ── Mode courant ────────────────────────────────────────────────────────
        Mode currentMode;
        { QMutexLocker l(&m_mutex); currentMode = m_mode; }

        if (currentMode == Paused) {
            // Émettre la frame même en pause (admin menu)
            cv::Mat rgb; cv::cvtColor(frame, rgb, cv::COLOR_BGR2RGB);
            emit frameReady(QImage(rgb.data, rgb.cols, rgb.rows,
                                   static_cast<int>(rgb.step),
                                   QImage::Format_RGB888).copy());
            QThread::msleep(66);
            continue;
        }

        // ── Luminosité ──────────────────────────────────────────────────────────
        float bright = frameBrightness(frame);
        if (bright < BRIGHT_MIN || bright > BRIGHT_MAX) {
            emit faceStatusChanged(false, false, false);
            cv::Mat rgb; cv::cvtColor(frame, rgb, cv::COLOR_BGR2RGB);
            emit frameReady(QImage(rgb.data, rgb.cols, rgb.rows,
                                   static_cast<int>(rgb.step),
                                   QImage::Format_RGB888).copy());
            QThread::msleep(33);
            continue;
        }

        // ── Détection (toutes les DETECT_EVERY_N frames) ────────────────────────
        if (frameCount % DETECT_EVERY_N == 0) {
            detector->setInputSize({frame.cols, frame.rows});
            detector->detect(frame, faces);
        }

        bool hasFace  = (!faces.empty() && faces.rows > 0);
        bool inRoi    = false;
        bool matched  = false;

        if (hasFace) {
            cv::Mat best = faces.row(bestFaceIdx(faces));
            inRoi = faceInRoi(best, frame.cols, frame.rows,
                              ROI_X, ROI_Y, ROI_W, ROI_H);

            if (inRoi) {
                // ── Extraction embedding ────────────────────────────────────────
                QVector<float> emb;
                try {
                    recognizer->alignCrop(frame, best, aligned);
                    recognizer->feature(aligned, feat);
                    emb = matToVector(feat);
                } catch (const cv::Exception &e) {
                    qDebug() << "[CameraWorker] embed error:" << e.what();
                    goto emit_frame;
                }

                if (currentMode == Enrolling) {
                    // ── Mode enrôlement ─────────────────────────────────────────
                    bool finalizeNow = false;
                    QString enrollName, enrollRole;
                    int samplesTarget, samplesCount;

                    {
                        QMutexLocker l(&m_mutex);
                        m_enrollSamples.append(emb);
                        samplesCount  = m_enrollSamples.size();
                        samplesTarget = m_enrollSamplesTarget;
                        enrollName    = m_enrollName;
                        enrollRole    = m_enrollRole;
                        finalizeNow   = m_enrollFinalizeRequested
                                     || (samplesCount >= samplesTarget);
                    }

                    // Émettre la progression
                    QVariantMap status;
                    status[QStringLiteral("in_roi")]        = true;
                    status[QStringLiteral("phase")]         = QStringLiteral("enrolling");
                    status[QStringLiteral("current_pose")]  = QStringLiteral("center");
                    status[QStringLiteral("samples")]       = samplesCount;
                    status[QStringLiteral("samples_target")]= samplesTarget;
                    emit enrollProgress(status);

                    if (finalizeNow) {
                        // Moyenne + sauvegarde
                        QVector<float> meanEmb;
                        {
                            QMutexLocker l(&m_mutex);
                            meanEmb = meanEmbedding(m_enrollSamples);
                        }
                        if (meanEmb.isEmpty()) {
                            emit enrollFinished(false, QStringLiteral("Pas d'embedding"));
                        } else {
                            FaceEntry entry;
                            entry.embedding = meanEmb;
                            entry.role      = enrollRole;
                            entry.active    = true;
                            entry.createdAt = QDateTime::currentDateTime()
                                                .toString(Qt::ISODate);
                            {
                                QMutexLocker l(&m_mutex);
                                m_db.insert(enrollName, entry);
                                m_db.save(m_dbPath);
                                m_enrollSamples.clear();
                                m_enrollFinalizeRequested = false;
                                m_mode = Detecting;
                            }
                            emit enrollFinished(true,
                                QStringLiteral("%1 enrôlé(e)").arg(enrollName));
                            qDebug() << "[CameraWorker] enrôlé :" << enrollName;
                        }
                    }

                } else {
                    // ── Mode détection — match + événement ─────────────────────
                    float   score    = 0.0f;
                    QString name;
                    {
                        QMutexLocker l(&m_mutex);
                        name = m_db.match(emb, MATCH_THRESH, &score);
                    }
                    matched = !name.isEmpty();

                    qint64 now      = QDateTime::currentMSecsSinceEpoch();
                    bool   cooldown = (now - lastEventMs > COOLDOWN_MS)
                                   || (name != lastEventName);

                    if (cooldown) {
                        lastEventMs   = now;
                        lastEventName = name;
                        if (matched)
                            emit accessGranted(name, score);
                        else
                            emit accessDenied(QStringLiteral("unknown"), score);
                    }
                }
            }
        }

        emit faceStatusChanged(hasFace, inRoi, matched);

        emit_frame:
        // ── Conversion BGR → RGB → QImage ──────────────────────────────────────
        cv::Mat rgb;
        cv::cvtColor(frame, rgb, cv::COLOR_BGR2RGB);
        emit frameReady(QImage(rgb.data, rgb.cols, rgb.rows,
                               static_cast<int>(rgb.step),
                               QImage::Format_RGB888).copy());

        QThread::msleep(16); // ~60 fps max
    }

    cap.release();
    qDebug() << "[CameraWorker] arrêté";
}

#endif // ACL_OPENCV_ENABLED
