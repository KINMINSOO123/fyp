import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../prediction/presentation/prediction_screen.dart';
import '../../model_management/presentation/model_list_screen.dart';
import '../../inventory/presentation/production_planning_screen.dart';
import '../../inventory/presentation/inventory_admin_screen.dart';
import '../../user_administration/presentation/user_list_screen.dart';
import '../../pos_simulation/presentation/pos_simulation_screen.dart';
import '../../leftovers/presentation/leftover_management_screen.dart';
import '../../leftovers/presentation/charity_partners_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/presentation/pending_actions_panel.dart';
import '../../notifications/data/push_registration_manager.dart';
import '../../administration/presentation/settings_screen.dart';
import '../../administration/presentation/audit_screen.dart';
import '../../administration/presentation/calendar_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.profile,
    required this.sessionController,
    super.key,
  });

  final UserProfile profile;
  final SessionController sessionController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    PushRegistrationManager.instance.start(widget.profile.userId);
    _notificationChannel = Supabase.instance.client
        .channel('home-notifications:${widget.profile.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_user_id',
            value: widget.profile.userId,
          ),
          callback: (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('New notification'),
                action: SnackBarAction(
                  label: 'View',
                  onPressed: () => _openNotifications(),
                ),
              ),
            );
          },
        )
        .subscribe();
  }

  Future<void> _openNotifications() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(userId: widget.profile.userId),
    ),
  );

  @override
  void dispose() {
    final channel = _notificationChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final sessionController = widget.sessionController;
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
                    final channel = _notificationChannel;
                    if (channel != null) {
                      await Supabase.instance.client.removeChannel(channel);
                      _notificationChannel = null;
                    }
                    await PushRegistrationManager.instance.stop();
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
            const PendingActionsPanel(),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: const Text(
                  'Review your alerts and delivery preferences.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await _openNotifications();
                },
              ),
            ),
            const SizedBox(height: 16),
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
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Bakery and Prediction Settings'),
                  subtitle: const Text(
                    'Edit validated bakery details and prediction factors.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Calendar Events'),
                  subtitle: const Text(
                    'Record sourced holidays and local events for predictions.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CalendarScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Audit History'),
                  subtitle: const Text(
                    'Review recorded user and system actions.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AuditScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: const Text('Inventory Administration'),
                  subtitle: const Text(
                    'Manage bread categories, recipes, ingredients and batches.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const InventoryAdminScreen(),
                      ),
                    );
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
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('POS Simulation'),
                subtitle: Text(
                  profile.role == UserRole.bakeryManager
                      ? 'Run confirmed production and review simulated sales.'
                      : 'Review completed simulated sales.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PosSimulationScreen(role: profile.role),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('Leftovers and Donations'),
                subtitle: Text(
                  profile.role == UserRole.bakeryManager
                      ? 'Allocate simulated leftovers and update donation progress.'
                      : 'Review completed leftover allocations.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LeftoverManagementScreen(role: profile.role),
                    ),
                  );
                },
              ),
            ),
            if (profile.role == UserRole.systemAdministrator) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('Charity Partners'),
                  subtitle: const Text(
                    'Add, update and deactivate donation partners.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CharityPartnersScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.assessment_outlined),
                title: const Text('Dashboard and Reports'),
                subtitle: const Text(
                  'Review simulated results and save filtered CSV or PDF reports.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReportsScreen(),
                    ),
                  );
                },
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
