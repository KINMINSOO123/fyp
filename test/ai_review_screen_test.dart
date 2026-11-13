import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/administration/data/ai_suggestions_service.dart';
import 'package:fyp/features/administration/presentation/ai_review_screen.dart';

class _ReviewGateway implements AiReviewGateway {
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> catalogue() async => {
    'categories': [
      {'id': 'bread-1', 'name': 'Coconut Bun', 'displayOrder': 1},
    ],
    'ingredients': [
      {'id': 'flour-1', 'name': 'Flour', 'isActive': true, 'unit': 'KG'},
    ],
  };
  @override
  Future<void> create(Map<String, dynamic> payload) async {
    saved = payload;
  }
}

void main() {
  testWidgets(
    'review reuses existing ingredient and requires new confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _ReviewGateway();
      const draft = AiBreadSuggestion(
        name: 'Pandan Bun',
        description: 'Soft bun',
        reason: 'Fits the bakery',
        recipe: [
          AiRecipeIngredient(
            name: 'Flour',
            gramsPerBread: 65,
            availability: 'AVAILABLE',
            availableGrams: 500,
          ),
          AiRecipeIngredient(
            name: 'Pandan paste',
            gramsPerBread: 5,
            availability: 'NOT_IN_INVENTORY',
            availableGrams: 0,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiReviewScreen(draft: draft, reviewService: gateway),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Existing ingredient'), findsOneWidget);
      expect(find.textContaining('grams per one bread'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Proposed new ingredient'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Proposed new ingredient'), findsOneWidget);
      expect(gateway.saved, isNull);
    },
  );
}
