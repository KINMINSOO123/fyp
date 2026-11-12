import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/inventory/data/recommendation_service.dart';
import 'package:fyp/features/inventory/data/restock_service.dart';
import 'package:fyp/features/inventory/domain/recommendation_plan.dart';
import 'package:fyp/features/inventory/presentation/production_planning_screen.dart';
import 'package:fyp/features/prediction/data/prediction_service.dart';
import 'package:fyp/features/prediction/domain/daily_prediction.dart';

const date = '2026-11-05';
const predictionId = '00000000-0000-4000-8000-000000000001';

Map<String, dynamic> planJson({
  bool confirmed = false,
  bool shortage = false,
}) => {
  'targetDate': date,
  'status': shortage ? 'COMMITMENT_SHORTAGE' : 'READY',
  'entries': [
    {
      'breadCategoryName': 'Wholemeal Bread',
      'predictionId': predictionId,
      'predictedUnitsSold': 6,
      'predictionMode': 'COLD_START',
      'confidence': null,
      'lowConfidence': true,
      'state': confirmed ? 'CONFIRMED' : 'UNCONFIRMED',
      'recommendedProduction': shortage ? null : 6,
      'maxProducible': shortage ? null : 10,
      'finalSelectedQty': confirmed ? 6 : null,
      'ingredientRequirements': [
        {
          'ingredientName': 'Flour',
          'gramsPerUnit': 100,
          'recommendedGrams': shortage ? null : 600,
        },
      ],
    },
  ],
  'shortages': shortage
      ? [
          {'ingredientName': 'Flour', 'shortageGrams': 200},
        ]
      : [],
};

class FakePredictionGateway implements PredictionGateway {
  @override
  Future<List<DailyPrediction>> getByDate(String date) async => [];
  @override
  Future<NextPredictionState> getNextDayState() async => NextPredictionState(
    targetDate: date,
    predictions: [
      DailyPrediction.fromJson({
        'id': predictionId,
        'targetDate': date,
        'breadCategoryId': 'category-1',
        'breadCategoryName': 'Wholemeal Bread',
        'predictedUnitsSold': 6,
        'predictionMode': 'COLD_START',
        'confidence': null,
        'modelVersionId': null,
      }),
    ],
  );
  @override
  Future<void> generateNextDay() async {}
}

class FakeRecommendationGateway implements RecommendationGateway {
  FakeRecommendationGateway(this.plan);
  RecommendationPlan plan;
  int confirmations = 0;

  @override
  Future<RecommendationPlan> getPlan(
    String targetDate, {
    String? revisingPredictionId,
  }) async => plan;
  @override
  Future<RecommendationPlan> confirm({
    required String predictionId,
    required int finalSelectedQty,
    required String selectedOption,
    required String? decisionReason,
  }) async {
    expect(finalSelectedQty, 6);
    expect(selectedOption, 'ACCEPT_RECOMMENDATION');
    expect(decisionReason, isNull);
    confirmations++;
    plan = RecommendationPlan.fromJson(planJson(confirmed: true));
    return plan;
  }
}

class FakeRestockGateway implements RestockGateway {
  FakeRestockGateway({this.shortage = false});
  final bool shortage;
  int submissions = 0;
  @override
  Future<RestockPreview> preview(String targetDate) async => RestockPreview(
    targetDate: targetDate,
    desiredQuantities: const [
      {
        'breadCategoryId': 'category-1',
        'breadCategoryName': 'Wholemeal Bread',
        'desiredQty': 6,
        'basis': 'PREDICTION',
      },
    ],
    shortages: shortage
        ? const [
            {
              'ingredientId': 'flour',
              'ingredientName': 'Flour',
              'requiredGrams': 600,
              'availableGrams': 400,
              'additionalGrams': 200,
            },
          ]
        : const [],
  );
  @override
  Future<Map<String, dynamic>> submit(RestockPreview preview) async {
    submissions++;
    return {
      'id': 'request',
      'productionDate': preview.targetDate,
      'status': 'PENDING',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> list({
    required bool administrator,
  }) async => submissions > 0
      ? [
          {'productionDate': date, 'status': 'PENDING'},
        ]
      : [];
  @override
  Future<void> cancel(String requestId, String reason) async {}
}

void main() {
  test(
    'T-INV-UI-01 [FR-INV-07]: shortage plan keeps recommendation unavailable',
    () {
      final plan = RecommendationPlan.fromJson(planJson(shortage: true));
      expect(plan.hasShortage, isTrue);
      expect(plan.entries.single.recommendedProduction, isNull);
      expect(plan.shortages.single.shortageGrams, 200);
    },
  );

  testWidgets(
    'T-INV-UI-02 [FR-INV-09]: manager explicitly confirms a saved prediction',
    (tester) async {
      final fake = FakeRecommendationGateway(
        RecommendationPlan.fromJson(planJson()),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionPlanningScreen(
            gateway: fake,
            predictionGateway: FakePredictionGateway(),
            restockGateway: FakeRestockGateway(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Confirming a plan does not deduct inventory.'),
        findsOneWidget,
      );
      expect(find.text('Recommended: 6 units'), findsOneWidget);
      await tester.tap(find.text('Confirm Production').first);
      await tester.pumpAndSettle();
      expect(fake.confirmations, 0);
      await tester.tap(find.byKey(const Key('save-production-decision')));
      await tester.pumpAndSettle();
      expect(fake.confirmations, 1);
      expect(find.text('Confirmed: 6 units'), findsOneWidget);
    },
  );

  testWidgets(
    'T-INV-UI-03 [FR-INV-07]: stock shortage blocks new confirmation',
    (tester) async {
      final fake = FakeRecommendationGateway(
        RecommendationPlan.fromJson(planJson(shortage: true)),
      );
      final restock = FakeRestockGateway(shortage: true);
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionPlanningScreen(
            gateway: fake,
            predictionGateway: FakePredictionGateway(),
            restockGateway: restock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('200.000 g short'), findsOneWidget);
      expect(find.text('Confirm Production'), findsNothing);
      expect(find.text('Request Restock'), findsOneWidget);
      await tester.tap(find.text('Request Restock'));
      await tester.pumpAndSettle();
      expect(find.text('Production date: $date'), findsOneWidget);
      await tester.tap(find.text('Confirm Request'));
      await tester.pumpAndSettle();
      expect(restock.submissions, 1);
    },
  );
}
