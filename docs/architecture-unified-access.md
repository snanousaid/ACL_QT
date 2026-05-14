# Architecture Unified Access — Badge + Face via Backend

## Objectif

Unifier la gestion des accès **Badge** et **Face ID** dans `acl_controller` (NestJS).
Aujourd'hui : Badge décidé serveur, Face décidé localement Qt avec DB JSON locale.
Demain : tout passe par le backend (source unique de vérité).

---

## Schéma Prisma — relation 1-1 User ↔ FaceProfile

```prisma
model User {
  ...
  cin            String?         // déjà existant — identifiant unique pour lookup
  badge          Badge[]
  faceProfile    FaceProfile?    // ← AJOUT, 1 seul profil par user
  ...
}

model FaceProfile {
  id          String   @id @default(uuid())
  userId      String   @unique          // @unique force le 1-1
  user        User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  embeddings  Json     // {"center":[512 floats],"left":[...],"right":[...],"up":[...],"down":[...]}
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}
```

**Choix design** :
- **1 user = 1 face** : pas de multi-profils ("apparences"). Si re-enroll → remplace l'existant.
- **Activation** : géré au niveau `User.isActif` (comme badge). Pas de `isActif` sur FaceProfile.
- **Suppression** : cascade `onDelete` — si on supprime un user, son FaceProfile part avec.

---

## Endpoints backend (`acl_controller`)

```
# Match face (appelé par Qt à chaque détection)
POST /face/match
  Body : { embedding: float[512], reader: string }
  Resp : { granted: bool, user: User|null, score: float, reason: string }
  Effet bord : emit 'access_event' SocketIO (source: 'face')

# Lookup user par CIN (pendant enrôlement)
GET /face/user-by-cin?cin=XXXX
  Resp 200 : User
  Resp 404 : "Utilisateur non trouvé"

# Enrôlement (upsert : remplace si existe déjà)
POST /face/enroll
  Body : { userId: string, embeddings: { center, left, right, up, down } }
  Resp : { profileId, isUpdate: bool }

# Liste profils faces (pour FaceSettingsModal)
GET /face/profiles
  Resp : [{ id, userId, user: { first_name, last_name, cin, isActif }, createdAt }]

# Suppression
DELETE /face/profile/:userId        # par userId (puisque 1-1)
```

### Logique match (pseudo)

```typescript
async match(embedding, reader) {
    const profiles = await prisma.faceProfile.findMany({ include: { user: true } });
    let bestUser = null, bestScore = -1;

    for (const p of profiles) {
        for (const vec of Object.values(p.embeddings)) {
            const s = cosine(embedding, vec);
            if (s > bestScore) { bestScore = s; bestUser = p.user; }
        }
    }

    if (bestScore < MATCH_THRESH || !bestUser) {
        emitAccessEvent({ source: 'face', granted: false, user: null,
                          name: 'Anonyme', score: bestScore, reader });
        return { granted: false, user: null, score: bestScore };
    }

    if (!bestUser.isActif) {
        emitAccessEvent({ source: 'face', granted: false, user: bestUser,
                          score: bestScore, reader });
        return { granted: false, user: bestUser, score: bestScore };
    }

    // Check permission door (logique badge réutilisée)
    const door = await findDoorByReader(reader);
    const granted = await userHasPermission(bestUser.id, door.id);

    emitAccessEvent({ source: 'face', granted, user: bestUser,
                     score: bestScore, reader });
    return { granted, user: bestUser, score: bestScore };
}
```

---

## Changements Qt (ACL_QT)

### `FaceWorker`
- **Suppression** du match local (`FaceDb`)
- **Nouveau signal** : `faceMatchRequest(QVector<float> embedding)`
- L'`access_event` arrive via SocketIO existant → géré par `AppController.handleEvent`
- Voting 2/3 + freeze 5s **restent côté Qt** (filtre avant envoi backend)

### `AppController`
```cpp
// Nouveaux slots
Q_INVOKABLE void lookupUserByCin(const QString &cin);    // GET /face/user-by-cin
Q_INVOKABLE void enrollFace(const QString &userId, const QVariantMap &embeddings);
Q_INVOKABLE void listFaceProfiles();                      // GET /face/profiles
Q_INVOKABLE void deleteFaceProfile(const QString &userId);

// Slot connecté à FaceWorker::faceMatchRequest
void onFaceMatchRequest(const QVector<float> &emb);       // POST /face/match

// Nouveaux signals
void userLookupResult(bool found, const QVariantMap &user, const QString &errorMsg);
void enrollFaceResult(bool ok, const QString &msg);
void faceProfilesLoaded(const QVariantList &profiles);
```

