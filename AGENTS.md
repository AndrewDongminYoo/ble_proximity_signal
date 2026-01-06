# Repository Guidelines

## Project Structure & Module Organization

- Root contains a federated Flutter plugin split into packages:
  - `ble_proximity_signal/` (public plugin API; example app in `ble_proximity_signal/example/`)
  - `ble_proximity_signal_platform_interface/` (shared platform interface and types)
  - `ble_proximity_signal_android/` (Android implementation; native code in `android/`)
  - `ble_proximity_signal_ios/` (iOS implementation; native code in `ios/`)
- Tests live in each package’s `test/` directory.

## Build, Test, and Development Commands

- `cd ble_proximity_signal && flutter pub get` — fetch dependencies for the main package (repeat per package as needed).
- `cd ble_proximity_signal && flutter test` — run unit tests for the plugin.
- `cd ble_proximity_signal/example && flutter run` — run the example app locally.
- `cd ble_proximity_signal/example && fluttium test flows/test_platform_name.yaml` — run integration tests (requires `fluttium_cli`).
- `trunk fmt` / `trunk check` — format/lint non-Dart files per `.trunk/trunk.yaml`.

## Coding Style & Naming Conventions

- Dart code follows `very_good_analysis` (`analysis_options.yaml`) and standard Dart formatting (`dart format .`).
- Indentation: 2 spaces for Dart/YAML.
- Prefer clear, package-scoped names (e.g., `BleProximitySignal*` in plugin code).

## Testing Guidelines

- Frameworks: `flutter_test` and `mocktail` (see `pubspec.yaml` in packages).
- Keep tests close to the package they validate (e.g., `ble_proximity_signal/test`).
- Name tests by behavior using `*_test.dart`.

## Commit & Pull Request Guidelines

- Commit messages follow Conventional Commits with gitmoji: `type: emoji subject` (e.g., `feat: ✨ add ...`, `docs: 📝 ...`, `chore: 🔨 ...`).
- PRs should include a concise description and check the relevant “Type of Change” boxes in `.github/PULL_REQUEST_TEMPLATE.md`. Link related issues when applicable.
