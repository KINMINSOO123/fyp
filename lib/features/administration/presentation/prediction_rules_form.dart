import 'dart:convert';

import 'package:flutter/material.dart';

const _weekdays = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];
const _weather = ['CLEAR', 'CLOUDY', 'RAIN', 'STORM', 'OTHER'];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// An editor for the existing prediction.context_rules JSON contract.
/// Only edited fields are converted back, so untouched numeric values retain
/// their original precision and unrelated settings stay intact.
class PredictionRulesForm extends StatefulWidget {
  const PredictionRulesForm({
    required this.rules,
    required this.activeCategories,
    required this.onSave,
    required this.busy,
    super.key,
  });

  final Map<String, dynamic> rules;
  final List<Map<String, dynamic>> activeCategories;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final bool busy;

  @override
  State<PredictionRulesForm> createState() => _PredictionRulesFormState();
}

class _PredictionRulesFormState extends State<PredictionRulesForm> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _values = <String, String>{};
  final _edited = <String>{};
  Set<int> _monsoonMonths = {};
  bool _monsoonEnabled = false;
  bool _monthsEdited = false;
  bool _weatherFallbackEnabled = false;
  bool _weatherFallbackEdited = false;
  bool _calendarFallback = false;
  bool _calendarFallbackEdited = false;
  String? _calendarCoverage;
  bool _demoFilled = false;
  String? _monthError;
  String? _formError;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(covariant PredictionRulesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rules, widget.rules)) {
      _restore();
      _revision++;
      _formKey = GlobalKey<FormState>();
    }
  }

  String _percent(num factor) {
    final value = (factor - 1) * 100;
    final fixed = value.toStringAsFixed(6);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _restore() {
    _values.clear();
    _edited.clear();
    final weekdays = widget.rules['weekdayFactors'] as Map;
    final weather = widget.rules['weatherFactors'] as Map;
    for (final day in _weekdays) {
      _values['weekdayFactors.$day'] = _percent(weekdays[day] as num);
    }
    for (final condition in _weather) {
      _values['weatherFactors.$condition'] = _percent(
        weather[condition] as num,
      );
    }
    for (final key in [
      'holidayFactor',
      'nonHolidayFactor',
      'monsoonFactor',
      'otherSeasonFactor',
    ]) {
      _values[key] = _percent(widget.rules[key] as num);
    }
    final fallback = widget.rules['weatherFallbackFactor'];
    _weatherFallbackEnabled = fallback is num;
    _values['weatherFallbackFactor'] = fallback is num
        ? _percent(fallback)
        : '0';
    final bases = widget.rules['baseQuantities'] as Map;
    for (final entry in bases.entries) {
      _values['baseQuantities.${entry.key}'] = entry.value.toString();
    }
    _monsoonMonths = (widget.rules['monsoonMonths'] as List)
        .cast<int>()
        .toSet();
    _monsoonEnabled = _monsoonMonths.isNotEmpty;
    _calendarFallback = widget.rules['allowCalendarFallback'] == true;
    _calendarCoverage = widget.rules['calendarVerifiedThrough'] as String?;
    _monthsEdited = false;
    _weatherFallbackEdited = false;
    _calendarFallbackEdited = false;
    _demoFilled = false;
    _monthError = null;
    _formError = null;
  }

  void _reset() {
    setState(() {
      _restore();
      _revision++;
      _formKey = GlobalKey<FormState>();
    });
  }

  void _useDemoDefaults() {
    setState(() {
      for (final day in _weekdays) {
        final key = 'weekdayFactors.$day';
        _values[key] = day == 'SATURDAY' || day == 'SUNDAY' ? '10' : '0';
        _edited.add(key);
      }
      for (final condition in _weather) {
        final key = 'weatherFactors.$condition';
        _values[key] = switch (condition) {
          'RAIN' => '-5',
          'STORM' => '-10',
          _ => '0',
        };
        _edited.add(key);
      }
      for (final entry in {
        'holidayFactor': '5',
        'nonHolidayFactor': '0',
        'monsoonFactor': '0',
        'otherSeasonFactor': '0',
      }.entries) {
        _values[entry.key] = entry.value;
        _edited.add(entry.key);
      }
      _monsoonEnabled = false;
      _monsoonMonths = {};
      _monthsEdited = true;
      _monthError = null;
      _formError = null;
      _demoFilled = true;
      _revision++;
      _formKey = GlobalKey<FormState>();
    });
  }

  String? _percentError(String? input) {
    final number = double.tryParse((input ?? '').trim());
    if (number == null || !number.isFinite) {
      return 'Enter a valid adjustment percentage.';
    }
    if (number < -100 || !(1 + number / 100).isFinite) {
      return 'Adjustment must be at least -100%.';
    }
    return null;
  }

  Widget _percentField(String label, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: _values[key] ?? '',
      enabled: !widget.busy,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        border: const OutlineInputBorder(),
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _percentError,
      onChanged: (value) {
        _values[key] = value;
        _edited.add(key);
      },
    ),
  );

  Widget _baseField(String id, String name) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: _values['baseQuantities.$id'] ?? '',
      enabled: !widget.busy,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '$name base units',
        helperText:
            'Used only when this category has no valid sales observations.',
        border: const OutlineInputBorder(),
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) {
        final number = int.tryParse((value ?? '').trim());
        if (number == null || number < 0 || number > 9007199254740991) {
          return 'Enter a nonnegative whole number.';
        }
        return null;
      },
      onChanged: (value) {
        _values['baseQuantities.$id'] = value;
        _edited.add('baseQuantities.$id');
      },
    ),
  );

  Map<String, dynamic> _buildRules() {
    final result = jsonDecode(jsonEncode(widget.rules)) as Map<String, dynamic>;
    final weekdays = Map<String, dynamic>.from(result['weekdayFactors'] as Map);
    final weather = Map<String, dynamic>.from(result['weatherFactors'] as Map);
    final bases = Map<String, dynamic>.from(result['baseQuantities'] as Map);
    for (final key in _edited) {
      if (key.startsWith('baseQuantities.')) {
        bases[key.substring('baseQuantities.'.length)] = int.parse(
          _values[key]!.trim(),
        );
      } else {
        final factor = 1 + double.parse(_values[key]!.trim()) / 100;
        if (key.startsWith('weekdayFactors.')) {
          weekdays[key.substring('weekdayFactors.'.length)] = factor;
        } else if (key.startsWith('weatherFactors.')) {
          weather[key.substring('weatherFactors.'.length)] = factor;
        } else {
          result[key] = factor;
        }
      }
    }
    result['weekdayFactors'] = weekdays;
    result['weatherFactors'] = weather;
    result['baseQuantities'] = bases;
    if (_monthsEdited) {
      result['monsoonMonths'] = _monsoonEnabled
          ? (_monsoonMonths.toList()..sort())
          : <int>[];
    }
    if (_weatherFallbackEdited) {
      result['weatherFallbackFactor'] = _weatherFallbackEnabled
          ? 1 + double.parse(_values['weatherFallbackFactor']!.trim()) / 100
          : null;
    }
    if (_calendarFallbackEdited) {
      result['allowCalendarFallback'] = _calendarFallback;
    }
    return result;
  }

  Future<void> _save() async {
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() {
      _monthError = _monsoonEnabled && _monsoonMonths.isEmpty
          ? 'Select at least one monsoon month.'
          : null;
      _formError = valid
          ? null
          : 'Review the highlighted fields, including collapsed sections.';
    });
    if (!valid || _monthError != null) return;
    await widget.onSave(_buildRules());
  }

  @override
  Widget build(BuildContext context) {
    final bases = widget.rules['baseQuantities'] as Map;
    final names = <String, String>{
      for (final row in widget.activeCategories)
        if (row['id'] is String)
          row['id'] as String: row['name']?.toString() ?? 'Category',
    };
    final ids = {
      ...bases.keys.map((key) => key.toString()),
      ...names.keys,
    }.toList()..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
    return Form(
      key: _formKey,
      child: KeyedSubtree(
        key: ValueKey(_revision),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'These are initial demo business assumptions, not scientifically '
              'validated effects. Adjustments change demand, not model confidence.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Cold-start adjustments multiply: a weekend holiday is '
              '1.10 \u00D7 1.05 = 1.155 before weather and season. Random Forest '
              'receives factors as features; a +10% input does not guarantee '
              'a +10% model prediction.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Older imported sales may have neutral context factors (1.00). '
              'Existing models may therefore have learned little context effect. '
              'Saving settings does not retrain models or change saved predictions.',
            ),
            const SizedBox(height: 16),
            Text(
              'Weekday adjustments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final day in _weekdays)
              _percentField(
                '${day[0]}${day.substring(1).toLowerCase()}',
                'weekdayFactors.$day',
              ),
            const SizedBox(height: 12),
            Text(
              'Weather adjustments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final condition in _weather)
              _percentField(condition, 'weatherFactors.$condition'),
            const SizedBox(height: 12),
            Text(
              'KL public holiday adjustments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'The holiday adjustment applies to published Kuala Lumpur '
              'public holidays after a successful year sync. Otherwise the '
              'non-holiday adjustment applies only with verified coverage.',
            ),
            const SizedBox(height: 8),
            _percentField('KL public holiday', 'holidayFactor'),
            _percentField('Non-holiday', 'nonHolidayFactor'),
            const SizedBox(height: 12),
            Text(
              'Monsoon adjustment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable monsoon months'),
              value: _monsoonEnabled,
              onChanged: widget.busy
                  ? null
                  : (value) {
                      setState(() {
                        _monsoonEnabled = value;
                        _monthsEdited = true;
                        if (!value) _monsoonMonths.clear();
                        _monthError = null;
                      });
                    },
            ),
            if (_monsoonEnabled) ...[
              const Text('Select the months that use the monsoon adjustment.'),
              Wrap(
                spacing: 6,
                children: [
                  for (var index = 0; index < 12; index++)
                    FilterChip(
                      label: Text(_monthNames[index]),
                      selected: _monsoonMonths.contains(index + 1),
                      onSelected: widget.busy
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _monsoonMonths.add(index + 1);
                                } else {
                                  _monsoonMonths.remove(index + 1);
                                }
                                _monthsEdited = true;
                                _monthError = null;
                              });
                            },
                    ),
                ],
              ),
              if (_monthError != null)
                Text(
                  _monthError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              _percentField('Monsoon months', 'monsoonFactor'),
            ],
            const Text(
              'With no monsoon months selected, the other-season adjustment '
              'applies all year.',
            ),
            const SizedBox(height: 8),
            _percentField('Other season', 'otherSeasonFactor'),
            const SizedBox(height: 12),
            ExpansionTile(
              maintainState: true,
              title: const Text('Category cold-start bases'),
              subtitle: Text('${ids.length} stored or active categories'),
              children: [
                const Text(
                  'These whole-unit bases apply only with no valid sales '
                  'observations. Existing category entries are preserved.',
                ),
                const SizedBox(height: 8),
                for (final id in ids)
                  _baseField(id, names[id] ?? 'Category $id'),
              ],
            ),
            ExpansionTile(
              maintainState: true,
              title: const Text('Missing-context options'),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use weather fallback if no record exists'),
                  value: _weatherFallbackEnabled,
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          setState(() {
                            _weatherFallbackEnabled = value;
                            _weatherFallbackEdited = true;
                            if (value) {
                              _values['weatherFallbackFactor'] = '0';
                            }
                          });
                        },
                ),
                if (_weatherFallbackEnabled)
                  _percentField(
                    'Missing-weather adjustment',
                    'weatherFallbackFactor',
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow unverified calendar fallback'),
                  value: _calendarFallback,
                  onChanged: widget.busy
                      ? null
                      : (value) {
                          setState(() {
                            _calendarFallback = value;
                            _calendarFallbackEdited = true;
                          });
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Legacy calendar verified-through setting'),
                  subtitle: Text('${_calendarCoverage ?? 'Not set'} · '
                      'KL public holiday coverage is managed by year sync.'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_demoFilled)
              const Text('Demo defaults filled. Select Save to apply them.'),
            if (_formError != null)
              Text(
                _formError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: widget.busy ? null : _save,
                  child: const Text('Save prediction adjustments'),
                ),
                OutlinedButton(
                  onPressed: widget.busy ? null : _reset,
                  child: const Text('Reset form'),
                ),
                TextButton(
                  onPressed: widget.busy ? null : _useDemoDefaults,
                  child: const Text('Use demo defaults'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
