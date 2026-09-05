# Automatic QuickShot updates

QuickShot 1.4 embeds Sparkle 2.9.6. Every installed 1.4+ copy checks the public HTTPS appcast hourly. Updates and the feed are Ed25519 signed. Downloads are verified before extraction. The app installs a downloaded update and relaunches when no capture, annotation editor, modal dialog, or camera menu is active. Saved snapshots are outside the app bundle and remain in Application Support.

**Automatic Updates** controls automatic checks and downloads; an already downloaded update can still install on a normal quit; **Check for Updates…** remains available. Offline Macs retry on a later scheduled check. Sleeping/offline Macs cannot receive a merge instantly. Version 1.3 and older require the one-time 1.4 bootstrap install because they have no updater.

## What merging a PR does

The `QuickShot` GitHub Actions workflow validates pull requests and pushes to `main`. A successful main build creates a universal arm64/x86_64 app and publishes a GitHub Release with the archive and signed `appcast.xml`. No manual version bump or tag is required. The Git ancestry count gives each main commit a deterministic increasing version (currently `1.4.<count>`, build `1000 + count`), including merges and squash merges. Published reruns are skipped; superseded main commits cannot replace the current feed. A failed build/sign/upload leaves the last working release intact. Assets are uploaded to a draft before it becomes the latest public release.

Feed: https://github.com/Wirenut33/quick-shot/releases/latest/download/appcast.xml

The workflow runs on GitHub-hosted macOS runners. Pull requests do not receive signing secrets; only the post-validation main release job does. Treat changes to the workflow/release scripts like changes to the installed application: main-branch write/merge access can publish code to every enrolled Mac.

## One-time signing setup

GitHub needs these repository Actions secrets before the first release:

- `APPLE_CERTIFICATE_P12_BASE64`: a password-protected `.p12` export of **Apple Development: MICHAEL ANTHONY MORALE (5K58FPSA8S)** including its private key. Export only this identity from Keychain Access, not the whole keychain.
- `APPLE_CERTIFICATE_PASSWORD`: the export password.
- `SPARKLE_PRIVATE_KEY`: the dedicated `quickshot-updates` Sparkle key from the MacBook login Keychain. Its public key is already embedded in `Info.plist`.

After authorizing GitHub to hold these signing credentials, run `bash scripts/configure_ci_signing.sh /absolute/path/to/QuickShot-signing.p12`. The script reads the P12 password privately, sends the three values directly to encrypted repository Actions secrets, and deletes its temporary Sparkle-key export. It does not print keys or add them to Git. Keep the original Keychain keys backed up securely.

CI imports the certificate into a temporary keychain and removes it at job completion. Never put private keys in source, artifacts, releases, or logs. The public key in `Info.plist` and `scripts/verify_release.py` must agree. Do not regenerate it for routine releases.

## Preserve Screen Recording approval

The initial fleet uses the existing Apple Development identity, bundle ID `com.quickshot.QuickShot`, and the same designated requirement. Release verification rejects a different identity. This preserves the requirement to which each Mac granted Screen Recording permission; toggling permission on an old ad-hoc record does not migrate that record.

This pipeline is signed for the existing fleet but **not Developer ID notarized**. A first install on a new Mac can need Gatekeeper approval as well as Screen Recording permission. Before broad public distribution, arrange a Developer ID certificate and notarization, and plan the signing-identity transition explicitly. Do not replace the certificate or weaken signature validation to get a failed release through. Apple Development certificates expire and need planned renewal; a signing failure prevents publication while existing apps continue to run.

## Validation and recovery

- `bash scripts/validate.sh` runs collection tests, release-contract tests, and builds both architectures. Tests require macOS pasteboard access.
- `bash scripts/test_updater.sh` exercises a real signed download, busy deferral, installation and relaunch using a disposable test app and a loopback feed. Run locally with the signing keys and a fresh `.build/UpdaterIntegration` directory after a signed release build. It never modifies `/Applications`.
- `scripts/release.sh` builds with the real identity, generates a signed feed, and verifies the app, feed signature, version, archive length, and immutable download URL.
- To test locally: set `RELEASE_VERSION`, `RELEASE_BUILD`, and `RELEASE_TAG`, then run `bash scripts/release.sh`. Keys stay in the local Keychain unless CI environment secrets are supplied.
- Keep `QuickShot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` committed. The package version is exact, and builds disallow automatic dependency resolution.
- If an update fails, leave the current release intact, fix the failure, and rerun the workflow from current main. Never overwrite a published version.
- To roll back app behavior, revert the offending PR and merge the revert. This creates a newer version containing the prior behavior; Sparkle will not automatically downgrade to an older version.
- Check the installed version, signature, actual capture, and another capture after relaunch on both Macs before declaring a rollout verified.

## Activation checklist

1. Publish this branch as a PR and review it, including the earlier snapshot-collection changes that have not yet reached GitHub main.
2. Configure the three signing secrets.
3. Install the bootstrap on each current Mac once.
4. Merge the PR; verify the workflow, public release and signed feed.
5. Verify a real automatic download/relaunch and capture after the update on both Macs.
