import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/prediction/domain/daily_prediction.dart';

Map<String, dynamic> predictionJson({
  String mode = 'MODEL',
  Object? confidence = 82.5,
  Object? modelId = 'model-1',
}) => {
  'id': 'prediction-1',
  'targetDate': '2026-11-05',
  'breadCategoryId': 'category-1',
  'breadCategoryName': 'Wholemeal Bread',
  'predictedUnitsSold': 12,
  'predictionMode': mode,
  'confidence': confidence,
  'modelVersionId': modelId,
  'contextSnapshot': {'lowConfidence': false},
};

void main() {
  test('MODEL requires bounded numerical confidence and model version', () {
    final model = DailyPrediction.fromJson(predictionJson());
    expect(model.mode, PredictionMode.model);
    expect(model.confidence, 82.5);
    expect(
      () => DailyPrediction.fromJson(predictionJson(confidence: null)),
      throwsFormatException,
    );
    expect(
      () => DailyPrediction.fromJson(predictionJson(confidence: 101)),
      throwsFormatException,
    );
    expect(
      () => DailyPrediction.fromJson(predictionJson(modelId: null)),
      throwsFormatException,
    );
  });

  test('COLD_START requires null confidence and model version', () {
    final cold = DailyPrediction.fromJson(
      predictionJson(mode: 'COLD_START', confidence: null, modelId: null),
    );
    expect(cold.confidence, isNull);
    expect(cold.confidenceLabel, 'Low-confidence heuristic estimate');
    expect(
      () => DailyPrediction.fromJson(
        predictionJson(mode: 'COLD_START', confidence: 65, modelId: null),
      ),
      throwsFormatException,
    );
  });
}
