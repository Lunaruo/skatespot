
async function findRideMyParkSpot(db, externalId, userId) {
  // Rechercher une fiche dÃ©jÃ  importÃ©e.
  let spot = await db.orm.public.SkateSpot
    .where({
      externalSource: 'ridemypark',
      externalId,
    })
    .first();

  if (spot) {
    return { spot, imported: false };
  }

  // RÃ©cupÃ©rer la fiche depuis RideMyPark.
  const apiUrl =
    'https://api.ridemypark.com/wp-json/rmp/v1/listing' +
    `?listing_id=${encodeURIComponent(externalId)}`;

  const apiResponse = await fetch(apiUrl, {
    headers: {
      Accept: 'application/json',
    },
  });

  if (!apiResponse.ok) {
    const error = new Error(
      'Impossible de rÃ©cupÃ©rer les informations du spot RideMyPark.'
    );
    error.statusCode = 502;
    throw error;
  }

  const listing = await apiResponse.json();

  const latitude = Number(listing.latitude);
  const longitude = Number(listing.longitude);

  if (
    String(listing.ID) !== externalId ||
    listing.listing_type !== 'spot' ||
    typeof listing.title !== 'string' ||
    !listing.title.trim() ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    const error = new Error(
      'Spot introuvable ou informations RideMyPark invalides.'
    );
    error.statusCode = 404;
    throw error;
  }

  // Importer la fiche dans SkateSpot.
  try {
    spot = await db.orm.public.SkateSpot.create({
      name: listing.title.trim(),
      description:
        typeof listing.description === 'string'
          ? listing.description
          : null,
      address:
        typeof listing.formattedAddress === 'string'
          ? listing.formattedAddress
          : null,
      latitude,
      longitude,
      externalSource: 'ridemypark',
      externalId,
      createdById: userId,
    });

    return { spot, imported: true };
  } catch (creationError) {
    // Une autre requÃªte a Ã©ventuellement importÃ© le spot
    // entre la recherche et sa crÃ©ation.
    spot = await db.orm.public.SkateSpot
      .where({
        externalSource: 'ridemypark',
        externalId,
      })
      .first();

    if (!spot) {
      throw creationError;
    }

    return { spot, imported: false };
  }
}

async function formatComments(db, spotId) {
  const comments = await db.orm.public.SpotComment
    .where({ spotId })
    .all();

  comments.sort(
    (a, b) =>
      new Date(b.createdAt).getTime() -
      new Date(a.createdAt).getTime()
  );

  const userIds = [
    ...new Set(comments.map((comment) => comment.userId)),
  ];

  const users = await Promise.all(
    userIds.map((userId) =>
      db.orm.public.User.where({ id: userId }).first()
    )
  );

  const usersById = new Map(
    users
      .filter(Boolean)
      .map((user) => [user.id, user.username])
  );

  return comments.map((comment) => ({
    id: comment.id,
    content: comment.content,
    userId: comment.userId,
    username: usersById.get(comment.userId) || 'Utilisateur',
    spotId: comment.spotId,
    createdAt: comment.createdAt,
  }));
}

