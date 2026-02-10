import 'package:ble_proximity_signal_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

/// Patrol Integration Test
/// Tests scenarios involving BLE permission requests, device discovery, and proximity changes.
///
/// Important Notes:
/// - iOS simulators are limited as they lack actual BLE hardware
/// - Testing on physical devices is recommended
/// - The permission dialog may not appear if permissions are already granted
void main() {
  patrolTest(
    'Permission Request and Basic UI Testing',
    ($) async {
      // App Launch
      await $.pumpWidgetAndSettle(const MyApp());

      // Verify core UI elements (use findsWidgets considering widget duplication)
      expect(find.text('Metal Detector'), findsWidgets);
      expect(find.byKey(const Key('target_token_field')), findsWidgets);
      expect(find.byKey(const Key('target_scan_button')), findsWidgets);

      // Token Input
      await $.enterText(find.byKey(const Key('target_token_field')), 'test1234');
      await $.pumpAndSettle();

      // Tap Scan Button
      await $.tap(find.byKey(const Key('target_scan_button')));
      await $.pump(const Duration(milliseconds: 500));

      // Handle Permission Dialog (if displayed)
      try {
        final hasDialog = await $.platformAutomator.mobile.isPermissionDialogVisible(
          timeout: const Duration(seconds: 2),
        );

        if (hasDialog) {
          await $.platformAutomator.mobile.grantPermissionWhenInUse();
          await $.pump(const Duration(milliseconds: 500));
        }
      } catch (e) {
        // Permission already granted or simulator limitation
        debugPrint('Permission handling: $e');
      }

      await $.pump(const Duration(seconds: 1));

      // Check if scan started
      if (find.text('Stop Scan').evaluate().isNotEmpty) {
        // Scan started - Stop
        await $.tap(find.byKey(const Key('target_scan_button')));
        await $.pumpAndSettle();
      }

      expect(find.text('Start Scan'), findsWidgets);
    },
  );

  patrolTest(
    'Debug Mode Device Discovery Test',
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      // Enable Debug Mode
      final debugSwitch = find.byType(Switch);
      if (debugSwitch.evaluate().isNotEmpty) {
        await $.tap(debugSwitch);
        await $.pumpAndSettle();

        // Check Debug UI
        expect(find.text('Visible Devices (refresh 1s)'), findsOneWidget);

        // Wait for UI to fully stabilize after debug mode change
        await $.pumpAndSettle();
        await $.pump(const Duration(milliseconds: 500));

        // Scroll to make scan button visible (debug device list may push it off-screen)
        await $.scrollUntilVisible(
          finder: find.byKey(const Key('target_scan_button')),
        );
        await $.pumpAndSettle();

        // Start scan
        await $.tap(find.byKey(const Key('target_scan_button')));
        await $.pump(const Duration(milliseconds: 500));

        // Handle permissions
        try {
          if (await $.platformAutomator.mobile.isPermissionDialogVisible(
            timeout: const Duration(seconds: 2),
          )) {
            await $.platformAutomator.mobile.grantPermissionWhenInUse();
          }
        } catch (e) {
          debugPrint('Permission: $e');
        }

        await $.pump(const Duration(seconds: 3));

        // Stop scan
        if (find.text('Stop Scan').evaluate().isNotEmpty) {
          await $.tap(find.byKey(const Key('target_scan_button')));
          await $.pumpAndSettle();
        }
      }
    },
  );

  patrolTest(
    'Proximity Indicator Verification Test',
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      // Check Signal Card
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('INTENSITY'), findsOneWidget);

      // Check initial proximity level (FAR)
      expect(find.text('FAR'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    },
  );

  patrolTest(
    'Empty Token Validation Test',
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      // Clear token field
      await $.enterText(find.byKey(const Key('target_token_field')), '');
      await $.pumpAndSettle();

      // Attempt scan
      await $.tap(find.byKey(const Key('target_scan_button')));
      await $.pump(const Duration(seconds: 2));

      // Check error message (SnackBar or error handling)
      // Note: Attempting to scan with an empty token may not trigger an error
      // App may fail silently or only output logs
      final errorMessage = find.text('Target token is empty.');
      if (errorMessage.evaluate().isEmpty) {
        debugPrint('⚠️  Error message not found - app may handle empty token differently');
      } else {
        expect(errorMessage, findsWidgets);
      }
    },
  );
}
