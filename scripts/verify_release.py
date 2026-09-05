"""Validate the release's version, immutable URLs, key and architecture before publishing."""
import base64
import plistlib
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
PUBLIC_KEY = "Q1/TD6JPGw6Er/WEapw7WIhOgkvFTbd9pywIQDvWmKw="
FEED = "https://github.com/Wirenut33/quick-shot/releases/latest/download/appcast.xml"
REQUIREMENT = '=identifier "com.quickshot.QuickShot" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: MICHAEL ANTHONY MORALE (5K58FPSA8S)" and certificate 1[field.1.2.840.113635.100.6.2.1]'


def validate_feed(feed: Path, archive: Path, version: str, build: str, tag: str) -> None:
    root = ET.parse(feed).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one current release")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update archive")
    expected = f"https://github.com/Wirenut33/quick-shot/releases/download/{tag}/{archive.name}"
    if enclosure.get("url") != expected:
        raise ValueError("Archive URL must target this immutable release")
    if item.findtext(f"{SPARKLE}version") != build or item.findtext(f"{SPARKLE}shortVersionString") != version:
        raise ValueError("Appcast version does not match the built app")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Archive length mismatch")
    if len(base64.b64decode(enclosure.get(f"{SPARKLE}edSignature", ""), validate=True)) != 64:
        raise ValueError("Missing or malformed update signature")
    if item.findtext(f"{SPARKLE}minimumSystemVersion") != "15.0":
        raise ValueError("Unexpected minimum OS")


def validate_app(app: Path, version: str, build: str) -> None:
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    for key, value in {"CFBundleIdentifier": "com.quickshot.QuickShot", "CFBundleVersion": build,
                       "CFBundleShortVersionString": version, "SUPublicEDKey": PUBLIC_KEY,
                       "SUFeedURL": FEED, "SURequireSignedFeed": True,
                       "SUVerifyUpdateBeforeExtraction": True}.items():
        if info.get(key) != value:
            raise ValueError(f"Unexpected {key}")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "-R", REQUIREMENT, str(app)], check=True)
    subprocess.run(["lipo", str(app / "Contents/MacOS/QuickShot"), "-verify_arch", "arm64", "x86_64"], check=True)


if __name__ == "__main__":
    app, feed, archive, version, build, tag = sys.argv[1:]
    validate_app(Path(app), version, build)
    validate_feed(Path(feed), Path(archive), version, build, tag)
    print("PASS: universal signed app, stable identity/key, matching version and immutable archive URL")
