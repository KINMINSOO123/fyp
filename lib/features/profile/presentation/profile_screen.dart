import 'package:flutter/material.dart';

import '../../auth/application/session_controller.dart';
import '../domain/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.sessionController, super.key});

  final SessionController sessionController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.sessionController.profile?.fullName ?? '',
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final succeeded = await widget.sessionController.updateFullName(
      _nameController.text.trim(),
    );

    if (!mounted) {
      return;
    }

    if (widget.sessionController.status == SessionStatus.signedOut) {
      Navigator.of(context).pop();
      return;
    }

    if (succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sessionController,
      builder: (context, _) {
        final profile = widget.sessionController.profile;

        if (profile == null) {
          return const Scaffold(
            body: Center(child: Text('Profile is unavailable.')),
          );
        }

        final roleLabel = switch (profile.role) {
          UserRole.bakeryManager => 'Bakery Manager',
          UserRole.systemAdministrator => 'System Administrator',
        };

        final statusLabel = switch (profile.accountStatus) {
          AccountStatus.active => 'Active',
          AccountStatus.inactive => 'Inactive',
        };

        final isSaving = widget.sessionController.isUpdatingProfile;

        return Scaffold(
          appBar: AppBar(title: const Text('My Profile')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !isSaving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Full name is required.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Role'),
                      subtitle: Text(roleLabel),
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Account status'),
                      subtitle: Text(statusLabel),
                    ),
                    if (widget.sessionController.profileUpdateError !=
                        null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.sessionController.profileUpdateError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: isSaving ? null : _save,
                      icon: isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save Profile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
