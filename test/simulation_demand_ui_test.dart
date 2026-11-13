import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/core/theme/bakery_theme.dart';
import 'package:fyp/features/administration/data/simulation_configuration_service.dart';
import 'package:fyp/features/administration/presentation/simulation_configuration_screen.dart';
import 'package:fyp/features/inventory/data/recommendation_service.dart';
import 'package:fyp/features/pos_simulation/data/pos_simulation_service.dart';
import 'package:fyp/features/pos_simulation/domain/simulation_result.dart';
import 'package:fyp/features/pos_simulation/presentation/pos_simulation_screen.dart';
import 'package:fyp/features/profile/domain/user_profile.dart';

class _ConfigGateway implements SimulationConfigurationGateway {
  int importedSaves = 0;
  @override
  Future<Map<String, dynamic>> load() async => {
    'categories': [
      {'id': 'bread-a', 'name': 'Wholemeal Bread', 'baseline': null},
    ],
    'scenario': {
      'scenarioVersion': 1,
      'weekdayFactors': {
        for (final day in [
          'MONDAY',
          'TUESDAY',
          'WEDNESDAY',
          'THURSDAY',
          'FRIDAY',
          'SATURDAY',
          'SUNDAY',
        ])
          day: 1,
      },
      'weatherFactors': {
        for (final condition in [
          'NEUTRAL',
          'CLEAR',
          'CLOUDY',
          'RAIN',
          'STORM',
          'OTHER',
        ])
          condition: 1,
      },
      'holidayFactor': 1,
      'nonHolidayFactor': 1,
      'variationMaxPct': 10,
    },
  };
  @override
  Future<void> saveImported(String categoryId) async {
    expect(categoryId, 'bread-a');
    importedSaves++;
  }

  @override
  Future<void> saveManual(String categoryId, double value) async {}
  @override
  Future<void> saveScenario(Map<String, dynamic> value) async {}
}

class _PosGateway implements PosSimulationGateway {
  _PosGateway({this.categoryName = 'Wholemeal Bread'});
  final String categoryName;
  @override
  Future<String> getBakeryToday() async => '2026-11-12';
  @override
  Future<SimulationResult> getResult(String date) async =>
      SimulationResult.fromJson({
        'date': date,
        'items': [
          {
            'breadCategoryName': categoryName,
            'predictedUnitsSold': 20,
            'simulatedDemand': 30,
            'simulationMethod': 'INDEPENDENT_CURRENT_WEATHER_V3',
            'simulationSnapshot': {
              'baseline': {'value': 30, 'source': 'MANUAL'},
              'scenarioVersion': 1,
              'weatherCondition': 'RAIN',
              'currentWeather': {
                'provider': 'OPENWEATHER_CURRENT',
                'condition': 'RAIN',
                'providerTimestamp': '2026-11-12T03:55:00.000Z',
                'fetchedAt': '2026-11-12T04:00:00.000Z',
                'location': {'latitude': 3.203, 'longitude': 101.723},
                'requestedLocation': {'latitude': 3.203, 'longitude': 101.723},
              },
              'holiday': false,
              'weekdayFactor': 1,
              'holidayFactor': 1,
              'weatherFactor': 1,
              'variationPct': 0,
            },
            'predictionMode': 'COLD_START',
            'confidence': null,
            'modelVersionId': null,
            'produced': 25,
            'unitsSold': 25,
            'lostSales': 5,
            'leftover': 0,
            'remainingUnallocatedLeftover': 0,
            'salesPredictionError': 5,
            'revenue': 50,
            'ingredientCost': 10,
            'grossProfit': 40,
            'dataOrigin': 'SIMULATION_GENERATED',
          },
        ],
      });
  @override
  Future<SimulationResult> run(String date) => throw UnimplementedError();
}

class _UnusedPlanningGateway implements RecommendationGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('T-POS-UI-01 [FR-POS-02]: admin sees saved-baseline setup form', (
    tester,
  ) async {
    final gateway = _ConfigGateway();
    await tester.pumpWidget(
      MaterialApp(home: SimulationConfigurationScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No baseline configured'), findsOneWidget);
    expect(find.text('Use imported average'), findsOneWidget);
    await tester.tap(find.text('Use imported average'));
    await tester.pumpAndSettle();
    expect(gateway.importedSaves, 1);
  });

  testWidgets(
    'T-POS-UI-02 [FR-POS-02]: completed card distinguishes three quantities',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BakeryTheme.light,
          home: PosSimulationScreen(
            role: UserRole.bakeryManager,
            gateway: _PosGateway(),
            planningGateway: _UnusedPlanningGateway(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Predicted sales'), findsOneWidget);
      expect(find.text('Simulated customer demand'), findsOneWidget);
      expect(find.text('Production quantity'), findsOneWidget);
      expect(find.text('Units sold'), findsOneWidget);
      expect(find.text('Lost sales'), findsOneWidget);
      expect(find.text('Leftover'), findsOneWidget);
      expect(
        find.text('Independent baseline with current weather v3'),
        findsOneWidget,
      );
      final details = find.text('Weather, holiday and scenario details');
      await tester.scrollUntilVisible(
        details,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('Current weather at simulation time'), findsOneWidget);
      expect(find.text('2026-11-12 11:55'), findsOneWidget);
    },
  );

  testWidgets('T-POS-UI-03 [NFR-USA-03]: narrow screen and large text wrap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: BakeryTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: PosSimulationScreen(
          role: UserRole.bakeryManager,
          gateway: _PosGateway(
            categoryName:
                'Extra Long Wholemeal Bread With Coconut Filling And Topping',
          ),
          planningGateway: _UnusedPlanningGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final details = find.text('Weather, holiday and scenario details');
    await tester.scrollUntilVisible(
      details,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Extra Long Wholemeal'), findsOneWidget);
  });
}
