import 'package:flutter_test/flutter_test.dart';
import 'package:fyp/features/home/presentation/home_screen.dart';

void main() {
  test('Bakery date renders the backend calendar day without device timezone conversion', () {
    expect(formatBakeryDate('2026-11-13'), 'Friday, 13 November 2026');
    expect(() => formatBakeryDate('2026-11-31'), throwsFormatException);
  });
}
