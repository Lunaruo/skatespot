import 'package:flutter_test/flutter_test.dart';
import 'package:skatespot/models/spot.dart';

void main() {
  test('un spot contient les informations principales', () {
    final createdAt = DateTime(2026, 10, 8);

    final spot = Spot(
      id: 'spot-1',
      name: 'Skatepark Central',
      description: 'Un spot pour le skate.',
      latitude: 50.6292,
      longitude: 3.0573,
      type: 'skatepark',
      createdBy: 'user-1',
      createdAt: createdAt,
    );

    expect(spot.id, 'spot-1');
    expect(spot.name, 'Skatepark Central');
    expect(spot.description, 'Un spot pour le skate.');
    expect(spot.latitude, 50.6292);
    expect(spot.longitude, 3.0573);
    expect(spot.type, 'skatepark');
    expect(spot.createdBy, 'user-1');
    expect(spot.createdAt, createdAt);
  });
}
