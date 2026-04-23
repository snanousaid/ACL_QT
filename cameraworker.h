#pragma once
#include <QThread>
#include <QImage>
#include <QMutex>
#include <QAtomicInt>
#include <QVariantMap>
#include "facedb.h"

class CameraWorker : public QThread
{
    Q_OBJECT
public:
    enum Mode { Detecting, Enrolling, Paused };

    explicit CameraWorker(QObject *parent = nullptr);
    ~CameraWorker() override;

    void stop();
    void pause();
    void resume();

    // Enrollment
    void startEnroll(const QString &name, const QString &role, int samplesPerPose);
    void finalizeEnroll();
    void cancelEnroll();

    // DB management (thread-safe)
    QVariantList listUsers()  const;
    void toggleUser(const QString &name);
    void deleteUser(const QString &name);

    void reloadDb();

signals:
    void frameReady(const QImage &image);
    void faceStatusChanged(bool faceDetected, bool inRoi, bool recognized);
    void accessGranted(const QString &name, float score);
    void accessDenied(const QString &reason, float score);
    void enrollProgress(const QVariantMap &status);
    void enrollFinished(bool ok, const QString &msg);

protected:
    void run() override;

private:
    // Pipeline config — correspond à config.yaml
    static const int   CAM_W          = 640;
    static const int   CAM_H          = 480;
    static const int   CAM_FPS        = 15;
    static const int   DETECT_EVERY_N = 2;
    static const int   COOLDOWN_MS    = 5000;
    static const int   ENROLL_SAMPLES = 10; // par enrôlement

    static constexpr float SCORE_THRESH        = 0.70f;
    static constexpr float NMS_THRESH          = 0.30f;
    static constexpr float MATCH_THRESH        = 0.70f;
    static constexpr float BRIGHT_MIN          = 40.0f;
    static constexpr float BRIGHT_MAX          = 220.0f;
    static constexpr float ROI_X               = 0.20f;
    static constexpr float ROI_Y               = 0.28f;
    static constexpr float ROI_W               = 0.60f;
    static constexpr float ROI_H               = 0.44f;
    static constexpr float ROI_MIN_OVERLAP     = 0.70f; // 70% du visage doit être dans la ROI
    // Enrôlement — filtres qualité (comme Python)
    static constexpr float ENROLL_MIN_SCORE    = 0.80f; // score YuNet minimum
    static constexpr int   ENROLL_MIN_WIDTH    = 80;    // largeur visage minimum (px)
    static constexpr int   ENROLL_INTERVAL_MS  = 150;   // intervalle min entre deux samples

    QAtomicInt m_running{0};
    mutable QMutex m_mutex;

    Mode    m_mode = Detecting;
    FaceDb  m_db;

    // Enrollment state
    QString              m_enrollName;
    QString              m_enrollRole;
    int                  m_enrollSamplesTarget = ENROLL_SAMPLES;
    QVector<QVector<float>> m_enrollSamples;
    bool                 m_enrollFinalizeRequested = false;
    qint64               m_enrollLastSampleMs      = 0;

    const QString m_modelsDir = QStringLiteral("/opt/ACL_qt/models");
    const QString m_dbPath    = QStringLiteral("/opt/ACL_qt/embeddings/known_faces.json");
};
