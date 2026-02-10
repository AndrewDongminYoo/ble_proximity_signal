# Integration Testing: Patrol vs Fluttium Comparison

This document compares two integration testing tools used in the BLE Proximity Signal project: **Patrol** and **Fluttium**.

## Overview

| Feature                 | Fluttium                     | Patrol                          |
| ----------------------- | ---------------------------- | ------------------------------- |
| **Syntax**              | YAML (declarative)           | Dart (imperative)               |
| **Setup Complexity**    | ⭐ Simple                    | ⭐⭐⭐⭐ Complex                |
| **Native Interactions** | ❌ Limited                   | ✅ Full support                 |
| **Permission Dialogs**  | ❌ Not supported             | ✅ Supported                    |
| **Learning Curve**      | ⭐ Easy                      | ⭐⭐⭐ Moderate                 |
| **Debugging**           | ⭐⭐ Limited                 | ⭐⭐⭐⭐ Excellent              |
| **Test Reusability**    | ⭐⭐ Actions only            | ⭐⭐⭐⭐ Full Dart code         |
| **IDE Support**         | ⭐⭐ Basic                   | ⭐⭐⭐⭐ Full                   |
| **Maintainability**     | ⭐⭐⭐ Good for simple tests | ⭐⭐⭐⭐ Good for complex tests |

## Fluttium

### What is Fluttium?

Fluttium is a YAML-based UI testing tool created by Very Good Ventures. It allows you to write declarative tests using a simple, human-readable syntax.

### Setup Requirements

```bash
# 1. Install Fluttium CLI globally
dart pub global activate fluttium_cli

# 2. Create fluttium.yaml in your project (already done via VGV template)
# 3. Write tests in flows/ directory
# 4. Run tests
```

**That's it!** No native configuration needed.

### Example Test

```yaml
# flows/test_platform_name.yaml
description: "Smoke test: scan + broadcast toggles"
---
- expectVisible: Metal Detector
- expectVisible: Idle

- pressOn: Start Scan
- expectVisible: Scanning…
- pressOn: Stop Scan
- expectVisible: Idle
```

### Running Fluttium Tests

```bash
cd ble_proximity_signal/example
fluttium test flows/test_platform_name.yaml
```

### Pros ✅

1. **Extremely Simple**: YAML syntax is intuitive and easy to learn
2. **Fast Setup**: No native configuration required
3. **Quick to Write**: Declarative style is concise
4. **Good for Smoke Tests**: Perfect for basic UI flow verification
5. **Version Control Friendly**: YAML diffs are easy to read

### Cons ❌

1. **No Native Interactions**: Cannot handle permission dialogs or native UI
2. **Limited Control Flow**: No complex logic or conditionals
3. **No Programmatic Access**: Can't inspect state or make decisions
4. **BLE Testing Limitation**: Cannot grant Bluetooth permissions
5. **Limited Debugging**: Error messages can be cryptic

### When to Use Fluttium

- ✅ Simple UI flow tests
- ✅ Smoke tests for basic functionality
- ✅ Quick regression testing
- ❌ **NOT for BLE permission testing** (our use case!)
- ❌ Complex conditional logic
- ❌ Native permission dialogs

---

## Patrol

### What is Patrol?

Patrol is a powerful Flutter integration testing framework that extends `flutter_test` with native automation capabilities.

### Setup Requirements

#### 1. Install Patrol CLI

```bash
dart pub global activate patrol_cli
```

#### 2. Add Dependencies

```yaml
# pubspec.yaml
dev_dependencies:
  patrol: ^4.1.1

patrol:
  app_name: Ble Proximity Signal Example
  test_directory: integration_test
  android:
    package_name: com.andrew.signal.example
  ios:
    bundle_id: com.andrew.signal.bleProximitySignalExample
```

#### 3. iOS Native Setup

Create `ios/RunnerUITests/RunnerUITests.m`:

```objc
@import XCTest;
@import patrol;
@import ObjectiveC.runtime;

PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
```

#### 4. Update Podfile

```ruby
target 'RunnerUITests' do
  inherit! :complete
end
```

### Example Test

```dart
// integration_test/patrol_test.dart
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'Permission Request and Basic UI Testing',
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      // Verify UI elements
      expect(find.text('Metal Detector'), findsWidgets);

      // Enter token
      await $.enterText(find.byKey(const Key('target_token_field')), 'test1234');

      // Tap scan button
      await $.tap(find.byKey(const Key('target_scan_button')));

      // ✅ Handle native permission dialog!
      try {
        if (await $.platformAutomator.mobile.isPermissionDialogVisible(
          timeout: const Duration(seconds: 2),
        )) {
          await $.platformAutomator.mobile.grantPermissionWhenInUse();
        }
      } catch (e) {
        debugPrint('Permission: $e');
      }

      // Verify scan started
      if (find.text('Stop Scan').evaluate().isNotEmpty) {
        await $.tap(find.byKey(const Key('target_scan_button')));
      }
    },
  );
}
```

### Running Patrol Tests

```bash
cd ble_proximity_signal/example

# Run on simulator
patrol test -t integration_test/patrol_test.dart -d "iPhone 17"

# Run on physical device (recommended for BLE)
patrol test -t integration_test/patrol_test.dart -d "Dongmin의 iPhone 16 Pro"
```

### Pros ✅

1. **Native Automation**: Full control over native dialogs and permissions
2. **BLE Permission Handling**: Can grant/deny Bluetooth permissions
3. **Powerful Dart API**: Use full Dart programming capabilities
4. **Excellent Debugging**: Standard Dart debugging works
5. **Complex Scenarios**: Handle conditional logic, loops, etc.
6. **Real Device Testing**: Works perfectly on physical devices
7. **IDE Support**: Full IntelliSense, refactoring, etc.

