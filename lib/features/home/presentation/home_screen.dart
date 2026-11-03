import 'package:flutter/material.dart';

import '../../auth/application/session_controller.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../user_administration/presentation/user_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.profile,
    required this.sessionController,
    super.key,
  });

  final UserProfile profile;
  final SessionController sessionController;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (profile.role) {
      UserRole.bakeryManager => 'Bakery Manager',
      UserRole.systemAdministrator => 'System Administrator',
    };

    final isSigningOut = sessionController.status == SessionStatus.signingOut;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Bakery'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: isSigningOut
                ? null
                : () async {
                    await sessionController.signOut();
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Welcome, ${profile.fullName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(roleLabel),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                subtitle: Text('${profile.fullName}\n$roleLabel'),
                isThreeLine: true,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProfileScreen(sessionController: sessionController),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (profile.role == UserRole.systemAdministrator)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Users and Roles'),
                  subtitle: const Text(
                    'Manage user accounts, assigned roles and account status.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UserListScreen(),
                      ),
                    );
                  },
                ),
              )
            else
              const Card(
                child: ListTile(
                  leading: Icon(Icons.dashboard_outlined),
                  title: Text('Bakery operations'),
                  subtitle: Text(
                    'Operational modules will appear here as they are implemented.',
                  ),
                ),
              ),
            if (isSigningOut) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
