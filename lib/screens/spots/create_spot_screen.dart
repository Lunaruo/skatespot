import 'package:flutter/material.dart';

import '../../services/spot_service.dart';

class CreateSpotScreen extends StatefulWidget {
  const CreateSpotScreen({
    super.key,
    required this.onSessionExpired,
    required this.latitude,
    required this.longitude,
  });

  final Future<void> Function() onSessionExpired;
  final double latitude;
  final double longitude;

  @override
  State<CreateSpotScreen> createState() => _CreateSpotScreenState();
}

class _CreateSpotScreenState extends State<CreateSpotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createSpot() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await SpotService.createSpot(
        name: _nameController.text.trim(),
        latitude: widget.latitude,
        longitude: widget.longitude,
        address: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;
      // Le résultat true permet à MapScreen d'actualiser les marqueurs.
      Navigator.of(context).pop(true);
    } on SessionExpiredException {
      if (!mounted) return;
      final onSessionExpired = widget.onSessionExpired;
      Navigator.of(context).pop();
      await onSessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter un spot')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Partage un nouveau spot avec la communauté.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: Colors.deepOrange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Position sélectionnée sur la carte',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${widget.latitude.toStringAsFixed(6)}, '
                              '${widget.longitude.toStringAsFixed(6)}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pour changer la position, reviens à la carte. '
                'Les coordonnées ne sont plus à saisir manuellement.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du spot *',
                  hintText: 'Ex. : Skatepark de Lille',
                  prefixIcon: Icon(Icons.skateboarding),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom du spot est obligatoire.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse ou ville (facultatif)',
                  prefixIcon: Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (facultatif)',
                  hintText: 'Décris le spot et ses caractéristiques',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _createSpot,
                  icon: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_location_alt),
                  label: Text(
                    _isSubmitting ? 'Création en cours...' : 'Publier le spot',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
