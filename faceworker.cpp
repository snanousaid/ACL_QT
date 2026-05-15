#include "faceworker.h"
#include "framequeue.h"
#include <QDebug>
#include <QDateTime>
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

FaceWorker::FaceWorker(FrameQueue *, const QString &, QObject *parent)
    : QThread(parent), m_queue(nullptr) {}
FaceWorker::~FaceWorker() { stop(); wait(); }
void FaceWorker::stop()    { m_running.store(0); }
void FaceWorker::pause()   { QMutexLocker l(&m_mutex); m_mode = Paused; }
void FaceWorker::resume()  { QMutexLocker l(&m_mutex); m_mode = Detecting; }
void FaceWorker::startEnroll(const QString &, int) {}
void FaceWorker::finalizeEnroll() {}
void FaceWorker::cancelEnroll()   {}
void FaceWorker::setEnrollResult(bool, const QString &) {}
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

// Validation géométrique d'un visage YuNet — filtre faux positifs (mains, etc.).
// Vérifie : aspect ratio, yeux au-dessus de la bouche, yeux horizontaux,
// écart inter-yeux cohérent, nez positionné entre yeux et bouche.
// face : 1×15 (x,y,w,h, rex,rey, lex,ley, nx,ny, rmx,rmy, lmx,lmy, score)
static bool isValidFace(const cv::Mat &face)
{
    float w = face.at<float>(0, 2);
    float h = face.at<float>(0, 3);
    if (w <= 0 || h <= 0) return false;

    // (1) Aspect ratio W/H : visage entre 0.6 et 1.3 (mains très elongees rejetees)
    float ratio = w / h;
    if (ratio < 0.6f || ratio > 1.3f) return false;

    float rex = face.at<float>(0, 4),  rey = face.at<float>(0, 5);
    float lex = face.at<float>(0, 6),  ley = face.at<float>(0, 7);
    float nx  = face.at<float>(0, 8),  ny  = face.at<float>(0, 9);
    float rmy = face.at<float>(0, 11), lmy = face.at<float>(0, 13);

    float eye_cx   = (rex + lex) / 2.0f;
    float eye_cy   = (rey + ley) / 2.0f;
    float mouth_cy = (rmy + lmy) / 2.0f;

    // (2) Yeux au-dessus de la bouche
    if (eye_cy >= mouth_cy) return false;

    // (3) Yeux à peu près horizontaux : |Δy| < 30% de l'écart inter-yeux
    float eye_dx = std::abs(lex - rex);
    if (eye_dx < 1e-3f) return false;
    if (std::abs(ley - rey) / eye_dx > 0.30f) return false;

    // (4) Écart inter-yeux entre 25 % et 60 % de la largeur du visage
    float eye_ratio = eye_dx / w;
    if (eye_ratio < 0.25f || eye_ratio > 0.60f) return false;

    // (5) Nez verticalement entre les yeux et la bouche (tolérance 5 % de h)
    if (ny < eye_cy - 0.05f * h || ny > mouth_cy + 0.05f * h) return false;

    // (6) Nez horizontalement entre les yeux (tolérance 40 % de l'écart inter-yeux)
    if (std::abs(nx - eye_cx) > 0.40f * eye_dx) return false;

    return true;
}

