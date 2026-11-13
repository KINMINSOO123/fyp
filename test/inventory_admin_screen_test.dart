import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/inventory/data/inventory_admin_service.dart';
import 'package:fyp/features/inventory/data/restock_service.dart';
import 'package:fyp/features/inventory/presentation/inventory_admin_screen.dart';
import 'package:fyp/features/inventory/presentation/restock_admin_screen.dart';
import 'package:fyp/features/profile/domain/user_profile.dart';

class FakeInventoryAdminGateway implements InventoryAdminGateway {
  @override
  Future<int> scanAlerts() async => 0;
  @override
  Future<List<Map<String, dynamic>>> categories() async => [
    {
      'id': 'category',
      'name': 'Wholemeal Bread',
      'displayOrder': 1,
      'isActive': true,
      'sellingPrice': 5.5,
      'description': null,
      'shelfLifeHours': 24,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> ingredients() async => [
    {
      'id': 'ingredient',
      'name': 'Flour',
      'unit': 'KG',
      'referenceUnitCost': 4.5,
      'reorderThresholdGrams': 500,
      'snapshotQuantityGrams': 1000,
      'isActive': true,
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> batches(int page) async => [
    {
      'id': 'batch',
      'ingredientId': 'ingredient',
      'receivedDate': '2026-11-01',
      'expiryDate': '2026-11-10',
      'remainingQuantityGrams': 1000,
      'unitCostSnapshot': 4.5,
      'status': 'ACTIVE',
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> recipe(String categoryId) async => [
    {'ingredientId': 'ingredient', 'gramsPerUnit': 100},
  ];
  @override
  Future<void> saveCategory(Map<String, dynamic> data, {String? id}) async {}
  @override
  Future<void> saveIngredient(Map<String, dynamic> data, {String? id}) async {}
  @override
  Future<void> replaceRecipe(
    String categoryId,
    List<Map<String, dynamic>> items,
  ) async {}
  @override
  Future<void> receiveBatch(Map<String, dynamic> data) async {}
  @override
  Future<void> removeBatchStock(
    String batchId,
    Map<String, dynamic> data,
  ) async {}
}

class FakeRestockGateway implements RestockGateway {
  @override
  Future<RestockPreview> preview(String date) async => const RestockPreview(
    targetDate: '2026-11-13',
    desiredQuantities: [],
    shortages: [],
  );
  @override
  Future<Map<String, dynamic>> submit(RestockPreview preview) async => {};
  @override
  Future<List<Map<String, dynamic>>> list({
    required bool administrator,
  }) async => [
    {
      'id': 'request',
      'productionDate': '2026-11-13',
      'requesterUserId': 'manager',
      'status': 'PENDING',
      'cancellationReason': null,
      'items': [
        {
          'id': 'item',
          'ingredientId': 'ingredient',
          'ingredientName': 'Flour',
          'requestedGrams': 500,
          'receivedGrams': 0,
          'cancelledGrams': 0,
          'outstandingGrams': 500,
        },
      ],
    },
  ];
  @override
  Future<void> cancel(String requestId, String reason) async {}
}

void main() {
  testWidgets(
    'T-INV-UI-01 [FR-INV-01, FR-INV-02]: admin catalogue and stock panels render',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryAdminScreen(gateway: FakeInventoryAdminGateway()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Wholemeal Bread'), findsOneWidget);
      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();
      expect(find.text('Flour'), findsOneWidget);
      expect(find.byTooltip('Add ingredient'), findsOneWidget);
      await tester.tap(find.text('Batches'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-11-10'), findsOneWidget);
      expect(find.byTooltip('Receive batch'), findsNothing);
      expect(find.byTooltip('Remove batch stock'), findsNothing);
    },
  );

  testWidgets('T-INV-UI-02 [FR-INV-02]: batch receipt cost remains editable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryAdminScreen(
          gateway: FakeInventoryAdminGateway(),
          role: UserRole.bakeryManager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batches'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove batch stock'), findsOneWidget);
    await tester.tap(find.byTooltip('Receive batch'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Batch cost (MYR/kg)'),
      '4.50',
    );
    await tester.pumpAndSettle();
    expect(find.text('4.50'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('T-RST-UI-01 [EXT-RST-04]: linked batch cost remains editable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: RestockAdminScreen(
          role: UserRole.bakeryManager,
          restockGateway: FakeRestockGateway(),
          inventoryGateway: FakeInventoryAdminGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive Batch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Batch cost (MYR/kg)'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Batch cost (MYR/kg)'),
      '4.50',
    );
    await tester.pumpAndSettle();
    expect(find.text('4.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
