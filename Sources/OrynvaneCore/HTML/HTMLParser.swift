public enum HTMLToken: Equatable, Sendable {
    case startTag(name: String, attributes: [HTMLAttribute], selfClosing: Bool)
    case endTag(name: String)
    case text(String)
    case comment(String)
    case doctype(String)
}

public struct HTMLTokenizer: Sendable {
    private let source: [Character]
    private var position = 0
    private var rawTextTag: String?

    public init(_ source: String) {
        self.source = Array(source)
    }

    public mutating func tokenize() -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        while let token = nextToken() {
            tokens.append(token)
        }
        return tokens
    }

    public mutating func nextToken() -> HTMLToken? {
        guard position < source.count else { return nil }

        if let rawTextTag {
            if let closingStart = findRawTextClosingTag(named: rawTextTag) {
                self.rawTextTag = nil
                if closingStart > position {
                    let text = String(source[position..<closingStart])
                    position = closingStart
                    return .text(text)
                }
            } else {
                self.rawTextTag = nil
                let text = String(source[position...])
                position = source.count
                return .text(text)
            }
        }

        if source[position] != "<" {
            let start = position
            while position < source.count, source[position] != "<" {
                position += 1
            }
            return .text(HTMLEntities.decode(String(source[start..<position])))
        }

        if matches("<!--", at: position) {
            return readComment()
        }
        if matches("</", at: position),
           position + 2 < source.count,
           source[position + 2].isHTMLNameStart {
            return readEndTag()
        }
        if matches("<!", at: position) {
            return readDeclaration()
        }
        if matches("<?", at: position) {
            return readProcessingInstruction()
        }
        if position + 1 < source.count, source[position + 1].isHTMLNameStart {
            return readStartTag()
        }

        position += 1
        return .text("<")
    }

    private mutating func readComment() -> HTMLToken {
        position += 4
        let start = position
        while position < source.count, !matches("-->", at: position) {
            position += 1
        }
        let text = String(source[start..<position])
        position = matches("-->", at: position) ? position + 3 : source.count
        return .comment(text)
    }

    private mutating func readDeclaration() -> HTMLToken {
        position += 2
        let start = position
        while position < source.count, source[position] != ">" {
            position += 1
        }
        var value = String(source[start..<position]).trimmingHTMLWhitespace()
        if position < source.count {
            position += 1
        }

        if value.lowercased().hasPrefix("doctype") {
            value = String(value.dropFirst(7)).trimmingHTMLWhitespace()
            return .doctype(value)
        }
        return .comment(value)
    }

    private mutating func readProcessingInstruction() -> HTMLToken {
        position += 2
        let start = position
        while position < source.count, source[position] != ">" {
            position += 1
        }
        let value = String(source[start..<position])
        if position < source.count {
            position += 1
        }
        return .comment(value)
    }

    private mutating func readEndTag() -> HTMLToken {
        position += 2
        let start = position
        while position < source.count, source[position].isHTMLNameCharacter {
            position += 1
        }
        let name = String(source[start..<position]).lowercased()
        while position < source.count, source[position] != ">" {
            position += 1
        }
        if position < source.count {
            position += 1
        }
        return .endTag(name: name)
    }

    private mutating func readStartTag() -> HTMLToken {
        position += 1
        let nameStart = position
        while position < source.count, source[position].isHTMLNameCharacter {
            position += 1
        }
        let name = String(source[nameStart..<position]).lowercased()
        var attributes: [HTMLAttribute] = []
        var selfClosing = false

        while position < source.count {
            skipWhitespace()
            guard position < source.count else { break }

            if source[position] == ">" {
                position += 1
                break
            }
            if source[position] == "/", position + 1 < source.count, source[position + 1] == ">" {
                selfClosing = true
                position += 2
                break
            }

            let attributeStart = position
            while position < source.count,
                  !source[position].isHTMLWhitespace,
                  source[position] != "=",
                  source[position] != ">",
                  source[position] != "/" {
                position += 1
            }

            if position == attributeStart {
                position += 1
                continue
            }

            let attributeName = String(source[attributeStart..<position]).lowercased()
            skipWhitespace()
            var value = ""
            if position < source.count, source[position] == "=" {
                position += 1
                skipWhitespace()
                value = readAttributeValue()
            }
            attributes.append(HTMLAttribute(name: attributeName, value: value))
        }

        if !selfClosing, name == "script" || name == "style" {
            rawTextTag = name
        }
        return .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    private mutating func readAttributeValue() -> String {
        guard position < source.count else { return "" }

        if source[position] == "\"" || source[position] == "'" {
            let quote = source[position]
            position += 1
            let start = position
            while position < source.count, source[position] != quote {
                position += 1
            }
            let value = HTMLEntities.decode(String(source[start..<position]))
            if position < source.count {
                position += 1
            }
            return value
        }

        let start = position
        while position < source.count,
              !source[position].isHTMLWhitespace,
              source[position] != ">" {
            position += 1
        }
        return HTMLEntities.decode(String(source[start..<position]))
    }

    private mutating func skipWhitespace() {
        while position < source.count, source[position].isHTMLWhitespace {
            position += 1
        }
    }

    private func findRawTextClosingTag(named name: String) -> Int? {
        var candidate = position
        while candidate + name.count + 2 <= source.count {
            guard source[candidate] == "<", candidate + 1 < source.count, source[candidate + 1] == "/" else {
                candidate += 1
                continue
            }

            let nameStart = candidate + 2
            let nameEnd = nameStart + name.count
            guard nameEnd <= source.count,
                  String(source[nameStart..<nameEnd]).lowercased() == name
            else {
                candidate += 1
                continue
            }

            if nameEnd == source.count || source[nameEnd] == ">" || source[nameEnd].isHTMLWhitespace {
                return candidate
            }
            candidate += 1
        }
        return nil
    }

    private func matches(_ literal: String, at index: Int) -> Bool {
        let literalCharacters = Array(literal)
        guard index + literalCharacters.count <= source.count else { return false }
        return Array(source[index..<(index + literalCharacters.count)]) == literalCharacters
    }
}