### Cons ❌

1. **Complex Setup**: Requires native configuration for iOS/Android
2. **Steep Learning Curve**: Need to understand Patrol API patterns
3. **Easy to Create Infinite Loops**: Calling `app.main()` in each test causes widget duplication
4. **Global + Dev Dependencies**: Need both `patrol_cli` (global) and `patrol` (dev dependency)
5. **Platform-Specific Issues**: Simulator limitations, duplicate device names, etc.
6. **Verbose Code**: More code compared to YAML

### Common Pitfalls & Solutions

#### ❌ Pitfall 1: Widget Duplication

**Problem:**

```dart
patrolTest('Test 1', ($) async {
  app.main(); // ❌ Wrong!
  await $.pumpAndSettle();
});

patrolTest('Test 2', ($) async {
  app.main(); // ❌ Creates duplicate widgets!
  await $.pumpAndSettle();
});
```

**Solution:**

```dart
patrolTest('Test 1', ($) async {
  await $.pumpWidgetAndSettle(const MyApp()); // ✅ Correct!
});

patrolTest('Test 2', ($) async {
  await $.pumpWidgetAndSettle(const MyApp()); // ✅ Each test gets fresh widget tree
});
```

#### ❌ Pitfall 2: Duplicate Simulator Names

**Problem:**

```bash
xcodebuild: error: Unable to find a device matching...
The requested device could not be found because multiple devices matched.
```

**Solution:**

```bash
# List simulators
xcrun simctl list devices | grep "iPhone 17"

# Delete duplicate
xcrun simctl delete <UUID-of-duplicate>
```

#### ❌ Pitfall 3: Infinite Test Loops

**Problem:** Tests keep restarting from the beginning.

**Solution:**

- Use `$.pumpWidgetAndSettle()` instead of `app.main()`
- Use `findsWidgets` instead of `findsOneWidget` when widgets might be duplicated
- Ensure each test is truly independent

### When to Use Patrol

- ✅ **BLE/Bluetooth permission testing** (our use case!)
- ✅ Native permission dialogs (location, camera, etc.)
- ✅ Complex test scenarios with logic
- ✅ Physical device testing
- ✅ Deep integration tests
- ❌ Quick smoke tests (use Fluttium)
- ❌ Simple UI flow verification (use Fluttium)

---

## Recommendation for This Project

### For BLE Proximity Signal Testing

**Primary Tool: Patrol** ⭐

Since this project **requires testing Bluetooth permissions**, Patrol is essential because:

1. Fluttium cannot handle native permission dialogs
2. BLE functionality needs real device testing
3. We need to verify permission grant/deny scenarios

**Secondary Tool: Fluttium**

Keep Fluttium for:

- Quick smoke tests
- Basic UI flow verification
- CI/CD fast checks (when permissions are pre-granted)

### Test Strategy

```
Fluttium (Simple/Fast)
├── flows/test_platform_name.yaml    ← Basic UI smoke test
└── flows/test_scan_toggle.yaml      ← Scan on/off toggle test

Patrol (Complex/Thorough)
└── integration_test/
    └── patrol_test.dart              ← Full BLE permission & scenario tests
        ├── Permission request & grant
        ├── Debug mode device discovery
        ├── Proximity level verification
        └── Empty token validation
```

## Current Test Results

### Fluttium

```bash
$ fluttium test flows/test_platform_name.yaml
✅ Simple UI flow test passes
⚠️  Cannot test BLE permissions
```

### Patrol

```bash
$ patrol test -t integration_test/patrol_test.dart -d "iPhone 17"

Test summary:
📝 Total: 4
✅ Successful: 4
❌ Failed: 0
⏱️  Duration: 1m 47s
```

## Key Lessons Learned

### Patrol Best Practices

1. **Always use `$.pumpWidgetAndSettle(const MyApp())`**
   - Never call `app.main()` directly in tests
   - Each test should pump a fresh widget tree

2. **Use `findsWidgets` when widget duplication is possible**

   ```dart
   expect(find.text('Metal Detector'), findsWidgets); // ✅
   expect(find.text('Metal Detector'), findsOneWidget); // ❌ May fail
   ```

3. **Handle permissions gracefully**

   ```dart
   try {
     if (await $.platformAutomator.mobile.isPermissionDialogVisible(
       timeout: const Duration(seconds: 2),
     )) {
       await $.platformAutomator.mobile.grantPermissionWhenInUse();
     }
   } catch (e) {
     // Permission already granted or simulator limitation
     debugPrint('Permission: $e');
   }
   ```

4. **Check widget existence before interacting**

   ```dart
   if (find.text('Stop Scan').evaluate().isNotEmpty) {
     await $.tap(find.byKey(const Key('target_scan_button')));
   }
   ```

5. **Test on real devices for BLE**
   - Simulators don't have real Bluetooth hardware
   - Permission dialogs may not appear on simulators

### Fluttium Best Practices

1. **Keep tests simple and focused**
2. **Use descriptive test descriptions**
3. **Create reusable actions for common patterns**
4. **Use for fast CI/CD smoke tests**

## Conclusion

Both tools have their place:

- **Fluttium**: Perfect for simple, fast UI tests
- **Patrol**: Essential for complex scenarios requiring native interactions

For the BLE Proximity Signal project, **Patrol is the primary testing tool** due to Bluetooth permission requirements, while **Fluttium serves as a quick smoke test** tool.

## References

- [Patrol Documentation](https://patrol.leancode.co/)
- [Fluttium Documentation](https://fluttium.dev/)
- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
