# Enrôlement Face ID depuis le Dashboard Web

Status : 📐 Architecture validée — implémentation en cours sur `feat/web-face-enroll` (3 repos).

Date : 2026-05-15

---

## Objectif

Permettre à l'admin d'enregistrer le visage d'un utilisateur **depuis le dashboard ACL_133_FRONT** (en plus du kiosque Qt actuel) avec :

- **Live caméra** (web) : stream MJPEG depuis Qt + capture multi-pose
- **Upload d'images** (web) : sélection 1 à 20 images depuis le PC admin
- **Multi-pose 5 directions** : center / left / right / up / down (comme Qt)
- **Samples par pose configurables** : variable côté live (équivalent Qt), 1 à 20 côté upload

Périmètre pour cette branche : **uniquement l'ajout Face ID**. Autres améliorations dashboard à voir après validation visuelle.

---

## Architecture validée

```
┌───────────────────┐                      ┌─────────────────────────┐
│  ACL_133_FRONT    │                      │  ACL_QT (kiosque A133)  │
│  React + axios    │                      │  - YuNet + SFace        │
│                   │ ── HTTP image(s) ──▶ │  - QTcpServer minimal   │
│  (page user)      │                      │  - extrait embeddings   │
│                   │ ◀── MJPEG stream ─── │                         │
└────────┬──────────┘                      └────────────┬────────────┘
         │                                              │
         │  (réponse: 200 OK,                           │
         │   embedding(s) sauvegardé(s)                 │
         │   par Qt directement)                        │
         │                                              │
         │                                              │ POST /face/enroll
         │                                              │ (embeddings 512-D)
         │                                              ▼
         │                                  ┌─────────────────────────┐
         └─── REST classique (JWT) ───────▶ │  acl_controller (Nest)  │
                                            │  Prisma → FaceProfile   │
                                            └─────────────────────────┘
```

**Décisions clefs :**

1. **Aucun nouveau service** : Qt sert directement les requêtes HTTP web (un mini-serveur dans le process Qt existant).
2. **Single host** : le front utilise la même IP que `acl_controller` (A133). Qt écoute sur un port distinct.
3. **Pas de sécurité** dans v1 (LAN privé). À durcir plus tard si besoin (token, allow-list IP).
4. **Stream à la demande** : Qt n'ouvre la diffusion que si le front la requête (`GET /face/stream`).
5. **Backend inchangé** côté API : Qt continue d'appeler `POST /face/enroll` (endpoint déjà en place sur la branche `feat/unified-face-access`).

---

## Endpoints du serveur Qt

Port : **9090**. v1 (upload) et v2 (live) sont tous deux implémentés.

| Méthode | Route | Body | Réponse |
|---|---|---|---|
| `GET`  | `/health` | — | `200 {status:"ok"}` |
| `POST` | `/enroll-from-images` | `multipart` : `userId`, `images[]` (1 à 20) | `200 {profileId, isUpdate, poses:{center:N,...}}` |
| `GET`  | `/stream` | — | `multipart/x-mixed-replace; boundary=frame` (MJPEG) |
| `POST` | `/enroll/start` | JSON `{userId, samplesPerPose}` | `200 {started, userId, samplesPerPose}` |
| `GET`  | `/enroll/status` | — | `200 {status:{...}, result:{op, ok, msg, ts}}` |
| `POST` | `/enroll/finalize` | — | `200 {finalize:"requested"}` |
| `POST` | `/enroll/cancel` | — | `200 {cancel:"requested"}` |

### Mode UPLOAD

Multipart `images[]` (1–20). Pas de pose à fournir : Qt auto-classifie via
landmarks YuNet (`classifyPose()` dans `httpserver.cpp`), groupe par pose,
moyenne et POST `/face/enroll` côté backend.

### Mode LIVE

Le front pilote le FaceWorker existant via HTTP (zéro duplication) :

1. `<img src="/stream">` côté web — Qt diffuse les frames camera en MJPEG
   (~15 FPS, JPEG q=75)
2. `POST /enroll/start` → `AppController::startEnroll(userId, samplesPerPose)`
   → le kiosque entre en mode enrollment, même comportement que dans QML
3. Le front poll `GET /enroll/status` toutes les ~300 ms pour la progression
   par pose (count/target, pose courante, message du worker)
4. Quand `enroll_complete=true`, le front affiche un bouton "Valider"
5. `POST /enroll/finalize` → finalize côté FaceWorker → embeddings moyennés
   par pose → POST backend `/face/enroll` → résultat persisté dans
   `lastEnrollResult` (lu par le polling)
6. `POST /enroll/cancel` à tout moment pour abandonner.

Le kiosque QML voit aussi l'enrôlement en cours (même `FaceWorker`).

### Comportement `/enroll-from-images` (v1)

