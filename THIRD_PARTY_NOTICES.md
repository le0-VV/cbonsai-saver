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
`cbonsai` executable selected by `scripts/bundle-cbonsai.sh`. When publishing a
release, make sure the corresponding `cbonsai` source remains available through
the upstream project or the package source used to build that executable.

## ncurses

Release builds may also bundle Homebrew `ncurses` runtime libraries required by
the bundled `cbonsai` executable.

- Project: https://invisible-island.net/ncurses/
- License: `X11-distribute-modifications-variant`
- Packaging reference: Homebrew `ncurses` formula
