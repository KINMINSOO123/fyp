import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/main.dart';

void main() {
  testWidgets('builds the Smart Bakery application', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const SmartBakeryApp(home: Scaffold(body: Text('Test home'))),
    );

    expect(find.text('Test home'), findsOneWidget);
  });
}
