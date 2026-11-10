import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/report_service.dart';
import '../domain/report_models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({this.gateway, super.key});
  final ReportGateway? gateway;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportGateway _gateway;
  BakeryReport? _report;
  List<ReportCategory> _categories = const [];
  String? _error;
  String? _today;
  String? _anchorDate;
  String? _fromDate;
  String? _toDate;
  String? _categoryId;
  String _period = 'DAY';
  String? _exporting;
  int _page = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? ReportService();
    _loadInitial();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as ReportService).close();
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to load report. Please try again.';
  }

  Future<void> _loadInitial() async {
    try {
      final report = await _gateway.get(const {});
      final categories = await _gateway.categories();
      if (!mounted) return;
      setState(() {
        _report = report;
        _categories = categories;
        _today = report.filters.fromDate;
        _anchorDate = report.filters.fromDate;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, String> _filters() {
    final values = <String, String>{'period': _period};
    if (_period == 'CUSTOM') {
      if (_fromDate != null && _toDate != null) {
        values['fromDate'] = _fromDate!;
        values['toDate'] = _toDate!;
      }
    } else if (_anchorDate != null) {
      values['date'] = _anchorDate!;
    }
    if (_categoryId != null) values['breadCategoryId'] = _categoryId!;
    return values;
  }

  Future<void> _load() async {
    if (_period == 'CUSTOM' && (_fromDate == null || _toDate == null)) return;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await _gateway.get(_filters());
      if (mounted) {
        setState(() {
          _report = report;
          _page = 0;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDate() async {
    final today = _today;
    if (today == null || _loading) return;
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_anchorDate ?? today),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(today),
    );
    if (chosen == null || !mounted) return;
    setState(() => _anchorDate = chosen.toIso8601String().substring(0, 10));
    await _load();
  }

  Future<bool> _chooseRange() async {
    final today = _today;
    if (today == null || _loading) return false;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(today),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(
              start: DateTime.parse(_fromDate!),
              end: DateTime.parse(_toDate!),
            )
          : null,
    );
    if (range == null || !mounted) return false;
    setState(() {
      _fromDate = range.start.toIso8601String().substring(0, 10);
      _toDate = range.end.toIso8601String().substring(0, 10);
    });
    await _load();
    return true;
  }

  Future<void> _export(String format) async {
    if (_report == null || _loading || _exporting != null) return;
    setState(() {
      _exporting = format;
      _error = null;
    });
    try {
      final saved = await _gateway.export(_filters(), format);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved in Downloads / Smart Bakery.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  String _rate(num? value) =>
      value == null ? 'Not Applicable' : '${value.toStringAsFixed(2)}%';
  String _money(num value) => 'RM ${value.toStringAsFixed(2)}';

  String _comparison(ReportRow row) => row.evaluationDataOrigin == null
      ? 'Comparable observation: Not Available'
      : 'Comparable ${row.evaluationDataOrigin}: '
            '${row.evaluationUnitsSold} sold, error ${row.evaluationPredictionError}';

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final total = report?.totals;
    final rows = report?.rows ?? const <ReportRow>[];
    final pages = (rows.length / 50).ceil();
    final visible = rows.skip(_page * 50).take(50);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard and Reports')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Simulated operational data. Financial values are reporting-only.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_period),
                initialValue: _period,
                decoration: const InputDecoration(labelText: 'Period'),
                items: const [
                  DropdownMenuItem(value: 'DAY', child: Text('Day')),
                  DropdownMenuItem(
                    value: 'WEEK',
                    child: Text('Week (Monday to Sunday)'),
                  ),
                  DropdownMenuItem(
                    value: 'CUSTOM',
                    child: Text('Custom range'),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (value) async {
                        if (value == null) return;
                        final previous = _period;
                        setState(() => _period = value);
                        if (value == 'CUSTOM' &&
                            (_fromDate == null || _toDate == null)) {
                          if (!await _chooseRange() && mounted) {
                            setState(() => _period = previous);
                          }
                        } else {
                          await _load();
                        }
                      },
              ),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : (_period == 'CUSTOM' ? _chooseRange : _chooseDate),
                icon: const Icon(Icons.date_range),
                label: Text(
                  _period == 'CUSTOM'
                      ? '${_fromDate ?? 'From'} to ${_toDate ?? 'To'}'
                      : _anchorDate ?? 'Choose date',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Bread category'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (value) async {
                        setState(() => _categoryId = value);
                        await _load();
                      },
              ),
              if (_loading || _exporting != null)
                const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (report != null && total != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${report.filters.fromDate} to ${report.filters.toDate}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${total.resultCount} completed category-days'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Metric('Predicted', '${total.predictedUnitsSold}'),
                    _Metric('Produced', '${total.produced}'),
                    _Metric('Sold', '${total.unitsSold}'),
                    _Metric('Lost sales', '${total.lostSales}'),
                    _Metric(
                      'Signed prediction error',
                      '${total.salesPredictionError}',
                    ),
                    _Metric('Leftover', '${total.leftover}'),
                    _Metric('Donated', '${total.donated}'),
                    _Metric('Discarded waste', '${total.wasted}'),
                    _Metric('Unallocated', '${total.remainingUnallocated}'),
                    _Metric('Leftover rate', _rate(total.leftoverRatePct)),
                    _Metric('Waste rate', _rate(total.discardedWasteRatePct)),
                    _Metric(
                      'Sales fulfilment',
                      _rate(total.salesFulfilmentPct),
                    ),
                    _Metric('Revenue', _money(total.revenue)),
                    _Metric('Ingredient cost', _money(total.ingredientCost)),
                    _Metric('Gross profit', _money(total.grossProfit)),
                    _Metric('Gross margin', _rate(total.grossProfitMarginPct)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exporting == null
                          ? () => _export('CSV')
                          : null,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('Save CSV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exporting == null
                          ? () => _export('PDF')
                          : null,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Save PDF'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rows.isEmpty)
                  const Text('No completed results for these filters.'),
                for (final row in visible)
                  Card(
                    child: ListTile(
                      title: Text('${row.date} · ${row.breadCategoryName}'),
                      subtitle: Text(
                        'Simulated · Predicted ${row.predictedUnitsSold} · '
                        'Produced ${row.produced} · Sold ${row.unitsSold}\n'
                        'Leftover ${row.leftover} · Donated ${row.donated} · '
                        'Discarded ${row.wasted}\n'
                        'Error ${row.salesPredictionError} · Revenue ${_money(row.revenue)} '
                        '· Cost ${_money(row.ingredientCost)} · '
                        'Profit ${_money(row.grossProfit)}\n'
                        '${_comparison(row)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                if (pages > 1)
                  Row(
                    children: [
                      TextButton(
                        onPressed: _page > 0
                            ? () => setState(() => _page--)
                            : null,
                        child: const Text('Previous'),
                      ),
                      Expanded(
                        child: Text(
                          'Page ${_page + 1} of $pages',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: _page + 1 < pages
                            ? () => setState(() => _page++)
                            : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}
