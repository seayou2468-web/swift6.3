#!/usr/bin/env python3
import argparse
import json
import shutil
from pathlib import Path


def safe_copy(src_root: Path, rel: str, out_root: Path) -> None:
    src = src_root / rel
    if not src.exists():
        raise FileNotFoundError(f"不足: {src}")
    dst = out_root / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def write_cmakelists(out_root: Path, source_set: dict) -> None:
    srcs = "\n  ".join(source_set["sources"])
    cmake = f"""cmake_minimum_required(VERSION 3.20)
project(SwiftIRGenExtract LANGUAGES CXX)

add_library(SwiftIRGenExtract STATIC
  {srcs}
)

target_include_directories(SwiftIRGenExtract PUBLIC
  ${{CMAKE_CURRENT_SOURCE_DIR}}/include
)

target_compile_features(SwiftIRGenExtract PUBLIC cxx_std_17)
"""
    (out_root / "CMakeLists.txt").write_text(cmake, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="抽出済みIRGenソースから最小バンドルを生成")
    parser.add_argument("--vendor-root", required=True)
    parser.add_argument("--source-set", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    vendor_root = Path(args.vendor_root)
    source_set = json.loads(Path(args.source_set).read_text(encoding="utf-8"))
    out_root = Path(args.output)

    if out_root.exists():
        shutil.rmtree(out_root)
    out_root.mkdir(parents=True, exist_ok=True)

    for rel in source_set.get("headers", []):
        safe_copy(vendor_root, rel, out_root)
    for rel in source_set.get("sources", []):
        safe_copy(vendor_root, rel, out_root)

    write_cmakelists(out_root, source_set)

    (out_root / "BUNDLE_INFO.json").write_text(
        json.dumps(source_set, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"生成完了: {out_root}")


if __name__ == "__main__":
    main()
