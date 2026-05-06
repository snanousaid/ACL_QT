#include "faceworker.h"
#include "framequeue.h"
#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QMutexLocker>
#include <QThread>

// ─────────────────────────────────────────────────────────────────────────────
// Poses
// ─────────────────────────────────────────────────────────────────────────────
namespace {
    const QStringList REQUIRED_POSES = { "center", "left", "right" };
    const QStringList OPTIONAL_POSES = { "up", "down" };
    const QStringList ACTIVE_POSES   = { "center", "left", "right", "up", "down" };

    QString poseLabel(const QString &id)
    {
        if (id == "center") return QStringLiteral("Face caméra");
        if (id == "left")   return QStringLiteral("Tourner à gauche");
        if (id == "right")  return QStringLiteral("Tourner à droite");
        if (id == "up")     return QStringLiteral("Lever la tête");
        if (id == "down")   return QStringLiteral("Baisser la tête");
        return id;
    }
}

#ifndef ACL_OPENCV_ENABLED
// ── Stub Windows / sans OpenCV ────────────────────────────────────────────────

FaceWorker::FaceWorker(FrameQueue *, const QString &, const QString &, QObject *parent)
    : QThread(parent), m_queue(nullptr) {}
FaceWorker::~FaceWorker() { stop(); wait(); }
void FaceWorker::stop()    { m_running.store(0); }
void FaceWorker::pause()   { QMutexLocker l(&m_mutex); m_mode = Paused; }
void FaceWorker::resume()  { QMutexLocker l(&m_mutex); m_mode = Detecting; }
void FaceWorker::startEnroll(const QString &, const QString &, int) {}
void FaceWorker::finalizeEnroll() {}
void FaceWorker::cancelEnroll()   {}
void FaceWorker::reloadDb()       {}
QVariantList FaceWorker::listUsers() const { return {}; }
void FaceWorker::toggleUser(const QString &) {}
void FaceWorker::deleteUser(const QString &) {}
QString FaceWorker::nextPoseToFill_locked() const { return QString(); }
bool    FaceWorker::allRequiredDone_locked() const { return false; }
QVariantMap FaceWorker::buildEnrollStatus_locked(bool) const { return {}; }

void FaceWorker::run()
{
    qDebug() << "[FaceWorker] OpenCV désactivé (build non-Linux)";
}

#else
// ── Implémentation Linux + OpenCV ─────────────────────────────────────────────
#include <opencv2/core.hpp>
#include <opencv2/objdetect.hpp>
#include <opencv2/imgproc.hpp>

// ── Helpers ───────────────────────────────────────────────────────────────────

static float frameBrightness(const cv::Mat &frame)
{
    cv::Mat hsv;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    return static_cast<float>(cv::mean(hsv)[2]);
}

// ≥70 % de la surface du visage doit être dans la ROI normalisée.
static bool faceInRoi(const cv::Mat &face, int fw, int fh,
                      float rx, float ry, float rw, float rh)
{
    float left   =  face.at<float>(0, 0)                       / fw;
    float top    =  face.at<float>(0, 1)                       / fh;
    float right  = (face.at<float>(0, 0) + face.at<float>(0, 2)) / fw;
    float bottom = (face.at<float>(0, 1) + face.at<float>(0, 3)) / fh;

    float roiRight  = rx + rw;
    float roiBottom = ry + rh;

    float interW = std::max(0.0f, std::min(right,  roiRight)  - std::max(left, rx));
    float interH = std::max(0.0f, std::min(bottom, roiBottom) - std::max(top,  ry));
    float interArea = interW * interH;
    float faceArea  = std::max(1e-9f, (right - left) * (bottom - top));
    return (interArea / faceArea) >= 0.70f;
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
    double norm = 0;
    for (float v : mean) norm += v * v;
    norm = std::sqrt(norm);
    if (norm > 1e-9) for (float &v : mean) v /= static_cast<float>(norm);
    return mean;
}

