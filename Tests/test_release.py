import base64
import importlib.util
import tempfile
import unittest
from pathlib import Path


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parents[1] / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


metadata = load("release_metadata")
verify = load("verify_release")


class ReleaseTests(unittest.TestCase):
    def test_versions_increase_and_reruns_are_stable(self):
        self.assertEqual(metadata.versions(10), ("1.4.10", "1010"))
        self.assertEqual(metadata.versions(10), metadata.versions(10))
        self.assertGreater(int(metadata.versions(11)[1]), int(metadata.versions(10)[1]))
        with self.assertRaises(ValueError):
            metadata.versions(0)

    def test_feed_rejects_mismatched_or_mutable_release(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "QuickShot-1.4.10.zip"
            archive.write_bytes(b"test archive")
            feed = Path(folder) / "appcast.xml"
            signature = base64.b64encode(bytes(64)).decode()
            content = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
            <sparkle:version>1010</sparkle:version><sparkle:shortVersionString>1.4.10</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/Wirenut33/quick-shot/releases/download/v1.4.10/{archive.name}"
            length="12" sparkle:edSignature="{signature}" /></item></channel></rss>'''
            feed.write_text(content)
            verify.validate_feed(feed, archive, "1.4.10", "1010", "v1.4.10")
            for bad in [content.replace("releases/download/v1.4.10", "releases/latest/download"),
                        content.replace("1010", "1009"), content.replace('length="12"', 'length="1"'),
                        content.replace(signature, "invalid"), content.replace("15.0", "26.0")]:
                feed.write_text(bad)
                with self.assertRaises(ValueError):
                    verify.validate_feed(feed, archive, "1.4.10", "1010", "v1.4.10")


if __name__ == "__main__":
    unittest.main()
