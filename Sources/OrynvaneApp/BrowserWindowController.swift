import AppKit
import OrynvaneCore

@MainActor
final class BrowserWindowController: NSWindowController {
    private let addressField = NSTextField()
    private let goButton = NSButton(title: "Go", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Enter an address.")
    private let pageView = PageView()
    private let client = HTTPClient()

    private var loadTask: Task<Void, Never>?
    private var navigationID = 0

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
        loadTask?.cancel()

        addressField.stringValue = url.absoluteString
        statusLabel.stringValue = "Loading…"
        goButton.isEnabled = false
        pageView.showMessage(title: "Loading", text: url.absoluteString)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await client.fetch(url)
                guard thisNavigation == navigationID, !Task.isCancelled else { return }

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
                window?.title = title?.isEmpty == false ? title! : "Orynvane"
                statusLabel.stringValue = "HTTP \(response.statusCode)"
                goButton.isEnabled = true
                pageView.display(page)
            } catch {
                guard thisNavigation == navigationID, !Task.isCancelled else { return }
                statusLabel.stringValue = "Load failed"
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = pageView

        pageView.onNavigate = { [weak self] url in
            self?.load(url)
        }
        pageView.showMessage(title: "Orynvane", text: "Enter an address above.")

        let content = NSView()
        window.contentView = content

        [addressField, goButton, statusLabel, scrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

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

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 7),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
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
