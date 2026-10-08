import 'package:flutter_test/flutter_test.dart';
import 'package:skatespot/main.dart';

void main() {
  testWidgets('SkateSpot affiche la page d’accueil', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SkateSpotApp());

    expect(find.text('Bienvenue sur SkateSpot'), findsOneWidget);
  });
}
