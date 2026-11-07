enum PredictionMode { model, coldStart }

class DailyPrediction {
  const DailyPrediction({
    required this.id,
    required this.targetDate,
    required this.breadCategoryId,
    required this.breadCategoryName,
    required this.predictedUnitsSold,
    required this.mode,
    required this.confidence,
    required this.modelVersionId,
    required this.contextSnapshot,
  });

  final String id;
  final String targetDate;
  final String breadCategoryId;
  final String breadCategoryName;
  final int predictedUnitsSold;
  final PredictionMode mode;
  final double? confidence;
  final String? modelVersionId;
  final Map<String, dynamic>? contextSnapshot;

  bool get isLowConfidence {
    if (mode == PredictionMode.coldStart) return true;
    final threshold = contextSnapshot?['confidenceThreshold'];
    if (threshold is num) return confidence! < threshold;
    return contextSnapshot?['lowConfidence'] == true;
  }

  String get confidenceLabel {
    if (mode == PredictionMode.coldStart) {
      return 'Low-confidence heuristic estimate';
    }
    if (isLowConfidence) return 'Low Confidence';
    return 'Model agreement';
  }

  bool get usedWeatherFallback =>
      contextSnapshot?['weatherSource'] == 'CONFIGURED_FALLBACK';

  bool get usedCalendarFallback =>
      contextSnapshot?['calendarSource'] == 'CONFIGURED_FALLBACK';

  Map<String, dynamic>? get factors {
    final value = contextSnapshot?['factors'];
    return value is Map<String, dynamic> ? value : null;
  }

  factory DailyPrediction.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final date = json['targetDate'];
    final categoryId = json['breadCategoryId'];
    final categoryName = json['breadCategoryName'];
    final units = json['predictedUnitsSold'];
    final modeText = json['predictionMode'];
    final confidenceValue = json['confidence'];
    final modelId = json['modelVersionId'];
    final context = json['contextSnapshot'];

    if (id is! String ||
        date is! String ||
        categoryId is! String ||
        categoryName is! String ||
        units is! int ||
        units < 0 ||
        (context != null && context is! Map<String, dynamic>)) {
      throw const FormatException('Invalid prediction response.');
    }
    final mode = switch (modeText) {
      'MODEL' => PredictionMode.model,
      'COLD_START' => PredictionMode.coldStart,
      _ => throw const FormatException('Invalid prediction mode.'),
    };
    final double? confidence;
    if (mode == PredictionMode.model) {
      if (confidenceValue is! num ||
          modelId is! String ||
          !confidenceValue.toDouble().isFinite ||
          confidenceValue < 0 ||
          confidenceValue > 100) {
        throw const FormatException('Invalid model confidence.');
      }
      confidence = confidenceValue.toDouble();
    } else {
      if (confidenceValue != null || modelId != null) {
        throw const FormatException('Cold-start confidence must be null.');
      }
      confidence = null;
    }
    return DailyPrediction(
      id: id,
      targetDate: date,
      breadCategoryId: categoryId,
      breadCategoryName: categoryName,
      predictedUnitsSold: units,
      mode: mode,
      confidence: confidence,
      modelVersionId: modelId as String?,
      contextSnapshot: context as Map<String, dynamic>?,
    );
  }
}

class NextPredictionState {
  const NextPredictionState({
    required this.targetDate,
    required this.predictions,
  });

  final String targetDate;
  final List<DailyPrediction> predictions;

  factory NextPredictionState.fromJson(Map<String, dynamic> json) {
    final targetDate = json['targetDate'];
    final rawPredictions = json['predictions'];
    if (targetDate is! String || rawPredictions is! List) {
      throw const FormatException('Invalid next-day prediction response.');
    }
    return NextPredictionState(
      targetDate: targetDate,
      predictions: rawPredictions.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid prediction item.');
        }
        return DailyPrediction.fromJson(item);
      }).toList(),
    );
  }
}
