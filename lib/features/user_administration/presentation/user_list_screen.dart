import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../profile/domain/user_profile.dart';
import '../data/user_administration_service.dart';
import '../domain/admin_user.dart';
import 'create_user_screen.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final UserAdministrationService _service = UserAdministrationService();

  AdminUserPage? _result;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.listUsers(page: page, pageSize: 20);

      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } on FormatException {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'The server returned invalid user information.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCreateUser() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreateUserScreen()),
    );

    if (!mounted || created != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User account created successfully.')),
    );

    await _loadPage(1);
  }

  String _roleLabel(UserRole? role) {
    return switch (role) {
      UserRole.bakeryManager => 'Bakery Manager',
      UserRole.systemAdministrator => 'System Administrator',
      null => 'Profile missing',
    };
  }

  String _statusLabel(AccountStatus? status) {
    return switch (status) {
      AccountStatus.active => 'Active',
      AccountStatus.inactive => 'Inactive',
      null => 'Unavailable',
    };
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Users and Roles')),
      body: SafeArea(child: _buildBody(result)),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create user',
        onPressed: _openCreateUser,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(AdminUserPage? result) {
    if (_isLoading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _loadPage(1),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (result == null) {
      return const SizedBox.shrink();
    }

    final hasPrevious = result.page > 1;
    final hasNext = result.page * result.pageSize < result.total;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${result.total} user account(s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _isLoading ? null : () => _loadPage(result.page),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_isLoading) const LinearProgressIndicator(),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadPage(result.page),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: result.users.length,
              itemBuilder: (context, index) {
                return _UserCard(
                  user: result.users[index],
                  roleLabel: _roleLabel(result.users[index].role),
                  statusLabel: _statusLabel(result.users[index].accountStatus),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: hasPrevious && !_isLoading
                    ? () => _loadPage(result.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              Expanded(
                child: Text('Page ${result.page}', textAlign: TextAlign.center),
              ),
              OutlinedButton.icon(
                onPressed: hasNext && !_isLoading
                    ? () => _loadPage(result.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.roleLabel,
    required this.statusLabel,
  });

  final AdminUser user;
  final String roleLabel;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.fullName ?? 'Missing user profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(user.email ?? 'No email available'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.badge_outlined, size: 18),
                  label: Text(roleLabel),
                ),
                Chip(
                  avatar: const Icon(Icons.circle, size: 12),
                  label: Text(statusLabel),
                ),
                if (!user.hasCompleteProfile)
                  Chip(
                    backgroundColor: colorScheme.errorContainer,
                    avatar: Icon(
                      Icons.warning_amber,
                      color: colorScheme.onErrorContainer,
                    ),
                    label: Text(
                      'Profile missing',
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
