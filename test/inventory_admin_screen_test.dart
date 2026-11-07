import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/inventory/data/inventory_admin_service.dart';
import 'package:fyp/features/inventory/presentation/inventory_admin_screen.dart';

class FakeInventoryAdminGateway implements InventoryAdminGateway {
  @override
  Future<List<Map<String, dynamic>>> categories() async => [
    {'id': 'category', 'name': 'Wholemeal Bread', 'displayOrder': 1,
      'isActive': true, 'sellingPrice': 5.5, 'description': null,
      'shelfLifeHours': 24},
  ];
  @override
  Future<List<Map<String, dynamic>>> ingredients() async => [
    {'id': 'ingredient', 'name': 'Flour', 'unit': 'KG',
      'referenceUnitCost': 4.5, 'reorderThresholdGrams': 500,
      'snapshotQuantityGrams': 1000, 'isActive': true},
  ];
  @override
  Future<List<Map<String, dynamic>>> batches(int page) async => [
    {'id': 'batch', 'ingredientId': 'ingredient',
      'receivedDate': '2026-11-01', 'expiryDate': '2026-11-10',
      'remainingQuantityGrams': 1000, 'unitCostSnapshot': 4.5,
      'status': 'ACTIVE'},
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
  Future<void> replaceRecipe(String categoryId, List<Map<String, dynamic>> items) async {}
  @override
  Future<void> receiveBatch(Map<String, dynamic> data) async {}
  @override
  Future<void> removeBatchStock(String batchId, Map<String, dynamic> data) async {}
}

void main() {
  testWidgets('T-INV-UI-01 [FR-INV-01, FR-INV-02]: admin catalogue and stock panels render',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: InventoryAdminScreen(
      gateway: FakeInventoryAdminGateway(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Wholemeal Bread'), findsOneWidget);
    await tester.tap(find.text('Ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Flour'), findsOneWidget);
    await tester.tap(find.text('Batches'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-11-10'), findsOneWidget);
  });
}
