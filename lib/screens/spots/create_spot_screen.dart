import 'package:flutter/material.dart';

import '../../services/spot_service.dart';

class CreateSpotScreen extends StatefulWidget {
  final Future<void> Function() onSessionExpired;

  const CreateSpotScreen({
    super.key,
    required this.onSessionExpired,
  });

  @override
  State<CreateSpotScreen> createState() => _CreateSpotScreenState();
}

class _CreateSpotScreenState extends State<CreateSpotScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  String? _validateCoordinate(
    String? value, {
    required double min,
    required double max,
    required String label,
  }) {
    final normalized = value?.trim().replaceAll(',', '.');
    final number = double.tryParse(normalized ?? '');

    if (number == null || !number.isFinite) {
      return 'Saisissez $label valide.';
    }

    if (number < min || number > max) {
      return '$label doit être compris entre $min et $max.';
    }

    return null;
  }

  Future<void> _createSpot() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final latitude = double.parse(
        _latitudeController.text.trim().replaceAll(',', '.'),
      );

      final longitude = double.parse(
        _longitudeController.text.trim().replaceAll(',', '.'),
      );

      await SpotService.createSpot(
        name: _nameController.text.trim(),
        latitude: latitude,
        longitude: longitude,
        address: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Spot créé avec succès !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } on SessionExpiredException {
      if (!mounted) return;

      // Conserver le callback avant de fermer cet écran.
      final onSessionExpired = widget.onSessionExpired;

      // Fermer l'écran de création avant de revenir à la connexion.
      Navigator.of(context).pop();

      // AuthGate supprimera le jeton et affichera LoginScreen.
      await onSessionExpired();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer un spot'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Partage un nouveau spot de skate avec la communauté.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du spot *',
                  hintText: 'Ex. : Skatepark de Lille',
                  prefixIcon: Icon(Icons.sports),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Le nom du spot est obligatoire.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse',
                  hintText: 'Ex. : Lille, France',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Décris le spot et ses caractéristiques',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _latitudeController,
                decoration: const InputDecoration(
                  labelText: 'Latitude *',
                  hintText: 'Ex. : 50.6330',
                  prefixIcon: Icon(Icons.north),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (value) => _validateCoordinate(
                  value,
                  min: -90,
                  max: 90,
                  label: 'La latitude',
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _longitudeController,
                decoration: const InputDecoration(
                  labelText: 'Longitude *',
                  hintText: 'Ex. : 3.0586',
                  prefixIcon: Icon(Icons.east),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (value) => _validateCoordinate(
                  value,
                  min: -180,
                  max: 180,
                  label: 'La longitude',
                ),
              ),
              const SizedBox(height: 8),

              const Text(
                '* Champs obligatoires. Les coordonnées permettent '
                'de situer le spot sur une carte ultérieurement.',
                style: TextStyle(fontSize: 12),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _createSpot,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add_location_alt),
                  label: Text(
                    _isSubmitting
                        ? 'Création en cours...'
                        : 'Créer le spot',
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