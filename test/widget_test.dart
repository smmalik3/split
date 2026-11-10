import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:split/main.dart';

void main() {
  testWidgets('Split app loads the landing screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SplitApp());
    await tester.pumpAndSettle();
    expect(find.text('Split'), findsWidgets);
    expect(find.text('Create a group'), findsOneWidget);
    expect(find.text('Join a group'), findsOneWidget);
  });
}
