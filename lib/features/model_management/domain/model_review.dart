enum ModelType { randomForest, linearRegression }

enum ModelStatus { candidate, active, inactive, rejected }

class TrainingCategory {
  const TrainingCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
  });
  final String id;
  final String name;
  final int displayOrder;

  factory TrainingCategory.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['displayOrder'] is! int) {
      throw const FormatException('Invalid training category.');
    }
    return TrainingCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      displayOrder: json['displayOrder'] as int,
    );
  }
}

class ModelEvaluationReview {
  const ModelEvaluationReview({
    required this.id,
    required this.holdoutStart,
    required this.holdoutEnd,
    required this.holdoutFingerprint,
    required this.evaluationLabel,
    required this.dataOrigins,
    required this.mae,
    required this.rmse,
    required this.mape,
    required this.rSquared,
    required this.sampleCount,
    required this.mapeSampleCount,
  });

  final String id;
  final String holdoutStart;
  final String holdoutEnd;
  final String holdoutFingerprint;
  final String evaluationLabel;
  final List<String> dataOrigins;
  final double mae;
  final double rmse;
  final double? mape;
  final double? rSquared;
  final int sampleCount;
  final int mapeSampleCount;

  factory ModelEvaluationReview.fromJson(Map<String, dynamic> json) {
    final origins = json['dataOrigins'];
    if (json['id'] is! String ||
        json['holdoutStart'] is! String ||
        json['holdoutEnd'] is! String ||
        json['holdoutFingerprint'] is! String ||
        json['evaluationLabel'] is! String ||
        origins is! List ||
        origins.any((value) => value is! String) ||
        json['mae'] is! num ||
        json['rmse'] is! num ||
        (json['mape'] != null && json['mape'] is! num) ||
        (json['rSquared'] != null && json['rSquared'] is! num) ||
        json['sampleCount'] is! int ||
        json['mapeSampleCount'] is! int) {
      throw const FormatException('Invalid model evaluation.');
    }
    final mae = (json['mae'] as num).toDouble();
    final rmse = (json['rmse'] as num).toDouble();
    final mape = (json['mape'] as num?)?.toDouble();
    final rSquared = (json['rSquared'] as num?)?.toDouble();
    if (!mae.isFinite ||
        mae < 0 ||
        !rmse.isFinite ||
        rmse < 0 ||
        (json['sampleCount'] as int) < 1 ||
        (json['mapeSampleCount'] as int) < 0 ||
        (json['mapeSampleCount'] as int) > (json['sampleCount'] as int) ||
        (mape != null && (!mape.isFinite || mape < 0)) ||
        (rSquared != null && !rSquared.isFinite)) {
      throw const FormatException('Invalid model evaluation metrics.');
    }
    return ModelEvaluationReview(
      id: json['id'] as String,
      holdoutStart: json['holdoutStart'] as String,
      holdoutEnd: json['holdoutEnd'] as String,
      holdoutFingerprint: json['holdoutFingerprint'] as String,
      evaluationLabel: json['evaluationLabel'] as String,
      dataOrigins: origins.cast<String>(),
      mae: mae,
      rmse: rmse,
      mape: mape,
      rSquared: rSquared,
      sampleCount: json['sampleCount'] as int,
      mapeSampleCount: json['mapeSampleCount'] as int,
    );
  }
}

class ModelVersionReview {
  const ModelVersionReview({
    required this.id,
    required this.version,
    required this.breadCategoryId,
    required this.breadCategoryName,
    required this.modelType,
    required this.lifecycleStatus,
    required this.trainingStart,
    required this.trainingEnd,
    required this.holdoutStart,
    required this.trainingGroupId,
    required this.trainingOriginCounts,
    required this.holdoutOriginCounts,
    required this.latestEvaluation,
  });

  final String id;
  final int version;
  final String breadCategoryId;
  final String breadCategoryName;
  final ModelType modelType;
  final ModelStatus lifecycleStatus;
  final String trainingStart;
  final String trainingEnd;
  final String? holdoutStart;
  final String? trainingGroupId;
  final Map<String, int>? trainingOriginCounts;
  final Map<String, int>? holdoutOriginCounts;
  final ModelEvaluationReview? latestEvaluation;

  bool get isRandomForestCandidate =>
      modelType == ModelType.randomForest &&
      lifecycleStatus == ModelStatus.candidate;
  bool get isRestorableType =>
      modelType == ModelType.randomForest &&
      lifecycleStatus == ModelStatus.inactive;

  factory ModelVersionReview.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['version'] is! int ||
        json['breadCategoryId'] is! String ||
        json['breadCategoryName'] is! String ||
        json['trainingStart'] is! String ||
        json['trainingEnd'] is! String ||
        (json['holdoutStart'] != null && json['holdoutStart'] is! String) ||
        (json['trainingGroupId'] != null &&
            json['trainingGroupId'] is! String)) {
      throw const FormatException('Invalid model version.');
    }
    final type = switch (json['modelType']) {
      'RANDOM_FOREST' => ModelType.randomForest,
      'LINEAR_REGRESSION' => ModelType.linearRegression,
      _ => throw const FormatException('Invalid model type.'),
    };
    final status = switch (json['lifecycleStatus']) {
      'CANDIDATE' => ModelStatus.candidate,
      'ACTIVE' => ModelStatus.active,
      'INACTIVE' => ModelStatus.inactive,
      'REJECTED' => ModelStatus.rejected,
      _ => throw const FormatException('Invalid model status.'),
    };
    Map<String, int>? counts(Object? raw) {
      if (raw == null) return null;
      if (raw is! Map<String, dynamic> ||
          raw.values.any((value) => value is! int)) {
        throw const FormatException('Invalid model origin counts.');
      }
      return raw.map((key, value) => MapEntry(key, value as int));
    }

    final evaluation = json['latestEvaluation'];
    if (evaluation != null && evaluation is! Map<String, dynamic>) {
      throw const FormatException('Invalid latest evaluation.');
    }
    return ModelVersionReview(
      id: json['id'] as String,
      version: json['version'] as int,
      breadCategoryId: json['breadCategoryId'] as String,
      breadCategoryName: json['breadCategoryName'] as String,
      modelType: type,
      lifecycleStatus: status,
      trainingStart: json['trainingStart'] as String,
      trainingEnd: json['trainingEnd'] as String,
      holdoutStart: json['holdoutStart'] as String?,
      trainingGroupId: json['trainingGroupId'] as String?,
      trainingOriginCounts: counts(json['trainingOriginCounts']),
      holdoutOriginCounts: counts(json['holdoutOriginCounts']),
      latestEvaluation: evaluation == null
          ? null
          : ModelEvaluationReview.fromJson(evaluation),
    );
  }
}

class ModelReviewPage {
  const ModelReviewPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });
  final List<ModelVersionReview> items;
  final int page;
  final int pageSize;
  final int total;

  factory ModelReviewPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List ||
        json['page'] is! int ||
        json['pageSize'] is! int ||
        json['total'] is! int ||
        (json['page'] as int) < 1 ||
        (json['pageSize'] as int) < 1 ||
        (json['total'] as int) < 0 ||
        items.length > (json['pageSize'] as int) ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid model list response.');
    }
    return ModelReviewPage(
      items: items
          .map(
            (item) => ModelVersionReview.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      page: json['page'] as int,
      pageSize: json['pageSize'] as int,
      total: json['total'] as int,
    );
  }
}
