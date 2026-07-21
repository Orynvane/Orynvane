public struct HTMLAttribute: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String = "") {
        self.name = name.lowercased()
        self.value = value
    }
}

public struct HTMLElement: Equatable, Sendable {
    public let name: String
    public let attributes: [HTMLAttribute]
    public let children: [HTMLNode]

    public init(
        name: String,
        attributes: [HTMLAttribute] = [],
        children: [HTMLNode] = []
    ) {
        self.name = name.lowercased()

        var seenNames: Set<String> = []
        self.attributes = attributes.filter { attribute in
            seenNames.insert(attribute.name.lowercased()).inserted
        }
        self.children = children
    }

    public func attribute(_ name: String) -> String? {
        let normalizedName = name.lowercased()
        return attributes.first { $0.name == normalizedName }?.value
    }

    public func hasAttribute(_ name: String) -> Bool {
        attribute(name) != nil
    }

    public var textContent: String {
        children.map(\.textContent).joined()
    }
}

public indirect enum HTMLNode: Equatable, Sendable {
    case element(HTMLElement)
    case text(String)
    case comment(String)
    case doctype(String)

    public var children: [HTMLNode] {
        guard case let .element(element) = self else { return [] }
        return element.children
    }

    public var textContent: String {
        switch self {
        case let .element(element):
            return element.textContent
        case let .text(text):
            return text
        case .comment, .doctype:
            return ""
        }
    }

    /// Visits this node and then each child in document order.
    public func walk(_ visit: (HTMLNode) throws -> Void) rethrows {
        try visit(self)
        for child in children {
            try child.walk(visit)
        }
    }

    public func elements(named name: String) -> [HTMLElement] {
        let normalizedName = name.lowercased()
        var matches: [HTMLElement] = []
        walk { node in
            if case let .element(element) = node, element.name == normalizedName {
                matches.append(element)
            }
        }
        return matches
    }
}

public struct HTMLDocument: Equatable, Sendable {
    public let children: [HTMLNode]

    public init(children: [HTMLNode] = []) {
        self.children = children
    }

    public var documentElement: HTMLElement? {
        for child in children {
            if case let .element(element) = child {
                return element
            }
        }
        return nil
    }

    public var head: HTMLElement? {
        firstElement(named: "head")
    }

    public var body: HTMLElement? {
        firstElement(named: "body")
    }

    public var title: String? {
        guard let titleElement = firstElement(named: "title") else { return nil }
        return titleElement.textContent.collapsingHTMLWhitespace()
    }

    /// Visits every node in depth-first document order.
    public func walk(_ visit: (HTMLNode) throws -> Void) rethrows {
        for child in children {
            try child.walk(visit)
        }
    }

    public func elements(named name: String) -> [HTMLElement] {
        let normalizedName = name.lowercased()
        var matches: [HTMLElement] = []
        walk { node in
            if case let .element(element) = node, element.name == normalizedName {
                matches.append(element)
            }
        }
        return matches
    }

    public func firstElement(named name: String) -> HTMLElement? {
        let normalizedName = name.lowercased()
        for child in children {
            if let match = child.firstElement(named: normalizedName) {
                return match
            }
        }
        return nil
    }
}

private extension HTMLNode {
    func firstElement(named normalizedName: String) -> HTMLElement? {
        if case let .element(element) = self {
            if element.name == normalizedName {
                return element
            }
            for child in element.children {
                if let match = child.firstElement(named: normalizedName) {
                    return match
                }
            }
        }
        return nil
    }
}

private extension String {
    func collapsingHTMLWhitespace() -> String {
        var result = ""
        var pendingSpace = false

        for character in self {
            if character.isHTMLWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace {
                    result.append(" ")
                }
                result.append(character)
                pendingSpace = false
            }
        }
        return result
    }
}

extension Character {
    var isHTMLWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{000C}"
    }

    var htmlASCIIValue: UInt32? {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first, scalar.value < 128 else {
            return nil
        }
        return scalar.value
    }

    var isHTMLNameStart: Bool {
        guard let value = htmlASCIIValue else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
    }

    var isHTMLNameCharacter: Bool {
        guard let value = htmlASCIIValue else { return false }
        return isHTMLNameStart || (48...57).contains(value) || value == 45 || value == 58 || value == 95
    }
}
