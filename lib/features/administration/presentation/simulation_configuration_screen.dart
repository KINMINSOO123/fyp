import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/simulation_configuration_service.dart';

class SimulationConfigurationScreen extends StatefulWidget {
  const SimulationConfigurationScreen({this.gateway, super.key});
  final SimulationConfigurationGateway? gateway;
  @override
  State<SimulationConfigurationScreen> createState() =>
      _SimulationConfigurationScreenState();
}

class _SimulationConfigurationScreenState
    extends State<SimulationConfigurationScreen> {
  static const _weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  static const _weather = [
    'NEUTRAL',
    'CLEAR',
    'CLOUDY',
    'RAIN',
    'STORM',
    'OTHER',
  ];
  final _form = GlobalKey<FormState>();
  late final SimulationConfigurationGateway _gateway;
  final _scenarioFields = <String, TextEditingController>{};
  final _manualFields = <String, TextEditingController>{};
  final _manualErrors = <String, String?>{};
  List<Map<String, dynamic>> _categories = const [];
  int? _version;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? SimulationConfigurationService();
    _load();
  }

  @override
  void dispose() {
    for (final field in _scenarioFields.values) {
      field.dispose();
    }
    for (final field in _manualFields.values) {
      field.dispose();
    }
    if (widget.gateway == null) {
      (_gateway as SimulationConfigurationService).close();
    }
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : error is FormatException
      ? error.message
      : 'Unable to load or save simulation settings.';

  String _percent(Object? factor) {
    if (factor is! num) throw const FormatException('Invalid scenario factor.');
    return ((factor.toDouble() - 1) * 100).toStringAsFixed(2);
  }

  void _replaceField(String key, String text) {
    _scenarioFields.putIfAbsent(key, TextEditingController.new).text = text;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _gateway.load();
      final rawCategories = data['categories'];
      final scenario = data['scenario'];
      if (rawCategories is! List ||
          scenario is! Map<String, dynamic> ||
          scenario['weekdayFactors'] is! Map ||
          scenario['weatherFactors'] is! Map ||
          scenario['scenarioVersion'] is! int) {
        throw const FormatException('Incomplete simulation configuration.');
      }
      final days = scenario['weekdayFactors'] as Map;
      final weather = scenario['weatherFactors'] as Map;
      for (final day in _weekdays) {
        _replaceField('weekday.$day', _percent(days[day]));
      }
      for (final condition in _weather) {
        _replaceField('weather.$condition', _percent(weather[condition]));
      }
      _replaceField('holiday', _percent(scenario['holidayFactor']));
      _replaceField('nonHoliday', _percent(scenario['nonHolidayFactor']));
      final variation = scenario['variationMaxPct'];
      if (variation is! num) {
        throw const FormatException('Invalid scenario variation.');
      }
      _replaceField('variation', variation.toString());
      final categories = rawCategories.map((raw) {
        if (raw is! Map<String, dynamic> ||
            raw['id'] is! String ||
            raw['name'] is! String) {
          throw const FormatException('Invalid simulation category.');
        }
        return raw;
      }).toList();
      for (final category in categories) {
        final id = category['id'] as String;
        final baseline = category['baseline'];
        final value = baseline is Map ? baseline['baseDemand'] : null;
        _manualFields.putIfAbsent(id, TextEditingController.new).text =
            value is num ? value.toString() : '';
      }
      if (mounted) {
        setState(() {
          _categories = categories;
          _version = scenario['scenarioVersion'] as int;
          _manualErrors.clear();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _factor(String key) =>
      1 + double.parse(_scenarioFields[key]!.text.trim()) / 100;

  Future<void> _saveScenario() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _gateway.saveScenario({
        'weekdayFactors': {
          for (final day in _weekdays) day: _factor('weekday.$day'),
        },
        'weatherFactors': {
          for (final condition in _weather)
            condition: _factor('weather.$condition'),
        },
        'holidayFactor': _factor('holiday'),
        'nonHolidayFactor': _factor('nonHoliday'),
        'variationMaxPct': double.parse(
          _scenarioFields['variation']!.text.trim(),
        ),
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBaseline(String id, {required bool imported}) async {
    if (_saving) return;
    double? value;
    if (!imported) {
      value = double.tryParse(_manualFields[id]!.text.trim());
      if (value == null ||
          !value.isFinite ||
          value < 0 ||
          value > 1000000 ||
          (value * 1000).roundToDouble() / 1000 != value) {
        setState(
          () => _manualErrors[id] =
              'Enter 0 to 1,000,000 units, up to three decimals.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
      _manualErrors[id] = null;
    });
    try {
      if (imported) {
        await _gateway.saveImported(id);
      } else {
        await _gateway.saveManual(id, value!);
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _percentField(String label, String key, {bool variation = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: _scenarioFields[key],
          enabled: !_saving && !_loading,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
          decoration: InputDecoration(
            labelText: '$label (%)',
            border: const OutlineInputBorder(),
          ),
          validator: (text) {
            final value = double.tryParse((text ?? '').trim());
            if (value == null ||
                !value.isFinite ||
                (variation
                    ? value < 0 ||
                          value > 30 ||
                          (value * 100).roundToDouble() / 100 != value
                    : value < -100 || value > 200)) {
              return variation
                  ? 'Enter 0–30%, up to two decimals.'
                  : 'Enter an adjustment from -100% to +200%.';
            }
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Simulation Demand Settings')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'These are demo customer-demand assumptions, separate '
            'from ML prediction factors. Saving settings does not change '
            'completed simulations or retrain a model.',
          ),
          if (_loading || _saving) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          Text(
            'Category baselines',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Enter a baseline manually, or explicitly calculate and '
            'save the average of selected validated imported sales. '
            'Simulation-generated sales are excluded.',
          ),
          for (final category in _categories)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category['name'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      category['baseline'] is Map
                          ? 'Saved: ${category['baseline']['baseDemand']} units '
                                '(${category['baseline']['source'] == 'MANUAL' ? 'manual' : 'validated imported average'})'
                          : 'No baseline configured',
                    ),
                    if (category['baseline'] is Map &&
                        category['baseline']['importedSampleCount'] != null)
                      Text(
                        'Imported days: '
                        '${category['baseline']['importedSampleCount']} '
                        '(${category['baseline']['importedFirstDate']} to '
                        '${category['baseline']['importedLastDate']})',
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualFields[category['id']],
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Manual base demand (units)',
                        border: const OutlineInputBorder(),
                        errorText: _manualErrors[category['id']],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _saveBaseline(
                                  category['id'] as String,
                                  imported: false,
                                ),
                          child: const Text('Save manual baseline'),
                        ),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _saveBaseline(
                                  category['id'] as String,
                                  imported: true,
                                ),
                          child: const Text('Use imported average'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 32),
          Text(
            'Scenario version ${_version ?? '—'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            '0% is neutral (factor 1.00). The weekday, KL holiday '
            'and observed current-weather adjustments multiply before bounded '
            'variation. A change creates a new scenario version.',
          ),
          if (_version != null)
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final day in _weekdays)
                    _percentField(day, 'weekday.$day'),
                  const SizedBox(height: 8),
                  for (final condition in _weather)
                    _percentField(
                      condition == 'NEUTRAL'
                          ? 'Neutral (legacy scenario only)'
                          : condition,
                      'weather.$condition',
                    ),
                  _percentField('KL holiday', 'holiday'),
                  _percentField('Non-holiday', 'nonHoliday'),
                  _percentField(
                    'Random variation bound',
                    'variation',
                    variation: true,
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _saveScenario,
                    child: const Text('Save scenario settings'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
