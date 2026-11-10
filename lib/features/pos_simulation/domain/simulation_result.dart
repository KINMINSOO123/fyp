class SimulationItem {
  const SimulationItem({
    required this.breadCategoryName,
    required this.predictedUnitsSold,
    required this.predictionMode,
    required this.confidence,
    required this.produced,
    required this.unitsSold,
    required this.lostSales,
    required this.leftover,
    required this.remainingUnallocatedLeftover,
    required this.salesPredictionError,
    required this.revenue,
    required this.ingredientCost,
    required this.grossProfit,
  });

  final String breadCategoryName;
  final int predictedUnitsSold;
  final String predictionMode;
  final double? confidence;
  final int produced;
  final int unitsSold;
  final int lostSales;
  final int leftover;
  final int remainingUnallocatedLeftover;
  final int salesPredictionError;
  final double revenue;
  final double ingredientCost;
  final double grossProfit;

  factory SimulationItem.fromJson(Map<String, dynamic> json) {
    const integers = [
      'predictedUnitsSold',
      'produced',
      'unitsSold',
      'lostSales',
      'leftover',
      'remainingUnallocatedLeftover',
      'salesPredictionError',
    ];
    if (json['breadCategoryName'] is! String ||
        json['dataOrigin'] != 'SIMULATION_GENERATED' ||
        integers.any((key) => json[key] is! int) ||
        json['revenue'] is! num ||
        json['ingredientCost'] is! num ||
        json['grossProfit'] is! num) {
      throw const FormatException('Invalid simulation result.');
    }
    final mode = json['predictionMode'];
    final confidence = json['confidence'];
    final modelVersionId = json['modelVersionId'];
    if ((mode == 'MODEL' &&
            (confidence is! num ||
                confidence < 0 ||
                confidence > 100 ||
                modelVersionId is! String)) ||
        (mode == 'COLD_START' &&
            (confidence != null || modelVersionId != null)) ||
        (mode != 'MODEL' && mode != 'COLD_START')) {
      throw const FormatException('Invalid simulation prediction context.');
    }
    return SimulationItem(
      breadCategoryName: json['breadCategoryName'] as String,
      predictedUnitsSold: json['predictedUnitsSold'] as int,
      predictionMode: mode as String,
      confidence: (confidence as num?)?.toDouble(),
      produced: json['produced'] as int,
      unitsSold: json['unitsSold'] as int,
      lostSales: json['lostSales'] as int,
      leftover: json['leftover'] as int,
      remainingUnallocatedLeftover: json['remainingUnallocatedLeftover'] as int,
      salesPredictionError: json['salesPredictionError'] as int,
      revenue: (json['revenue'] as num).toDouble(),
      ingredientCost: (json['ingredientCost'] as num).toDouble(),
      grossProfit: (json['grossProfit'] as num).toDouble(),
    );
  }
}

class SimulationResult {
  const SimulationResult({required this.date, required this.items});
  final String date;
  final List<SimulationItem> items;

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (json['date'] is! String ||
        items is! List ||
        items.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException('Invalid simulation response.');
    }
    return SimulationResult(
      date: json['date'] as String,
      items: items
          .map((item) => SimulationItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