// Estime la pose (center / left / right / up / down / transition) depuis les
// 5 landmarks YuNet (yeux droit/gauche, nez, coins de bouche).
//   Ordre YuNet : [x,y,w,h, rex,rey, lex,ley, nx,ny, rmx,rmy, lmx,lmy, score]
static QString estimatePose(const cv::Mat &face)
{
    float rex = face.at<float>(0, 4),  rey = face.at<float>(0, 5);
    float lex = face.at<float>(0, 6),  ley = face.at<float>(0, 7);
    float nx  = face.at<float>(0, 8),  ny  = face.at<float>(0, 9);
    float rmy = face.at<float>(0, 11), lmy = face.at<float>(0, 13);

    float eye_cx   = (rex + lex) / 2.0f;
    float eye_cy   = (rey + ley) / 2.0f;
    float mouth_cy = (rmy + lmy) / 2.0f;
    float inter_eye = std::max(std::abs(lex - rex), 1.0f);

    float yaw = (nx - eye_cx) / inter_eye;
    float em  = mouth_cy - eye_cy;
    float pitch = (em > 1.0f) ? ((ny - eye_cy) / em - 0.5f) : 0.0f;

    if (std::abs(yaw) < 0.18f && std::abs(pitch) < 0.07f) return QStringLiteral("center");
    if (yaw < -0.30f && std::abs(pitch) < 0.20f)          return QStringLiteral("left");
    if (yaw >  0.30f && std::abs(pitch) < 0.20f)          return QStringLiteral("right");
    if (pitch < -0.06f && std::abs(yaw) < 0.30f)          return QStringLiteral("up");
    if (pitch >  0.08f && std::abs(yaw) < 0.30f)          return QStringLiteral("down");
    return QStringLiteral("transition");
}

// ── Constructeur / Destructeur ────────────────────────────────────────────────

FaceWorker::FaceWorker(FrameQueue *queue,
                       const QString &dbPath,
                       const QString &modelsDir,
                       QObject *parent)
    : QThread(parent), m_queue(queue), m_dbPath(dbPath), m_modelsDir(modelsDir)
{
    QDir().mkpath(QFileInfo(m_dbPath).absolutePath());
    m_db.load(m_dbPath);
    qDebug() << "[FaceWorker] DB chargée —" << m_db.count() << "utilisateurs";
}

FaceWorker::~FaceWorker()
{
    stop();
    wait();
}

// ── Contrôle ──────────────────────────────────────────────────────────────────

void FaceWorker::stop()   { m_running.store(0); }
void FaceWorker::pause()  { QMutexLocker l(&m_mutex); m_mode = Paused; }
void FaceWorker::resume() { QMutexLocker l(&m_mutex); m_mode = Detecting; }

void FaceWorker::startEnroll(const QString &name, const QString &role, int samplesPerPose)
{
    QMutexLocker l(&m_mutex);
    m_enrollName              = name;
    m_enrollRole              = role;
    m_enrollSamplesTarget     = qMax(1, samplesPerPose);
    m_enrollBins.clear();
    for (const QString &p : ACTIVE_POSES) m_enrollBins.insert(p, {});
    m_enrollCurrentPose       = QStringLiteral("transition");
    m_enrollLastMsg           = QString();
    m_enrollFinalizeRequested = false;
    m_enrollLastSampleMs      = 0;
    m_mode                    = Enrolling;
    qDebug() << "[FaceWorker] enrollment démarré pour" << name
             << "—" << samplesPerPose << "samples/pose";
}

void FaceWorker::finalizeEnroll()
{
    QMutexLocker l(&m_mutex);
    m_enrollFinalizeRequested = true;
}

void FaceWorker::cancelEnroll()
{
    QMutexLocker l(&m_mutex);
    m_enrollBins.clear();
    m_enrollFinalizeRequested = false;
    m_mode = Detecting;
    qDebug() << "[FaceWorker] enrollment annulé";
}

