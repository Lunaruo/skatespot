
require('dotenv').config();

const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const app = express();
const PORT = Number(process.env.PORT) || 3001;
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error(
    'JWT_SECRET absent ou trop court. VÃ©rifiez la configuration du fichier .env.'
  );
}

const JWT_ISSUER = 'skatespot-api';
const JWT_AUDIENCE = 'skatespot-app';

const ACCESS_TOKEN_SECONDS = 60 * 60;
const REFRESH_TOKEN_SECONDS = 30 * 24 * 60 * 60;

app.use(express.json());

async function getDb() {
  const { db } = await import('./src/prisma/db.ts');
  return db;
}

function createAccessToken(userId) {
  return jwt.sign({}, JWT_SECRET, {
    subject: String(userId),
    expiresIn: ACCESS_TOKEN_SECONDS,
    issuer: JWT_ISSUER,
    audience: JWT_AUDIENCE,
  });
}

function createRefreshToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function refreshTokenExpiry() {
  return new Date(
    Date.now() + REFRESH_TOKEN_SECONDS * 1000
  ).toISOString();
}

async function saveRefreshToken(db, userId, token) {
  await db.orm.public.RefreshToken.create({
    tokenHash: hashRefreshToken(token),
    userId,
    expiresAt: refreshTokenExpiry(),
  });
}

// Middleware : vÃ©rifier le jeton JWT et identifier l'utilisateur.
function authenticateToken(req, res, next) {
  const authorization = req.headers.authorization;

  if (typeof authorization !== 'string') {
    return res.status(401).json({
      message: 'Authentification requise',
    });
  }

  const parts = authorization.split(' ');

  if (parts.length !== 2 || parts[0] !== 'Bearer' || !parts[1]) {
    return res.status(401).json({
      message: 'Format du jeton invalide',
    });
  }

  try {
    const payload = jwt.verify(parts[1], JWT_SECRET, {
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
    });

    if (
      typeof payload !== 'object' ||
      typeof payload.sub !== 'string'
    ) {
      return res.status(401).json({
        message: 'Jeton invalide',
      });
    }

    const userId = Number(payload.sub);

    if (!Number.isSafeInteger(userId) || userId <= 0) {
      return res.status(401).json({
        message: 'IdentitÃ© utilisateur invalide',
      });
    }

    req.authUserId = userId;
    return next();
  } catch {
    return res.status(401).json({
      message: 'Jeton invalide ou expirÃ©',
    });
  }
}

// Route d'accueil
app.get('/', (req, res) => {
  res.json({
    message: 'Bienvenue sur l API SkateSpot',
  });
});

// Inscription
app.post('/api/auth/register', async (req, res) => {
  const { email, password } = req.body ?? {};
  let { username } = req.body ?? {};

  if (typeof email !== 'string' || typeof password !== 'string') {
    return res.status(400).json({
      message: 'Email et mot de passe requis',
    });
  }

  const normalizedEmail = email.trim().toLowerCase();

  if (
    normalizedEmail.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)
  ) {
    return res.status(400).json({
      message: 'Adresse email invalide',
    });
  }

  if (
    password.length < 8 ||
    Buffer.byteLength(password, 'utf8') > 72
  ) {
    return res.status(400).json({
      message:
        'Le mot de passe doit contenir au moins 8 caractÃ¨res et ne pas dÃ©passer 72 octets',
    });
  }

  if (username !== undefined && username !== null) {
    if (typeof username !== 'string') {
      return res.status(400).json({
        message: 'Nom dâ€™utilisateur invalide',
      });
    }

    username = username.trim();

    if (username === '') {
      username = null;
    } else if (username.length < 2 || username.length > 30) {
      return res.status(400).json({
        message:
          'Le nom dâ€™utilisateur doit contenir entre 2 et 30 caractÃ¨res',
      });
    }
  } else {
    username = null;
  }

  try {
    const db = await getDb();

    const existingEmail = await db.orm.public.User
      .where({ email: normalizedEmail })
      .first();

    if (existingEmail) {
      return res.status(409).json({
        message: 'Cette adresse email est dÃ©jÃ  utilisÃ©e',
      });
    }

    if (username !== null) {
      const existingUsername = await db.orm.public.User
        .where({ username })
        .first();

      if (existingUsername) {
        return res.status(409).json({
          message: 'Ce nom dâ€™utilisateur est dÃ©jÃ  utilisÃ©',
        });
      }
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const user = await db.orm.public.User.create({
      email: normalizedEmail,
      username,
      passwordHash,
    });

    return res.status(201).json({
      message: 'Compte crÃ©Ã© avec succÃ¨s',
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
      },
    });
  } catch (error) {
    console.error('Erreur lors de lâ€™inscription :', error);

    return res.status(500).json({
      message: 'Erreur lors de la crÃ©ation du compte',
    });
  }
});

