
const MAX_REASON_LENGTH = 500;
const MAX_DETAILS_LENGTH = 500;

function validId(value) {
  return Number.isSafeInteger(value) && value > 0;
}

function validateReportBody(body) {
  const reason =
    typeof body?.reason === 'string'
      ? body.reason.trim()
      : '';

  if (reason.length < 3 || reason.length > MAX_REASON_LENGTH) {
    return {
      error: 'Le motif doit contenir entre 3 et 500 caractères.',
    };
  }

  if (
    body?.details !== undefined &&
    body?.details !== null &&
    typeof body.details !== 'string'
  ) {
    return {
      error: 'La précision doit être un texte.',
    };
  }

  const details =
    typeof body?.details === 'string'
      ? body.details.trim()
      : '';

  if (details.length > MAX_DETAILS_LENGTH) {
    return {
      error: 'La précision ne doit pas dépasser 500 caractères.',
    };
  }

  return {
    reason,
    details: details || null,
  };
}

function registerContentReportRoutes(
  app,
  { getDb, authenticateToken }
) {
  // ============================================================
  // 1. SIGNALER UN COMMENTAIRE
  //
  // POST /api/comments/:commentId/reports
  // Fonctionne pour SkateSpot et RideMyPark.
  // ============================================================

  app.post(
    '/api/comments/:commentId/reports',
    authenticateToken,
    async (req, res) => {
      const commentId = Number(req.params.commentId);

      if (!validId(commentId)) {
        return res.status(400).json({
          message: 'Identifiant de commentaire invalide.',
        });
      }

      const input = validateReportBody(req.body);

      if (input.error) {
        return res.status(400).json({
          message: input.error,
        });
      }

      try {
        const db = await getDb();
        const reporterId = req.authUserId;

        const reporter = await db.orm.public.User
          .where({ id: reporterId })
          .first();

        if (!reporter) {
          return res.status(401).json({
            message: 'Utilisateur authentifié introuvable.',
          });
        }

        const comment = await db.orm.public.SpotComment
          .where({ id: commentId })
          .first();

        if (!comment) {
          return res.status(404).json({
            message: 'Commentaire introuvable.',
          });
        }

        if (comment.userId === reporterId) {
          return res.status(403).json({
            message:
              'Vous ne pouvez pas signaler votre propre commentaire.',
          });
        }

        const pendingReport =
          await db.orm.public.SpotCommentReport
            .where({
              commentId,
              reporterId,
              status: 'pending',
            })
            .first();

        if (pendingReport) {
          return res.status(409).json({
            message:
              'Vous avez déjà signalé ce commentaire.',
          });
        }

        const report =
          await db.orm.public.SpotCommentReport.create({
            commentId,
            reporterId,
            reason: input.reason,
            details: input.details,
            contentSnapshot: comment.content,
            status: 'pending',
            reviewedAt: null,
          });

        return res.status(201).json({
          message:
            'Commentaire signalé. Une modération est nécessaire.',
          report: {
            id: report.id,
            commentId: report.commentId,
            status: report.status,
          },
        });
      } catch (error) {
        console.error(
          'Erreur de signalement de commentaire :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors du signalement du commentaire.',
        });
      }
    }
  );

  // ============================================================
  // 2. SIGNALER UNE DESCRIPTION COMMUNAUTAIRE
  //
  // Utilisé par les routes SkateSpot et RideMyPark.
  // ============================================================

  function reportDescription(isRideMyPark) {
    return async (req, res) => {
      const spotId = isRideMyPark
        ? null
        : Number(req.params.id);

      const externalId = isRideMyPark
        ? req.params.externalId
        : null;

      if (
        isRideMyPark
          ? !/^\d+$/.test(externalId)
          : !validId(spotId)
      ) {
        return res.status(400).json({
          message: 'Identifiant de spot invalide.',
        });
      }

      const input = validateReportBody(req.body);

      if (input.error) {
        return res.status(400).json({
          message: input.error,
        });
      }

      try {
        const db = await getDb();
        const reporterId = req.authUserId;

        const reporter = await db.orm.public.User
          .where({ id: reporterId })
          .first();

        if (!reporter) {
          return res.status(401).json({
            message: 'Utilisateur authentifié introuvable.',
          });
        }

        const spot = isRideMyPark
          ? await db.orm.public.SkateSpot
              .where({
                externalSource: 'ridemypark',
                externalId,
              })
              .first()
          : await db.orm.public.SkateSpot
              .where({ id: spotId })
              .first();

        if (!spot) {
          return res.status(404).json({
            message: 'Spot introuvable.',
          });
        }

        const description = spot.communityDescription;

        if (
          typeof description !== 'string' ||
          !description.trim()
        ) {
          return res.status(404).json({
            message:
              'Aucune description communautaire à signaler.',
          });
        }

        if (spot.communityDescriptionAuthorId == null) {
          return res.status(409).json({
            message:
              'Auteur de la description introuvable.',
          });
        }

        if (
          spot.communityDescriptionAuthorId === reporterId
        ) {
          return res.status(403).json({
            message:
              'Vous ne pouvez pas signaler votre propre description.',
          });
        }

        const pendingReport =
          await db.orm.public.SpotCommunityDescriptionReport
            .where({
              spotId: spot.id,
              reporterId,
              status: 'pending',
            })
            .first();

        if (pendingReport) {
          return res.status(409).json({
            message:
              'Vous avez déjà signalé cette description.',
          });
        }

        const report =
          await db.orm.public.SpotCommunityDescriptionReport
            .create({
              spotId: spot.id,
              reporterId,
              reason: input.reason,
              details: input.details,
              descriptionSnapshot: description,
              status: 'pending',
              reviewedAt: null,
            });

        return res.status(201).json({
          message:
            'Description signalée. Une modération est nécessaire.',
          report: {
            id: report.id,
            spotId: report.spotId,
            status: report.status,
          },
        });
      } catch (error) {
        console.error(
          'Erreur de signalement de description :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors du signalement de la description.',
        });
      }
    };
  }

  app.post(
    '/api/spots/:id/community-description/reports',
    authenticateToken,
    reportDescription(false)
  );

  app.post(
    '/api/ridemypark/spots/:externalId/community-description/reports',
    authenticateToken,
    reportDescription(true)
  );
}

module.exports = {
  registerContentReportRoutes,
};
