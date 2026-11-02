import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';

/// Fiche commune : ID SQL pour SkateSpot, ID externe pour RideMyPark.
class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({super.key, required this.spot});
  final Map<String, dynamic> spot;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  final _picker = ImagePicker();
  final _commentController = TextEditingController();
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _comments = [];
  bool _loadingMedia = true;
  bool _loadingComments = true;
  bool _loadingDescription = true;
  bool _uploading = false;
  bool _posting = false;
  bool _saving = false;
  String? _mediaError;
  String? _commentsError;
  String? _descriptionError;
  String _communityDescription = '';
  String _originalDescription = '';
  String _descriptionAuthor = '';

  bool get _native =>
      widget.spot['_source'] == 'skatespot' ||
      widget.spot['isNativeSpot'] == true;
  String get _spotId => _native
      ? (widget.spot['id'] ?? '').toString()
      : (widget.spot['ID'] ??
                widget.spot['externalId'] ??
                widget.spot['id'] ??
                '')
            .toString();
  String get _root =>
      _native ? '/api/spots/$_spotId' : '/api/ridemypark/spots/$_spotId';
  Uri _url(String suffix) => Uri.parse('${AuthService.baseUrl}$_root$suffix');

  String _text(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final v = widget.spot[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return v.toString();
      if (v is List && v.isNotEmpty) {
        final first = v.first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map) {
          final u = first['url'] ?? first['source_url'] ?? first['src'];
          if (u is String && u.isNotEmpty) return u;
        }
      }
      if (v is Map) {
        final u = v['url'] ?? v['source_url'] ?? v['src'];
        if (u is String && u.isNotEmpty) return u;
      }
    }
    return fallback;
  }

  String get _name => _text(['title', 'name'], 'Spot sans nom');
  String get _image => _text([
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _toast(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  String _error(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map) {
        return '${d['message'] ?? d['error'] ?? 'Erreur HTTP ${r.statusCode}'}';
      }
    } catch (_) {}
    return 'Erreur HTTP ${r.statusCode}';
  }

  Future<http.Response> _jsonRequest(
    String method,
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    Future<http.Response> send(String token) {
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      return (method == 'PUT'
              ? http.put(uri, headers: headers, body: jsonEncode(body))
              : http.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 20));
    }

    var token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Session expirée. Reconnecte-toi.');
    }
    var response = await send(token);
    if (response.statusCode == 401) {
      token = await AuthService.refreshAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('Session expirée ou renouvellement impossible.');
      }
      response = await send(token);
    }
    return response;
  }

  Future<void> _refresh() async {
    if (_spotId.isEmpty) {
      _toast('Identifiant du spot introuvable.');
      return;
    }
    await Future.wait([_loadMedia(), _loadComments(), _loadDescription()]);
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;
    setState(() {
      _loadingMedia = true;
      _mediaError = null;
    });
    try {
      final r = await http
          .get(_url('/media?page=1&limit=12'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception(_error(r));
      final data = jsonDecode(r.body);
      if (data is! Map || data['media'] is! List) {
        throw const FormatException('Photos invalides');
      }
      if (!mounted) return;
      setState(() {
        _media = (data['media'] as List)
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        _loadingMedia = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMedia = false;
          _mediaError = '$e';
        });
      }
    }
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() {
      _loadingComments = true;
      _commentsError = null;
    });
    try {
      final r = await http
          .get(_url('/comments'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception(_error(r));
      final data = jsonDecode(r.body);
      if (data is! Map || data['comments'] is! List) {
        throw const FormatException('Commentaires invalides');
      }
      if (!mounted) return;
      setState(() {
        _comments = (data['comments'] as List)
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .toList();
        _loadingComments = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingComments = false;
          _commentsError = '$e';
        });
      }
    }
  }

  Future<void> _loadDescription() async {
    if (!mounted) return;
    setState(() {
      _loadingDescription = true;
      _descriptionError = null;
    });
    try {
      final r = await http
          .get(_url('/community-description'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception(_error(r));
      final data = jsonDecode(r.body);
      if (data is! Map || data['description'] is! Map) {
        throw const FormatException('Description invalide');
      }
      final d = data['description'] as Map;
      if (!mounted) return;
      setState(() {
        _originalDescription = '${d['description'] ?? ''}';
        _communityDescription = '${d['communityDescription'] ?? ''}';
        _descriptionAuthor = '${d['communityDescriptionAuthorUsername'] ?? ''}';
        _loadingDescription = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDescription = false;
          _descriptionError = '$e';
        });
      }
    }
  }

  Future<http.Response> _sendPhoto(XFile image, String token) async {
    final request = http.MultipartRequest('POST', _url('/media'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('photo', image.path));
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    return http.Response.fromStream(streamed);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_uploading) return;
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image == null || !mounted) return;
      setState(() => _uploading = true);
      var token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Session expirée. Reconnecte-toi.');
      }
      var r = await _sendPhoto(image, token);
      if (r.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null || token.isEmpty) {
          throw Exception('Renouvellement de session impossible.');
        }
        r = await _sendPhoto(image, token);
      }
      if (r.statusCode != 201) throw Exception(_error(r));
      _toast('Photo publiée !');
      await _loadMedia();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Appareil photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publishComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _posting) return;
    if (content.length > 1000) {
      _toast('Maximum : 1000 caractères.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _posting = true);
    try {
      final r = await _jsonRequest('POST', _url('/comments'), {
        'content': content,
      });
      if (r.statusCode != 201) throw Exception(_error(r));
      _commentController.clear();
      _toast('Commentaire publié !');
      await _loadComments();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _editDescription() async {
    final controller = TextEditingController(text: _communityDescription);
    bool isSubmitting = false;
    bool wasPublished = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Description communautaire'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  maxLength: 2000,
                  minLines: 4,
                  maxLines: 8,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(
                    hintText: 'Décris les modules, le revêtement, les accès...',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final value = controller.text.trim();
                      if (value.isEmpty || value.length > 2000) {
                        setDialogState(() {
                          dialogError = 'La description doit faire entre 1 et 2000 caractères.';
                        });
                        return;
                      }

                      setDialogState(() {
                        isSubmitting = true;
                        dialogError = null;
                      });
                      if (mounted) setState(() => _saving = true);

                      try {
                        final response = await _jsonRequest(
                          'PUT',
                          _url('/community-description'),
                          {'communityDescription': value},
                        );
                        if (response.statusCode != 200 &&
                            response.statusCode != 201) {
                          throw Exception(_error(response));
                        }
                        wasPublished = true;
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            dialogError = error.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                          });
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => isSubmitting = false);
                        }
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(isSubmitting ? 'Enregistrement...' : 'Publier'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (wasPublished && mounted) {
      _toast('Description publiée !');
      await _loadDescription();
    }
  }

  Future<void> _report(Uri target, String label) async {
    final reason = TextEditingController();
    final details = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Signaler $label'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Motif (obligatoire)',
                ),
              ),
              TextField(
                controller: details,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Précisions (facultatif)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, [reason.text.trim(), details.text.trim()]),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reason.dispose();
      details.dispose();
    });
    if (!mounted || values == null) return;
    if (values[0].length < 3 || values[0].length > 500) {
      _toast('Le motif doit faire entre 3 et 500 caractères.');
      return;
    }
    try {
      final r = await _jsonRequest('POST', target, {
        'reason': values[0],
        if (values[1].isNotEmpty) 'details': values[1],
      });
      if (r.statusCode != 201) throw Exception(_error(r));
      _toast('Signalement transmis.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _date(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '';
    final local = d.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  void _showPhoto(String url) {
    if (url.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              size: 60,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: Colors.teal),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    ],
  );

  Widget _retry(String message, VoidCallback action) => Column(
    children: [
      Text(message),
      TextButton(onPressed: action, child: const Text('Réessayer')),
    ],
  );

  Widget _photos() {
    if (_loadingMedia) return const Center(child: CircularProgressIndicator());
    if (_mediaError != null) return _retry(_mediaError!, _loadMedia);
    if (_media.isEmpty) {
      return const Text('Aucune photo communautaire pour le moment.');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _media.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final photo = _media[index];
        final url = '${photo['url'] ?? ''}';
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _showPhoto(url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE0E0E0),
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
            if (photo['id'] != null)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton.filledTonal(
                  tooltip: 'Signaler la photo',
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () => _report(
                    Uri.parse(
                      '${AuthService.baseUrl}/api/media/${photo['id']}/reports',
                    ),
                    'cette photo',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _descriptionSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Description communautaire', Icons.edit_note),
      const SizedBox(height: 10),
      if (_loadingDescription)
        const Center(child: CircularProgressIndicator())
      else if (_descriptionError != null)
        _retry(_descriptionError!, _loadDescription)
      else ...[
        Text(
          _communityDescription.trim().isNotEmpty
              ? _communityDescription
              : 'La communauté n’a pas encore décrit ce spot.',
        ),
        if (_descriptionAuthor.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Par $_descriptionAuthor',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_communityDescription.trim().isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _report(
                _url('/community-description/reports'),
                'cette description',
              ),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Signaler'),
            ),
          ),
      ],
      OutlinedButton.icon(
        onPressed: _saving ? null : _editDescription,
        icon: const Icon(Icons.edit_outlined),
        label: Text(
          _saving
              ? 'Enregistrement...'
              : _communityDescription.isEmpty
              ? 'Ajouter une description'
              : 'Modifier la description',
        ),
      ),
    ],
  );

  Widget _commentsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Commentaires', Icons.forum_outlined),
      const SizedBox(height: 12),
      if (_loadingComments)
        const Center(child: CircularProgressIndicator())
      else if (_commentsError != null)
        _retry(_commentsError!, _loadComments)
      else if (_comments.isEmpty)
        const Text('Aucun commentaire. Sois le premier !')
      else
        ..._comments.map(
          (comment) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_circle_outlined, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${comment['username'] ?? 'Rider'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        _date(comment['createdAt']),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (comment['id'] != null)
                        IconButton(
                          tooltip: 'Signaler le commentaire',
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          onPressed: () => _report(
                            Uri.parse(
                              '${AuthService.baseUrl}/api/comments/${comment['id']}/reports',
                            ),
                            'ce commentaire',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${comment['content'] ?? ''}'),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _commentController,
        maxLength: 1000,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Écrire un commentaire',
          border: OutlineInputBorder(),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: _posting ? null : _publishComment,
          icon: const Icon(Icons.send),
          label: Text(_posting ? 'Publication...' : 'Publier'),
        ),
      ),
    ],
  );

  Widget _placeholder() => ColoredBox(
    color: Colors.grey.shade200,
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera_outlined, size: 54),
          SizedBox(height: 10),
          Text('Aucune photo principale disponible'),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final description = _originalDescription.trim().isNotEmpty
        ? _originalDescription
        : _text(['description', 'content', 'excerpt']);
    final address = _text([
      'formattedAddress',
      'formatted_address',
      'address',
      'location',
    ]);
    final latitude = _text(['latitude']);
    final longitude = _text(['longitude']);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Actualiser la fiche',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            SizedBox(
              height: 240,
              width: double.infinity,
              child: _image.isEmpty
                  ? _placeholder()
                  : Image.network(
                      _image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.skateboarding, size: 20),
                    label: Text(
                      _native ? 'Communauté SkateSpot' : 'RideMyPark',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _heading(
                    _native
                        ? 'À propos du spot'
                        : 'Description originale RideMyPark',
                    Icons.info_outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description.isEmpty
                        ? 'Aucune description initiale disponible.'
                        : description,
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _heading('Adresse', Icons.location_on_outlined),
                    const SizedBox(height: 8),
                    Text(address),
                  ],
                  const SizedBox(height: 20),
                  _heading('Localisation', Icons.explore_outlined),
                  const SizedBox(height: 8),
                  Text(
                    'Latitude : ${latitude.isEmpty ? 'Non disponible' : latitude}',
                  ),
                  Text(
                    'Longitude : ${longitude.isEmpty ? 'Non disponible' : longitude}',
                  ),
                  const Divider(height: 42),
                  _descriptionSection(),
                  const Divider(height: 42),
                  _heading(
                    'Photos de la communauté',
                    Icons.photo_library_outlined,
                  ),
                  const SizedBox(height: 8),
                  const Text('Partage tes photos avec les autres riders.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _uploading ? null : _choosePhoto,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        _uploading ? 'Publication...' : 'Ajouter une photo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _photos(),
                  const Divider(height: 42),
                  _commentsSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
