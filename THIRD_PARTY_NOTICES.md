# Third-party notices

`cbonsai-saver` is licensed under the GNU General Public License version 3 or
later (`GPL-3.0-or-later`).

## cbonsai

Release builds bundle the original `cbonsai` executable so the screen saver does
not depend on a user-installed command-line binary at runtime.

- Project: https://gitlab.com/jallbrit/cbonsai
- License: `GPL-3.0-or-later`
- Packaging reference: Homebrew `cbonsai` formula

The release package is built from this repository and copies the local
`cbonsai` executable selected by `scripts/bundle-cbonsai.sh`. Official release
archives are built by `scripts/package-release.sh`, which compiles `cbonsai`
from the pinned upstream source archive verified by
`scripts/build-cbonsai-source.sh`.

## ncurses

Release builds may also bundle `ncurses` runtime libraries required by the
bundled `cbonsai` executable. Apple Silicon Homebrew release builds use
Homebrew `ncurses`; Intel macOS 10.15 release builds compile `ncurses` from the
pinned upstream source archive verified by `scripts/build-ncurses-source.sh`.

- Project: https://invisible-island.net/ncurses/
- License: `X11-distribute-modifications-variant`
- Packaging reference: Homebrew `ncurses` formula and upstream source archive