// Renvoie l'index du plus grand visage VALIDE, ou -1 si aucun.
static int bestFaceIdx(const cv::Mat &faces)
{
    int   idx  = -1;
    float best = 0;
    for (int i = 0; i < faces.rows; i++) {
        if (!isValidFace(faces.row(i))) continue;
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
                       const QString &modelsDir,
                       QObject *parent)
    : QThread(parent), m_queue(queue), m_modelsDir(modelsDir)
{
    qDebug() << "[FaceWorker] init — DB cote backend (REST)";
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

void FaceWorker::startEnroll(const QString &userId, int samplesPerPose)
{
    QMutexLocker l(&m_mutex);
    m_enrollUserId            = userId;
    m_enrollSamplesTarget     = qMax(1, samplesPerPose);
    m_enrollBins.clear();
    for (const QString &p : ACTIVE_POSES) m_enrollBins.insert(p, {});
    m_enrollCurrentPose       = QStringLiteral("transition");
    m_enrollLastMsg           = QString();
    m_enrollFinalizeRequested = false;
    m_enrollLastSampleMs      = 0;
    m_mode                    = Enrolling;
    qDebug() << "[FaceWorker] enrollment demarre userId=" << userId
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
    qDebug() << "[FaceWorker] enrollment annule";
}

// Slot appele par AppController apres reponse REST POST /face/enroll
void FaceWorker::setEnrollResult(bool ok, const QString &msg)
{
    emit enrollFinished(ok, msg);
}

// (DB locale supprimee — listUsers/toggleUser/deleteUser/reloadDb sont
//  desormais cote AppController via endpoints REST /face/profiles)

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
    status[QStringLiteral("enroll_user_id")] = m_enrollUserId;
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
    // Apres un event d'acces, on freeze toute detection pendant 5s :
    // - evite spam events sur visage stable
    // - economise CPU pendant que l'AccessCard est affichee
    constexpr qint64  EVENT_FREEZE_MS     = 5000;
    // (Vote 2/3 + scoring Anonyme : geres cote backend desormais)

    cv::Mat frame, faces, aligned, feat;
    cv::Mat prevGray, smallFrame, gray;

    qint64  eventFreezeUntilMs = 0;     // freeze post-event (cooldown global)
    qint64  lastFaceMs    = 0;
    qint64  lastSFaceMs   = 0;
    cv::Rect lastFaceBox;
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

        // ── Event freeze : apres un emit accessGranted/Denied, on stoppe
        //    toute detection pendant EVENT_FREEZE_MS (5s) pour eviter spam
        //    et economiser CPU pendant que l'AccessCard est visible.
        //    L'enrollement ignore le freeze (responsivite requise).
        if (!enrolling && nowMs < eventFreezeUntilMs) {
            QThread::msleep(100);
            continue;
        }

        // ── Finalize enrolement (independant de la detection de visage) ────────
        // Si l'utilisateur clique 'Valider' alors qu'il a deja capture les
        // poses requises, la finalisation se fait IMMEDIATEMENT — peu importe
        // s'il y a un visage actuellement dans la ROI.
        bool finalizePending = false;
        if (enrolling) {
            QMutexLocker l(&m_mutex);
            finalizePending = m_enrollFinalizeRequested;
        }
        if (finalizePending) {
            bool requiredDone = false;
            QString enrollUserId;
            QMap<QString, QVector<QVector<float>>> binsCopy;
            int sampleTarget;
            {
                QMutexLocker l(&m_mutex);
                requiredDone  = allRequiredDone_locked();
                enrollUserId  = m_enrollUserId;
                binsCopy      = m_enrollBins;
                sampleTarget  = m_enrollSamplesTarget;
                // Reset flag + sortie mode enrollment AVANT emit pour eviter
                // re-traitement sur les frames suivantes.
                m_enrollFinalizeRequested = false;
                m_enrollBins.clear();
                m_mode = Detecting;
            }
            if (!requiredDone) {
                QStringList missing;
                for (const QString &p : REQUIRED_POSES) {
                    if (binsCopy.value(p).size() < sampleTarget)
                        missing.append(poseLabel(p));
                }
                qDebug() << "[FaceWorker] finalize refuse — manque :" << missing;
                emit enrollFinished(false,
                    QStringLiteral("Poses manquantes : %1").arg(missing.join(", ")));
            } else {
                // Construit la map { center: [...], left: [...], ... } avec
                // moyenne par pose et emit -> AppController POST /face/enroll.
                QVariantMap embeddingsMap;
                int totalSamples = 0;
                for (const QString &p : ACTIVE_POSES) {
                    const auto &samples = binsCopy.value(p);
                    if (samples.isEmpty()) continue;
                    QVector<float> poseMean = meanEmbedding(samples);
                    QVariantList vec;
                    for (float v : poseMean) vec.append(v);
                    embeddingsMap[p] = vec;
                    totalSamples += samples.size();
                }
                if (embeddingsMap.isEmpty()) {
                    emit enrollFinished(false, QStringLiteral("Pas d'embedding"));
                } else {
                    qDebug() << "[FaceWorker] finalize -> backend : userId="
                             << enrollUserId << "poses=" << embeddingsMap.keys()
                             << "samples=" << totalSamples;
                    emit enrollEmbeddingsReady(enrollUserId, embeddingsMap);
                }
            }
            continue;  // skip detection pour cette frame
        }

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

        // Sélection du meilleur visage VALIDE (filtre faux positifs : mains, etc.)
        int  bestIdx = (!faces.empty() && faces.rows > 0) ? bestFaceIdx(faces) : -1;
        bool hasFace = (bestIdx >= 0);
        bool inRoi   = false;
        bool matched = false;

        if (hasFace) lastFaceMs = nowMs;

        if (hasFace) {
            cv::Mat best = faces.row(bestIdx);
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

                        statusMap = buildEnrollStatus_locked(true);
                    }

                    emit enrollProgress(statusMap);

                    // (finalize traite au top du loop, hors detection,
                    //  pour fonctionner meme sans visage dans ROI)
                } else {
                    // ── Mode détection — envoi embedding au backend ────────────
                    // (Pas de match local : la DB est cote serveur, le backend
                    //  fait cosinus + permission + emit access_event SocketIO.)
                    //
                    // SFace cooldown : evite de re-extraire l'embedding 30x/s
                    // pour le meme visage stable.
                    cv::Rect curBox(static_cast<int>(best.at<float>(0, 0)),
                                    static_cast<int>(best.at<float>(0, 1)),
                                    static_cast<int>(best.at<float>(0, 2)),
                                    static_cast<int>(best.at<float>(0, 3)));
                    bool sameFace = (lastFaceBox.width > 0)
                                 && std::abs(curBox.x - lastFaceBox.x) < SFACE_BBOX_TOL_PX
                                 && std::abs(curBox.y - lastFaceBox.y) < SFACE_BBOX_TOL_PX;
                    bool sfaceFresh = (nowMs - lastSFaceMs) < SFACE_COOLDOWN_MS;

                    if (sameFace && sfaceFresh) {
                        // Meme visage recent : skip extraction (CPU)
                    } else {
                        // Extraction embedding via SFace
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
                        lastSFaceMs = nowMs;
                        lastFaceBox = curBox;

                        // Emit -> AppController POST /face/match
                        // Le backend decide granted/denied/Anonyme + permission
                        // + emit access_event SocketIO -> AppController.handleEvent
                        // Cote Qt, on freeze toute detection 5s post-emit
                        // (l'access_event arrive ~50-100ms apres, le freeze
                        //  evite de spam le backend).
                        emit faceMatchRequest(emb);
                        eventFreezeUntilMs = nowMs + EVENT_FREEZE_MS;
                        matched = true;   // pour faceStatusChanged en fin de loop
                        qDebug() << "[FaceWorker] embedding -> backend (freeze 5s)";
                    }
                }
            }
        }

        emit faceStatusChanged(hasFace, inRoi, matched);
    }

    qDebug() << "[FaceWorker] arrêté";
}

#endif // ACL_OPENCV_ENABLED
