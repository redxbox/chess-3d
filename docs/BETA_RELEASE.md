# Beta release checklist

## Required one-time external setup

1. Create a private upload keystore locally; never add it to Git.
2. Add these GitHub Actions repository secrets:
   - `ANDROID_RELEASE_KEYSTORE_BASE64`: base64 of the complete keystore file.
   - `ANDROID_RELEASE_KEY_ALIAS`: upload-key alias.
   - `ANDROID_RELEASE_KEYSTORE_PASSWORD`: keystore/key password.
3. Run **Android Beta Release** from GitHub Actions.
4. Download and retain the signed AAB and SHA-256 checksum.
5. Create the Google Play app for package `com.redxbox.chess3d`, complete Data safety using `PRIVACY.md`, and upload the AAB to Internal testing.
6. Publish the privacy policy at a stable public HTTPS URL and enter it in Play Console.
7. Add tester accounts, install from Play on multiple physical devices, and record results below.

## Never do

- Do not commit a keystore, password, service-account JSON, or Play credential.
- Do not replace or lose the upload key without following Google Play key-reset procedures.
- Do not upload debug APKs to a production track.

## Physical-device matrix

| Device / Android | Install from Play | Landscape | Resume/audio | Save upgrade | 30-min battery/thermal | Result |
|---|---:|---:|---:|---:|---:|---|
| Pending | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | Pending |
| Pending | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | Pending |
| Pending | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | Pending |

## Beta feedback

Use GitHub Issues with device model, Android version, game version, steps to reproduce, expected result, actual result, and an optional screenshot. Never include private game files or device identifiers unless necessary and knowingly volunteered.
