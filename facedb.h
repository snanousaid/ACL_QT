#pragma once
#include <QString>
#include <QMap>
#include <QVector>
#include <QList>
#include <QPair>

struct FaceEntry {
    QVector<float> embedding;   // SFace : 128 floats
    QString        role;
    bool           active    = true;
    QString        createdAt;
};

class FaceDb
{
public:
    bool load(const QString &path);
    bool save(const QString &path) const;

    int  count()                       const { return m_db.size(); }
    bool contains(const QString &name) const { return m_db.contains(name); }

    void insert   (const QString &name, const FaceEntry &e);
    void remove   (const QString &name);
    void setActive(const QString &name, bool active);

    // Retourne le nom du meilleur match (ou "" si sous le seuil)
    QString match(const QVector<float> &emb, float threshold,
                  float *scoreOut = nullptr) const;

    QList<QPair<QString, FaceEntry>> entries() const;

private:
    static float cosine(const QVector<float> &a, const QVector<float> &b);
    QMap<QString, FaceEntry> m_db;
};