public struct HTMLParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> HTMLDocument {
        var tokenizer = HTMLTokenizer(source)
        var roots: [HTMLNode] = []
        var stack: [ElementBuilder] = []

        func append(_ node: HTMLNode) {
            if let parent = stack.last {
                parent.append(node)
            } else {
                appendMergingText(node, to: &roots)
            }
        }

        func closeTopElement() {
            guard let builder = stack.popLast() else { return }
            append(.element(builder.element))
        }

        while let token = tokenizer.nextToken() {
            if withUnsafeCurrentTask(body: { $0?.isCancelled == true }) {
                break
            }
            switch token {
            case let .startTag(name, attributes, selfClosing):
                implicitlyCloseElement(ifNeededBefore: name, stack: &stack, closeTop: closeTopElement)
                let builder = ElementBuilder(name: name, attributes: attributes)
                if selfClosing || Self.voidElements.contains(name) {
                    append(.element(builder.element))
                } else if stack.count < Self.maximumNestingDepth {
                    stack.append(builder)
                }

            case let .endTag(name):
                guard let matchingIndex = stack.lastIndex(where: { $0.name == name }) else { continue }
                while stack.count > matchingIndex {
                    closeTopElement()
                }

            case let .text(text):
                if !text.isEmpty {
                    append(.text(text))
                }

            case let .comment(comment):
                append(.comment(comment))

            case let .doctype(name):
                append(.doctype(name))
            }
        }

        while !stack.isEmpty {
            closeTopElement()
        }
        return HTMLDocument(children: roots)
    }

    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// Keeps later DOM traversal safely below the process stack limit.
    private static let maximumNestingDepth = 256

    private func implicitlyCloseElement(
        ifNeededBefore name: String,
        stack: inout [ElementBuilder],
        closeTop: () -> Void
    ) {
        let repeatedElementNames: Set<String> = ["li", "option", "p", "tr"]
        let closesTableCell = (name == "td" || name == "th")
        let matchingIndex: Int?

        if repeatedElementNames.contains(name) {
            matchingIndex = stack.lastIndex { $0.name == name }
        } else if closesTableCell {
            matchingIndex = stack.lastIndex { $0.name == "td" || $0.name == "th" }
        } else {
            matchingIndex = nil
        }

        guard let matchingIndex else { return }
        while stack.count > matchingIndex {
            closeTop()
        }
    }
}

private final class ElementBuilder {
    let name: String
    let attributes: [HTMLAttribute]
    private var children: [HTMLNode] = []

    init(name: String, attributes: [HTMLAttribute]) {
        self.name = name
        self.attributes = attributes
    }

    func append(_ node: HTMLNode) {
        appendMergingText(node, to: &children)
    }

    var element: HTMLElement {
        HTMLElement(name: name, attributes: attributes, children: children)
    }
}

private func appendMergingText(_ node: HTMLNode, to nodes: inout [HTMLNode]) {
    if case let .text(newText) = node,
       case let .text(existingText)? = nodes.last {
        nodes[nodes.count - 1] = .text(existingText + newText)
    } else {
        nodes.append(node)
    }
}

private extension String {
    func trimmingHTMLWhitespace() -> String {
        var characters = Array(self)
        while characters.first?.isHTMLWhitespace == true {
            characters.removeFirst()
        }
        while characters.last?.isHTMLWhitespace == true {
            characters.removeLast()
        }
        return String(characters)
    }
}