// Connexion : crÃ©ation des deux jetons.
app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body ?? {};

  if (typeof email !== 'string' || typeof password !== 'string') {
    return res.status(400).json({
      message: 'Email et mot de passe requis',
    });
  }

  const normalizedEmail = email.trim().toLowerCase();

  try {
    const db = await getDb();

    const user = await db.orm.public.User
      .where({ email: normalizedEmail })
      .first();

    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      return res.status(401).json({
        message: 'Email ou mot de passe incorrect',
      });
    }

    const accessToken = createAccessToken(user.id);
    const refreshToken = createRefreshToken();

    await saveRefreshToken(db, user.id, refreshToken);

    return res.json({
      message: 'Connexion rÃ©ussie',
      token: accessToken,
      tokenType: 'Bearer',
      expiresIn: ACCESS_TOKEN_SECONDS,
      refreshToken,
      refreshTokenExpiresIn: REFRESH_TOKEN_SECONDS,
      user: {
        id: user.id,
        email: user.email,
        username: user.username,
      },
    });
  } catch (error) {
    console.error('Erreur lors de la connexion :', error);

    return res.status(500).json({
      message: 'Erreur lors de la connexion',
    });
  }
});

// Renouvellement : le jeton prÃ©cÃ©dent est remplacÃ© par un nouveau.
app.post('/api/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body ?? {};

  if (
    typeof refreshToken !== 'string' ||
    refreshToken.length < 40 ||
    refreshToken.length > 200
  ) {
    return res.status(401).json({
      message: 'Jeton de renouvellement invalide ou expirÃ©',
    });
  }

  try {
    const db = await getDb();
    const tokenHash = hashRefreshToken(refreshToken);

    const storedToken = await db.orm.public.RefreshToken
      .where({ tokenHash })
      .first();

    if (!storedToken) {
      return res.status(401).json({
        message: 'Jeton de renouvellement invalide ou expirÃ©',
      });
    }

    if (new Date(storedToken.expiresAt).getTime() <= Date.now()) {
      await db.orm.public.RefreshToken
        .where({ id: storedToken.id })
        .delete();

      return res.status(401).json({
        message: 'Jeton de renouvellement invalide ou expirÃ©',
      });
    }

    const user = await db.orm.public.User
      .where({ id: storedToken.userId })
      .first();

    if (!user) {
      await db.orm.public.RefreshToken
        .where({ id: storedToken.id })
        .delete();

      return res.status(401).json({
        message: 'Session invalide',
      });
    }

    // Invalider l'ancien jeton avant d'en Ã©mettre un nouveau.
    await db.orm.public.RefreshToken
      .where({ id: storedToken.id })
      .delete();

    const newRefreshToken = createRefreshToken();

    await saveRefreshToken(db, user.id, newRefreshToken);

    const accessToken = createAccessToken(user.id);

    return res.json({
      message: 'Session renouvelÃ©e',
      token: accessToken,
      tokenType: 'Bearer',
      expiresIn: ACCESS_TOKEN_SECONDS,
      refreshToken: newRefreshToken,
      refreshTokenExpiresIn: REFRESH_TOKEN_SECONDS,
    });
  } catch (error) {
    console.error('Erreur lors du renouvellement :', error);

    return res.status(500).json({
      message: 'Erreur lors du renouvellement de la session',
    });
  }
});

