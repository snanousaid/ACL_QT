#pragma once
#include <QThread>
#include <QMutex>
#include <QAtomicInt>
#include <QVariantMap>
#include <QVariantList>
#include <QMap>
#include <QStringList>
#include "facedb.h"

class FrameQueue;

// ─────────────────────────────────────────────────────────────────────────────
// FaceWorker — Détection (YuNet) + reconnaissance (SFace) + enrôlement
// multi-poses (iPhone-like : 3 obligatoires + 2 optionnelles).
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
    // ── Constantes pipeline ─────────────────────────────────────────────────
    static const int   COOLDOWN_MS    = 5000;
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

    // ── Helpers enrôlement (appelés depuis run() avec mutex tenu) ───────────
    QString nextPoseToFill_locked() const;
    bool    allRequiredDone_locked() const;
    QVariantMap buildEnrollStatus_locked(bool inRoi) const;

    // ── État partagé ────────────────────────────────────────────────────────
    FrameQueue    *m_queue;
    const QString  m_dbPath;
    const QString  m_modelsDir;

    QAtomicInt     m_running{0};
    mutable QMutex m_mutex;
    Mode           m_mode = Detecting;
    FaceDb         m_db;

    // Enrollment state
    QString                                   m_enrollName;
    QString                                   m_enrollRole;
    int                                       m_enrollSamplesTarget = 10;
    QMap<QString, QVector<QVector<float>>>    m_enrollBins;
    QString                                   m_enrollCurrentPose;
    QString                                   m_enrollLastMsg;
    bool                                      m_enrollFinalizeRequested = false;
    qint64                                    m_enrollLastSampleMs      = 0;
};
