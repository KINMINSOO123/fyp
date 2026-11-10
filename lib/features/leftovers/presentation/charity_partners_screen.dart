import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../data/leftover_service.dart';
import '../domain/leftover_models.dart';

class CharityPartnersScreen extends StatefulWidget {
  const CharityPartnersScreen({this.gateway, super.key});
  final CharityAdminGateway? gateway;
  @override
  State<CharityPartnersScreen> createState() => _CharityPartnersScreenState();
}

class _CharityPartnersScreenState extends State<CharityPartnersScreen> {
  late final CharityAdminGateway _gateway;
  List<CharityPartner> _partners = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? CharityAdminService();
    _load();
  }

  @override
  void dispose() {
    if (widget.gateway == null) (_gateway as CharityAdminService).close();
    super.dispose();
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Unable to save or load charity partners.';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final partners = await _gateway.list();
      if (mounted) setState(() => _partners = partners);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([CharityPartner? partner]) async {
    final input = await showDialog<_CharityInput>(
      context: context,
      builder: (_) => _CharityEditor(partner: partner),
    );
    if (input == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _gateway.save(
        id: partner?.id,
        name: input.name,
        contactInfo: input.contactInfo,
        isActive: input.isActive,
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Charity Partners')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading ? null : () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add'),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Administrators manage partners. Deactivation keeps donation history.',
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_loading && _partners.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text('No charity partners yet.'),
              ),
            for (final partner in _partners)
              Card(
                child: ListTile(
                  title: Text(partner.name),
                  subtitle: Text(
                    '${partner.isActive ? 'ACTIVE' : 'INACTIVE'}${partner.contactInfo == null ? '' : '\n${partner.contactInfo}'}',
                  ),
                  isThreeLine: partner.contactInfo != null,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _loading ? null : () => _edit(partner),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CharityInput {
  const _CharityInput(this.name, this.contactInfo, this.isActive);
  final String name;
  final String? contactInfo;
  final bool isActive;
}

class _CharityEditor extends StatefulWidget {
  const _CharityEditor({this.partner});
  final CharityPartner? partner;
  @override
  State<_CharityEditor> createState() => _CharityEditorState();
}

class _CharityEditorState extends State<_CharityEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.partner?.name ?? '');
    _contact = TextEditingController(text: widget.partner?.contactInfo ?? '');
    _active = widget.partner?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.partner == null ? 'Add Charity' : 'Edit Charity'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'A name is required.'
                  : null,
            ),
            TextFormField(
              controller: _contact,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Contact information (optional)',
              ),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _CharityInput(
              _name.text.trim(),
              _contact.text.trim().isEmpty ? null : _contact.text.trim(),
              _active,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