### `EnrollmentModal` — nouveau flux

```
Étape "form" :
  - Champ CIN (au lieu de Nom + Rôle)
  - Bouton "Rechercher"
       ↓
       lookupUserByCin(cin)
       ↓
  - Affichage résultat :
       Trouvé : "Said Snanou" + [Continuer]
       Non trouvé : "Aucun utilisateur avec ce CIN.
                     Demandez à l'admin de créer l'utilisateur dans le dashboard."

Étape "live" : capture 5 poses (inchangé)

Étape "done" :
  - POST /face/enroll { userId, embeddings }
  - Si user a déjà un FaceProfile : message "Mise à jour"
  - Sinon : "Enrôlement créé"
```

**Suppressions** :
- Champ "Nom" (vient du backend)
- Champ "Rôle" (géré dashboard via User.role / Team)
- `samplesPerPose` : conservé (utile qualité)

### `FaceSettingsModal` — liste backend
```qml
// Avant
controller.listFaceUsers()  // listait FaceDb local

// Après
controller.listFaceProfiles()  // GET /face/profiles
// Item delegate affiche : first_name + last_name + cin + (User.isActif → pill)
// Plus de bouton "toggle" (géré dashboard)
// Bouton delete : DELETE /face/profile/:userId
```

### `FaceDb` local → **supprimé**
- `facedb.cpp`, `facedb.h` retirés du `.pro`
- Fichier `embeddings/known_faces.json` ignoré (peut être archivé)
- App nécessite désormais une connexion backend pour fonctionner

---

## Plan de migration (étapes ordonnées)

| # | Côté | Tâche | Effort |
|---|---|---|---|
| 1 | **acl_controller** | Migration Prisma : `FaceProfile` + relation `User` | 30 min |
| 2 | **acl_controller** | Module `face` : controller + service | 30 min |
| 3 | **acl_controller** | Endpoint `POST /face/match` + logique permission + emit event | 1h |
| 4 | **acl_controller** | Endpoints `GET /face/user-by-cin`, `POST /face/enroll`, `GET /face/profiles`, `DELETE /face/profile/:userId` | 1h |
| 5 | **ACL_QT** | `FaceWorker` : retire DB locale, emit `faceMatchRequest` | 1h |
| 6 | **ACL_QT** | `AppController` : slots REST + slot bridge match | 1h |
| 7 | **ACL_QT** | `EnrollmentModal` : étape "CIN lookup" + flow enrôlement | 1h |
| 8 | **ACL_QT** | `FaceSettingsModal` : liste backend + suppression | 30 min |
| 9 | **ACL_QT** | Cleanup `FaceDb.cpp/h` + `.pro` + ressources | 15 min |
| 10 | **ACL_QT** | Test end-to-end | 30 min |

**Total ~6-7h**.

---

## Comportement final attendu

| Scénario | Effet |
|---|---|
| User présente visage devant caméra | Qt extrait embedding → POST /face/match → backend match + permission → access_event SocketIO → AccessCard |
| Visage inconnu (pas en DB) | `name: "Anonyme"`, denied |
| User désactivé (`isActif=false`) | denied avec nom |
| User actif mais pas de permission pour cette porte | denied avec nom |
| User actif + permission OK | granted ✅ |
| Admin tape "+ Nouveau" Face ID | EnrollmentModal → CIN → si exist : capture + enroll, si pas : erreur |
| Suppression d'un profil face | Profil supprimé, user reste (badge fonctionne toujours) |

---

## Source unique de vérité

| Données | Source |
|---|---|
| Liste users | Backend Prisma `User` |
| Badge | Backend Prisma `Badge` |
| FaceProfile (embeddings) | Backend Prisma `FaceProfile` |
| Permissions (door access) | Backend Prisma `Permission` |
| isActif user | Backend Prisma `User.isActif` |
| Events (badge + face) | Backend Prisma `Event` |
| **Qt local** | Aucune donnée business (juste runtime) |

---

## Status

📝 Documenté — implémentation en cours sur branches `feat/unified-face-access`.

## Branches

- ACL_QT : `feat/unified-face-access` (créée le 2026-05-14)
- acl_controller : `feat/unified-face-access` (créée le 2026-05-14)
