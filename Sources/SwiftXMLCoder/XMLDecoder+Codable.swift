import Foundation
import Logging

// MARK: - Shared decoder infrastructure
//
// Decode pipeline:
//   XMLDecoder.decode(T.self, from: data)
//     → SAX parse via _XMLStreamingParserSession
//     → _XMLStreamingDecoder processes events inline
//     → _XMLSAXDecoder used as buffered fallback for out-of-order children

extension XMLDecoder {
    // Extension anchor satisfies the '+Codable' file-naming convention.
}

struct _XMLDecoderOptions {
    let itemElementName: String
    let fieldCodingOverrides: XMLFieldCodingOverrides
    let dateDecodingStrategy: XMLDecoder.DateDecodingStrategy
    let dataDecodingStrategy: XMLDecoder.DataDecodingStrategy
    let keyTransformStrategy: XMLKeyTransformStrategy
    let validationPolicy: XMLValidationPolicy
    let logger: Logger
    let userInfo: [CodingUserInfoKey: Any]
    let keyNameCache: _XMLKeyNameCache
    /// Per-property date format hints populated from `XMLDateCodingOverrideProvider`.
    var perPropertyDateHints: [String: XMLDateFormatHint] = [:]

    init(configuration: XMLDecoder.Configuration) {
        self.itemElementName = configuration.itemElementName
        self.fieldCodingOverrides = configuration.fieldCodingOverrides
        self.dateDecodingStrategy = configuration.dateDecodingStrategy
        self.dataDecodingStrategy = configuration.dataDecodingStrategy
        self.keyTransformStrategy = configuration.keyTransformStrategy
        self.validationPolicy = configuration.validationPolicy
        self.logger = configuration.logger
        self.userInfo = configuration.userInfo
        self.keyNameCache = _XMLKeyNameCache()
    }
}

struct _XMLDecodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "Index\(intValue)"
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index\(index)"
        self.intValue = index
    }
}

#if !canImport(Darwin) && swift(<6.0)
/// Hotfix for Linux swift-corelibs-foundation (pre-Swift 6 Foundation rewrite).
///
/// The old Linux URL parser may accept unbalanced IPv6 brackets instead of returning nil,
/// and does not auto-percent-encode spaces (both handled correctly by Swift 6 swift-foundation).
/// Normalises both behaviours so Linux Swift 5 decoding matches macOS and Linux Swift 6+.
internal func _xmlParityDecodeURL(_ lexical: String) -> URL? {
    var balance = 0
    for char in lexical {
        if char == "[" { balance += 1 } else if char == "]" {
            balance -= 1
            if balance < 0 { return nil }
        }
    }
    guard balance == 0 else { return nil }

    if lexical.range(of: " ") != nil {
        let encoded = lexical.replacingOccurrences(of: " ", with: "%20")
        return URL(string: encoded)
    }

    return URL(string: lexical)
}
#endif // !canImport(Darwin) && swift(<6.0)
