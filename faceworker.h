#pragma once
#include <QThread>
#include <QMutex>
#include <QAtomicInt>
#include <QVariantMap>
#include <QVariantList>
#include <QMap>
#include <QStringList>
#include <QVector>

class FrameQueue;

// ─────────────────────────────────────────────────────────────────────────────
// FaceWorker — Détection (YuNet) + extraction embedding (SFace) + enrôlement
// multi-poses. La DB et le match sont désormais 100% côté backend
// (acl_controller). Ce worker NE STOCKE RIEN — il extrait des embeddings et
// les envoie à AppController via signaux (qui POST vers /face/match et
// /face/enroll).
// ─────────────────────────────────────────────────────────────────────────────
class FaceWorker : public QThread
{
    Q_OBJECT
public:
    enum Mode { Detecting, Paused, Enrolling };

    FaceWorker(FrameQueue *queue,
               const QString &modelsDir,
               QObject *parent = nullptr);
    ~FaceWorker() override;

    void stop();
    void pause();
    void resume();

    // Enrollment — userId vient du backend (lookup CIN avant)
    void startEnroll(const QString &userId, int samplesPerPose);
    void finalizeEnroll();
    void cancelEnroll();

signals:
    void faceStatusChanged(bool faceDetected, bool inRoi, bool recognized);

    // Détection : émis quand la majorité de vote (2/3) est atteinte
    // sur une frame valide. AppController POST /face/match avec cet embedding.
    void faceMatchRequest(const QVector<float> &embedding);

    // Enrôlement : progression visuelle (5 poses)
    void enrollProgress(const QVariantMap &status);

    // Enrôlement : émis quand l'utilisateur valide les 5 poses.
    // AppController POST /face/enroll avec userId + map d'embeddings par pose.
    void enrollEmbeddingsReady(const QString &userId,
                               const QVariantMap &embeddings);

    // Enrôlement : feedback final (succès/échec) après réponse backend.
    // Émis par AppController via setEnrollResult() (réception POST réponse).
    void enrollFinished(bool ok, const QString &msg);

public slots:
    // Appelé par AppController après réponse de POST /face/enroll
    void setEnrollResult(bool ok, const QString &msg);

protected:
    void run() override;

private:
    // ── Constantes pipeline ─────────────────────────────────────────────────
    static constexpr float SCORE_THRESH       = 0.70f;
    static constexpr float NMS_THRESH         = 0.30f;
    static constexpr float BRIGHT_MIN         = 40.0f;
    static constexpr float BRIGHT_MAX         = 220.0f;
    static constexpr float ROI_X              = 0.20f;
    static constexpr float ROI_Y              = 0.28f;
    static constexpr float ROI_W              = 0.60f;
    static constexpr float ROI_H              = 0.44f;
    static constexpr float ROI_MIN_OVERLAP    = 0.70f;
    static constexpr float ENROLL_MIN_SCORE   = 0.80f;
    static constexpr int   ENROLL_MIN_WIDTH   = 80;
    static constexpr int   ENROLL_INTERVAL_MS = 150;

    // ── Helpers enrôlement (appelés depuis run() avec mutex tenu) ───────────
    QString nextPoseToFill_locked() const;
    bool    allRequiredDone_locked() const;
    QVariantMap buildEnrollStatus_locked(bool inRoi) const;

    // ── État partagé ────────────────────────────────────────────────────────
    FrameQueue    *m_queue;
    const QString  m_modelsDir;

    QAtomicInt     m_running{0};
    mutable QMutex m_mutex;
    Mode           m_mode = Detecting;

    // Enrollment state
    QString                                   m_enrollUserId;
    int                                       m_enrollSamplesTarget = 10;
    QMap<QString, QVector<QVector<float>>>    m_enrollBins;
    QString                                   m_enrollCurrentPose;
    QString                                   m_enrollLastMsg;
    bool                                      m_enrollFinalizeRequested = false;
    qint64                                    m_enrollLastSampleMs      = 0;
};
