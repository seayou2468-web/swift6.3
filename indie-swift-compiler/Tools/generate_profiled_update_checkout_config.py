#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="互換プロファイルに基づく最小 update-checkout JSON 生成")
    parser.add_argument("--source", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--scheme", default="release/6.3")
    args = parser.parse_args()

    source = json.loads(Path(args.source).read_text(encoding="utf-8"))
    profile = json.loads(Path(args.profile).read_text(encoding="utf-8"))
    enabled = profile.get("enable", [])

    if not enabled:
        raise SystemExit("profile.enable が空です")

    repos = source.get("repos", {})
    schemes = source.get("branch-schemes", {})
    if args.scheme not in schemes:
        raise SystemExit(f"scheme が見つかりません: {args.scheme}")

    missing = [name for name in enabled if name not in repos]
    if missing:
        raise SystemExit(f"repos に未定義: {missing}")

    scheme_repos = schemes[args.scheme].get("repos", {})
    missing_scheme = [name for name in enabled if name not in scheme_repos]
    if missing_scheme:
        raise SystemExit(f"scheme repos に未定義: {missing_scheme}")

    out = {
        "ssh-clone-pattern": source.get("ssh-clone-pattern", "git@github.com:%s.git"),
        "https-clone-pattern": source.get("https-clone-pattern", "https://github.com/%s.git"),
        "repos": {name: repos[name] for name in enabled},
        "default-branch-scheme": args.scheme,
        "branch-schemes": {
            args.scheme: {
                "aliases": schemes[args.scheme].get("aliases", [args.scheme]),
                "repos": {name: scheme_repos[name] for name in enabled},
            }
        },
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"生成完了: {out_path}")


if __name__ == "__main__":
    main()
