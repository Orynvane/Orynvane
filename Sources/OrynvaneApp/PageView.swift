import AppKit
import OrynvaneCore

@MainActor
final class PageView: NSView {
    struct PreparedPage: Sendable {
        fileprivate let blocks: [RenderBlock]
    }

    var onNavigate: ((URL) -> Void)?

    private var blocks: [RenderBlock] = []
    private var displayItems: [DisplayItem] = []
    private var isLayingOut = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        nil
    }

    nonisolated static func prepare(_ document: HTMLDocument, baseURL: URL) -> PreparedPage {
        PreparedPage(blocks: DocumentFlattener(baseURL: baseURL).flatten(document))
    }

    func display(_ page: PreparedPage) {
        blocks = page.blocks
        if blocks.isEmpty {
            showMessage(title: "Empty page", text: "The document has no displayable text.")
            return
        }
        layoutPage()
    }

    func showMessage(title: String, text: String) {
        blocks = [
            RenderBlock(pieces: [.text(title, .heading(1), nil)], topMargin: 8, bottomMargin: 10),
            RenderBlock(pieces: [.text(text, .body, nil)], topMargin: 0, bottomMargin: 8)
        ]
        layoutPage()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, !isLayingOut, !blocks.isEmpty {
            layoutPage()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        for item in displayItems where item.frame.intersects(dirtyRect) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: item.font,
                .foregroundColor: item.link == nil ? NSColor.labelColor : NSColor.linkColor
            ]
            if item.link != nil {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            (item.text as NSString).draw(at: item.frame.origin, withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let url = displayItems.first(where: { $0.link != nil && $0.frame.contains(point) })?.link else {
            super.mouseDown(with: event)
            return
        }
        onNavigate?(url)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for item in displayItems where item.link != nil {
            addCursorRect(item.frame, cursor: .pointingHand)
        }
    }

    private func layoutPage() {
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        let left: CGFloat = 18
        let right: CGFloat = max(left + 1, bounds.width - 18)
        let availableWidth = right - left
        var y: CGFloat = 14
        var items: [DisplayItem] = []

        for block in blocks {
            y += block.topMargin
            var x = left
            var currentLineHeight: CGFloat = 0
            var pendingSpace = false
            var lineHasContent = false

            func finishLine(force: Bool = false) {
                if lineHasContent || force {
                    y += max(currentLineHeight, 18)
                }
                x = left
                currentLineHeight = 0
                pendingSpace = false
                lineHasContent = false
            }

            for piece in block.pieces {
                switch piece {
                case .lineBreak:
                    finishLine(force: true)

                case let .text(text, style, link):
                    let font = style.font
                    let lineHeight = ceil(font.ascender - font.descender + font.leading + 2)
                    var word = ""

                    func placeChunk(_ chunk: String, usePendingSpace: Bool) {
                        let chunkSize = (chunk as NSString).size(withAttributes: [.font: font])
                        let spaceWidth = usePendingSpace && pendingSpace && lineHasContent
                            ? (" " as NSString).size(withAttributes: [.font: font]).width
                            : 0

                        if lineHasContent, x + spaceWidth + chunkSize.width > right {
                            finishLine()
                        }

                        if usePendingSpace, pendingSpace, lineHasContent {
                            x += (" " as NSString).size(withAttributes: [.font: font]).width
                        }

                        let frame = NSRect(
                            x: x,
                            y: y,
                            width: chunkSize.width,
                            height: lineHeight
                        )
                        items.append(DisplayItem(text: chunk, font: font, frame: frame, link: link))
                        x += chunkSize.width
                        currentLineHeight = max(currentLineHeight, lineHeight)
                        lineHasContent = true
                        pendingSpace = false
                    }

                    func placeWord() {
                        guard !word.isEmpty else { return }
                        let wordSize = (word as NSString).size(withAttributes: [.font: font])

                        if wordSize.width <= availableWidth {
                            placeChunk(word, usePendingSpace: true)
                        } else {
                            if lineHasContent {
                                finishLine()
                            }
                            var chunk = ""
                            var chunkWidth: CGFloat = 0
                            for character in word {
                                let characterText = String(character)
                                let characterWidth = (characterText as NSString)
                                    .size(withAttributes: [.font: font]).width
                                if chunkWidth + characterWidth > availableWidth, !chunk.isEmpty {
                                    placeChunk(chunk, usePendingSpace: false)
                                    finishLine()
                                    chunk = characterText
                                    chunkWidth = characterWidth
                                } else {
                                    chunk.append(character)
                                    chunkWidth += characterWidth
                                }
                            }
                            if !chunk.isEmpty {
                                placeChunk(chunk, usePendingSpace: false)
                            }
                        }
                        word.removeAll(keepingCapacity: true)
                    }

                    for character in text {
                        if character.isWhitespace {
                            placeWord()
                            pendingSpace = true
                        } else {
                            word.append(character)
                        }
                    }
                    placeWord()
                }
            }

            finishLine()
            y += block.bottomMargin
        }

        displayItems = items
        let viewportHeight = enclosingScrollView?.contentSize.height ?? 0
        let contentHeight = max(y + 14, viewportHeight)
        super.setFrameSize(NSSize(width: max(frame.width, 1), height: contentHeight))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
}

private struct DisplayItem {
    let text: String
    let font: NSFont
    let frame: NSRect
    let link: URL?
}

private struct RenderBlock: Sendable {
    var pieces: [InlinePiece]
    var topMargin: CGFloat
    var bottomMargin: CGFloat
}

private enum InlinePiece: Sendable {
    case text(String, TextStyle, URL?)
    case lineBreak
}

private struct TextStyle: Sendable {
    let size: CGFloat
    let bold: Bool
    let italic: Bool
    let monospaced: Bool

    static let body = TextStyle(size: 15, bold: false, italic: false, monospaced: false)

    static func heading(_ level: Int) -> TextStyle {
        let sizes: [CGFloat] = [28, 24, 21, 18, 16, 15]
        return TextStyle(size: sizes[min(max(level - 1, 0), sizes.count - 1)], bold: true, italic: false, monospaced: false)
    }

    func with(bold: Bool? = nil, italic: Bool? = nil, monospaced: Bool? = nil) -> TextStyle {
        TextStyle(
            size: size,
            bold: bold ?? self.bold,
            italic: italic ?? self.italic,
            monospaced: monospaced ?? self.monospaced
        )
    }

    var font: NSFont {
        var font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}

private final class DocumentFlattener {
    private static let maximumVisibleCharacters = 50_000

    private let baseURL: URL
    private var blocks: [RenderBlock] = []
    private var currentPieces: [InlinePiece] = []
    private var remainingCharacters = maximumVisibleCharacters
    private var didTruncate = false

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func flatten(_ document: HTMLDocument) -> [RenderBlock] {
        let nodes = document.body?.children ?? document.children
        visit(nodes, style: .body, link: nil)
        flush()
        if didTruncate {
            blocks.append(RenderBlock(
                pieces: [.text("[Page text truncated]", .body.with(italic: true), nil)],
                topMargin: 8,
                bottomMargin: 8
            ))
        }
        return blocks
    }

    private func visit(_ nodes: [HTMLNode], style: TextStyle, link: URL?) {
        for node in nodes {
            if withUnsafeCurrentTask(body: { $0?.isCancelled == true }) {
                return
            }
            switch node {
            case let .text(text):
                append(text, style: style, link: link)

            case let .element(element):
                visit(element, inheritedStyle: style, inheritedLink: link)

            case .comment, .doctype:
                continue
            }
        }
    }

    private func append(_ text: String, style: TextStyle, link: URL?) {
        guard remainingCharacters > 0 else {
            if !text.isEmpty { didTruncate = true }
            return
        }

        let count = text.count
        if count <= remainingCharacters {
            currentPieces.append(.text(text, style, link))
            remainingCharacters -= count
        } else {
            currentPieces.append(.text(String(text.prefix(remainingCharacters)), style, link))
            remainingCharacters = 0
            didTruncate = true
        }
    }

    private func visit(_ element: HTMLElement, inheritedStyle: TextStyle, inheritedLink: URL?) {
        let name = element.name

        if Self.hiddenElements.contains(name) {
            return
        }

        if let level = Self.headingLevel(name) {
            flush()
            visit(element.children, style: .heading(level), link: inheritedLink)
            flush(top: 8, bottom: 8)
            return
        }

        if Self.paragraphElements.contains(name) {
            flush()
            if name == "li" {
                currentPieces.append(.text("•", inheritedStyle, nil))
                currentPieces.append(.text(" ", inheritedStyle, nil))
            }
            visit(element.children, style: inheritedStyle, link: inheritedLink)
            flush(top: 3, bottom: 7)
            return
        }

        if Self.containerElements.contains(name) {
            flush()
            visit(element.children, style: inheritedStyle, link: inheritedLink)
            flush()
            return
        }

        switch name {
        case "br":
            currentPieces.append(.lineBreak)
        case "hr":
            flush()
            currentPieces.append(.text("────────────────", inheritedStyle, nil))
            flush(top: 4, bottom: 8)
        case "a":
            let destination = element.attribute("href").flatMap {
                URLResolver.link($0, relativeTo: baseURL)
            }
            visit(element.children, style: inheritedStyle, link: destination ?? inheritedLink)
        case "b", "strong":
            visit(element.children, style: inheritedStyle.with(bold: true), link: inheritedLink)
        case "i", "em":
            visit(element.children, style: inheritedStyle.with(italic: true), link: inheritedLink)
        case "code", "pre", "kbd", "samp":
            visit(element.children, style: inheritedStyle.with(monospaced: true), link: inheritedLink)
        default:
            visit(element.children, style: inheritedStyle, link: inheritedLink)
        }
    }

    private func flush(top: CGFloat = 0, bottom: CGFloat = 0) {
        guard currentPieces.contains(where: { piece in
            if case let .text(text, _, _) = piece { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }) else {
            currentPieces.removeAll(keepingCapacity: true)
            return
        }
        blocks.append(RenderBlock(pieces: currentPieces, topMargin: top, bottomMargin: bottom))
        currentPieces.removeAll(keepingCapacity: true)
    }

    private static func headingLevel(_ name: String) -> Int? {
        guard name.count == 2, name.first == "h", let level = Int(String(name.last!)), (1...6).contains(level) else {
            return nil
        }
        return level
    }

    private static let hiddenElements: Set<String> = [
        "head", "script", "style", "template", "noscript", "svg", "canvas"
    ]

    private static let paragraphElements: Set<String> = [
        "p", "li", "blockquote", "pre", "dt", "dd"
    ]

    private static let containerElements: Set<String> = [
        "html", "body", "main", "article", "section", "div", "header", "footer",
        "nav", "aside", "ul", "ol", "dl", "table", "thead", "tbody", "tfoot",
        "tr", "td", "th"
    ]
}