// DÃ©connexion : rÃ©vocation du jeton de renouvellement cÃ´tÃ© serveur.
app.post('/api/auth/logout', async (req, res) => {
  const { refreshToken } = req.body ?? {};

  try {
    if (
      typeof refreshToken === 'string' &&
      refreshToken.length >= 40 &&
      refreshToken.length <= 200
    ) {
      const db = await getDb();
      const tokenHash = hashRefreshToken(refreshToken);

      await db.orm.public.RefreshToken
        .where({ tokenHash })
        .delete();
    }

    // RÃ©ponse identique mÃªme si le jeton est absent ou inconnu.
    return res.json({
      message: 'DÃ©connexion effectuÃ©e',
    });
  } catch (error) {
    console.error('Erreur lors de la dÃ©connexion :', error);

    return res.status(500).json({
      message: 'Erreur lors de la dÃ©connexion',
    });
  }
});

// Liste de tous les spots
app.get('/api/spots', async (req, res) => {
  try {
    const db = await getDb();
    const spots = await db.orm.public.SkateSpot.all();

    return res.json({
      message: 'Liste des spots',
      count: spots.length,
      spots,
    });
  } catch (error) {
    console.error('Erreur lors de la rÃ©cupÃ©ration des spots :', error);

    return res.status(500).json({
      message: 'Erreur lors de la rÃ©cupÃ©ration des spots',
    });
  }
});

// DÃ©tail d'un spot
app.get('/api/spots/:id', async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isSafeInteger(id) || id <= 0) {
    return res.status(400).json({
      message: 'Identifiant de spot invalide',
    });
  }

  try {
    const db = await getDb();

    const spot = await db.orm.public.SkateSpot
      .where({ id })
      .first();

    if (!spot) {
      return res.status(404).json({
        message: 'Spot introuvable',
      });
    }

    return res.json({
      message: 'DÃ©tail du spot',
      spot,
    });
  } catch (error) {
    console.error('Erreur lors de la rÃ©cupÃ©ration du spot :', error);

    return res.status(500).json({
      message: 'Erreur lors de la rÃ©cupÃ©ration du spot',
    });
  }
});

// CrÃ©ation d'un spot : JWT obligatoire
app.post('/api/spots', authenticateToken, async (req, res) => {
  const {
    name,
    description,
    address,
    latitude,
    longitude,
  } = req.body ?? {};

  if (
    typeof name !== 'string' ||
    !name.trim() ||
    typeof latitude !== 'number' ||
    typeof longitude !== 'number' ||
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return res.status(400).json({
      message: 'DonnÃ©es invalides : nom et coordonnÃ©es requis',
    });
  }

  if (
    (description !== undefined &&
      description !== null &&
      typeof description !== 'string') ||
    (address !== undefined &&
      address !== null &&
      typeof address !== 'string')
  ) {
    return res.status(400).json({
      message:
        'La description et lâ€™adresse doivent Ãªtre des chaÃ®nes de caractÃ¨res',
    });
  }

  try {
    const db = await getDb();
    const createdById = req.authUserId;

    const user = await db.orm.public.User
      .where({ id: createdById })
      .first();

    if (!user) {
      return res.status(401).json({
        message: 'Utilisateur authentifiÃ© introuvable',
      });
    }

    const spot = await db.orm.public.SkateSpot.create({
      name: name.trim(),
      description: description ?? null,
      address: address ?? null,
      latitude,
      longitude,
      createdById,
    });

    return res.status(201).json({
      message: 'Spot crÃ©Ã© avec succÃ¨s',
      spot,
    });
  } catch (error) {
    console.error('Erreur lors de la crÃ©ation du spot :', error);

    return res.status(500).json({
      message: 'Erreur lors de la crÃ©ation du spot',
    });
  }
});

const { registerMediaRoutes } = require('./media_routes');
registerMediaRoutes(app, { getDb, authenticateToken });

const { registerCommentRoutes } = require('./comment_routes');
registerCommentRoutes(app, { getDb, authenticateToken });

const { registerCommunityDescriptionRoutes } =
  require('./community_description_routes');

registerCommunityDescriptionRoutes(app, {
  getDb,
  authenticateToken,
});

const { registerContentReportRoutes } =
  require('./content_report_routes');

registerContentReportRoutes(app, {
  getDb,
  authenticateToken,
});

app.listen(PORT, () => {
  console.log(`Serveur SkateSpot dÃ©marrÃ© sur le port ${PORT}`);
});
