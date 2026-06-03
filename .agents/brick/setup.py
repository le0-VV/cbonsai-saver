#!/usr/bin/env python3
from pathlib import Path
import sys


def _bootstrap() -> None:
    brick_root = Path(__file__).resolve().parent
    src = brick_root / "src"
    if not src.is_dir():
        print(
            "brick setup: missing `.agents/brick/src`; re-run the Brick installer.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    sys.path.insert(0, str(src))


_bootstrap()

try:
    from brick.cli import main
except ModuleNotFoundError as exc:
    print(
        "brick setup: missing Python module or dependency "
        f"`{exc.name}`; re-run the Brick installer, then `./brick setup`.",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc


if __name__ == "__main__":
    raise SystemExit(main(["setup", *sys.argv[1:]]))
