# Tuning Détection Visage — 2 problèmes observés

Status : 📝 Documenté — implémentation différée (sur décision user).

---

## Problèmes observés

### 🔴 Problème 1 — Coins gris (`out`) sans vrai visage

**Symptôme** : aucun visage devant la caméra, mais le cadre ROI passe en **gris** (état `out`).

**État machine** : `faceInFrame === true` && `faceInRoi === false`

**Cause** : YuNet détecte **quelque chose** qui passe nos filtres `isValidFace()` (landmarks géométriques) mais qui n'est pas centré dans la ROI :
- Visage de profil détecté en bord de cadre
- Faux positif YuNet sur arrière-plan (motifs, cartons, posters)
- Lumière qui crée un pattern type visage
- Reflets sur écran ou surface lisse

### 🔴 Problème 2 — Visage dans ROI sans détection

**Symptôme** : utilisateur met son visage dans le cadre, **rien ne se passe**.

**État machine** : `faceInFrame === false` alors que visage présent

**Causes possibles dans le pipeline** (faceworker.cpp) :

1. **Motion gate** (`MOTION_THRESH = 0.008`)
   - Si l'utilisateur arrive immobile → frame diff < 0.8% → skip détection totale

2. **Rate limiting**
   - `IDLE_INTERVAL = 10` (1 frame sur 10 traitée en idle ≈ 3 FPS)
   - `ACTIVE_INTERVAL = 3` (≈ 10 FPS quand face vu récemment)
   - Brève apparition peut tomber sur frame skip

3. **Downscale YuNet** (`DETECT_SCALE = 0.5`)
   - Image entrée 320×240 au lieu de 640×480
   - Visages éloignés / petits peuvent être ratés

4. **Score threshold YuNet** (`SCORE_THRESH = 0.70`)
   - Visage flou, mal éclairé, ou de profil → score < 0.70 → rejeté

---

## Propositions de fix

### Pour Problème 1 — Faux positifs `out`

| ID | Option | Effet | Impact CPU |
|----|---|---|---|
| **A** | Raise YuNet `SCORE_THRESH` 0.70 → 0.80 | Moins de faux positifs, peut rater visages flous | Aucun |
| **B** | "Stable detection" : N=2 frames consécutives avant `faceInFrame=true` | Filtre les flashs transitoires, latence +200ms | Faible |
| **C** | Reset `out` → `idle` après 500ms si `faceInRoi` reste false | Cadre revient à idle plus vite | Faible |
| **D** | Resserrer `isValidFace()` (eye_ratio plus strict, ratio aspect plus serré) | Plus de faux positifs filtrés | Aucun |

### Pour Problème 2 — Visage non détecté

| ID | Option | Effet | Impact CPU |
|----|---|---|---|
| **E** | Désactiver motion gate si `faceInFrame=true` récent (< 3s) | Détection continue tant que visage vu | Faible |
| **F** | `IDLE_INTERVAL` 10 → 5 | +CPU mais détection 2× plus réactive | Modéré |
| **G** | `DETECT_SCALE` 0.5 → 0.7 | Meilleure détection visages éloignés | +30% CPU |
| **H** | Lower `SCORE_THRESH` 0.70 → 0.60 | Plus de détections mais +faux positifs | Aucun |

---

## Combinaisons recommandées

### 🟢 Combo Conservateur (faible risque)

**Options : B + E**

- Stable detection 2 frames (anti-flash gris)
- Skip motion gate si face récent

Résout ~80% des cas. CPU quasi-inchangé. Latence détection +200ms (acceptable).

### 🟡 Combo Équilibré

**Options : B + E + F**

- Stable detection 2 frames
- Skip motion gate si face récent
- IDLE_INTERVAL 5 (au lieu de 10)

Compromis qualité/CPU. CPU idle environ +10%.

### 🔴 Combo Agressif

**Options : A + B + D + E + G**

- SCORE_THRESH 0.80 (anti-faux positifs)
- Stable detection 2 frames
- isValidFace() strict
- Skip motion gate si face récent
- DETECT_SCALE 0.7 (moins de downscale)

Qualité maximum. CPU +30-40%.

---

## Recommandation

**Commencer par Combo Conservateur (B + E)**.

Si insuffisant après test → bascule sur Combo Équilibré.

Si toujours problèmes → Combo Agressif ou tuning ciblé.

---

## Diagnostic préalable (optionnel)

Avant de tuner, on peut ajouter des logs détaillés dans `faceworker.cpp` pour voir précisément :

- Score YuNet de chaque détection
- Raison de rejet (motion gate / rate limit / score / isValidFace / ROI)
- Coordonnées bbox vs ROI
- Frames per second réelles

Si on veut diagnostiquer plus précisément avant de tuner.

---

## Constantes actuelles (référence)

```cpp
// faceworker.cpp run()
constexpr float   MOTION_THRESH      = 0.008f;   // 0.8 % pixels changés
constexpr int     IDLE_INTERVAL      = 10;       // ~3 FPS idle
constexpr int     ACTIVE_INTERVAL    = 3;        // ~10 FPS actif
constexpr qint64  IDLE_TIMEOUT_MS    = 2000;
constexpr qint64  SFACE_COOLDOWN_MS  = 2000;
constexpr int     SFACE_BBOX_TOL_PX  = 40;
constexpr float   DETECT_SCALE       = 0.5f;
constexpr qint64  EVENT_FREEZE_MS    = 5000;
constexpr float   ANON_MIN_SCORE     = 0.40f;

// faceworker.h
static constexpr float SCORE_THRESH       = 0.70f;    // YuNet
static constexpr float NMS_THRESH         = 0.30f;
static constexpr float MATCH_THRESH       = 0.70f;    // SFace cosinus (cote backend)
static constexpr float BRIGHT_MIN         = 40.0f;
static constexpr float BRIGHT_MAX         = 220.0f;
static constexpr float ROI_X              = 0.20f;
static constexpr float ROI_Y              = 0.28f;
static constexpr float ROI_W              = 0.60f;
static constexpr float ROI_H              = 0.44f;
static constexpr float ROI_MIN_OVERLAP    = 0.70f;
```

---

## Date

2026-05-15

## Status

📝 Documenté. Implémentation différée — l'utilisateur choisira la combinaison plus tard.
