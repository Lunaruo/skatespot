
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';

class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({super.key, required this.spot});

  final Map<String, dynamic> spot;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _media = [];

  bool _isLoadingMedia = true;
  bool _isUploading = false;
  String? _mediaError;

  String get _externalId {
    return (widget.spot['ID'] ?? widget.spot['id'] ?? '').toString();
  }


  String _firstText(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = widget.spot[key];

      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }

      if (value is num) {
        return value.toString();
      }

      // Certains champs RideMyPark sont des listes d'images.
      if (value is List && value.isNotEmpty) {
        final first = value.first;

        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }

        if (first is Map) {
          final url =
              first['url'] ?? first['source_url'] ?? first['src'];

          if (url is String && url.trim().isNotEmpty) {
            return url.trim();
          }
        }
      }

      if (value is Map) {
        final nestedValue =
            value['url'] ?? value['source_url'] ?? value['src'];

        if (nestedValue is String && nestedValue.trim().isNotEmpty) {
          return nestedValue.trim();
        }
      }
    }

    return fallback;
  }


  String _formatTypes(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return value.join(', ');
    }

    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return 'Type non renseigné';
  }

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  // ============================================================
  // RÉCUPÉRER LES PHOTOS DU SPOT
  // ============================================================

  Future<void> _loadMedia() async {
    if (_externalId.isEmpty) {
      setState(() {
        _isLoadingMedia = false;
        _mediaError = 'Identifiant du spot introuvable.';
      });
      return;
    }

    setState(() {
      _isLoadingMedia = true;
      _mediaError = null;
    });

    try {
      final uri = Uri.parse(
        '${AuthService.baseUrl}/api/ridemypark/spots/'
            '$_externalId/media?page=1&limit=12',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      final List<dynamic> items = data['media'] ?? [];

      if (!mounted) return;

      setState(() {
        _media = items
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _isLoadingMedia = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingMedia = false;
        _mediaError = 'Impossible de charger les photos.';
      });

      debugPrint('Erreur chargement photos : $error');
    }
  }

  // ============================================================
  // CHOISIR ET PUBLIER UNE PHOTO
  // ============================================================

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    if (_isUploading) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      await _uploadPhoto(image);
    } catch (error) {
      _showMessage('Impossible de sélectionner cette photo.');
      debugPrint('Erreur sélection photo : $error');
    }
  }

  Future<void> _uploadPhoto(XFile image) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final token = await AuthService.getToken();

      if (token == null || token.isEmpty) {
        throw Exception('Session expirée. Reconnecte-toi.');
      }

      final uri = Uri.parse(
        '${AuthService.baseUrl}/api/ridemypark/spots/'
            '$_externalId/media',
      );

      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          image.path,
        ),
      );

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 201) {
        throw Exception(
          data['message'] ?? 'Erreur lors de la publication.',
        );
      }

      if (!mounted) return;

      _showMessage('Photo publiée avec succès !');

      await _loadMedia();
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
      );

      debugPrint('Erreur publication photo : $error');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir dans la galerie'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ============================================================
  // AFFICHAGE DE LA GALERIE
  // ============================================================

  Widget _buildGallery() {
    if (_isLoadingMedia) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_mediaError != null) {
      return Column(
        children: [
          Text(_mediaError!),
          TextButton(
            onPressed: _loadMedia,
            child: const Text('Réessayer'),
          ),
        ],
      );
    }

    if (_media.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Aucune photo publiée pour le moment.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _media.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final photo = _media[index];
        final url = photo['url']?.toString() ?? '';

        return GestureDetector(
          onTap: () {
            _showFullPhoto(url);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showFullPhoto(String url) {
    if (url.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 50,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // CONSTRUCTION DE L'ÉCRAN
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final title = _firstText(
      ['title', 'name'],
      fallback: 'Spot sans nom',
    );

    final description = _firstText([
      'description',
      'content',
      'excerpt',
    ]);

    final address = _firstText([
      'address',
      'formatted_address',
      'location',
    ]);

    final imageUrl = _firstText([
  'logo',
  'cover',
  'image_url',
  'image',
  'photo_url',
  'photo',
  'thumbnail',
  'featured_image',
  'imageUrl',
]);

    final latitude = _firstText(['latitude']);
    final longitude = _firstText(['longitude']);

    final spotType = _formatTypes(
      widget.spot['spot_type'] ?? widget.spot['type_name'],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail du spot'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo principale du spot.
            SizedBox(
              width: double.infinity,
              height: 250,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildImagePlaceholder();
                },
              )
                  : _buildImagePlaceholder(),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Chip(
                    avatar: const Icon(Icons.skateboarding, size: 20),
                    label: Text(spotType),
                  ),

                  const SizedBox(height: 24),

                  _buildSectionTitle(
                    context,
                    'À propos de ce spot',
                    Icons.info_outline,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    description.isNotEmpty
                        ? description
                        : 'Aucune description disponible pour le moment.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.5),
                  ),

                  const SizedBox(height: 24),

                  if (address.isNotEmpty) ...[
                    _buildSectionTitle(
                      context,
                      'Adresse',
                      Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      address,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                  ],

                  _buildSectionTitle(
                    context,
                    'Localisation',
                    Icons.explore_outlined,
                  ),

                  const SizedBox(height: 12),

                  _buildInfoRow(
                    Icons.place_outlined,
                    'Latitude',
                    latitude.isNotEmpty ? latitude : 'Non disponible',
                  ),

                  const SizedBox(height: 10),

                  _buildInfoRow(
                    Icons.explore_outlined,
                    'Longitude',
                    longitude.isNotEmpty ? longitude : 'Non disponible',
                  ),

                  const SizedBox(height: 32),

                  // Galerie communautaire.
                  _buildSectionTitle(
                    context,
                    'Photos de la communauté',
                    Icons.photo_library_outlined,
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Partage tes photos de ce spot avec les autres riders.',
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading
                          ? null
                          : _showPhotoSourceDialog,
                      icon: _isUploading
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _isUploading
                            ? 'Publication en cours...'
                            : 'Ajouter une photo',
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildGallery(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COMPOSANTS VISUELS
  // ============================================================

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 64,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune photo disponible',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
      BuildContext context,
      String title,
      IconData icon,
      ) {
    return Row(
      children: [
        Icon(icon, color: Colors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
      IconData icon,
      String label,
      String value,
      ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