void FaceWorker::reloadDb()
{
    QMutexLocker l(&m_mutex);
    m_db.load(m_dbPath);
    qDebug() << "[FaceWorker] DB rechargée —" << m_db.count() << "utilisateurs";
}

// ── DB ────────────────────────────────────────────────────────────────────────

QVariantList FaceWorker::listUsers() const
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

void FaceWorker::toggleUser(const QString &name)
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

void FaceWorker::deleteUser(const QString &name)
{
    QMutexLocker l(&m_mutex);
    m_db.remove(name);
    m_db.save(m_dbPath);
}

// ── Helpers enrôlement (mutex tenu) ───────────────────────────────────────────

QString FaceWorker::nextPoseToFill_locked() const
{
    for (const QString &p : REQUIRED_POSES) {
        if (m_enrollBins.value(p).size() < m_enrollSamplesTarget) return p;
    }
    for (const QString &p : OPTIONAL_POSES) {
        if (m_enrollBins.value(p).size() < m_enrollSamplesTarget) return p;
    }
    return QString();
}

bool FaceWorker::allRequiredDone_locked() const
{
    for (const QString &p : REQUIRED_POSES) {
        if (m_enrollBins.value(p).size() < m_enrollSamplesTarget) return false;
    }
    return true;
}

QVariantMap FaceWorker::buildEnrollStatus_locked(bool inRoi) const
{
    QVariantMap status;
    status[QStringLiteral("in_roi")]       = inRoi;
    status[QStringLiteral("phase")]        = QStringLiteral("enrolling");
    status[QStringLiteral("enroll_msg")]   = m_enrollLastMsg;
    status[QStringLiteral("enroll_name")]  = m_enrollName;
    status[QStringLiteral("enroll_current_pose")] = m_enrollCurrentPose;
    status[QStringLiteral("enroll_next")]  = nextPoseToFill_locked();
    status[QStringLiteral("enroll_complete")] = allRequiredDone_locked();

    QVariantList poses;
    for (const QString &p : ACTIVE_POSES) {
        QVariantMap pose;
        pose[QStringLiteral("id")]       = p;
        pose[QStringLiteral("label")]    = poseLabel(p);
        pose[QStringLiteral("count")]    = m_enrollBins.value(p).size();
        pose[QStringLiteral("target")]   = m_enrollSamplesTarget;
        pose[QStringLiteral("done")]     = m_enrollBins.value(p).size() >= m_enrollSamplesTarget;
        pose[QStringLiteral("required")] = REQUIRED_POSES.contains(p);
        poses.append(pose);
    }
    status[QStringLiteral("enroll_poses")] = poses;
    return status;
}

// ── Boucle principale ─────────────────────────────────────────────────────────

