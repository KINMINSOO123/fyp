import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/administration_service.dart';
import 'prediction_rules_form.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.gateway, super.key});
  final AdministrationGateway? gateway;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AdministrationGateway _gateway;
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _opens = TextEditingController();
  final _closes = TextEditingController();
  final _timezone = TextEditingController();
  final _threshold = TextEditingController();
  Map<String, dynamic>? _contextRules;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _updatedAt;
  Map<String, dynamic>? _serviceStatus;
  List<Map<String, dynamic>> _activeCategories = const [];

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? AdministrationService();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _opens.dispose();
    _closes.dispose();
    _timezone.dispose();
    _threshold.dispose();
    if (widget.gateway == null) (_gateway as AdministrationService).close();
    super.dispose();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : error is FormatException
      ? error.message
      : 'Unable to load or save settings.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _gateway.settings();
      final bakery = data['bakery'];
      final settings = data['systemSettings'];
      if (bakery is! Map<String, dynamic> || settings is! List) {
        throw const FormatException('Invalid settings data.');
      }
      final byKey = <String, dynamic>{};
      for (final item in settings) {
        if (item is! Map<String, dynamic> || item['key'] is! String) {
          throw const FormatException('Invalid system setting.');
        }
        byKey[item['key'] as String] = item['value'];
      }
      if (!mounted) return;
      setState(() {
        _name.text = bakery['name']?.toString() ?? '';
        _location.text = bakery['locationType']?.toString() ?? '';
        _opens.text = bakery['opensAt']?.toString() ?? '';
        _closes.text = bakery['closesAt']?.toString() ?? '';
        _timezone.text = bakery['timezone']?.toString() ?? '';
        _updatedAt = bakery['updatedAt']?.toString();
        _threshold.text =
            byKey['prediction.low_confidence_threshold']?.toString() ?? '';
        final rules = byKey['prediction.context_rules'];
        _contextRules = rules is Map<String, dynamic> ? rules : null;
      });
      try {
        final status = await _gateway.serviceStatus();
        if (mounted) setState(() => _serviceStatus = status);
      } catch (_) {
        if (mounted) setState(() => _serviceStatus = null);
      }
      try {
        final categories = await _gateway.activeCategories();
        if (mounted) setState(() => _activeCategories = categories);
      } catch (_) {
        if (mounted) setState(() => _activeCategories = const []);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved and audited.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBakery() => _save(() async {
    await _gateway.saveBakery({
      'name': _name.text.trim(),
      'locationType': _location.text.trim(),
      'opensAt': _opens.text.trim(),
      'closesAt': _closes.text.trim(),
      'timezone': _timezone.text.trim(),
    });
  });

  Future<void> _saveThreshold() => _save(() async {
    final value = double.tryParse(_threshold.text.trim());
    if (value == null || value < 0 || value > 100) {
      throw const FormatException(
        'Enter a confidence threshold from 0 to 100.',
      );
    }
    await _gateway.saveSetting('prediction.low_confidence_threshold', value);
  });

  Future<void> _saveContext(Map<String, dynamic> value) => _save(() async {
    await _gateway.saveSetting('prediction.context_rules', value);
  });

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      enabled: !_saving && !_loading,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bakery Settings'),
      actions: [
        IconButton(
          tooltip: 'Reload settings',
          onPressed: _loading || _saving ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading || _saving) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          Text('Bakery', style: Theme.of(context).textTheme.titleLarge),
          if (_updatedAt != null) Text('Last saved: $_updatedAt'),
          const SizedBox(height: 12),
          _field('Name', _name),
          _field('Location type', _location),
          _field('Opening time (HH:mm)', _opens),
          _field('Closing time (HH:mm)', _closes),
          _field('IANA timezone', _timezone),
          FilledButton(
            onPressed: _saving || _loading ? null : _saveBakery,
            child: const Text('Save bakery settings'),
          ),
          const Divider(height: 36),
          Text(
            'Prediction confidence',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Model confidence below this percentage is labelled Low Confidence.',
          ),
          const SizedBox(height: 12),
          _field(
            'Threshold (%)',
            _threshold,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: _saving || _loading ? null : _saveThreshold,
            child: const Text('Save confidence threshold'),
          ),
          const Divider(height: 36),
          Text(
            'Prediction context factors',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Demand adjustments are stored with the bakery prediction rules. '
            'Weather and calendar fallbacks are labelled in saved predictions.',
          ),
          const SizedBox(height: 12),
          if (_contextRules == null)
            const Text('Prediction rules are unavailable.')
          else
            PredictionRulesForm(
              rules: _contextRules!,
              activeCategories: _activeCategories,
              busy: _saving || _loading,
              onSave: _saveContext,
            ),
          const Divider(height: 36),
          Text('Service status', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'Status is checked on request. FCM configuration does not prove delivery.',
          ),
          if (_serviceStatus == null)
            const Text('Service status is unavailable.'),
          for (final entry
              in _serviceStatus?.entries ?? <MapEntry<String, dynamic>>[])
            if (entry.key != 'note')
              ListTile(
                dense: true,
                title: Text(entry.key),
                trailing: Text(entry.value.toString()),
              ),
        ],
      ),
    ),
  );
}
