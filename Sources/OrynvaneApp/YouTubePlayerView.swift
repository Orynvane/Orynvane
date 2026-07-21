import AppKit
import AVFoundation
import AVKit
import OrynvaneCore

@MainActor
final class YouTubePlayerView: NSView {
    var onPlaybackFailure: ((Error) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailsLabel = NSTextField(labelWithString: "")
    private let playerView = AVPlayerView()

    private var player: AVPlayer?
    private var itemObservation: NSKeyValueObservation?
    private var playbackFailureObservation: NSObjectProtocol?
    private var requestedStartTime: TimeInterval = 0
    private var initialSeekCompleted = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.font = .systemFont(ofSize: 12)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.lineBreakMode = .byTruncatingTail

        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.allowsPictureInPicturePlayback = true

        [titleLabel, detailsLabel, playerView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            detailsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            playerView.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    var resumeTime: TimeInterval {
        if !initialSeekCompleted {
            return requestedStartTime
        }
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    func play(_ playback: YouTubePlayback, startingAt startTime: TimeInterval = 0) {
        stop()

        titleLabel.stringValue = playback.title
        let source = playback.isLive ? "YouTube Live" : "YouTube"
        let byline = playback.author.map { " • \($0)" } ?? ""
        detailsLabel.stringValue = "\(source) • \(playback.qualityLabel)\(byline)"

        let item = AVPlayerItem(url: playback.streamURL)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            let status = item?.status
            let error = item?.error
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.player?.currentItem === item,
                      status == .failed else {
                    return
                }
                self.onPlaybackFailure?(error ?? YouTubePlaybackError.noPlayableStream)
            }
        }
        playbackFailureObservation = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      self.player?.currentItem === item else {
                    return
                }
                self.onPlaybackFailure?(error ?? YouTubePlaybackError.noPlayableStream)
            }
        }

        let player = AVPlayer(playerItem: item)
        self.player = player
        playerView.player = player

        requestedStartTime = startTime.isFinite ? max(0, startTime) : 0
        initialSeekCompleted = requestedStartTime == 0
        if requestedStartTime > 0 {
            player.seek(
                to: CMTime(seconds: requestedStartTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self, weak player] completed in
                Task { @MainActor [weak self, weak player] in
                    guard let self, self.player === player else { return }
                    self.initialSeekCompleted = completed
                }
            }
        }
        player.play()
    }

    func stop() {
        itemObservation = nil
        if let playbackFailureObservation {
            NotificationCenter.default.removeObserver(playbackFailureObservation)
            self.playbackFailureObservation = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerView.player = nil
        player = nil
        requestedStartTime = 0
        initialSeekCompleted = true
    }
}
