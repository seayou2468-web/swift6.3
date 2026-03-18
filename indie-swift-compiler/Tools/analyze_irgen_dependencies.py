#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

INCLUDE_RE = re.compile(r'^\s*#\s*include\s+["<]([^">]+)[">]')


def extract_includes(path: Path) -> set[str]:
    includes: set[str] = set()
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = INCLUDE_RE.match(line)
        if m:
            includes.add(m.group(1))
    return includes


def main() -> None:
    parser = argparse.ArgumentParser(description="抽出IRGenソースの依存ヘッダ分析")
    parser.add_argument("--vendor-root", required=True)
    parser.add_argument("--source-set", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    vendor = Path(args.vendor_root)
    source_set = json.loads(Path(args.source_set).read_text(encoding="utf-8"))

    files = source_set.get("headers", []) + source_set.get("sources", [])
    report: dict[str, object] = {
        "source_set": source_set.get("name", "unknown"),
        "files": files,
        "includes_by_file": {},
        "summary": {},
    }

    all_includes: set[str] = set()
    swift_includes: set[str] = set()
    llvm_includes: set[str] = set()

    for rel in files:
        path = vendor / rel
        includes = sorted(extract_includes(path)) if path.exists() else []
        report["includes_by_file"][rel] = includes
        all_includes.update(includes)
        for inc in includes:
            if inc.startswith("swift/"):
                swift_includes.add(inc)
            if inc.startswith("llvm/") or inc.startswith("clang/"):
                llvm_includes.add(inc)

    report["summary"] = {
        "total_includes": len(all_includes),
        "swift_include_count": len(swift_includes),
        "llvm_clang_include_count": len(llvm_includes),
        "swift_includes": sorted(swift_includes),
        "llvm_clang_includes": sorted(llvm_includes),
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"生成完了: {out}")


if __name__ == "__main__":
    main()
