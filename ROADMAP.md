# Roadmap

- Build a native macOS screen saver bundle that runs the original `cbonsai` binary when available.
- Launch `cbonsai` through a non-interactive `/bin/sh -c` process attached to a pseudo-terminal, so curses/ANSI terminal output works without a Terminal.app dependency.
- Keep rendering lightweight by maintaining a small in-memory terminal grid and drawing it directly in the `ScreenSaverView`.
- Store user-editable executable path, argument string, and font size through macOS screen saver settings using `ScreenSaverDefaults`.
