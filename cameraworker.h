#pragma once
#include <QThread>
#include <QImage>
#include <QMutex>
#include <QAtomicInt>
#include <QVariantMap>
#include <QVariantList>

// ─────────────────────────────────────────────────────────────────────────────
// CameraWorker — Étape 1 : capture pure (V4L2 → QImage @ 30 fps)
// La détection / reconnaissance sera déplacée dans FaceWorker (étape 2).
// Les méthodes face/enroll présentes ici sont des stubs no-op pour préserver
// la compatibilité de l'AppController existant.
// ─────────────────────────────────────────────────────────────────────────────
class CameraWorker : public QThread
{
    Q_OBJECT
public:
    enum Mode { Detecting, Paused };

    explicit CameraWorker(QObject *parent = nullptr);
    ~CameraWorker() override;

    void stop();
    void pause();
    void resume();

    // ── Stubs (déplacés vers FaceWorker à l'étape 2) ────────────────────────
    void startEnroll(const QString &name, const QString &role, int samplesPerPose);
    void finalizeEnroll();
    void cancelEnroll();
    QVariantList listUsers() const;
    void toggleUser(const QString &name);
    void deleteUser(const QString &name);
    void reloadDb();

signals:
    void frameReady(const QImage &image);
    // Signaux face — émis depuis FaceWorker à l'étape 2
    void faceStatusChanged(bool faceDetected, bool inRoi, bool recognized);
    void accessGranted(const QString &name, float score);
    void accessDenied(const QString &reason, float score);
    void enrollProgress(const QVariantMap &status);
    void enrollFinished(bool ok, const QString &msg);

protected:
    void run() override;

private:
    static const int CAM_W   = 640;
    static const int CAM_H   = 480;
    static const int CAM_FPS = 30;

    QAtomicInt     m_running{0};
    mutable QMutex m_mutex;
    Mode           m_mode = Detecting;
};
