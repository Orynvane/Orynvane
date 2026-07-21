import AppKit
import OrynvaneCore

@MainActor
final class BrowserWindowController: NSWindowController {
    private let addressField = NSTextField()
    private let goButton = NSButton(title: "Go", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Enter an address.")
    private let pageView = PageView()
    private let pageScrollView = NSScrollView()
    private let youtubePlayerView = YouTubePlayerView()
    private let client = HTTPClient()
    private let youtubeResolver = YouTubePlaybackResolver()

    private var pageLoadTask: Task<Void, Never>?
    private var playbackLoadTask: Task<Void, Never>?
    private var navigationID = 0
    private var playbackVideoID: String?
    private var playbackSourceURL: URL?
    private var playbackRetryCount = 0
    private var currentPlaybackIsLive = false
    private var mediaTitle: String?
    private var pageStatus: String?
    private var mediaStatus: String?
    private var pageTopWithoutPlayer: NSLayoutConstraint!
    private var pageTopWithPlayer: NSLayoutConstraint!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        configureWindow()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }

    func load(_ url: URL) {
        navigationID += 1
        let thisNavigation = navigationID
        pageLoadTask?.cancel()
        playbackLoadTask?.cancel()
        pageLoadTask = nil
        playbackLoadTask = nil
        playbackVideoID = nil
        playbackSourceURL = nil
        playbackRetryCount = 0
        currentPlaybackIsLive = false
        mediaTitle = nil

        addressField.stringValue = url.absoluteString
        setPlayerVisible(false)
        youtubePlayerView.stop()
        pageStatus = "Loading…"
        mediaStatus = nil
        refreshStatus()
        goButton.isEnabled = false
        pageView.showMessage(title: "Loading", text: url.absoluteString)

        if YouTubeURL.videoID(from: url) != nil {
            startYouTubePlayback(url, navigationID: thisNavigation)
        }

        pageLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await client.fetch(url)
                guard thisNavigation == navigationID, !Task.isCancelled else { return }

                if let finalVideoID = YouTubeURL.videoID(from: response.finalURL),
                   finalVideoID != playbackVideoID {
                    startYouTubePlayback(response.finalURL, navigationID: thisNavigation)
                }

                let preparationTask = Task.detached(priority: .userInitiated) {
                    let document = HTMLParser().parse(Self.decode(response))
                    return (
                        document.title,
                        PageView.prepare(document, baseURL: response.finalURL)
                    )
                }
                let (title, page) = await withTaskCancellationHandler(operation: {
                    await preparationTask.value
                }, onCancel: {
                    preparationTask.cancel()
                })
                guard thisNavigation == navigationID, !Task.isCancelled else { return }
                addressField.stringValue = response.finalURL.absoluteString
                if mediaTitle == nil {
                    window?.title = title?.isEmpty == false ? title! : "Orynvane"
                }
                pageStatus = "HTTP \(response.statusCode)"
                refreshStatus()
                goButton.isEnabled = true
                pageView.display(page)
            } catch {
                guard thisNavigation == navigationID, !Task.isCancelled else { return }
                pageStatus = "Load failed"
                refreshStatus()
                goButton.isEnabled = true
                pageView.showMessage(title: "Could not load page", text: error.localizedDescription)
            }
        }
    }

    private func configureWindow() {
        guard let window else { return }
        window.title = "Orynvane"
        window.center()
        window.minSize = NSSize(width: 480, height: 320)

        addressField.placeholderString = "https://example.com"
        addressField.font = .systemFont(ofSize: 14)
        addressField.target = self
        addressField.action = #selector(go)

        goButton.target = self
        goButton.action = #selector(go)
        goButton.keyEquivalent = "\r"

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        pageScrollView.hasVerticalScroller = true
        pageScrollView.autohidesScrollers = true
        pageScrollView.borderType = .noBorder
        pageScrollView.drawsBackground = false
        pageScrollView.documentView = pageView

        youtubePlayerView.isHidden = true
        youtubePlayerView.onPlaybackFailure = { [weak self] error in
            guard let self, playbackVideoID != nil else { return }
            let resumeTime = currentPlaybackIsLive ? 0 : youtubePlayerView.resumeTime
            youtubePlayerView.stop()
            setPlayerVisible(false)

            if let sourceURL = playbackSourceURL, playbackRetryCount < 1 {
                playbackRetryCount += 1
                mediaStatus = "Refreshing YouTube stream…"
                refreshStatus()
                startYouTubePlayback(
                    sourceURL,
                    navigationID: navigationID,
                    startingAt: resumeTime,
                    isRetry: true
                )
                return
            }

            mediaStatus = "YouTube playback failed: \(error.localizedDescription)"
            refreshStatus()
        }

        pageView.onNavigate = { [weak self] url in
            self?.load(url)
        }
        pageView.showMessage(title: "Orynvane", text: "Enter an address above.")

        let content = NSView()
        window.contentView = content

        [addressField, goButton, statusLabel, pageScrollView, youtubePlayerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        pageTopWithoutPlayer = pageScrollView.topAnchor.constraint(
            equalTo: statusLabel.bottomAnchor,
            constant: 7
        )
        pageTopWithPlayer = pageScrollView.topAnchor.constraint(
            equalTo: youtubePlayerView.bottomAnchor,
            constant: 7
        )
        pageTopWithPlayer.isActive = false

        let playerProportionalHeight = youtubePlayerView.heightAnchor.constraint(
            equalTo: content.heightAnchor,
            multiplier: 0.55
        )
        playerProportionalHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            addressField.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            addressField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            goButton.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 8),
            goButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            goButton.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            goButton.widthAnchor.constraint(equalToConstant: 54),

            statusLabel.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 5),
            statusLabel.leadingAnchor.constraint(equalTo: addressField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: goButton.trailingAnchor),

            pageTopWithoutPlayer,
            pageScrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pageScrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pageScrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            youtubePlayerView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 7),
            youtubePlayerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            youtubePlayerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            youtubePlayerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            youtubePlayerView.heightAnchor.constraint(lessThanOrEqualToConstant: 360),
            playerProportionalHeight,
        ])

        window.makeFirstResponder(addressField)
    }

    @objc private func go() {
        guard let url = URLResolver.address(addressField.stringValue) else {
            statusLabel.stringValue = "Enter an HTTP or HTTPS address."
            return
        }
        load(url)
    }

    private func startYouTubePlayback(
        _ url: URL,
        navigationID expectedNavigationID: Int,
        startingAt startTime: TimeInterval = 0,
        isRetry: Bool = false
    ) {
        guard let videoID = YouTubeURL.videoID(from: url) else { return }

        playbackLoadTask?.cancel()
        playbackVideoID = videoID
        playbackSourceURL = url
        if !isRetry {
            playbackRetryCount = 0
        }
        let requestedStartTime = isRetry ? startTime : YouTubeURL.startTime(from: url)
        mediaStatus = "Resolving YouTube video…"
        refreshStatus()

        playbackLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let playback = try await youtubeResolver.resolve(url)
                guard expectedNavigationID == navigationID, !Task.isCancelled else { return }

                mediaTitle = playback.title
                currentPlaybackIsLive = playback.isLive
                mediaStatus = playback.isLive
                    ? "YouTube Live • \(playback.qualityLabel)"
                    : "YouTube • \(playback.qualityLabel)"
                refreshStatus()
                window?.title = "\(playback.title) — Orynvane"
                setPlayerVisible(true)
                youtubePlayerView.play(playback, startingAt: requestedStartTime)
            } catch {
                guard expectedNavigationID == navigationID, !Task.isCancelled else { return }
                mediaStatus = "YouTube video unavailable: \(error.localizedDescription)"
                refreshStatus()
            }
        }
    }

    private func setPlayerVisible(_ isVisible: Bool) {
        guard pageTopWithoutPlayer != nil, pageTopWithPlayer != nil else {
            youtubePlayerView.isHidden = !isVisible
            return
        }
        pageTopWithoutPlayer.isActive = false
        pageTopWithPlayer.isActive = false
        (isVisible ? pageTopWithPlayer : pageTopWithoutPlayer).isActive = true
        youtubePlayerView.isHidden = !isVisible
    }

    private func refreshStatus() {
        let values = [pageStatus, mediaStatus].compactMap { $0 }
        statusLabel.stringValue = values.isEmpty ? "Enter an address." : values.joined(separator: " • ")
    }

    nonisolated private static func decode(_ response: HTTPResponse) -> String {
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        let encoding: String.Encoding

        if contentType.contains("iso-8859-1") || contentType.contains("latin1") {
            encoding = .isoLatin1
        } else if contentType.contains("windows-1252") {
            encoding = .windowsCP1252
        } else if contentType.contains("us-ascii") {
            encoding = .ascii
        } else {
            encoding = .utf8
        }

        return String(data: response.body, encoding: encoding)
            ?? String(decoding: response.body, as: UTF8.self)
    }
}
