#pragma once
#include <QString>

// Retourne "OK: OpenCV X.X.X | DNN ok | Camera ok | YuNet ok | SFace ok"
// ou "FAIL: <raison>" à la première erreur rencontrée.
QString runOpenCvTest(const QString &modelsDir);
