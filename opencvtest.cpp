#include "opencvtest.h"
#include <QDebug>

#ifdef ACL_OPENCV_ENABLED

#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/objdetect.hpp>
#include <opencv2/imgproc.hpp>

QString runOpenCvTest(const QString &modelsDir)
{
    // ── 1. Version ────────────────────────────────────────────────────────
    QString version = QString::fromStdString(cv::getVersionString());
    qDebug() << "[OpenCV] version:" << version;

    // ── 2. Caméra ─────────────────────────────────────────────────────────
    cv::VideoCapture cap(0, cv::CAP_V4L2);
    if (!cap.isOpened()) {
        cap.open(0, cv::CAP_ANY);
        if (!cap.isOpened())
            return QStringLiteral("FAIL: impossible d'ouvrir la caméra");
    }
    cv::Mat frame;
    cap >> frame;
    cap.release();
    if (frame.empty())
        return QStringLiteral("FAIL: frame caméra vide");
    qDebug() << "[OpenCV] camera ok —" << frame.cols << "x" << frame.rows;

    // ── 3. YuNet (détection) ──────────────────────────────────────────────
    std::string yunet = (modelsDir + "/face_detection_yunet_2023mar.onnx").toStdString();
    cv::Ptr<cv::FaceDetectorYN> detector;
    try {
        detector = cv::FaceDetectorYN::create(yunet, "", {frame.cols, frame.rows});
        cv::Mat faces;
        detector->detect(frame, faces);
        qDebug() << "[OpenCV] YuNet ok — visages détectés:" << faces.rows;
    } catch (const cv::Exception &e) {
        qDebug() << "[OpenCV] YuNet FAIL (modèle incompatible OpenCV 4.5.4?):" << e.what();
        return QStringLiteral("FAIL: YuNet — ") + QString::fromStdString(e.what());
    }

    // ── 4. SFace (reconnaissance) ─────────────────────────────────────────
    std::string sface = (modelsDir + "/face_recognition_sface_2021dec.onnx").toStdString();
    cv::Ptr<cv::FaceRecognizerSF> recognizer;
    try {
        recognizer = cv::FaceRecognizerSF::create(sface, "");
        qDebug() << "[OpenCV] SFace ok";
    } catch (const cv::Exception &e) {
        return QStringLiteral("FAIL: SFace — ") + QString::fromStdString(e.what());
    }

    return QStringLiteral("OK: OpenCV %1 | camera %2x%3 | YuNet ok | SFace ok")
               .arg(version)
               .arg(frame.cols).arg(frame.rows);
}

#else

QString runOpenCvTest(const QString &)
{
    return QStringLiteral("OpenCV désactivé (Windows build)");
}

#endif
