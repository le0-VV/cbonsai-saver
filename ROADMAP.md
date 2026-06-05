# Roadmap

- Build a native macOS screen saver bundle that runs the original `cbonsai` binary when available.
- Launch the bundled `cbonsai` binary directly through a pseudo-terminal, so curses/ANSI terminal output works without a shell or Terminal.app dependency.
- Keep rendering lightweight by maintaining a small in-memory terminal grid and drawing it directly in the `ScreenSaverView`.
- Bundle the original `cbonsai` binary with the saver, store only typed cbonsai options through `ScreenSaverDefaults`, and size the terminal font automatically from the saver view bounds.
