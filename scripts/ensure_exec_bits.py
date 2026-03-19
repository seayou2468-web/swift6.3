#!/usr/bin/env python3

import argparse
import os
from pathlib import Path


def ensure_exec_bits(root: Path) -> int:
    updated = 0
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            with path.open("rb") as f:
                if f.read(2) != b"#!":
                    continue
        except OSError:
            continue

        mode = path.stat().st_mode
        if mode & 0o111:
            continue

        os.chmod(path, mode | 0o755)
        updated += 1
    return updated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, help="Directory tree to scan")
    args = parser.parse_args()

    root = Path(args.root)
    updated = ensure_exec_bits(root)
    print(f"updated executable bit for {updated} script(s) under {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
