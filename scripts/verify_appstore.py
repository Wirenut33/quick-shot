"""Check a built App Store app for the things App Review and upload validation reject."""
import plistlib
import struct
import subprocess
import sys
from pathlib import Path

DIRECT_BUNDLE_ID = "com.quickshot.QuickShot"
REQUIRED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    # Screen recordings with the microphone and the camera bubble.
    "com.apple.security.device.audio-input": True,
    "com.apple.security.device.camera": True,
}
ALLOWED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox",
    "com.apple.security.files.bookmarks.app-scope",
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.device.audio-input",
    "com.apple.security.device.camera",
    # Added by Apple at distribution signing.
    "com.apple.application-identifier",
    "com.apple.developer.team-identifier",
}
FORBIDDEN_STRINGS = (b"/usr/sbin/screencapture", b"SUFeedURL", b"SPUStandardUpdaterController")


def validate_entitlements(entitlements: dict) -> None:
    for key, value in REQUIRED_ENTITLEMENTS.items():
        if entitlements.get(key) is not value:
            raise ValueError(f"Missing entitlement {key}")
    unexpected = sorted(set(entitlements) - ALLOWED_ENTITLEMENTS)
    if unexpected:
        raise ValueError(f"Unexpected entitlements: {', '.join(unexpected)}")


def validate_info(info: dict) -> None:
    updater_keys = sorted(key for key in info if key.startswith("SU"))
    if updater_keys:
        raise ValueError(f"Updater keys present: {', '.join(updater_keys)}")
    if info.get("CFBundleIdentifier") == DIRECT_BUNDLE_ID:
        raise ValueError("The App Store build must not share the direct build's bundle identifier")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        raise ValueError("ITSAppUsesNonExemptEncryption must be false")
    if not info.get("LSApplicationCategoryType"):
        raise ValueError("Missing LSApplicationCategoryType")
    if not info.get("NSHumanReadableCopyright"):
        raise ValueError("Missing NSHumanReadableCopyright")
    for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
        if not info.get(key):
            raise ValueError(f"Missing {key}")
    if info.get("LSMinimumSystemVersion") != "15.0":
        raise ValueError("Unexpected minimum OS")


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as file:
        header = file.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG")
    return struct.unpack(">II", header[16:24])


def validate_app(app: Path) -> None:
    with (app / "Contents/Info.plist").open("rb") as file:
        validate_info(plistlib.load(file))

    if list(app.rglob("Sparkle.framework")) or (app / "Contents/Frameworks").exists():
        raise ValueError("The App Store build must not embed frameworks or Sparkle")
    if not (app / "Contents/Resources/PrivacyInfo.xcprivacy").exists():
        raise ValueError("Missing privacy manifest")

    binary = app / "Contents/MacOS/QuickShot"
    # One architecture per call: newer lipo releases reject several after -verify_arch.
    for arch in ("arm64", "x86_64"):
        subprocess.run(["lipo", str(binary), "-verify_arch", arch], check=True)
    linked = subprocess.run(["otool", "-L", str(binary)], check=True, capture_output=True, text=True).stdout
    if "Sparkle" in linked:
        raise ValueError("The App Store build links Sparkle")
    contents = binary.read_bytes()
    for needle in FORBIDDEN_STRINGS:
        if needle in contents:
            raise ValueError(f"Binary contains {needle.decode()}")

    # Read what is actually signed into the app, not the entitlements source file.
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    signed = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)],
                            check=True, capture_output=True).stdout
    if not signed.strip():
        raise ValueError("The app has no signed entitlements")
    validate_entitlements(plistlib.loads(signed))


def validate_icon(iconset: Path) -> None:
    if png_size(iconset / "icon_512x512@2x.png") != (1024, 1024):
        raise ValueError("The App Store needs a 1024 x 1024 icon")


if __name__ == "__main__":
    app = Path(sys.argv[1])
    validate_app(app)
    validate_icon(Path(__file__).resolve().parent.parent / "QuickShot/Assets.xcassets/AppIcon.appiconset")
    print("PASS: sandboxed universal App Store app, no updater, expected entitlements, privacy manifest, 1024 px icon")
