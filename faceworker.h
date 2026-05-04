#pragma once
#include <QThread>
#include <QMutex>
#include <QAtomicInt>
#include <QVariantMap>
#include <QVariantList>
#include "facedb.h"

class FrameQueue;

// ─────────────────────────────────────────────────────────────────────────────
// FaceWorker — Étape 2 : détection (YuNet) + reconnaissance (SFace) sur les
// frames livrées par CameraWorker via une FrameQueue.
//
// Mode Detecting  : pipeline normal (ROI → embedding → match DB → events)
// Mode Paused     : aucune détection (pause admin)
// Mode Enrolling  : collecte d'échantillons jusqu'à samplesTarget puis finalize
// ─────────────────────────────────────────────────────────────────────────────
class FaceWorker : public QThread
{
    Q_OBJECT
public:
    enum Mode { Detecting, Paused, Enrolling };

    FaceWorker(FrameQueue *queue,
               const QString &dbPath,
               const QString &modelsDir,
               QObject *parent = nullptr);
    ~FaceWorker() override;

    void stop();
    void pause();
    void resume();

    // Enrollment
    void startEnroll(const QString &name, const QString &role, int samplesPerPose);
    void finalizeEnroll();
    void cancelEnroll();

    // DB management (thread-safe)
    QVariantList listUsers() const;
    void toggleUser(const QString &name);
    void deleteUser(const QString &name);
    void reloadDb();

signals:
    void faceStatusChanged(bool faceDetected, bool inRoi, bool recognized);
    void accessGranted(const QString &name, float score);
    void accessDenied(const QString &reason, float score);
    void enrollProgress(const QVariantMap &status);
    void enrollFinished(bool ok, const QString &msg);

protected:
    void run() override;

private:
    // ── Constantes pipeline (alignées sur Python) ───────────────────────────
    static const int   COOLDOWN_MS    = 5000;
    static const int   ENROLL_SAMPLES = 10;
    static constexpr float SCORE_THRESH    = 0.70f;
    static constexpr float NMS_THRESH      = 0.30f;
    static constexpr float MATCH_THRESH    = 0.70f;
    static constexpr float BRIGHT_MIN      = 40.0f;
    static constexpr float BRIGHT_MAX      = 220.0f;
    static constexpr float ROI_X           = 0.20f;
    static constexpr float ROI_Y           = 0.28f;
    static constexpr float ROI_W           = 0.60f;
    static constexpr float ROI_H           = 0.44f;
    static constexpr float ROI_MIN_OVERLAP = 0.70f;
    static constexpr float ENROLL_MIN_SCORE   = 0.80f;
    static constexpr int   ENROLL_MIN_WIDTH   = 80;
    static constexpr int   ENROLL_INTERVAL_MS = 150;

    // ── État partagé ────────────────────────────────────────────────────────
    FrameQueue    *m_queue;
    const QString  m_dbPath;
    const QString  m_modelsDir;

    QAtomicInt     m_running{0};
    mutable QMutex m_mutex;
    Mode           m_mode = Detecting;
    FaceDb         m_db;

    // Enrollment state
    QString                  m_enrollName;
    QString                  m_enrollRole;
    int                      m_enrollSamplesTarget = ENROLL_SAMPLES;
    QVector<QVector<float>>  m_enrollSamples;
    bool                     m_enrollFinalizeRequested = false;
    qint64                   m_enrollLastSampleMs      = 0;
};
