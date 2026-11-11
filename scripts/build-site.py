#!/usr/bin/env python3
"""Build the macOS website from the published release's signed appcast."""

import argparse
import html
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
RELEASES = "https://github.com/wanggang316/handbyte-macos/releases/download/"


def build_site(appcast: Path, tag: str, output: Path) -> None:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected a stable release tag vX.Y.Z")
    items = []
    for item in ET.parse(appcast).findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue

        def field(name: str) -> str:
            return enclosure.get(f"{{{SPARKLE}}}{name}") or item.findtext(f"{{{SPARKLE}}}{name}", "")

        if field("channel"):
            continue
        items.append((int(field("version")), field("shortVersionString"), enclosure))
    if not items:
        raise ValueError("Appcast has no stable release")
    build, version, enclosure = max(items, key=lambda value: value[0])
    expected_url = f"{RELEASES}{tag}/Handbyte-{tag[1:]}.dmg"
    if build <= 0 or version != tag[1:] or enclosure.get("url") != expected_url:
        raise ValueError("Appcast does not match the latest macOS release")
    if not enclosure.get(f"{{{SPARKLE}}}edSignature"):
        raise ValueError("Appcast enclosure has no Sparkle signature")

    source = Path(__file__).resolve().parent.parent / "site"
    page = (source / "index.html").read_text()
    page = page.replace("{{VERSION}}", html.escape(version))
    page = page.replace("{{DOWNLOAD_URL}}", html.escape(expected_url, quote=True))
    shutil.copytree(source, output)
    (output / "index.html").write_text(page)
    # Preserve the signed release feed exactly for installed clients.
    shutil.copyfile(appcast, output / "appcast.xml")
    print(f"Built website for {tag} (build {build}) at {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    build_site(args.appcast, args.tag, args.output)
