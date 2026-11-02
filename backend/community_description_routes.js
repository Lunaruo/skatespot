
const { findRideMyParkSpot } = require('./comment_routes');

const MAX_DESCRIPTION_LENGTH = 2000;

function isValidId(id) {
  return Number.isSafeInteger(id) && id > 0;
}

function isValidExternalId(externalId) {
  return (
    typeof externalId === 'string' &&
    /^\d+$/.test(externalId)
  );
}

// Renvoie la description originale et la description
// communautaire dans deux champs distincts.
async function formatDescription(db, spot, externalId = null) {
  if (!spot) {
    return {
      spotId: null,
      externalId,
      description: null,
      communityDescription: null,
      communityDescriptionAuthorId: null,
      communityDescriptionAuthorUsername: null,
      communityDescriptionUpdatedAt: null,
    };
  }

  let authorUsername = null;

  if (spot.communityDescriptionAuthorId != null) {
    const author = await db.orm.public.User
      .where({ id: spot.communityDescriptionAuthorId })
      .first();

    authorUsername = author?.username ?? null;
  }

  return {
    spotId: spot.id,
    externalId: spot.externalId ?? null,
    description: spot.description ?? null,
    communityDescription: spot.communityDescription ?? null,
    communityDescriptionAuthorId:
      spot.communityDescriptionAuthorId ?? null,
    communityDescriptionAuthorUsername: authorUsername,
    communityDescriptionUpdatedAt:
      spot.communityDescriptionUpdatedAt ?? null,
  };
}

function registerCommunityDescriptionRoutes(
  app,
  { getDb, authenticateToken }
) {
  // ============================================================
  // 1. LIRE UNE DESCRIPTION - SKATESPOT
  // GET /api/spots/:id/community-description
  // ============================================================

  app.get(
    '/api/spots/:id/community-description',
    async (req, res) => {
      const spotId = Number(req.params.id);

      if (!isValidId(spotId)) {
        return res.status(400).json({
          message: 'Identifiant de spot invalide.',
        });
      }

      try {
        const db = await getDb();

        const spot = await db.orm.public.SkateSpot
          .where({ id: spotId })
          .first();

        if (!spot) {
          return res.status(404).json({
            message: 'Spot introuvable.',
          });
        }

        return res.json({
          description: await formatDescription(db, spot),
        });
      } catch (error) {
        console.error(
          'Erreur de lecture de description :',
          error
        );

        return res.status(500).json({
          message: 'Erreur lors de la lecture de la description.',
        });
      }
    }
  );

  // ============================================================
  // 2. LIRE UNE DESCRIPTION - RIDEMYPARK
  // GET /api/ridemypark/spots/:externalId/community-description
  //
  // Ne crée aucun spot en base lors d'une simple lecture.
  // ============================================================

  app.get(
    '/api/ridemypark/spots/:externalId/community-description',
    async (req, res) => {
      const externalId = req.params.externalId;

      if (!isValidExternalId(externalId)) {
        return res.status(400).json({
          message: 'Identifiant RideMyPark invalide.',
        });
      }

      try {
        const db = await getDb();

        const spot = await db.orm.public.SkateSpot
          .where({
            externalSource: 'ridemypark',
            externalId,
          })
          .first();

        return res.json({
          description: await formatDescription(
            db,
            spot,
            externalId
          ),
        });
      } catch (error) {
        console.error(
          'Erreur de lecture de description RideMyPark :',
          error
        );

        return res.status(500).json({
          message: 'Erreur lors de la lecture de la description.',
        });
      }
    }
  );

  // ============================================================
  // 3. CRÉER OU MODIFIER UNE DESCRIPTION
  //
  // PUT /api/spots/:id/community-description
  // PUT /api/ridemypark/spots/:externalId/community-description
  //
  // Corps JSON :
  // { "communityDescription": "Description proposée" }
  // ============================================================

  function updateDescription(isRideMyPark) {
    return async (req, res) => {
      const spotId = isRideMyPark
        ? null
        : Number(req.params.id);

      const externalId = isRideMyPark
        ? req.params.externalId
        : null;

      if (
        isRideMyPark
          ? !isValidExternalId(externalId)
          : !isValidId(spotId)
      ) {
        return res.status(400).json({
          message: 'Identifiant de spot invalide.',
        });
      }

      const value = req.body?.communityDescription;

      if (typeof value !== 'string') {
        return res.status(400).json({
          message: 'La description doit être un texte.',
        });
      }

      const communityDescription = value.trim();

      if (
        communityDescription.length === 0 ||
        communityDescription.length > MAX_DESCRIPTION_LENGTH
      ) {
        return res.status(400).json({
          message:
            'La description doit contenir entre 1 et 2000 caractères.',
        });
      }

      try {
        const db = await getDb();
        const userId = req.authUserId;

        const user = await db.orm.public.User
          .where({ id: userId })
          .first();

        if (!user) {
          return res.status(401).json({
            message: 'Utilisateur authentifié introuvable.',
          });
        }

        let spot;

        if (isRideMyPark) {
          // Réutilise le mécanisme d'import existant :
          // externalId RideMyPark -> id interne SkateSpot.
          spot = await findRideMyParkSpot(
            db,
            externalId,
            userId
          );
        } else {
          spot = await db.orm.public.SkateSpot
            .where({ id: spotId })
            .first();
        }

        if (!spot) {
          return res.status(404).json({
            message: 'Spot introuvable.',
          });
        }

        const existingDescription =
          typeof spot.communityDescription === 'string' &&
          spot.communityDescription.trim().length > 0;

        const currentAuthorId =
          spot.communityDescriptionAuthorId;

        // Une description existante appartient à son auteur.
        if (existingDescription && currentAuthorId !== userId) {
          return res.status(403).json({
            message:
              'Seul l’auteur de cette description peut la modifier.',
          });
        }

        // Une description vide mais avec un auteur déjà associé
        // ne doit pas pouvoir être revendiquée par quelqu'un d'autre.
        if (
          !existingDescription &&
          currentAuthorId != null &&
          currentAuthorId !== userId
        ) {
          return res.status(403).json({
            message:
              'Cette description est réservée à son auteur.',
          });
        }



        const isFirstCreation = !existingDescription;
        const now = new Date().toISOString();

        const updates = {
          communityDescription,
          communityDescriptionUpdatedAt: now,
        };

        if (currentAuthorId == null) {
          updates.communityDescriptionAuthorId = userId;
        }

        // La description originale "description" reste intacte.
        await db.orm.public.SkateSpot
          .where({ id: spot.id })
          .update(updates);

        const updatedSpot = await db.orm.public.SkateSpot
          .where({ id: spot.id })
          .first();

        return res.status(isFirstCreation ? 201 : 200).json({
          message: isFirstCreation
            ? 'Description communautaire créée.'
            : 'Description communautaire modifiée.',
          description: await formatDescription(
            db,
            updatedSpot,
            externalId
          ),
        });
      } catch (error) {
        console.error(
          'Erreur de modification de description :',
          error
        );

        return res.status(error.statusCode || 500).json({
          message:
            error.statusCode && error.message
              ? error.message
              : 'Erreur lors de l’enregistrement de la description.',
        });
      }
    };
  }

  app.put(
    '/api/spots/:id/community-description',
    authenticateToken,
    updateDescription(false)
  );

  app.put(
    '/api/ridemypark/spots/:externalId/community-description',
    authenticateToken,
    updateDescription(true)
  );
}

module.exports = {
  registerCommunityDescriptionRoutes,
};
