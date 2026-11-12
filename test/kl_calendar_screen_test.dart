import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/administration/data/calendar_service.dart';
import 'package:fyp/features/administration/presentation/calendar_screen.dart';

class FakeCalendarGateway implements CalendarGateway {
  int reads = 0;
  int refreshes = 0;
  @override
  Future<Map<String, dynamic>> year(int year) async {
    reads += 1;
    return _data(year);
  }

  @override
  Future<Map<String, dynamic>> refresh(int year) async {
    refreshes += 1;
    return _data(year);
  }

  Map<String, dynamic> _data(int year) => {
    'year': year,
    'stateCode': 'KUL',
    'coverage': {
      'lastSuccessfulAt': '2026-11-12T00:00:00Z',
      'refreshAfter': '2026-11-19T00:00:00Z',
    },
    'events': [
      {
        'eventDate': '$year-11-13',
        'eventName': 'KL Public Holiday',
        'sourceReference': 'https://example.org/source',
      },
    ],
  };
}

void main() {
  testWidgets('T-DP-KL-UI-01: calendar list is read-only and refreshable',
      (tester) async {
    final gateway = FakeCalendarGateway();
    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(gateway: gateway),
    ));
    await tester.pumpAndSettle();
    expect(gateway.reads, 1);
    expect(find.text('KL Public Holiday'), findsOneWidget);
    expect(find.textContaining('Last successful sync'), findsOneWidget);
    expect(find.text('Record event'), findsNothing);
    await tester.tap(find.text('Retry / Refresh'));
    await tester.pumpAndSettle();
    expect(gateway.refreshes, 1);
  });
}
