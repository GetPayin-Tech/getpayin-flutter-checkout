import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout_example/main.dart';
import 'package:getpayin_checkout_example/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('asks for the saved cards as it starts, not only after a payment',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ExampleApp(store: await DemoStore.open()));

    // No test server answers here, so the list settles on what it last had: none. A page
    // that never asked stays on its loading rows and never gets this far.
    await tester.pump(const Duration(seconds: 11));

    expect(find.text('Vaulted cards'), findsOneWidget);
    expect(find.textContaining('None held'), findsOneWidget);
  });
}
