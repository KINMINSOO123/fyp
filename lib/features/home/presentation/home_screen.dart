import 'package:flutter/material.dart';

import '../../auth/application/session_controller.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../prediction/presentation/prediction_screen.dart';
import '../../model_management/presentation/model_list_screen.dart';
import '../../inventory/presentation/production_planning_screen.dart';
import '../../inventory/presentation/inventory_admin_screen.dart';
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
              ),
            const SizedBox(height: 16),
            if (profile.role == UserRole.systemAdministrator) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: const Text('Inventory Administration'),
                  subtitle: const Text('Manage bread categories, recipes, ingredients and batches.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const InventoryAdminScreen(),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.model_training),
                  title: const Text('Model Management'),
                  subtitle: const Text(
                    'Train, evaluate and manage model versions.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ModelListScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_graph),
                title: const Text('Demand Prediction'),
                subtitle: Text(
                  profile.role == UserRole.bakeryManager
                      ? 'Generate and review next-day predictions.'
                      : 'Review saved next-day predictions.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PredictionScreen(role: profile.role),
                    ),
                  );
                },
              ),
            ),
            if (profile.role == UserRole.bakeryManager) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Production Planning'),
                  subtitle: const Text(
                    'Review shared stock and confirm next-day production.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProductionPlanningScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
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
