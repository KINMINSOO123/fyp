class ReportCategory {
  const ReportCategory({required this.id, required this.name});
  final String id;
  final String name;

  factory ReportCategory.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['name'] is! String) {
      throw const FormatException('Invalid report category.');
    }
    return ReportCategory(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}

class ReportFilters {
  const ReportFilters({
    required this.period,
    required this.fromDate,
    required this.toDate,
    required this.breadCategoryId,
  });
  final String period;
  final String fromDate;
  final String toDate;
  final String? breadCategoryId;

  factory ReportFilters.fromJson(Map<String, dynamic> json) {
    if (json['period'] is! String ||
        json['fromDate'] is! String ||
        json['toDate'] is! String ||
        (json['breadCategoryId'] != null &&
            json['breadCategoryId'] is! String)) {
      throw const FormatException('Invalid report filters.');
    }
    return ReportFilters(
      period: json['period'] as String,
      fromDate: json['fromDate'] as String,
      toDate: json['toDate'] as String,
      breadCategoryId: json['breadCategoryId'] as String?,
    );
  }
}

num _number(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid report $name.');
  }
  return value;
}

num? _rate(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid report $name.');
  }
  return value;
}

class ReportTotals {
  const ReportTotals({
    required this.resultCount,
    required this.predictedUnitsSold,
    required this.produced,
    required this.unitsSold,
    required this.lostSales,
    required this.estimatedDemand,
    required this.leftover,
    required this.donated,
    required this.wasted,
    required this.remainingUnallocated,
    required this.salesPredictionError,
    required this.revenue,
    required this.ingredientCost,
    required this.grossProfit,
    required this.leftoverRatePct,
    required this.discardedWasteRatePct,
    required this.salesFulfilmentPct,
    required this.grossProfitMarginPct,
  });
  final num resultCount, predictedUnitsSold, produced, unitsSold, lostSales;
  final num estimatedDemand, leftover, donated, wasted, remainingUnallocated;
  final num salesPredictionError, revenue, ingredientCost, grossProfit;
  final num? leftoverRatePct, discardedWasteRatePct, salesFulfilmentPct;
  final num? grossProfitMarginPct;

  factory ReportTotals.fromJson(Map<String, dynamic> json) => ReportTotals(
    resultCount: _number(json, 'resultCount'),
    predictedUnitsSold: _number(json, 'predictedUnitsSold'),
    produced: _number(json, 'produced'),
    unitsSold: _number(json, 'unitsSold'),
    lostSales: _number(json, 'lostSales'),
    estimatedDemand: _number(json, 'estimatedDemand'),
    leftover: _number(json, 'leftover'),
    donated: _number(json, 'donated'),
    wasted: _number(json, 'wasted'),
    remainingUnallocated: _number(json, 'remainingUnallocated'),
    salesPredictionError: _number(json, 'salesPredictionError'),
    revenue: _number(json, 'revenue'),
    ingredientCost: _number(json, 'ingredientCost'),
    grossProfit: _number(json, 'grossProfit'),
    leftoverRatePct: _rate(json, 'leftoverRatePct'),
    discardedWasteRatePct: _rate(json, 'discardedWasteRatePct'),
    salesFulfilmentPct: _rate(json, 'salesFulfilmentPct'),
    grossProfitMarginPct: _rate(json, 'grossProfitMarginPct'),
  );
}

class ReportRow {
  const ReportRow({
    required this.date,
    required this.breadCategoryName,
    required this.dataOrigin,
    required this.predictedUnitsSold,
    required this.produced,
    required this.unitsSold,
    required this.leftover,
    required this.donated,
    required this.wasted,
    required this.salesPredictionError,
    required this.revenue,
    required this.ingredientCost,
    required this.grossProfit,
    required this.evaluationDataOrigin,
    required this.evaluationUnitsSold,
    required this.evaluationPredictionError,
  });
  final String date, breadCategoryName, dataOrigin;
  final num predictedUnitsSold, produced, unitsSold, leftover, donated, wasted;
  final num salesPredictionError, revenue, ingredientCost, grossProfit;
  final String? evaluationDataOrigin;
  final num? evaluationUnitsSold, evaluationPredictionError;

  factory ReportRow.fromJson(Map<String, dynamic> json) {
    if (json['date'] is! String ||
        json['breadCategoryName'] is! String ||
        json['dataOrigin'] != 'SIMULATION_GENERATED' ||
        (json['evaluationDataOrigin'] != null &&
            !const [
              'ACTUAL_TRANSACTION',
              'IMPORTED_HISTORICAL',
              'SIMULATION_GENERATED',
            ].contains(json['evaluationDataOrigin'])) ||
        (json['evaluationUnitsSold'] == null) !=
            (json['evaluationDataOrigin'] == null) ||
        (json['evaluationPredictionError'] == null) !=
            (json['evaluationDataOrigin'] == null)) {
      throw const FormatException('Invalid report row.');
    }
    return ReportRow(
      date: json['date'] as String,
      breadCategoryName: json['breadCategoryName'] as String,
      dataOrigin: json['dataOrigin'] as String,
      predictedUnitsSold: _number(json, 'predictedUnitsSold'),
      produced: _number(json, 'produced'),
      unitsSold: _number(json, 'unitsSold'),
      leftover: _number(json, 'leftover'),
      donated: _number(json, 'donated'),
      wasted: _number(json, 'wasted'),
      salesPredictionError: _number(json, 'salesPredictionError'),
      revenue: _number(json, 'revenue'),
      ingredientCost: _number(json, 'ingredientCost'),
      grossProfit: _number(json, 'grossProfit'),
      evaluationDataOrigin: json['evaluationDataOrigin'] as String?,
      evaluationUnitsSold: json['evaluationUnitsSold'] == null
          ? null
          : _number(json, 'evaluationUnitsSold'),
      evaluationPredictionError: json['evaluationPredictionError'] == null
          ? null
          : _number(json, 'evaluationPredictionError'),
    );
  }
}

class BakeryReport {
  const BakeryReport({
    required this.filters,
    required this.totals,
    required this.rows,
    required this.generatedAt,
  });
  final ReportFilters filters;
  final ReportTotals totals;
  final List<ReportRow> rows;
  final String generatedAt;

  factory BakeryReport.fromJson(Map<String, dynamic> json) {
    if (json['filters'] is! Map<String, dynamic> ||
        json['totals'] is! Map<String, dynamic> ||
        json['rows'] is! List ||
        json['generatedAt'] is! String ||
        json['sourceLabel'] != 'SIMULATED_OPERATIONAL_RESULTS') {
      throw const FormatException('Invalid report response.');
    }
    final rawRows = json['rows'] as List;
    if (rawRows.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Invalid report rows.');
    }
    return BakeryReport(
      filters: ReportFilters.fromJson(json['filters'] as Map<String, dynamic>),
      totals: ReportTotals.fromJson(json['totals'] as Map<String, dynamic>),
      rows: rawRows
          .map((row) => ReportRow.fromJson(row as Map<String, dynamic>))
          .toList(),
      generatedAt: json['generatedAt'] as String,
    );
  }
}
