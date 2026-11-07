class IngredientRequirement {
  const IngredientRequirement({
    required this.name,
    required this.gramsPerUnit,
    required this.recommendedGrams,
  });
  final String name;
  final double gramsPerUnit;
  final double? recommendedGrams;

  factory IngredientRequirement.fromJson(Map<String, dynamic> json) {
    if (json['ingredientName'] is! String ||
        json['gramsPerUnit'] is! num ||
        (json['recommendedGrams'] != null &&
            json['recommendedGrams'] is! num)) {
      throw const FormatException('Invalid ingredient requirement.');
    }
    return IngredientRequirement(
      name: json['ingredientName'] as String,
      gramsPerUnit: (json['gramsPerUnit'] as num).toDouble(),
      recommendedGrams: (json['recommendedGrams'] as num?)?.toDouble(),
    );
  }
}

enum PlanningState { unconfirmed, confirmed, processed }

class RecommendationEntry {
  const RecommendationEntry({
    required this.breadCategoryName,
    required this.predictionId,
    required this.predictedUnitsSold,
    required this.predictionMode,
    required this.confidence,
    required this.lowConfidence,
    required this.state,
    required this.recommendedProduction,
    required this.maxProducible,
    required this.finalSelectedQty,
    required this.ingredientRequirements,
  });

  final String breadCategoryName;
  final String predictionId;
  final int predictedUnitsSold;
  final String predictionMode;
  final double? confidence;
  final bool lowConfidence;
  final PlanningState state;
  final int? recommendedProduction;
  final int? maxProducible;
  final int? finalSelectedQty;
  final List<IngredientRequirement> ingredientRequirements;

  factory RecommendationEntry.fromJson(Map<String, dynamic> json) {
    final requirements = json['ingredientRequirements'];
    if (json['breadCategoryName'] is! String ||
        json['predictionId'] is! String ||
        json['predictedUnitsSold'] is! int ||
        json['lowConfidence'] is! bool ||
        (json['recommendedProduction'] != null &&
            json['recommendedProduction'] is! int) ||
        (json['maxProducible'] != null && json['maxProducible'] is! int) ||
        (json['finalSelectedQty'] != null &&
            json['finalSelectedQty'] is! int) ||
        requirements is! List ||
        requirements.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid production recommendation.');
    }
    final state = switch (json['state']) {
      'UNCONFIRMED' => PlanningState.unconfirmed,
      'CONFIRMED' => PlanningState.confirmed,
      'PROCESSED' => PlanningState.processed,
      _ => throw const FormatException('Invalid production state.'),
    };
    final mode = json['predictionMode'];
    final confidenceValue = json['confidence'];
    if ((mode == 'MODEL' &&
            (confidenceValue is! num ||
                confidenceValue < 0 ||
                confidenceValue > 100 ||
                !confidenceValue.toDouble().isFinite)) ||
        (mode == 'COLD_START' && confidenceValue != null) ||
        (mode != 'MODEL' && mode != 'COLD_START')) {
      throw const FormatException('Invalid prediction confidence in plan.');
    }
    return RecommendationEntry(
      breadCategoryName: json['breadCategoryName'] as String,
      predictionId: json['predictionId'] as String,
      predictedUnitsSold: json['predictedUnitsSold'] as int,
      predictionMode: mode as String,
      confidence: (confidenceValue as num?)?.toDouble(),
      lowConfidence: json['lowConfidence'] as bool,
      state: state,
      recommendedProduction: json['recommendedProduction'] as int?,
      maxProducible: json['maxProducible'] as int?,
      finalSelectedQty: json['finalSelectedQty'] as int?,
      ingredientRequirements: requirements
          .map(
            (item) =>
                IngredientRequirement.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class IngredientShortage {
  const IngredientShortage({required this.name, required this.shortageGrams});
  final String name;
  final double shortageGrams;
  factory IngredientShortage.fromJson(Map<String, dynamic> json) {
    if (json['ingredientName'] is! String || json['shortageGrams'] is! num) {
      throw const FormatException('Invalid ingredient shortage.');
    }
    return IngredientShortage(
      name: json['ingredientName'] as String,
      shortageGrams: (json['shortageGrams'] as num).toDouble(),
    );
  }
}

class RecommendationPlan {
  const RecommendationPlan({
    required this.targetDate,
    required this.hasShortage,
    required this.entries,
    required this.shortages,
  });
  final String targetDate;
  final bool hasShortage;
  final List<RecommendationEntry> entries;
  final List<IngredientShortage> shortages;

  factory RecommendationPlan.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    final shortages = json['shortages'];
    if (json['targetDate'] is! String ||
        entries is! List ||
        shortages is! List ||
        entries.any((item) => item is! Map<String, dynamic>) ||
        shortages.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid production plan.');
    }
    final hasShortage = switch (json['status']) {
      'READY' => false,
      'COMMITMENT_SHORTAGE' => true,
      _ => throw const FormatException('Invalid production plan status.'),
    };
    return RecommendationPlan(
      targetDate: json['targetDate'] as String,
      hasShortage: hasShortage,
      entries: entries
          .map(
            (item) =>
                RecommendationEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      shortages: shortages
          .map(
            (item) => IngredientShortage.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