function registerCommentRoutes(app, { getDb, authenticateToken }) {

  // ============================================================
  // GET /api/spots/:id/comments
  // Commentaires d'un spot SkateSpot interne.
  // Route publique.
  // ============================================================

  app.get('/api/spots/:id/comments', async (req, res) => {
    const spotId = Number(req.params.id);

    if (!Number.isSafeInteger(spotId) || spotId <= 0) {
      return res.status(400).json({
        message: 'Identifiant du spot invalide.',
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

      const comments = await formatComments(db, spotId);

      return res.json({
        spotId,
        comments,
      });
    } catch (error) {
      console.error(
        'Erreur lors de la rÃ©cupÃ©ration des commentaires :',
        error
      );

      return res.status(500).json({
        message: 'Erreur lors de la rÃ©cupÃ©ration des commentaires.',
      });
    }
  });


  // ============================================================
  // POST /api/spots/:id/comments
  // Publier sur un spot SkateSpot interne.
  // JWT obligatoire.
  // ============================================================

  app.post(
    '/api/spots/:id/comments',
    authenticateToken,
    async (req, res) => {
      const spotId = Number(req.params.id);

      if (!Number.isSafeInteger(spotId) || spotId <= 0) {
        return res.status(400).json({
          message: 'Identifiant du spot invalide.',
        });
      }

      const content =
        typeof req.body?.content === 'string'
          ? req.body.content.trim()
          : '';

      if (!content) {
        return res.status(400).json({
          message: 'Le commentaire ne peut pas Ãªtre vide.',
        });
      }

      if (content.length > 1000) {
        return res.status(400).json({
          message: 'Le commentaire ne peut pas dÃ©passer 1000 caractÃ¨res.',
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

        const user = await db.orm.public.User
          .where({ id: req.authUserId })
          .first();

        if (!user) {
          return res.status(401).json({
            message: 'Utilisateur authentifiÃ© introuvable.',
          });
        }

        const comment = await db.orm.public.SpotComment.create({
          content,
          userId: req.authUserId,
          spotId,
        });

        return res.status(201).json({
          message: 'Commentaire publiÃ© avec succÃ¨s.',
          comment: {
            id: comment.id,
            content: comment.content,
            userId: comment.userId,
            username: user.username,
            spotId: comment.spotId,
            createdAt: comment.createdAt,
          },
        });
      } catch (error) {
        console.error(
          'Erreur lors de la publication du commentaire :',
          error
        );

        return res.status(500).json({
          message: 'Erreur lors de la publication du commentaire.',
        });
      }
    }
  );


  // ============================================================
  // GET /api/ridemypark/spots/:externalId/comments
  // Commentaires d'un spot RideMyPark.
  // Route publique.
  // ============================================================

  app.get(
    '/api/ridemypark/spots/:externalId/comments',
    async (req, res) => {
      const externalId = req.params.externalId;

      if (!/^\d+$/.test(externalId)) {
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

        // Ne pas importer un spot simplement parce qu'on
        // consulte ses commentaires.
        if (!spot) {
          return res.json({
            spotId: null,
            comments: [],
          });
        }

        const comments = await formatComments(db, spot.id);

        return res.json({
          spotId: spot.id,
          comments,
        });
      } catch (error) {
        console.error(
          'Erreur lors de la rÃ©cupÃ©ration des commentaires RideMyPark :',
          error
        );

        return res.status(500).json({
          message: 'Erreur lors de la rÃ©cupÃ©ration des commentaires.',
        });
      }
    }
  );


  // ============================================================
  // POST /api/ridemypark/spots/:externalId/comments
  // Publier sur un spot RideMyPark.
  // Import automatique si nÃ©cessaire.
  // JWT obligatoire.
  // ============================================================

  app.post(
    '/api/ridemypark/spots/:externalId/comments',
    authenticateToken,
    async (req, res) => {
      const externalId = req.params.externalId;

      if (!/^\d+$/.test(externalId)) {
        return res.status(400).json({
          message: 'Identifiant RideMyPark invalide.',
        });
      }

      const content =
        typeof req.body?.content === 'string'
          ? req.body.content.trim()
          : '';

      if (!content) {
        return res.status(400).json({
          message: 'Le commentaire ne peut pas Ãªtre vide.',
        });
      }

      if (content.length > 1000) {
        return res.status(400).json({
          message: 'Le commentaire ne peut pas dÃ©passer 1000 caractÃ¨res.',
        });
      }

      try {
        const db = await getDb();

        const user = await db.orm.public.User
          .where({ id: req.authUserId })
          .first();

        if (!user) {
          return res.status(401).json({
            message: 'Utilisateur authentifiÃ© introuvable.',
          });
        }

        const { spot, imported } = await findRideMyParkSpot(
          db,
          externalId,
          req.authUserId
        );

        const comment = await db.orm.public.SpotComment.create({
          content,
          userId: req.authUserId,
          spotId: spot.id,
        });

        return res.status(201).json({
          message: 'Commentaire publiÃ© avec succÃ¨s.',
          imported,
          spot: {
            id: spot.id,
            name: spot.name,
            externalSource: spot.externalSource,
            externalId: spot.externalId,
          },
          comment: {
            id: comment.id,
            content: comment.content,
            userId: comment.userId,
            username: user.username,
            spotId: comment.spotId,
            createdAt: comment.createdAt,
          },
        });
      } catch (error) {
        console.error(
          'Erreur lors de la publication du commentaire RideMyPark :',
          error
        );

        return res.status(error.statusCode || 500).json({
          message:
            error.statusCode
              ? error.message
              : 'Erreur lors de la publication du commentaire.',
        });
      }
    }
  );
}

module.exports = {
  registerCommentRoutes,
  findRideMyParkSpot,
};
