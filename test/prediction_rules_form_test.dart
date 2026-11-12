import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/administration/data/administration_service.dart';
import 'package:fyp/features/administration/presentation/prediction_rules_form.dart';
import 'package:fyp/features/administration/presentation/settings_screen.dart';

const categoryId = '12345678-1234-4123-8123-123456789abc';

Map<String, dynamic> savedRules() => {
  'baseQuantities': {categoryId: 12},
  'weekdayFactors': {
    'MONDAY': 1,
    'TUESDAY': 1,
    'WEDNESDAY': 1,
    'THURSDAY': 1,
    'FRIDAY': 1,
    'SATURDAY': 1,
    'SUNDAY': 1,
  },
  'monsoonMonths': <int>[],
  'monsoonFactor': 1,
  'otherSeasonFactor': 1,
  'weatherFactors': {
    'CLEAR': 1,
    'CLOUDY': 1,
    'RAIN': 1,
    'STORM': 1,
    'OTHER': 1,
  },
  'weatherFallbackFactor': 0.8,
  'holidayFactor': 1,
  'nonHolidayFactor': 1,
  'calendarVerifiedThrough': '2026-10-31',
  'allowCalendarFallback': false,
};

Future<void> showForm(
  WidgetTester tester,
  Future<void> Function(Map<String, dynamic>) onSave,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PredictionRulesForm(
            rules: savedRules(),
            activeCategories: const [
              {'id': categoryId, 'name': 'Wholemeal Bread'},
            ],
            busy: false,
            onSave: onSave,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeAdministrationGateway implements AdministrationGateway {
  Map<String, dynamic> rules = savedRules();
  final savedKeys = <String>[];

  @override
  Future<Map<String, dynamic>> settings() async => {
    'bakery': {
      'name': 'Smart Bakery',
      'locationType': 'Residential',
      'opensAt': '06:00',
      'closesAt': '18:00',
      'timezone': 'Asia/Kuala_Lumpur',
    },
    'systemSettings': [
      {
        'key': 'prediction.context_rules',
        'value': jsonDecode(jsonEncode(rules)),
      },
      {'key': 'prediction.low_confidence_threshold', 'value': 75},
    ],
  };
  @override
  Future<Map<String, dynamic>> serviceStatus() async => {};
  @override
  Future<List<Map<String, dynamic>>> activeCategories() async => [
    {'id': categoryId, 'name': 'Wholemeal Bread', 'isActive': true},
  ];
  @override
  Future<Map<String, dynamic>> saveBakery(Map<String, dynamic> values) async =>
      values;
  @override
  Future<Map<String, dynamic>> saveSetting(String key, Object value) async {
    savedKeys.add(key);
    if (key == 'prediction.context_rules') {
      rules = value as Map<String, dynamic>;
    }
    return {'key': key, 'value': value};
  }

  @override
  Future<Map<String, dynamic>> audit(Map<String, String> filters) async => {};
}

void main() {
  testWidgets('demo preset requires Save and preserves unrelated rules', (
    tester,
  ) async {
    final saved = <Map<String, dynamic>>[];
    await showForm(tester, (value) async => saved.add(value));
    await tester.scrollUntilVisible(
      find.text('Use demo defaults'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Use demo defaults'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(
      find.text('Demo defaults filled. Select Save to apply them.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save prediction adjustments'));
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    final rules = saved.single;
    expect((rules['weekdayFactors'] as Map)['SATURDAY'], 1.1);
    expect((rules['weekdayFactors'] as Map)['SUNDAY'], 1.1);
    expect((rules['weekdayFactors'] as Map)['FRIDAY'], 1);
    expect((rules['weatherFactors'] as Map)['RAIN'], 0.95);
    expect((rules['weatherFactors'] as Map)['STORM'], 0.9);
    expect(rules['holidayFactor'], 1.05);
    expect(rules['nonHolidayFactor'], 1);
    expect(rules['monsoonMonths'], isEmpty);
    expect(rules['monsoonFactor'], 1);
    expect(rules['otherSeasonFactor'], 1);
    expect((rules['baseQuantities'] as Map)[categoryId], 12);
    expect(rules['weatherFallbackFactor'], 0.8);
    expect(rules['calendarVerifiedThrough'], '2026-10-31');
    expect(rules['allowCalendarFallback'], false);
  });

  testWidgets('Reset restores last saved factors before Save', (tester) async {
    final saved = <Map<String, dynamic>>[];
    await showForm(tester, (value) async => saved.add(value));
    await tester.ensureVisible(find.text('Use demo defaults'));
    await tester.tap(find.text('Use demo defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset form'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect((saved.single['weekdayFactors'] as Map)['SATURDAY'], 1);
    expect((saved.single['weatherFactors'] as Map)['RAIN'], 1);
  });

  testWidgets('invalid percentage shows field error and blocks Save', (
    tester,
  ) async {
    final saved = <Map<String, dynamic>>[];
    await showForm(tester, (value) async => saved.add(value));
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'RAIN'));
    await tester.enterText(find.widgetWithText(TextFormField, 'RAIN'), '-101');
    await tester.ensureVisible(find.text('Save prediction adjustments'));
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect(find.text('Adjustment must be at least -100%.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('monsoon needs a month and saves its selected adjustment', (
    tester,
  ) async {
    final saved = <Map<String, dynamic>>[];
    await showForm(tester, (value) async => saved.add(value));
    await tester.ensureVisible(find.text('Enable monsoon months'));
    await tester.tap(find.text('Enable monsoon months'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save prediction adjustments'));
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect(find.text('Select at least one monsoon month.'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.ensureVisible(find.text('Nov'));
    await tester.tap(find.text('Nov'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monsoon months'),
      '20',
    );
    await tester.ensureVisible(find.text('Save prediction adjustments'));
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect(saved.single['monsoonMonths'], [11]);
    expect(saved.single['monsoonFactor'], 1.2);
    expect(saved.single['otherSeasonFactor'], 1);
  });

  testWidgets('category bases and fallback options remain editable', (
    tester,
  ) async {
    final saved = <Map<String, dynamic>>[];
    await showForm(tester, (value) async => saved.add(value));
    await tester.ensureVisible(find.text('Category cold-start bases'));
    await tester.tap(find.text('Category cold-start bases'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Wholemeal Bread base units'),
      '20',
    );
    await tester.ensureVisible(find.text('Missing-context options'));
    await tester.tap(find.text('Missing-context options'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Missing-weather adjustment'),
      '-10',
    );
    await tester.ensureVisible(find.text('Allow unverified calendar fallback'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow unverified calendar fallback'));
    await tester.ensureVisible(find.text('Save prediction adjustments'));
    await tester.tap(find.text('Save prediction adjustments'));
    await tester.pumpAndSettle();
    expect((saved.single['baseQuantities'] as Map)[categoryId], 20);
    expect(saved.single['weatherFallbackFactor'], 0.9);
    expect(saved.single['allowCalendarFallback'], true);
    expect(saved.single['calendarVerifiedThrough'], '2026-10-31');
  });

  testWidgets(
    'Settings loads rules and saves the demo preset through the gateway',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeAdministrationGateway();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prediction rules (JSON)'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Use demo defaults'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use demo defaults'));
      await tester.pumpAndSettle();
      expect(gateway.savedKeys, isEmpty);
      await tester.ensureVisible(find.text('Save prediction adjustments'));
      await tester.tap(find.text('Save prediction adjustments'));
      await tester.pumpAndSettle();
      expect(gateway.savedKeys, ['prediction.context_rules']);
      expect((gateway.rules['weatherFactors'] as Map)['RAIN'], 0.95);
      expect((gateway.rules['baseQuantities'] as Map)[categoryId], 12);
    },
  );
}
