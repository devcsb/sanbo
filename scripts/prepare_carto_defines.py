#!/usr/bin/env python3
"""Write build defines without printing credentials or replacing user files."""
import json
import os
import sys


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: prepare_carto_defines.py <new-output-json-path>")
    key = os.environ.get("CARTO_BASEMAP_KEY", "").strip()
    if not key:
        raise SystemExit("CARTO_BASEMAP_KEY is required for release builds")
    try:
        with open(
            sys.argv[1], "x", encoding="utf-8",
            opener=lambda path, flags: os.open(path, flags, 0o600),
        ) as output:
            os.fchmod(output.fileno(), 0o600)
            json.dump({"CARTO_BASEMAP_KEY": key}, output)
    except (OSError, UnicodeError):
        raise SystemExit("could not create private CARTO build configuration") from None


if __name__ == "__main__":
    main()
