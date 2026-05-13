# Robustesse Face Recognition — Problème des variations (lunettes, etc.)

## Problème constaté

Quand un utilisateur s'enrole **avec lunettes** et se présente ensuite **sans lunettes** (ou inversement), le modèle SFace classe le visage comme **"Anonyme"** (score < `MATCH_THRESH = 0.70`).

C'est un problème classique de robustesse en reconnaissance faciale : les embeddings sont sensibles aux occlusions (lunettes, masque, barbe, coiffure, etc.).

---

## Cause technique

Architecture actuelle (faceworker.cpp, facedb.cpp) :

1. **Enrôlement** capture **50 échantillons** (5 poses × 10) tous dans une seule condition (ex: avec lunettes)
2. `meanEmbedding(all)` calcule **UN SEUL embedding moyen** sur tous les samples
3. Cet unique vecteur 512-D est stocké dans `FaceEntry.embedding`
4. `m_db.match(emb, MATCH_THRESH)` compare l'embedding live à cet unique vecteur via cosinus
5. Si la condition change (lunettes ôtées) → similarité chute (typiquement 0.55-0.65) → en dessous du seuil 0.70 → fallback "Anonyme"

Valeurs typiques SFace (cosinus) :
- Même personne, même condition : **0.75 - 0.95**
- Même personne, condition différente (lunettes/pas, lumière) : **0.55 - 0.80**
- Personnes différentes : **0.20 - 0.55**

---

## 3 solutions possibles

### 🔵 Option A — Quick : abaisser le seuil 0.70 → 0.60/0.65

**Modification** : `faceworker.h:60` → `constexpr float MATCH_THRESH = 0.60f;`

| ✅ Avantage | ❌ Inconvénient |
|---|---|
| 1 ligne, déployable en 2 min | Risque accru de faux positifs (confusion entre personnes similaires) |
| Tolère plus les variations | Peut activer "Said" pour un visage proche mais différent |

**Effort** : 2 min
**Risque sécurité** : moyen — à éviter sur un système d'accès strict.

---

### 🟢 Option B — Recommandée : multi-embedding par pose

Stocker **5 embeddings** (1 par pose) par utilisateur au lieu d'un seul moyen global.

#### Structure modifiée

```cpp
// FaceEntry actuel
struct FaceEntry {
    QVector<float> embedding;   // 1 seul vecteur 512-D
    QString        role;
    bool           active;
    QString        createdAt;
};

// FaceEntry proposé
struct FaceEntry {
    QMap<QString, QVector<float>> embeddings;  // 5 vecteurs (center/left/right/up/down)
    QString        role;
    bool           active;
    QString        createdAt;
};
```

#### Algorithme match

```cpp
QString FaceDb::match(const QVector<float> &emb, float threshold,
                      float *scoreOut, bool *activeOut) const
{
    QString bestName;
    float   bestScore = -1.0f;

    for (auto userIt = m_db.begin(); userIt != m_db.end(); ++userIt) {
        // Calcule cosinus contre CHAQUE embedding de pose du user
        float userMax = -1.0f;
        for (auto poseIt = userIt.value().embeddings.constBegin();
             poseIt != userIt.value().embeddings.constEnd(); ++poseIt) {
            float s = cosine(emb, poseIt.value());
            if (s > userMax) userMax = s;
        }
        // Le meilleur score de ce user (toutes poses confondues)
        if (userMax > bestScore) {
            bestScore = userMax;
            bestName  = userIt.key();
        }
    }
    return (bestScore >= threshold) ? bestName : QString();
}
```

#### Modification enroll finalize

```cpp
// faceworker.cpp finalize : stocker par pose au lieu de mean global
FaceEntry entry;
for (const QString &p : ACTIVE_POSES) {
    if (!m_enrollBins[p].isEmpty())
        entry.embeddings[p] = meanEmbedding(m_enrollBins[p]);
}
entry.role      = enrollRole;
entry.active    = true;
entry.createdAt = ...;
m_db.insert(enrollName, entry);
```

#### Compatibilité descendante (DB existante)

```cpp
// Loader : si l'ancienne DB a une seule embedding -> migrer en "global"
if (oldFormat) entry.embeddings["global"] = oldEmbedding;
```

