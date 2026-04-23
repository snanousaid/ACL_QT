#include "facedb.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <cmath>

bool FaceDb::load(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return false;
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject()) return false;

    m_db.clear();
    const QJsonObject root = doc.object();
    for (auto it = root.begin(); it != root.end(); ++it) {
        const QJsonObject o = it.value().toObject();
        FaceEntry e;
        e.role      = o[QStringLiteral("role")].toString(QStringLiteral("user"));
        e.active    = o[QStringLiteral("active")].toBool(true);
        e.createdAt = o[QStringLiteral("created_at")].toString();
        const QJsonArray arr = o[QStringLiteral("embedding")].toArray();
        e.embedding.reserve(arr.size());
        for (const QJsonValue &v : arr)
            e.embedding.append(static_cast<float>(v.toDouble()));
        m_db[it.key()] = e;
    }
    return true;
}

bool FaceDb::save(const QString &path) const
{
    QJsonObject root;
    for (auto it = m_db.constBegin(); it != m_db.constEnd(); ++it) {
        QJsonObject o;
        o[QStringLiteral("role")]       = it.value().role;
        o[QStringLiteral("active")]     = it.value().active;
        o[QStringLiteral("created_at")] = it.value().createdAt;
        QJsonArray arr;
        for (float v : it.value().embedding) arr.append(static_cast<double>(v));
        o[QStringLiteral("embedding")]  = arr;
        root[it.key()] = o;
    }
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    return true;
}

void FaceDb::insert(const QString &name, const FaceEntry &e) { m_db[name] = e; }
void FaceDb::remove(const QString &name)                     { m_db.remove(name); }

void FaceDb::setActive(const QString &name, bool active)
{
    if (m_db.contains(name)) m_db[name].active = active;
}

QList<QPair<QString, FaceEntry>> FaceDb::entries() const
{
    QList<QPair<QString, FaceEntry>> r;
    for (auto it = m_db.constBegin(); it != m_db.constEnd(); ++it)
        r.append({it.key(), it.value()});
    return r;
}

float FaceDb::cosine(const QVector<float> &a, const QVector<float> &b)
{
    if (a.size() != b.size() || a.isEmpty()) return 0.0f;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.size(); i++) {
        dot += a[i] * b[i];
        na  += a[i] * a[i];
        nb  += b[i] * b[i];
    }
    double denom = std::sqrt(na) * std::sqrt(nb);
    return (denom < 1e-9) ? 0.0f : static_cast<float>(dot / denom);
}

QString FaceDb::match(const QVector<float> &emb, float threshold, float *scoreOut) const
{
    QString bestName;
    float   bestScore = -1.0f;
    for (auto it = m_db.constBegin(); it != m_db.constEnd(); ++it) {
        if (!it.value().active) continue;
        float s = cosine(emb, it.value().embedding);
        if (s > bestScore) { bestScore = s; bestName = it.key(); }
    }
    if (scoreOut) *scoreOut = bestScore;
    return (bestScore >= threshold) ? bestName : QString();
}