void FaceWorker::run()
{
    qDebug() << "[FaceWorker] démarrage — détection + reconnaissance + enrôlement multi-poses";

    if (!m_queue) {
        qDebug() << "[FaceWorker] ERREUR : pas de FrameQueue";
        return;
    }

    // ── Modèles ────────────────────────────────────────────────────────────────
    std::string yunet = (m_modelsDir + "/face_detection_yunet_2022mar.onnx").toStdString();
    std::string sface = (m_modelsDir + "/face_recognition_sface_2021dec.onnx").toStdString();

    cv::Ptr<cv::FaceDetectorYN>  detector;
    cv::Ptr<cv::FaceRecognizerSF> recognizer;
    try {
        detector   = cv::FaceDetectorYN::create(yunet, "", {640, 480},
                                                 SCORE_THRESH, NMS_THRESH, 50);
        recognizer = cv::FaceRecognizerSF::create(sface, "");
    } catch (const cv::Exception &e) {
        qDebug() << "[FaceWorker] ERREUR modèles :" << e.what();
        return;
    }
    qDebug() << "[FaceWorker] modèles chargés — OK";

    m_running.store(1);

    // ── Optim CPU ──────────────────────────────────────────────────────────────
    // 1. Motion gating  : skip total si pas de mouvement (idle)
    // 2. Rate limiting  : 3 FPS idle, 10 FPS actif (frame skipping)
    // 3. Downscale      : YuNet sur 0.5× (4× moins de pixels)
    // 4. SFace cooldown : ne pas re-matcher 30×/s le même visage stable
    constexpr float   MOTION_THRESH       = 0.008f;   // 0.8 % pixels changés
    constexpr int     IDLE_INTERVAL       = 10;       // ~3 FPS si caméra 30 FPS
    constexpr int     ACTIVE_INTERVAL     = 3;        // ~10 FPS
    constexpr qint64  IDLE_TIMEOUT_MS     = 2000;
    constexpr qint64  SFACE_COOLDOWN_MS   = 2000;
    constexpr int     SFACE_BBOX_TOL_PX   = 40;
    constexpr float   DETECT_SCALE        = 0.5f;

    cv::Mat frame, faces, aligned, feat;
    cv::Mat prevGray, smallFrame, gray;

    qint64  lastEventMs   = 0;
    QString lastEventName;
    qint64  lastFaceMs    = 0;
    qint64  lastSFaceMs   = 0;
    cv::Rect lastFaceBox;
    QString lastMatchName;
    bool    lastMatchActive = false;
    float   lastMatchScore  = 0.0f;
    int     frameCounter    = 0;

    while (m_running.load()) {
        if (!m_queue->pop(frame, 200)) continue;
        if (frame.empty()) continue;
        frameCounter++;

        // ── Mode courant ────────────────────────────────────────────────────────
        Mode currentMode;
        { QMutexLocker l(&m_mutex); currentMode = m_mode; }

        if (currentMode == Paused) {
            QThread::msleep(50);
            continue;
        }

        const qint64 nowMs    = QDateTime::currentMSecsSinceEpoch();
        const bool   enrolling = (currentMode == Enrolling);
        const bool   isIdle    = !enrolling && (nowMs - lastFaceMs > IDLE_TIMEOUT_MS);

        // ── (1) Motion gate + (proxy luminosité sur la même grayscale) ──────────
        // Une seule conversion BGR→gray downscalée 80×60, réutilisée pour le
        // diff de mouvement ET le check luminosité. ~0.5 ms vs ~5 ms full-res HSV.
        cv::resize(frame, gray, cv::Size(80, 60), 0, 0, cv::INTER_AREA);
        cv::cvtColor(gray, gray, cv::COLOR_BGR2GRAY);

        float bright = static_cast<float>(cv::mean(gray)[0]);
        if (bright < BRIGHT_MIN || bright > BRIGHT_MAX) {
            prevGray = gray.clone();
            emit faceStatusChanged(false, false, false);
            continue;
        }

        bool motion = true;
        if (!prevGray.empty()) {
            cv::Mat diff;
            cv::absdiff(gray, prevGray, diff);
            cv::threshold(diff, diff, 25, 255, cv::THRESH_BINARY);
            float ratio = static_cast<float>(cv::countNonZero(diff))
                          / static_cast<float>(gray.rows * gray.cols);
            motion = ratio > MOTION_THRESH;
        }
        prevGray = gray.clone();

        // En idle sans mouvement → skip total (le plus gros gain CPU)
        if (isIdle && !motion) {
            emit faceStatusChanged(false, false, false);
            continue;
        }

        // ── (2) Rate limiting ───────────────────────────────────────────────────
        const int interval = enrolling ? 1
                                       : (isIdle ? IDLE_INTERVAL : ACTIVE_INTERVAL);
        if (frameCounter % interval != 0) continue;

        // ── (3) Détection YuNet sur frame downscalée ────────────────────────────
        cv::resize(frame, smallFrame, cv::Size(), DETECT_SCALE, DETECT_SCALE,
                   cv::INTER_LINEAR);
        detector->setInputSize({smallFrame.cols, smallFrame.rows});
        detector->detect(smallFrame, faces);

        // Remap coords (cols 0..13 = bbox + 5 landmarks) vers full-res pour SFace
        if (!faces.empty() && faces.rows > 0) {
            const float invScale = 1.0f / DETECT_SCALE;
            for (int i = 0; i < faces.rows; i++)
                for (int j = 0; j < 14; j++)
                    faces.at<float>(i, j) *= invScale;
        }

        bool hasFace = (!faces.empty() && faces.rows > 0);
        bool inRoi   = false;
        bool matched = false;

        if (hasFace) lastFaceMs = nowMs;

        if (hasFace) {
            cv::Mat best = faces.row(bestFaceIdx(faces));
            inRoi = faceInRoi(best, frame.cols, frame.rows,
                              ROI_X, ROI_Y, ROI_W, ROI_H);

            if (inRoi) {
                if (currentMode == Enrolling) {
                    // ── Mode enrôlement multi-pose ─────────────────────────────
                    // Embedding requis pour stocker les samples.
                    QVector<float> emb;
                    try {
                        recognizer->alignCrop(frame, best, aligned);
                        recognizer->feature(aligned, feat);
                        emb = matToVector(feat);
                    } catch (const cv::Exception &e) {
                        qDebug() << "[FaceWorker] embed error:" << e.what();
                        emit faceStatusChanged(hasFace, inRoi, false);
                        continue;
                    }

                    float yunetScore = best.at<float>(0, 14);
                    float faceWidth  = best.at<float>(0, 2);

                    QString pose = estimatePose(best);

                    bool finalizeNow = false;
                    bool requiredDone = false;
                    QString enrollName, enrollRole;
                    QMap<QString, QVector<QVector<float>>> binsCopy;
                    QVariantMap statusMap;

                    {
                        QMutexLocker l(&m_mutex);
                        m_enrollCurrentPose = pose;

                        // Filtres qualité
                        if (yunetScore < ENROLL_MIN_SCORE) {
                            m_enrollLastMsg = QStringLiteral("score trop faible");
                        } else if (faceWidth < ENROLL_MIN_WIDTH) {
                            m_enrollLastMsg = QStringLiteral("trop loin");
                        } else if ((nowMs - m_enrollLastSampleMs) < ENROLL_INTERVAL_MS) {
                            // trop rapide, pas de message
                        } else if (pose == "transition" || !ACTIVE_POSES.contains(pose)) {
                            m_enrollLastMsg = QStringLiteral("pose intermédiaire");
                        } else {
                            QVector<QVector<float>> &bucket = m_enrollBins[pose];
                            if (bucket.size() >= m_enrollSamplesTarget) {
                                m_enrollLastMsg = QStringLiteral("pose '%1' complète")
                                                  .arg(poseLabel(pose));
                            } else {
                                bucket.append(emb);
                                m_enrollLastSampleMs = nowMs;
                                m_enrollLastMsg = QStringLiteral("+1 %1 (%2/%3)")
                                                  .arg(pose)
                                                  .arg(bucket.size())
                                                  .arg(m_enrollSamplesTarget);
                            }
                        }

                        statusMap     = buildEnrollStatus_locked(true);
                        finalizeNow   = m_enrollFinalizeRequested;
                        requiredDone  = allRequiredDone_locked();
                        enrollName    = m_enrollName;
                        enrollRole    = m_enrollRole;
                        binsCopy      = m_enrollBins;
                    }

                    emit enrollProgress(statusMap);

                    if (finalizeNow) {
                        if (!requiredDone) {
                            // refuse — poses obligatoires manquantes
                            QStringList missing;
                            for (const QString &p : REQUIRED_POSES) {
                                if (binsCopy.value(p).size() < m_enrollSamplesTarget)
                                    missing.append(poseLabel(p));
                            }
                            {
                                QMutexLocker l(&m_mutex);
                                m_enrollBins.clear();
                                m_enrollFinalizeRequested = false;
                                m_mode = Detecting;
                            }
                            emit enrollFinished(false,
                                QStringLiteral("Poses manquantes : %1").arg(missing.join(", ")));
                            qDebug() << "[FaceWorker] enrôlement refusé — manque :" << missing;
                        } else {
                            // moyenne globale (toutes poses confondues)
                            QVector<QVector<float>> all;
                            for (const QString &p : ACTIVE_POSES)
                                for (const auto &s : binsCopy.value(p)) all.append(s);

                            QVector<float> meanEmb = meanEmbedding(all);
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
                                    m_enrollBins.clear();
                                    m_enrollFinalizeRequested = false;
                                    m_mode = Detecting;
                                }
                                emit enrollFinished(true,
                                    QStringLiteral("%1 enrôlé(e) (%2 échantillons)")
                                        .arg(enrollName).arg(all.size()));
                                qDebug() << "[FaceWorker] enrôlé :" << enrollName
                                         << "—" << all.size() << "samples";
                            }
                        }
                    }
                } else {
                    // ── Mode détection — match + événement ─────────────────────
                    // (4) SFace cooldown : si même visage à la même position
                    // depuis <2 s, on réutilise le dernier match au lieu de
                    // refaire alignCrop+feature+match (le plus coûteux).
                    cv::Rect curBox(static_cast<int>(best.at<float>(0, 0)),
                                    static_cast<int>(best.at<float>(0, 1)),
                                    static_cast<int>(best.at<float>(0, 2)),
                                    static_cast<int>(best.at<float>(0, 3)));
                    bool sameFace = (lastFaceBox.width > 0)
                                 && std::abs(curBox.x - lastFaceBox.x) < SFACE_BBOX_TOL_PX
                                 && std::abs(curBox.y - lastFaceBox.y) < SFACE_BBOX_TOL_PX;
                    bool sfaceFresh = (nowMs - lastSFaceMs) < SFACE_COOLDOWN_MS;

                    QString name;
                    float   score  = 0.0f;
                    bool    active = true;

                    if (sameFace && sfaceFresh && !lastMatchName.isEmpty()) {
                        // Cooldown actif → on skip alignCrop+feature+match
                        name   = lastMatchName;
                        score  = lastMatchScore;
                        active = lastMatchActive;
                    } else {
                        // Pas de cooldown → calcul embedding + match
                        QVector<float> emb;
                        try {
                            recognizer->alignCrop(frame, best, aligned);
                            recognizer->feature(aligned, feat);
                            emb = matToVector(feat);
                        } catch (const cv::Exception &e) {
                            qDebug() << "[FaceWorker] embed error:" << e.what();
                            emit faceStatusChanged(hasFace, inRoi, false);
                            continue;
                        }
                        {
                            QMutexLocker l(&m_mutex);
                            name = m_db.match(emb, MATCH_THRESH, &score, &active);
                        }
                        lastSFaceMs     = nowMs;
                        lastFaceBox     = curBox;
                        lastMatchName   = name;
                        lastMatchScore  = score;
                        lastMatchActive = active;
                    }
                    matched = !name.isEmpty() && active;

                    if (!name.isEmpty()) {
                        bool eventCooldown = (nowMs - lastEventMs > COOLDOWN_MS)
                                          || (name != lastEventName);
                        if (eventCooldown) {
                            lastEventMs   = nowMs;
                            lastEventName = name;
                            if (active)
                                emit accessGranted(name, score);
                            else
                                emit accessDenied(name, score);
                        }
                    }
                }
            }
        }

        emit faceStatusChanged(hasFace, inRoi, matched);
    }

    qDebug() << "[FaceWorker] arrêté";
}

#endif // ACL_OPENCV_ENABLED
