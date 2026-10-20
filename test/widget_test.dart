import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skatespot/main.dart';

void main() {
  testWidgets('SkateSpot affiche le titre et le chargement', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SkateSpotApp());

    expect(find.text('SkateSpot'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
