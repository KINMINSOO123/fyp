import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/prediction/data/prediction_service.dart';
import 'package:fyp/features/prediction/domain/daily_prediction.dart';
import 'package:fyp/features/prediction/presentation/prediction_screen.dart';
import 'package:fyp/features/profile/domain/user_profile.dart';

class FakePredictionGateway implements PredictionGateway {
  FakePredictionGateway(this.state);
  NextPredictionState state;
  int generationCount = 0;
  final requestedDates = <String>[];
  final savedByDate = <String, List<DailyPrediction>>{};

  @override
  Future<NextPredictionState> getNextDayState() async => state;

  @override
  Future<List<DailyPrediction>> getByDate(String date) async {
    requestedDates.add(date);
    return savedByDate[date] ?? [];
  }

  @override
  Future<void> generateNextDay() async {
    generationCount++;
    state = NextPredictionState(
      targetDate: state.targetDate,
      predictions: [
        DailyPrediction.fromJson({
          'id': 'prediction-1',
          'targetDate': state.targetDate,
          'breadCategoryId': 'category-1',
          'breadCategoryName': 'Wholemeal Bread',
          'predictedUnitsSold': 12,
          'predictionMode': 'COLD_START',
          'confidence': null,
          'modelVersionId': null,
          'contextSnapshot': {
            'lowConfidence': true,
            'weatherSource': 'CONFIGURED_FALLBACK',
          },
        }),
      ],
    );
  }
}

void main() {
  testWidgets('manager explicitly generates then sees cold-start result', (
    tester,
  ) async {
    final gateway = FakePredictionGateway(
      const NextPredictionState(targetDate: '2026-11-05', predictions: []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PredictionScreen(role: UserRole.bakeryManager, gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generate Prediction'), findsOneWidget);
    await tester.tap(find.text('Generate Prediction'));
    await tester.pumpAndSettle();
    expect(gateway.generationCount, 1);
    expect(find.text('Wholemeal Bread'), findsOneWidget);
    expect(find.text('12 units'), findsOneWidget);
    expect(find.text('Low-confidence heuristic estimate'), findsOneWidget);
    expect(find.text('Weather fallback used'), findsOneWidget);
    expect(find.text('Generate Prediction'), findsNothing);
    expect(find.textContaining('65%'), findsNothing);
  });

  testWidgets('administrator can review but cannot generate', (tester) async {
    final gateway = FakePredictionGateway(
      const NextPredictionState(targetDate: '2026-11-05', predictions: []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PredictionScreen(
          role: UserRole.systemAdministrator,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No prediction has been saved for this date.'),
      findsOneWidget,
    );
    expect(find.text('Generate Prediction'), findsNothing);
    expect(gateway.generationCount, 0);
  });

  testWidgets('selected past date reads saved predictions without generating', (
    tester,
  ) async {
    final gateway = FakePredictionGateway(
      const NextPredictionState(targetDate: '2026-11-05', predictions: []),
    );
    gateway.savedByDate['2026-11-04'] = [
      DailyPrediction.fromJson({
        'id': 'older-prediction',
        'targetDate': '2026-11-04',
        'breadCategoryId': 'category-1',
        'breadCategoryName': 'Wholemeal Bread',
        'predictedUnitsSold': 9,
        'predictionMode': 'COLD_START',
        'confidence': null,
        'modelVersionId': null,
        'contextSnapshot': null,
      }),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PredictionScreen(role: UserRole.bakeryManager, gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(gateway.requestedDates, ['2026-11-04']);
    expect(find.text('2026-11-04'), findsOneWidget);
    expect(find.text('9 units'), findsOneWidget);
    expect(find.text('Generate Prediction'), findsNothing);
    expect(gateway.generationCount, 0);
  });

  testWidgets('past date without predictions shows empty state only', (
    tester,
  ) async {
    final gateway = FakePredictionGateway(
      const NextPredictionState(targetDate: '2026-11-05', predictions: []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PredictionScreen(role: UserRole.bakeryManager, gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(gateway.requestedDates, ['2026-11-04']);
    expect(
      find.text('No prediction has been saved for this date.'),
      findsOneWidget,
    );
    expect(find.text('Generate Prediction'), findsNothing);
    expect(gateway.generationCount, 0);
  });
}
