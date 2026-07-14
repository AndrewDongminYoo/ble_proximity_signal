# Releasing

Each package in this workspace publishes to pub.dev independently through the `publish` GitHub Actions workflow (`.github/workflows/publish.yml`).
The workflow authenticates with pub.dev via OIDC — no tokens or secrets are stored.
Pushing a per-package version tag triggers the matching publish job.

## One-time setup (per package)

Automated publishing must be enabled once per package on pub.dev:

1. Publish the package's first version manually with `dart pub publish`.
   OIDC automated publishing cannot bootstrap the very first version.
2. On pub.dev open the package's Admin › Automated publishing and enable GitHub Actions publishing with:
   - Repository: `AndrewDongminYoo/ble_proximity_signal`
   - Tag pattern: `<package_name>-v{{version}}`

## Cutting a release

Releases are per package.
To release, for example, `ble_proximity_signal` 0.2.2:

1. Bump `version:` in that package's `pubspec.yaml`.
2. Add a matching entry to that package's `CHANGELOG.md`.
3. Commit with a conventional message, e.g. `chore: 🔖 release ble_proximity_signal 0.2.2`.
4. Create and push the tag:

   ```sh
   git tag ble_proximity_signal-v0.2.2
   git push origin ble_proximity_signal-v0.2.2
   ```

5. The `publish` workflow runs the matching job and publishes to pub.dev.

The tag version must equal the package's `pubspec.yaml` version, or pub.dev rejects the publish.

## Tag conventions

| Package                                   | Tag pattern                                          |
| ----------------------------------------- | ---------------------------------------------------- |
| `ble_proximity_signal`                    | `ble_proximity_signal-v<version>`                    |
| `ble_proximity_signal_platform_interface` | `ble_proximity_signal_platform_interface-v<version>` |
| `ble_proximity_signal_android`            | `ble_proximity_signal_android-v<version>`            |
| `ble_proximity_signal_ios`                | `ble_proximity_signal_ios-v<version>`                |

Only tags matching `<package_name>-v<major>.<minor>.<patch>` trigger the workflow, and each tag runs only its own package's job.

## Notes

- Publish only the packages that actually changed.
  A version bump with no code or doc changes adds noise on pub.dev, so leave unchanged packages at their current version.
- `ble_proximity_signal` 0.2.1 was published manually while the automated workflow was being set up.
  From the next version on, use the tag flow above.
