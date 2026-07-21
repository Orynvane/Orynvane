# Orynvane

Orynvane is a Mac-native web browser with an independent engine built from
first principles. Enter a web address, load HTTP or HTTPS pages, read HTML
documents, and follow links in a native Mac interface.

## Features

- HTTP and HTTPS browsing
- address-bar navigation
- clickable links and relative URL resolution
- native text, heading, list, and inline-format rendering
- direct YouTube-link playback inside the app
- standard Mac text editing shortcuts
- a directly buildable macOS app bundle

## Independent browser engine

Orynvane does not embed WebKit, Chromium, Gecko, or another browser engine. It
uses AppKit for the native window and text drawing, and Apple's Network
framework for TCP and TLS. HTTP parsing, HTML parsing, document layout,
navigation, and painting are implemented by Orynvane itself.

YouTube pages still travel through that independent engine. For recognized
video links, Orynvane also resolves YouTube's anonymous player response with its
own HTTP client and gives a compatible MP4 or HLS asset to AVFoundation for
media decoding. AVKit supplies the native playback, seeking, Picture in Picture,
and fullscreen controls above the page that Orynvane parsed and painted.

The engine focuses on HTML documents. CSS, JavaScript, images, forms, cookies,
caching, tabs, bookmarks, and history are not currently implemented. Loads are
capped at 8 MiB and 15 seconds, and the page view lays out up to 50,000 visible
characters. YouTube playback is anonymous, and on-demand videos currently use
the best combined MP4 supplied to the native client, which is commonly standard
definition. Restricted videos can require sign-in, and YouTube's undocumented
player endpoint can change.

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
