import Foundation

/// A single event emitted by ``XMLStreamParser`` during SAX-style XML parsing.
///
/// `XMLStreamEvent` represents one unit of structure in an XML document.
/// Events are emitted in document order: ``startDocument`` first,
/// ``endDocument`` last, with element, text, CDATA, comment, and processing
/// instruction events interleaved in between.
///
/// ## Usage with XMLStreamParser
///
/// ```swift
/// let parser = XMLStreamParser()
/// try parser.parse(data: xmlData) { event in
///     switch event {
///     case .startElement(let name, _, _):
///         process(name.localName)
///     case .text(let str):
///         process(str)
///     default:
///         break
///     }
/// }
/// ```
///
/// - SeeAlso: ``XMLStreamParser``, ``XMLStreamWriter``
public enum XMLStreamEvent: Sendable, Equatable {

    // MARK: - Document lifecycle

    // swiftlint:disable discouraged_optional_boolean
    /// The XML declaration at the start of the document.
    ///
    /// - Parameters:
    ///   - version: The XML version string (e.g. `"1.0"`), or `nil` if absent.
    ///   - encoding: The declared encoding (e.g. `"UTF-8"`), or `nil` if absent.
    ///   - standalone: The standalone declaration, or `nil` if absent.
    case startDocument(version: String?, encoding: String?, standalone: Bool?)
    // swiftlint:enable discouraged_optional_boolean

    /// The end of the XML document. Always the last event emitted.
    case endDocument

    // MARK: - Elements

    /// An opening element tag.
    ///
    /// - Parameters:
    ///   - name: The qualified name of the element (local name, prefix, namespace URI).
    ///   - attributes: All attributes declared on this element, in document order.
    ///   - namespaceDeclarations: `xmlns:` declarations introduced on this element.
    case startElement(
        name: XMLQualifiedName,
        attributes: [XMLTreeAttribute],
        namespaceDeclarations: [XMLNamespaceDeclaration]
    )

    /// A closing element tag matching the most recent ``startElement``.
    ///
    /// - Parameter name: The qualified name of the element being closed.
    case endElement(name: XMLQualifiedName)

    // MARK: - Content

    /// A text content node.
    ///
    /// Consecutive character data between element tags is delivered as a single
    /// `.text` event. Whitespace handling depends on
    /// ``XMLTreeParser/WhitespaceTextNodePolicy``.
    case text(String)

    /// A CDATA section (`<![CDATA[...]]>`).
    case cdata(String)

    /// An XML comment (`<!-- ... -->`).
    case comment(String)

    /// A processing instruction (`<?target data?>`).
    ///
    /// - Parameters:
    ///   - target: The PI target name (e.g. `"xml-stylesheet"`).
    ///   - data: The PI data string, or `nil` if absent.
    case processingInstruction(target: String, data: String?)
}
