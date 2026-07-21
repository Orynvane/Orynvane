# Orynvane

Orynvane is a Mac-native web browser with an independent engine built from
first principles. Enter a web address, load HTTP or HTTPS pages, read HTML
documents, and follow links in a native Mac interface.

## Features

- HTTP and HTTPS browsing
- address-bar navigation
- clickable links and relative URL resolution
- native text, heading, list, and inline-format rendering
- standard Mac text editing shortcuts
- a directly buildable macOS app bundle

## Independent browser engine

Orynvane does not embed WebKit, Chromium, Gecko, or another browser engine. It
uses AppKit for the native window and text drawing, and Apple's Network
framework for TCP and TLS. HTTP parsing, HTML parsing, document layout,
navigation, and painting are implemented by Orynvane itself.

The current engine focuses on HTML documents. CSS, JavaScript, images, forms,
cookies, caching, tabs, bookmarks, and history are not currently implemented.
Loads are capped at 8 MiB and 15 seconds, and the page view lays out up to
50,000 visible characters.

## Run

Requires macOS 13 or newer and Xcode command-line tools.

```sh
swift run Orynvane
```

An initial URL can be supplied on the command line:

```sh
swift run Orynvane https://example.com/
```

## Build a Mac app

```sh
./scripts/build-app.sh
open dist/Orynvane.app
```

## Test

```sh
swift test
```

## Releases

GitHub Releases are published automatically from `main` after the test suite
passes. Release versions are calculated from Conventional Commit messages since
the latest `vX.Y.Z` tag:

- `fix:` and `perf:` create a patch release.
- `feat:` creates a minor release.
- A `BREAKING CHANGE:` footer or `!` after the commit type creates a major
  release.
- Other commit types, such as `docs:`, `test:`, `chore:`, and `ci:`, do not
  create a release by themselves.

The release workflow creates the version tag, release notes, and GitHub Release;
version tags should not be created manually.