| ✅ Avantage | ❌ Inconvénient |
|---|---|
| Résout à la source sans baisser le seuil | Refactor FaceDb + finalize + match |
| Naturellement robuste à toutes les variations | Compatibilité DB ascendante |
| Capacité disque négligeable (5×2 KB/user) | ~30 min de travail |
| Pas de faux positifs supplémentaires | |

**Effort** : ~30 min
**Risque sécurité** : faible

---

### 🟠 Option C — Apparences multiples ajoutables

Permettre à l'utilisateur d'ajouter des "sessions d'enrôlement" supplémentaires à un user existant (avec/sans lunettes, etc.).

#### UI ajoutée

Dans `FaceSettingsModal`, ajouter un bouton "+ Apparence" pour chaque user enrôlé.

- Clic → relance EnrollmentModal en mode "append" pour cet user
- L'enrôlement complète l'existant (5 poses additionnelles)
- Stockage : `FaceEntry.appearances[appearanceId].embeddings` (Option B × N apparences)

#### Algorithme

Au match, on itère sur **toutes** les apparences de chaque user, on prend le max global.

| ✅ Avantage | ❌ Inconvénient |
|---|---|
| Maximum de flexibilité (user peut ajouter au fil du temps) | ~1h de travail (UI + API + storage hiérarchique) |
| Reconnaît avec/sans lunettes, avant/après barbe, etc. | Stockage légèrement plus important |
| Pas de re-enroll complet nécessaire | Modèle DB plus complexe |

**Effort** : ~1h
**Risque sécurité** : faible

---

## Recommandations combinées

### Implémentation progressive recommandée

1. **Phase 1 (immédiat)** : Option B (multi-embedding par pose)
   - Résout 80 % des cas (variations lunettes/lumière par pose)
   - Refactor propre, foundation solide

2. **Phase 2 (si nécessaire)** : Option C (apparences multiples)
   - À déclencher uniquement si Phase 1 insuffisante
   - User peut "compléter" un profil au fil du temps

### Bonus UX (toutes options)

Pendant l'enrolement, afficher un message :

> 💡 **Conseil** : Si vous portez des lunettes parfois, alternez avec/sans pendant les 5 poses pour une meilleure reconnaissance dans toutes les conditions.

Effort : 5 min — modif `EnrollmentModal.qml` état "form".

### Configuration recommandée

- `MATCH_THRESH = 0.65` (au lieu de 0.70 par défaut)
  - Compromis entre tolérance et sécurité
  - Combiné avec Option B, devient très robuste

---

## Détails techniques

### Constantes actuelles (`faceworker.h`)

```cpp
static const int   COOLDOWN_MS    = 5000;     // ← ancien, remplacé par EVENT_FREEZE_MS
static constexpr float SCORE_THRESH    = 0.70f;
static constexpr float NMS_THRESH      = 0.30f;
static constexpr float MATCH_THRESH    = 0.70f;  // ← à baisser potentiellement
static constexpr float ENROLL_MIN_SCORE   = 0.80f;
static constexpr int   ENROLL_MIN_WIDTH   = 80;
```

### Fichiers à modifier (Option B)

- `facedb.h` : `FaceEntry.embedding` → `embeddings: QMap<QString, QVector<float>>`
- `facedb.cpp` :
  - `match()` : itérer sur les poses, prendre max
  - `save()` / `load()` : sérialiser/désérialiser le map
  - Migration : charger ancien format en `embeddings["global"]`
- `faceworker.cpp` :
  - `finalizeEnroll` (success path) : remplir `entry.embeddings` au lieu de `entry.embedding`

### Tests à effectuer

1. Enroller "Said" avec lunettes
2. Vérifier reconnaissance avec lunettes → score ~0.85
3. Vérifier reconnaissance sans lunettes → score ~0.60-0.70 (Option B améliore)
4. Comparer faux positifs : présenter une personne différente → ne doit pas être reconnue comme Said
5. Vérifier compat DB ascendante : ancien user reconnu après migration

---

## Date de rédaction

2026-05-12

## Status

📝 Documenté — implémentation en attente de validation utilisateur.
