const express = require('express');

const app = express();
const PORT = Number(process.env.PORT) || 3000;

app.use(express.json());

// Route d'accueil
app.get('/', (req, res) => {
  res.json({
    message: 'Bienvenue sur l API SkateSpot',
  });
});

// Liste de tous les spots
app.get('/api/spots', async (req, res) => {
  try {
    const { db } = await import('./src/prisma/db.ts');
    const spots = await db.orm.public.SkateSpot.all();

    res.json({
      message: 'Liste des spots',
      count: spots.length,
      spots,
    });
  } catch (error) {
    console.error('Erreur lors de la récupération des spots :', error);

    res.status(500).json({
      message: 'Erreur lors de la récupération des spots',
    });
  }
});

// Détail d'un spot par son identifiant
app.get('/api/spots/:id', async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isSafeInteger(id) || id <= 0) {
    return res.status(400).json({
      message: 'Identifiant de spot invalide',
    });
  }

  try {
    const { db } = await import('./src/prisma/db.ts');

    const spot = await db.orm.public.SkateSpot
      .where({ id })
      .first();

    if (!spot) {
      return res.status(404).json({
        message: 'Spot introuvable',
      });
    }

    res.json({
      message: 'Détail du spot',
      spot,
    });
  } catch (error) {
    console.error('Erreur lors de la récupération du spot :', error);

    res.status(500).json({
      message: 'Erreur lors de la récupération du spot',
    });
  }
});

// Créer un nouveau spot
app.post('/api/spots', async (req, res) => {
  const {
    name,
    description,
    address,
    latitude,
    longitude,
    createdById,
  } = req.body;

  // Vérifier les champs obligatoires
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
    longitude > 180 ||
    !Number.isSafeInteger(createdById) ||
    createdById <= 0
  ) {
    return res.status(400).json({
      message: 'Données invalides : nom, coordonnées et créateur requis',
    });
  }

  // Vérifier les champs facultatifs
  if (
    (description !== undefined &&
      description !== null &&
      typeof description !== 'string') ||
    (address !== undefined &&
      address !== null &&
      typeof address !== 'string')
  ) {
    return res.status(400).json({
      message: 'La description et l’adresse doivent être des chaînes de caractères',
    });
  }

  try {
    const { db } = await import('./src/prisma/db.ts');

    // Vérifier que le créateur existe
    const user = await db.orm.public.User
      .where({ id: createdById })
      .first();

    if (!user) {
      return res.status(400).json({
        message: 'Utilisateur créateur introuvable',
      });
    }

    // Créer le spot
    const spot = await db.orm.public.SkateSpot.create({
      name: name.trim(),
      description: description ?? null,
      address: address ?? null,
      latitude,
      longitude,
      createdById,
    });

    return res.status(201).json({
      message: 'Spot créé avec succès',
      spot,
    });
  } catch (error) {
    console.error('Erreur lors de la création du spot :', error);

    return res.status(500).json({
      message: 'Erreur lors de la création du spot',
    });
  }
});

app.listen(PORT, () => {
  console.log(`Serveur SkateSpot démarré sur le port ${PORT}`);
});
