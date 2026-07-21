public enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "apos": "'", "copy": "©", "gt": ">", "hellip": "…",
        "laquo": "«", "ldquo": "“", "lsquo": "‘", "lt": "<", "mdash": "—",
        "nbsp": "\u{00A0}", "ndash": "–", "quot": "\"", "raquo": "»",
        "rdquo": "”", "reg": "®", "rsquo": "’", "trade": "™"
    ]

    /// Decodes the small set of named entities used by ordinary pages, plus
    /// decimal and hexadecimal numeric character references.
    public static func decode(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        var index = 0

        while index < characters.count {
            guard characters[index] == "&",
                  let entity = decodeEntity(in: characters, afterAmpersand: index + 1)
            else {
                result.append(characters[index])
                index += 1
                continue
            }

            result += entity.value
            index = entity.nextIndex
        }
        return result
    }

    private static func decodeEntity(
        in characters: [Character],
        afterAmpersand start: Int
    ) -> (value: String, nextIndex: Int)? {
        guard start < characters.count else { return nil }

        if characters[start] == "#" {
            return decodeNumericEntity(in: characters, start: start + 1)
        }

        var end = start
        while end < characters.count,
              let value = characters[end].htmlASCIIValue,
              (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) {
            end += 1
        }

        guard end > start else { return nil }
        let name = String(characters[start..<end])
        guard let value = named[name] else { return nil }

        if end < characters.count, characters[end] == ";" {
            return (value, end + 1)
        }

        // Browsers also accept common entities without a semicolon when the
        // following character cannot be part of the entity name.
        if end == characters.count || characters[end].isHTMLWhitespace || characters[end] == "<" {
            return (value, end)
        }
        return nil
    }

    private static func decodeNumericEntity(
        in characters: [Character],
        start: Int
    ) -> (value: String, nextIndex: Int)? {
        guard start < characters.count else { return nil }

        var index = start
        var radix: UInt32 = 10
        if characters[index] == "x" || characters[index] == "X" {
            radix = 16
            index += 1
        }
        let digitsStart = index
        var value: UInt32 = 0
        var overflowed = false

        while index < characters.count, let digit = digitValue(characters[index], radix: radix) {
            if value > (UInt32.max - digit) / radix {
                overflowed = true
            } else if !overflowed {
                value = value * radix + digit
            }
            index += 1
        }

        guard index > digitsStart else { return nil }
        if index < characters.count, characters[index] == ";" {
            index += 1
        }

        let replacement = "\u{FFFD}"
        guard !overflowed,
              value != 0,
              !(0xD800...0xDFFF).contains(value),
              value <= 0x10FFFF,
              let scalar = Unicode.Scalar(value)
        else {
            return (replacement, index)
        }
        return (String(scalar), index)
    }

    private static func digitValue(_ character: Character, radix: UInt32) -> UInt32? {
        guard let value = character.htmlASCIIValue else { return nil }
        if (48...57).contains(value) {
            return value - 48
        }
        guard radix == 16 else { return nil }
        if (65...70).contains(value) {
            return value - 55
        }
        if (97...102).contains(value) {
            return value - 87
        }
        return nil
    }
}
