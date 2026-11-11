#!/usr/bin/env python3
"""Check that website publication uses the expected signed macOS release."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("build_site", Path(__file__).parents[1] / "build-site.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
FEED = '''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>20261111001</sparkle:version>
<sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
<enclosure url="https://github.com/wanggang316/handbyte-macos/releases/download/v0.2.0/Handbyte-0.2.0.dmg" sparkle:edSignature="fixture-signature"/>
</item></channel></rss>'''


class BuildSiteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.feed = self.root / "feed.xml"
        self.feed.write_text(FEED)
        self.output = self.root / "site"

    def test_copies_feed_and_renders_download(self):
        MODULE.build_site(self.feed, "v0.2.0", self.output)
        self.assertEqual((self.output / "appcast.xml").read_bytes(), self.feed.read_bytes())
        page = (self.output / "index.html").read_text()
        self.assertIn('href="https://github.com/wanggang316/handbyte-macos/releases/download/v0.2.0/Handbyte-0.2.0.dmg"', page)
        self.assertIn("v0.2.0", page)
        self.assertNotIn("{{", page)
        for asset in ("styles.css", "app.js", "favicon.svg", "install.sh"):
            self.assertTrue((self.output / asset).is_file())

    def test_rejects_another_repository(self):
        self.feed.write_text(FEED.replace("/handbyte-macos/", "/handbyte/"))
        with self.assertRaisesRegex(ValueError, "does not match"):
            MODULE.build_site(self.feed, "v0.2.0", self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_old_feed_for_new_release(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            MODULE.build_site(self.feed, "v0.3.0", self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_unsigned_enclosure(self):
        self.feed.write_text(FEED.replace('sparkle:edSignature="fixture-signature"', ""))
        with self.assertRaisesRegex(ValueError, "no Sparkle signature"):
            MODULE.build_site(self.feed, "v0.2.0", self.output)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
