import 'package:flutter_test/flutter_test.dart';
import 'package:adapt_app/main.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UniAccessApp());
    expect(find.byType(UniAccessApp), findsOneWidget);
  });
}
