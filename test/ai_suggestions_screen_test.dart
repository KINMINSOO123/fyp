import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/core/theme/bakery_theme.dart';
import 'package:fyp/features/administration/data/ai_suggestions_service.dart';
import 'package:fyp/features/administration/presentation/ai_suggestions_screen.dart';

class _Gateway implements AiSuggestionsGateway {
  final pending = Completer<List<AiBreadSuggestion>>();
  int calls = 0;
  @override
  Future<List<AiBreadSuggestion>> generate(String description) {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'administrator reviews draft recipes without duplicate requests',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway();
      await tester.pumpWidget(
        MaterialApp(
          theme: BakeryTheme.light,
          home: AiSuggestionsScreen(gateway: gateway),
        ),
      );
      expect(find.textContaining('trial baking'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Suggest a bun similar to Coconut Bun',
      );
      await tester.tap(find.text('Generate suggestions'));
      await tester.pump();
      expect(gateway.calls, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final generateButton = find.byWidgetPredicate((widget) =>
        widget is FilledButton);
      expect(
        tester.widget<FilledButton>(generateButton).onPressed,
        isNull,
      );
      gateway.pending.complete(const [
        AiBreadSuggestion(
          name: 'Pandan Bun',
          description: 'Soft fragrant bun',
          reason: 'Fits the bakery catalogue',
          recipe: [
            AiRecipeIngredient(
              name: 'Pandan paste',
              gramsPerBread: 5,
              availability: 'NOT_IN_INVENTORY',
              availableGrams: 0,
            ),
          ],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Pandan Bun'), findsOneWidget);
      expect(find.text('Not in existing inventory'), findsOneWidget);
      expect(gateway.calls, 1);
    },
  );
}