**Le front n'envoie qu'un champ unique `images`** (1 à 20 fichiers). Qt
auto-classifie chaque image par pose via les landmarks YuNet (même logique
que l'enrôlement live, fonction `classifyPose()` dans `httpserver.cpp`).

Pour chaque image reçue :
- YuNet détecte le visage (rejet si aucun visage valide).
- Estimation de la pose (yaw/pitch via landmarks) → `center` / `left` /
  `right` / `up` / `down`. Les images ambiguës tombent dans `center`.
- SFace extrait l'embedding 512-D.

Ensuite, par pose détectée :
- **Moyenne** des embeddings + normalisation L2.
- Le résultat `{ pose → vector[512] }` est POSTé à `acl_controller`
  `POST /face/enroll`.

Champ legacy `images_<pose>` toujours accepté (compat avec une future v2 où
le mode live pourra forcer la pose côté front sans auto-classification).

Renvoie au front : `{ profileId, isUpdate, poses: { center: N, left: N, ... } }`
où `N` = nombre d'images valides retenues pour cette pose.

### Mode v1 côté web

- **Upload unique** : l'admin glisse-dépose entre 1 et 20 images dans une
  seule zone (pas de sélection de pose). Front envoie tout dans une seule
  requête `multipart/form-data` à `POST /enroll-from-images`.
- Minimum 1 image valide (avec visage détecté) pour valider — sinon `422`.
- Maximum 20 images par enrôlement (rejet `413` côté Qt).

---

## Implémentation Qt (résumé)

Qt 5.12 ne propose pas `QHttpServer` (apparu en Qt 6.4). On utilise :

- `QTcpServer` pour écouter le port
- Parsing HTTP minimal (request line + headers + multipart boundary)
- Réutilisation directe de `FaceWorker::cvFaceDetector` (YuNet) et `cvFaceRecognizer` (SFace)
- Stream MJPEG : on tape sur `AppController::frameReady` (`QImage`) déjà disponible (lien actuel CameraImgProvider) → `QImage::save(QIODevice, "JPEG")`

Nouveau fichier : `ACL_QT/httpserver.{h,cpp}` instancié dans `main.cpp`, après `AppController`.

Sécurité minimale (v1) :
- Écoute uniquement sur l'interface souhaitée (configurable, par défaut `0.0.0.0`).
- Limite taille requête (ex. 20 Mo total upload).
- Timeout par socket (5 s headers, 30 s body).

---

## Implémentation Front (résumé)

Page `UserDetail` (ou nouvelle modale "Face ID") avec :

- Onglet **Live**
  - `<img>` pointant `http://<HOST>:8080/stream` (MJPEG natif navigateur).
  - 5 boutons pose (center/left/right/up/down). Bouton "Capturer" lance la rafale N images via `canvas` + `fetch /extract-image`. Stocke embeddings côté front jusqu'au "Enregistrer".
  - Champ "samples par pose" (défaut 10, min 1, max 30).
- Onglet **Upload**
  - Pour chaque pose : `<input type="file" multiple accept="image/*">` (max 20).
  - Bouton "Enregistrer" → POST `multipart` à `/extract-multipose` (ou `/enroll-from-images` si on veut que Qt enroll directement).

**Routage** : `VITE_API_URL` pointe sur `acl_controller`. On dérive l'URL Qt automatiquement (`new URL(API_URL).hostname + ':9090'`). Une variable d'override `VITE_QT_URL` est lue si présente, pour les setups multi-A133 ou test local.

---

## Découpage des branches

Toutes en `feat/web-face-enroll` :

| Repo | Base | Travail |
|---|---|---|
| ACL_QT | `feat/unified-face-access` | `httpserver.{h,cpp}`, intégration `main.cpp`, instrumentation `FaceWorker` (méthode publique d'extraction sur image arbitraire) |
| acl_controller | `feat/unified-face-access` | Rien à modifier en théorie. À garder ouverte pour ajustements éventuels (CORS, log) |
| ACL_133_FRONT | `main` | Page Face ID (live + upload), service `qtClient.ts` |

---

## Étapes ordonnées — v1 (upload only)

1. ✅ Branches créées (3 repos)
2. ✅ Architecture validée (ce document)
3. 🔨 Qt : exposer `FaceWorker::extractEmbeddingFromImage(const QImage&)` thread-safe
4. 🔨 Qt : `httpserver.{h,cpp}` (QTcpServer + parser HTTP minimal + handlers `/health`, `/enroll-from-images`)
5. 🔨 Qt : POST sortant vers `acl_controller` `/face/enroll` (réutiliser `QNetworkAccessManager` existant)
6. 🔨 Front : service `qtClient.ts` (+ utilitaire dérivation URL)
7. 🔨 Front : composant `FaceEnrollment.tsx` (upload-only, 5 poses, 1-20 images/pose)
8. 🔨 Front : intégration dans page user (onglet ou modale)
9. 🧪 Test bout-en-bout : upload 5 poses depuis dashboard → enroll → match depuis kiosque

**v2 (live)** — repoussé : ajouter `/stream` (MJPEG) + `/extract-image` + onglet Live front avec capture rafale par pose.

---

## Décisions finales validées (2026-05-15)

- ✅ Port Qt HTTP : **9090**
- ✅ Endpoint groupé `/enroll-from-images` (1 appel, Qt POSTe au backend en interne)
- ✅ Multi-pose en une requête multipart unique (5 champs `images_<pose>`)
- ✅ Scope v1 : **upload seulement**. Live (stream MJPEG) repoussé en v2.
- ✅ Sécurité : aucune en v1 (LAN privé)
- ✅ Routage : front dérive URL Qt depuis `VITE_API_URL` (même host, port 9090)

---

## Hors-scope (à voir plus tard)

- Sécurité (JWT/token entre front et Qt, CORS strict)
- Capture caméra **côté navigateur** (webcam admin) — pas demandé
- Liste/suppression Face profiles depuis le dashboard (déjà possible dans Qt, et endpoint backend existe)
- Stats matchings (graphique scores)
- Audit log côté backend pour les enrôlements web

---

## Référence des endpoints backend déjà disponibles

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/face/enroll` | `{userId, embeddings:{pose: number[512]}}` → upsert FaceProfile |
| `GET`  | `/face/user-by-cin?cin=` | Lookup user pour pré-fill formulaire |
| `GET`  | `/face/profiles` | Liste tous les FaceProfile |
| `DELETE` | `/face/profile/:userId` | Supprime profile |

Le serveur Qt **n'a qu'à proxy** vers `POST /face/enroll` après extraction.
