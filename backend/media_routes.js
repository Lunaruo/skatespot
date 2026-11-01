const multer = require('multer');
const sharp = require('sharp');
const { v2: cloudinary } = require('cloudinary');

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const MAX_ACTIVE_PHOTOS_PER_USER_PER_SPOT = 10;

const ALLOWED_FORMATS = new Set(['jpeg', 'png', 'webp']);
const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

// Configuration de Cloudinary à partir du fichier .env.
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

// Réception d'une seule photo de 5 Mo maximum.
const upload = multer({
  storage: multer.memoryStorage(),

  limits: {
    fileSize: MAX_PHOTO_BYTES,
    files: 1,
    fields: 5,
  },

  fileFilter(_req, file, callback) {
  // Le type MIME fourni par le téléphone n'est pas fiable.
  // Le véritable format sera vérifié par Sharp après réception.
  callback(null, true);
},

});

// Sérialisation des vérifications de quota par utilisateur et par spot.
// Cela évite les dépassements lors de publications simultanées
// traitées par cette instance du serveur.
const uploadLocks = new Map();

async function withUploadLock(key, operation) {
  const previous = uploadLocks.get(key) || Promise.resolve();

  let release;

  const current = new Promise((resolve) => {
    release = resolve;
  });

  const tail = previous.then(() => current);

  uploadLocks.set(key, tail);

  await previous;

  try {
    return await operation();
  } finally {
    release();

    if (uploadLocks.get(key) === tail) {
      uploadLocks.delete(key);
    }
  }
}

// Gestion des erreurs de réception du fichier.
function runUploadMiddleware(req, res, next) {
  upload.single('photo')(req, res, (error) => {
    if (!error) {
      return next();
    }

    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({
        message: 'La photo ne doit pas dépasser 5 Mo.',
      });
    }

    return res.status(400).json({
      message:
        error.message || 'Impossible de recevoir la photo.',
    });
  });
}

// Envoi d'une image vers Cloudinary.
function cloudinaryUpload(buffer, format) {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: 'skatespot/spots',
        resource_type: 'image',
        format,
        unique_filename: true,
        overwrite: false,
      },
      (error, result) => {
        if (error) {
          return reject(error);
        }

        if (
          !result ||
          !result.secure_url ||
          !result.public_id
        ) {
          return reject(
            new Error(
              'Cloudinary n’a pas retourné les informations de la photo.'
            )
          );
        }

        resolve(result);
      }
    );

    stream.end(buffer);
  });
}

// Suppression d'une image sur Cloudinary.
async function cloudinaryDelete(publicId) {
  if (!publicId) {
    return;
  }

  try {
    await cloudinary.uploader.destroy(publicId, {
      resource_type: 'image',
    });
  } catch (error) {
    console.error(
      'Suppression Cloudinary impossible pour',
      publicId,
      error.message
    );
  }
}

