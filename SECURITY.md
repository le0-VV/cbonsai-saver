# Security Policy

## Supported versions

Security fixes are provided for the latest published release and the current
`main` branch.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for this repository if it is
available. If it is not available, open a minimal public issue asking for a
private security contact channel; do not include exploit details in that issue.

Please include:

- The affected version or commit.
- The macOS version and hardware architecture.
- Steps to reproduce the issue.
- Whether the issue affects the screen saver host, bundled `cbonsai`, bundled
  runtime libraries, release packaging, or Homebrew installation.

## Scope

In scope:

- The native macOS screen saver bundle.
- Process launch, pseudo-terminal handling, and terminal output rendering.
- Bundling and release packaging scripts.
- Homebrew tap/cask installation behavior.

Out of scope:

- Vulnerabilities in upstream `cbonsai`, except where this project bundles or
  invokes it unsafely.
- Vulnerabilities in macOS ScreenSaver.framework or system libraries.
- Social engineering, spam, or reports that require physical access to an
  already-unlocked machine.

## Response

Expect an initial maintainer response within 7 days. Confirmed vulnerabilities
will be fixed on `main`, released, and credited where appropriate unless the
reporter asks otherwise.
