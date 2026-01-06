import 'package:ble_proximity_signal_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E', () {
    testWidgets('renders metal detector UI', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      expect(find.text('Metal Detector'), findsOneWidget);
      expect(find.text('Start Scan'), findsOneWidget);
    });
  });
}
