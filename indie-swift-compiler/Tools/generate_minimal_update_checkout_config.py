#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

REQUIRED_REPOS = [
    "swift",
    "llvm-project",
    "cmark",
    "swift-syntax",
    "swift-driver",
    "swift-llvm-bindings",
]


def pick_repos(full: dict, names: list[str]) -> dict:
    repos = full.get("repos", {})
    out = {}
    for name in names:
        if name not in repos:
            raise KeyError(f"repos に '{name}' がありません")
        out[name] = repos[name]
    return out


def pick_scheme(full: dict, scheme: str, names: list[str]) -> dict:
    schemes = full.get("branch-schemes", {})
    if scheme not in schemes:
        raise KeyError(f"branch-schemes に '{scheme}' がありません")

    source = schemes[scheme]
    branch_repos = source.get("repos", {})
    out_repos = {}
    for name in names:
        if name not in branch_repos:
            raise KeyError(f"branch-schemes/{scheme}/repos に '{name}' がありません")
        out_repos[name] = branch_repos[name]

    return {
        "aliases": source.get("aliases", [scheme]),
        "repos": out_repos,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Swift update-checkout 設定から最小構成JSONを生成")
    parser.add_argument("--source", required=True, help="元の update-checkout-config.json")
    parser.add_argument("--output", required=True, help="出力先JSON")
    parser.add_argument("--scheme", default="release/6.3", help="抽出する branch-scheme")
    parser.add_argument(
        "--repos",
        nargs="+",
        default=REQUIRED_REPOS,
        help="抽出する repos 名のリスト",
    )
    args = parser.parse_args()

    source_path = Path(args.source)
    output_path = Path(args.output)

    with source_path.open("r", encoding="utf-8") as fp:
        full = json.load(fp)

    minimal = {
        "ssh-clone-pattern": full.get("ssh-clone-pattern", "git@github.com:%s.git"),
        "https-clone-pattern": full.get("https-clone-pattern", "https://github.com/%s.git"),
        "repos": pick_repos(full, args.repos),
        "default-branch-scheme": args.scheme,
        "branch-schemes": {
            args.scheme: pick_scheme(full, args.scheme, args.repos),
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fp:
        json.dump(minimal, fp, indent=2, ensure_ascii=False)
        fp.write("\n")

    print(f"生成完了: {output_path}")


if __name__ == "__main__":
    main()
