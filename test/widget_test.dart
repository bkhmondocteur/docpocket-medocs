import 'package:flutter_test/flutter_test.dart';
import 'package:docpocket_medocs/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DocPocketMedocsApp());
    expect(find.text('DocPocket Medocs'), findsOneWidget);
  });
}