// Enregistrement des routes de gestion des photos.
function registerMediaRoutes(
  app,
  { getDb, authenticateToken }
) {
  const cloudinaryConfigured = Boolean(
    process.env.CLOUDINARY_CLOUD_NAME &&
      process.env.CLOUDINARY_API_KEY &&
      process.env.CLOUDINARY_API_SECRET
  );

  // ============================================================
  // 1. AFFICHER LES PHOTOS D'UN SPOT
  //
  // GET /api/spots/:id/media?page=1&limit=12
  // ============================================================

  app.get('/api/spots/:id/media', async (req, res) => {
    const spotId = Number(req.params.id);

    if (
      !Number.isSafeInteger(spotId) ||
      spotId <= 0
    ) {
      return res.status(400).json({
        message: 'Identifiant de spot invalide.',
      });
    }

    const requestedPage = Number(req.query.page);
    const requestedLimit = Number(req.query.limit);

    const page =
      Number.isSafeInteger(requestedPage) &&
      requestedPage > 0
        ? requestedPage
        : 1;

    const limit =
      Number.isSafeInteger(requestedLimit) &&
      requestedLimit > 0
        ? Math.min(requestedLimit, 30)
        : 12;

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

      const allMedia = await db.orm.public.SpotMedia
        .where({
          spotId,
          deletedAt: null,
          moderationStatus: 'approved',
        })
        .all();

      const visible = allMedia.sort(
        (a, b) =>
          new Date(b.createdAt).getTime() -
          new Date(a.createdAt).getTime()
      );

      const start = (page - 1) * limit;

      const media = visible
        .slice(start, start + limit)
        .map((item) => ({
          id: item.id,
          url: item.url,
          type: item.type,
          spotId: item.spotId,
          userId: item.userId,
          createdAt: item.createdAt,
        }));

      return res.json({
        media,
        page,
        limit,
        total: visible.length,
        hasMore: start + media.length < visible.length,
      });
    } catch (error) {
      console.error(
        'Erreur de récupération des photos :',
        error
      );

      return res.status(500).json({
        message:
          'Erreur lors de la récupération des photos.',
      });
    }
  });


  // ============================================================
  // 1 BIS. AFFICHER LES PHOTOS D'UN SPOT RIDEMYPARK
  //
  // GET /api/ridemypark/spots/:externalId/media?page=1&limit=12
  // ============================================================

  app.get(
    '/api/ridemypark/spots/:externalId/media',
    async (req, res) => {
      const externalId = req.params.externalId;

      if (!/^\d+$/.test(externalId)) {
        return res.status(400).json({
          message: 'Identifiant RideMyPark invalide.',
        });
      }

      const requestedPage = Number(req.query.page);
      const requestedLimit = Number(req.query.limit);

      const page =
        Number.isSafeInteger(requestedPage) &&
        requestedPage > 0
          ? requestedPage
          : 1;

      const limit =
        Number.isSafeInteger(requestedLimit) &&
        requestedLimit > 0
          ? Math.min(requestedLimit, 30)
          : 12;

      try {
        const db = await getDb();

        // Retrouver le spot importé dans SkateSpot.
        const spot = await db.orm.public.SkateSpot
          .where({
            externalSource: 'ridemypark',
            externalId,
          })
          .first();

        // Un spot non importé ne possède pas encore
        // de photos publiées sur SkateSpot.
        if (!spot) {
          return res.json({
            media: [],
            page,
            limit,
            total: 0,
            hasMore: false,
          });
        }

        // Récupérer uniquement les photos visibles.
        const allMedia = await db.orm.public.SpotMedia
          .where({
            spotId: spot.id,
            deletedAt: null,
            moderationStatus: 'approved',
          })
          .all();

        const visible = allMedia.sort(
          (a, b) =>
            new Date(b.createdAt).getTime() -
            new Date(a.createdAt).getTime()
        );

        const start = (page - 1) * limit;

        const media = visible
          .slice(start, start + limit)
          .map((item) => ({
            id: item.id,
            url: item.url,
            type: item.type,
            spotId: item.spotId,
            userId: item.userId,
            createdAt: item.createdAt,
          }));

        return res.json({
          media,
          page,
          limit,
          total: visible.length,
          hasMore: start + media.length < visible.length,
        });
      } catch (error) {
        console.error(
          'Erreur de récupération des photos RideMyPark :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors de la récupération des photos.',
        });
      }
    }
  );


  // ============================================================
  // 2. PUBLIER UNE PHOTO
  //
  // POST /api/spots/:id/media
  // Authentification obligatoire.
  // Corps : multipart/form-data, champ "photo".
  // ============================================================

  app.post(
    '/api/spots/:id/media',
    authenticateToken,
    runUploadMiddleware,
    async (req, res) => {
      const spotId = Number(req.params.id);

      if (
        !Number.isSafeInteger(spotId) ||
        spotId <= 0
      ) {
        return res.status(400).json({
          message: 'Identifiant de spot invalide.',
        });
      }

      if (!req.file) {
        return res.status(400).json({
          message: 'Sélectionnez une photo à publier.',
        });
      }

      if (!cloudinaryConfigured) {
        return res.status(503).json({
          message:
            'Le stockage des photos n’est pas configuré.',
        });
      }

      try {
        // Vérifier le contenu réel de l'image.
        // Le MIME fourni par le client ne suffit pas.
        const metadata = await sharp(req.file.buffer, {
          failOn: 'error',
          limitInputPixels: 40000000,
        }).metadata();

        if (!ALLOWED_FORMATS.has(metadata.format)) {
          return res.status(415).json({
            message:
              'Format refusé. Seules les images JPEG, PNG et WebP sont acceptées.',
          });
        }

        if (!metadata.width || !metadata.height) {
          return res.status(400).json({
            message: 'Fichier image invalide.',
          });
        }

        // Décoder et réencoder l'image.
        // L'orientation est corrigée et les métadonnées inutiles
        // ne sont pas conservées.
        const normalizedBuffer = await sharp(
          req.file.buffer,
          {
            failOn: 'error',
            limitInputPixels: 40000000,
          }
        )
          .rotate()
          .toFormat(
            metadata.format,
            metadata.format === 'jpeg'
              ? { quality: 90 }
              : undefined
          )
          .toBuffer();

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
            message:
              'Utilisateur authentifié introuvable.',
          });
        }

        const lockKey = `${req.authUserId}:${spotId}`;

        const media = await withUploadLock(
          lockKey,
          async () => {
            // Les photos supprimées ne comptent plus.
            const activePhotos =
              await db.orm.public.SpotMedia
                .where({
                  userId: req.authUserId,
                  spotId,
                  deletedAt: null,
                })
                .all();

            if (
              activePhotos.length >=
              MAX_ACTIVE_PHOTOS_PER_USER_PER_SPOT
            ) {
              const error = new Error('QUOTA_REACHED');
              error.code = 'QUOTA_REACHED';
              throw error;
            }

            // La photo est hébergée avant l'enregistrement
            // de ses métadonnées en base.
            const uploaded = await cloudinaryUpload(
              normalizedBuffer,
              metadata.format
            );

            try {
              return await db.orm.public.SpotMedia.create({
                url: uploaded.secure_url,
                type: metadata.format,
                storageKey: uploaded.public_id,
                moderationStatus: 'approved',
                moderationReason: null,
                deletedAt: null,
                userId: req.authUserId,
                spotId,
              });
            } catch (error) {
              // Éviter de laisser un fichier orphelin
              // si l'enregistrement en base échoue.
              await cloudinaryDelete(uploaded.public_id);
              throw error;
            }
          }
        );

        return res.status(201).json({
          message: 'Photo publiée avec succès.',
          media: {
            id: media.id,
            url: media.url,
            type: media.type,
            spotId: media.spotId,
            userId: media.userId,
            createdAt: media.createdAt,
          },
        });
      } catch (error) {
        if (error.code === 'QUOTA_REACHED') {
          return res.status(409).json({
            message:
              'Vous avez atteint la limite de 10 photos actives pour ce spot.',
          });
        }

        if (
          error.name === 'InputError' ||
          /unsupported image format|corrupt|input buffer/i.test(
            error.message || ''
          )
        ) {
          return res.status(415).json({
            message:
              'Le fichier fourni n’est pas une image valide.',
          });
        }

        console.error(
          'Erreur de publication de photo :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors de la publication de la photo.',
        });
      }
    }
  );

  // ============================================================
  // 2 BIS. PUBLIER UNE PHOTO SUR UN SPOT RIDEMY​​PARK
  //
  // POST /api/ridemypark/spots/:externalId/media
  // Corps : multipart/form-data, champ "photo".
  // ============================================================

  app.post(
    '/api/ridemypark/spots/:externalId/media',
    authenticateToken,
    runUploadMiddleware,
    async (req, res) => {
      const externalId = req.params.externalId;

      if (!/^\d+$/.test(externalId)) {
        return res.status(400).json({
          message: 'Identifiant RideMyPark invalide.',
        });
      }

      if (!req.file) {
        return res.status(400).json({
          message: 'Sélectionnez une photo à publier.',
        });
      }

      if (!cloudinaryConfigured) {
        return res.status(503).json({
          message: 'Le stockage des photos n’est pas configuré.',
        });
      }

      try {
        // 1. Vérifier le contenu réel de l'image.
        const metadata = await sharp(req.file.buffer, {
          failOn: 'error',
          limitInputPixels: 40000000,
        }).metadata();

        if (!ALLOWED_FORMATS.has(metadata.format)) {
          return res.status(415).json({
            message:
              'Format refusé. Seules les images JPEG, PNG et WebP sont acceptées.',
          });
        }

        if (!metadata.width || !metadata.height) {
          return res.status(400).json({
            message: 'Fichier image invalide.',
          });
        }

        // 2. Normaliser l'image.
        const normalizedBuffer = await sharp(req.file.buffer, {
          failOn: 'error',
          limitInputPixels: 40000000,
        })
          .rotate()
          .toFormat(
            metadata.format,
            metadata.format === 'jpeg'
              ? { quality: 90 }
              : undefined
          )
          .toBuffer();

        const db = await getDb();

        // 3. Vérifier l'utilisateur connecté.
        const user = await db.orm.public.User
          .where({ id: req.authUserId })
          .first();

        if (!user) {
          return res.status(401).json({
            message: 'Utilisateur authentifié introuvable.',
          });
        }

        // 4. Rechercher si le spot RideMyPark existe déjà
        // dans notre base SkateSpot.
        let spot = await db.orm.public.SkateSpot
          .where({
            externalSource: 'ridemypark',
            externalId,
          })
          .first();

        let imported = false;

        // 5. Si absent, récupérer sa fiche depuis RideMyPark.
        if (!spot) {
          const apiUrl =
            'https://api.ridemypark.com/wp-json/rmp/v1/listing' +
            `?listing_id=${encodeURIComponent(externalId)}`;

          const apiResponse = await fetch(apiUrl, {
            headers: {
              Accept: 'application/json',
            },
          });

          if (!apiResponse.ok) {
            return res.status(502).json({
              message:
                'Impossible de récupérer les informations du spot RideMyPark.',
            });
          }

          const listing = await apiResponse.json();

          const latitude = Number(listing.latitude);
          const longitude = Number(listing.longitude);

          // Vérifier les informations reçues de l'API.
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
            return res.status(404).json({
              message:
                'Spot introuvable ou informations RideMyPark invalides.',
            });
          }

          // 6. Importer le spot dans notre base SkateSpot.
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
              createdById: req.authUserId,
            });

            imported = true;
          } catch (creationError) {
            // Une autre publication a pu importer le spot
            // entre notre recherche et sa création.
            spot = await db.orm.public.SkateSpot
              .where({
                externalSource: 'ridemypark',
                externalId,
              })
              .first();

            if (!spot) {
              throw creationError;
            }
          }
        }

        // 7. Vérifier le quota de photos de l'utilisateur.
        const lockKey = `${req.authUserId}:${spot.id}`;

        const media = await withUploadLock(
          lockKey,
          async () => {
            const activePhotos =
              await db.orm.public.SpotMedia
                .where({
                  userId: req.authUserId,
                  spotId: spot.id,
                  deletedAt: null,
                })
                .all();

            if (
              activePhotos.length >=
              MAX_ACTIVE_PHOTOS_PER_USER_PER_SPOT
            ) {
              const error = new Error('QUOTA_REACHED');
              error.code = 'QUOTA_REACHED';
              throw error;
            }

            // 8. Envoyer la photo sur Cloudinary.
            const uploaded = await cloudinaryUpload(
              normalizedBuffer,
              metadata.format
            );

            try {
              // 9. Associer la photo à l'ID INTERNE SkateSpot.
              return await db.orm.public.SpotMedia.create({
                url: uploaded.secure_url,
                type: metadata.format,
                storageKey: uploaded.public_id,
                moderationStatus: 'approved',
                moderationReason: null,
                deletedAt: null,
                userId: req.authUserId,
                spotId: spot.id,
              });
            } catch (error) {
              await cloudinaryDelete(uploaded.public_id);
              throw error;
            }
          }
        );

        return res.status(201).json({
          message: 'Photo publiée avec succès.',
          imported,
          spot: {
            id: spot.id,
            name: spot.name,
            externalSource: spot.externalSource,
            externalId: spot.externalId,
          },
          media: {
            id: media.id,
            url: media.url,
            type: media.type,
            spotId: media.spotId,
            userId: media.userId,
            createdAt: media.createdAt,
          },
        });
      } catch (error) {
        if (error.code === 'QUOTA_REACHED') {
          return res.status(409).json({
            message:
              'Vous avez atteint la limite de 10 photos actives pour ce spot.',
          });
        }

        if (
          error.name === 'InputError' ||
          /unsupported image format|corrupt|input buffer/i.test(
            error.message || ''
          )
        ) {
          return res.status(415).json({
            message: 'Le fichier fourni n’est pas une image valide.',
          });
        }

        console.error(
          'Erreur de publication sur un spot RideMyPark :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors de la publication de la photo sur ce spot.',
        });
      }
    }
  );



  // ============================================================
  // 3. SUPPRIMER SA PROPRE PHOTO
  //
  // DELETE /api/media/:id
  // ============================================================

  app.delete(
    '/api/media/:id',
    authenticateToken,
    async (req, res) => {
      const mediaId = Number(req.params.id);

      if (
        !Number.isSafeInteger(mediaId) ||
        mediaId <= 0
      ) {
        return res.status(400).json({
          message: 'Identifiant de photo invalide.',
        });
      }

      try {
        const db = await getDb();

        const media = await db.orm.public.SpotMedia
          .where({ id: mediaId })
          .first();

        if (!media || media.deletedAt) {
          return res.status(404).json({
            message: 'Photo introuvable.',
          });
        }

        if (media.userId !== req.authUserId) {
          return res.status(403).json({
            message:
              'Vous ne pouvez supprimer que vos propres photos.',
          });
        }

        // Suppression logique : la photo est masquée et
        // ne compte plus dans le quota.
        await db.orm.public.SpotMedia
          .where({ id: mediaId })
          .update({
            deletedAt: new Date().toISOString(),
          });

        await cloudinaryDelete(media.storageKey);

        return res.json({
          message: 'Photo supprimée.',
        });
      } catch (error) {
        console.error(
          'Erreur de suppression de photo :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors de la suppression de la photo.',
        });
      }
    }
  );

  // ============================================================
  // 4. SIGNALER UNE PHOTO
  //
  // POST /api/media/:id/reports
  // Corps JSON : { "reason": "..." }
  // ============================================================

  app.post(
    '/api/media/:id/reports',
    authenticateToken,
    async (req, res) => {
      const mediaId = Number(req.params.id);

      const reason =
        typeof req.body?.reason === 'string'
          ? req.body.reason.trim()
          : '';

      if (
        !Number.isSafeInteger(mediaId) ||
        mediaId <= 0
      ) {
        return res.status(400).json({
          message: 'Identifiant de photo invalide.',
        });
      }

      if (reason.length < 3 || reason.length > 500) {
        return res.status(400).json({
          message:
            'Le motif doit contenir entre 3 et 500 caractères.',
        });
      }

      try {
        const db = await getDb();

        const media = await db.orm.public.SpotMedia
          .where({ id: mediaId })
          .first();

        if (
          !media ||
          media.deletedAt ||
          media.moderationStatus !== 'approved'
        ) {
          return res.status(404).json({
            message: 'Photo introuvable.',
          });
        }

        // Le signalement ne masque pas automatiquement
        // la photo : une décision de modération est nécessaire.
        const report =
          await db.orm.public.SpotMediaReport.create({
            mediaId,
            reporterId: req.authUserId,
            reason,
            status: 'pending',
            reviewedAt: null,
          });

        return res.status(201).json({
          message:
            'Signalement transmis. La photo reste visible pendant son examen.',
          report: {
            id: report.id,
            mediaId: report.mediaId,
            status: report.status,
          },
        });
      } catch (error) {
        console.error(
          'Erreur de signalement de photo :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors du signalement de la photo.',
        });
      }
    }
  );

  // ============================================================
  // 5. RETIRER UNE PHOTO AU TITRE DE LA MODÉRATION
  //
  // DELETE /api/media/:id/moderate
  //
  // Configurer SKATESPOT_MODERATOR_IDS dans .env avec
  // une liste d'identifiants utilisateur séparés par des virgules.
  // ============================================================

  app.delete(
    '/api/media/:id/moderate',
    authenticateToken,
    async (req, res) => {
      const moderatorIds = (
        process.env.SKATESPOT_MODERATOR_IDS || ''
      )
        .split(',')
        .map((value) => Number(value.trim()))
        .filter(
          (value) =>
            Number.isSafeInteger(value) && value > 0
        );

      if (!moderatorIds.includes(req.authUserId)) {
        return res.status(403).json({
          message: 'Action réservée à la modération.',
        });
      }

      const mediaId = Number(req.params.id);

      const reason =
        typeof req.body?.reason === 'string'
          ? req.body.reason.trim().slice(0, 500)
          : 'Retrait par la modération';

      if (
        !Number.isSafeInteger(mediaId) ||
        mediaId <= 0
      ) {
        return res.status(400).json({
          message: 'Identifiant de photo invalide.',
        });
      }

      try {
        const db = await getDb();

        const media = await db.orm.public.SpotMedia
          .where({ id: mediaId })
          .first();

        if (!media || media.deletedAt) {
          return res.status(404).json({
            message: 'Photo introuvable.',
          });
        }

        await db.orm.public.SpotMedia
          .where({ id: mediaId })
          .update({
            deletedAt: new Date().toISOString(),
            moderationStatus: 'rejected',
            moderationReason:
              reason || 'Retrait par la modération',
          });

        await cloudinaryDelete(media.storageKey);

        return res.json({
          message: 'Photo retirée par la modération.',
        });
      } catch (error) {
        console.error(
          'Erreur de modération de photo :',
          error
        );

        return res.status(500).json({
          message:
            'Erreur lors du retrait de la photo.',
        });
      }
    }
  );
}

module.exports = {
  registerMediaRoutes,
};