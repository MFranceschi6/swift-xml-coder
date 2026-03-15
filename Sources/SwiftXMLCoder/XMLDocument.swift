import Foundation
import Logging
import XMLCoderCompatibility
#if swift(>=6.0)
import SwiftXMLCoderOwnership6
#endif

// swiftlint:disable type_body_length
public struct XMLDocument: Sendable {
    public struct ParsingConfiguration: Sendable, Hashable {
        public enum ExternalResourceLoadingPolicy: Sendable, Hashable {
            case forbidNetwork
            case allowNetwork
        }

        public enum DTDLoadingPolicy: Sendable, Hashable {
            case forbid
            case allow
        }

        public enum EntityDecodingPolicy: Sendable, Hashable {
            case preserveReferences
            case substituteEntities
        }

        public let trimBlankTextNodes: Bool
        public let externalResourceLoadingPolicy: ExternalResourceLoadingPolicy
        public let dtdLoadingPolicy: DTDLoadingPolicy
        public let entityDecodingPolicy: EntityDecodingPolicy

        public init(
            trimBlankTextNodes: Bool = true,
            externalResourceLoadingPolicy: ExternalResourceLoadingPolicy = .forbidNetwork,
            dtdLoadingPolicy: DTDLoadingPolicy = .forbid,
            entityDecodingPolicy: EntityDecodingPolicy = .preserveReferences
        ) {
            self.trimBlankTextNodes = trimBlankTextNodes
            self.externalResourceLoadingPolicy = externalResourceLoadingPolicy
            self.dtdLoadingPolicy = dtdLoadingPolicy
            self.entityDecodingPolicy = entityDecodingPolicy
        }

        fileprivate var libxmlOptions: Int32 {
            var options: Int32 = 0

            if trimBlankTextNodes {
                options |= Int32(XML_PARSE_NOBLANKS.rawValue)
            }

            if externalResourceLoadingPolicy == .forbidNetwork {
                options |= Int32(XML_PARSE_NONET.rawValue)
            }

            if dtdLoadingPolicy == .allow {
                options |= Int32(XML_PARSE_DTDLOAD.rawValue)
            }

            if entityDecodingPolicy == .substituteEntities {
                options |= Int32(XML_PARSE_NOENT.rawValue)
            }

            return options
        }
    }

    private final class Storage: @unchecked Sendable {
        let documentPointer: xmlDocPtr

        init(documentPointer: xmlDocPtr) {
            self.documentPointer = documentPointer
        }

        deinit {
            xmlFreeDoc(documentPointer)
        }
    }

    private let storage: Storage
    private let logger: Logger

    #if swift(>=6.0)
    public init(rootElementName: String, logger: Logger? = nil) throws(XMLParsingError) {
        do {
            try self.init(createDocument: rootElementName, rootNamespace: nil, logger: logger ?? Self.defaultLogger())
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML document creation error.")
        }
    }

    public init(rootElementName: String, rootNamespace: XMLNamespace, logger: Logger? = nil) throws(XMLParsingError) {
        do {
            try self.init(
                createDocument: rootElementName,
                rootNamespace: rootNamespace as XMLNamespace?,
                logger: logger ?? Self.defaultLogger()
            )
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML document creation error.")
        }
    }

    public init(
        data: Data,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws(XMLParsingError) {
        do {
            try self.init(
                parseDocument: data,
                sourceURL: nil,
                parsingConfiguration: parsingConfiguration,
                logger: logger ?? Self.defaultLogger()
            )
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML parsing error.")
        }
    }

    public init(
        data: Data,
        sourceURL: URL,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws(XMLParsingError) {
        do {
            try self.init(
                parseDocument: data,
                sourceURL: sourceURL,
                parsingConfiguration: parsingConfiguration,
                logger: logger ?? Self.defaultLogger()
            )
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML parsing error.")
        }
    }

    public init(
        url: URL,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws(XMLParsingError) {
        let effectiveLogger: Logger = logger ?? Self.defaultLogger()

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XMLParsingError.other(
                underlyingError: error,
                message: "Unable to load XML data from URL '\(url.absoluteString)'."
            )
        }

        do {
            try self.init(
                parseDocument: data,
                sourceURL: url,
                parsingConfiguration: parsingConfiguration,
                logger: effectiveLogger
            )
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML parsing error.")
        }
    }
    #else
    public init(rootElementName: String, logger: Logger? = nil) throws {
        try self.init(createDocument: rootElementName, rootNamespace: nil, logger: logger ?? Self.defaultLogger())
    }

    public init(rootElementName: String, rootNamespace: XMLNamespace, logger: Logger? = nil) throws {
        try self.init(
            createDocument: rootElementName,
            rootNamespace: rootNamespace as XMLNamespace?,
            logger: logger ?? Self.defaultLogger()
        )
    }

    public init(
        data: Data,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws {
        try self.init(
            parseDocument: data,
            sourceURL: nil,
            parsingConfiguration: parsingConfiguration,
            logger: logger ?? Self.defaultLogger()
        )
    }

    public init(
        data: Data,
        sourceURL: URL,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws {
        try self.init(
            parseDocument: data,
            sourceURL: sourceURL,
            parsingConfiguration: parsingConfiguration,
            logger: logger ?? Self.defaultLogger()
        )
    }

    public init(
        url: URL,
        parsingConfiguration: ParsingConfiguration = ParsingConfiguration(),
        logger: Logger? = nil
    ) throws {
        let effectiveLogger: Logger = logger ?? Self.defaultLogger()

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XMLParsingError.other(
                underlyingError: error,
                message: "Unable to load XML data from URL '\(url.absoluteString)'."
            )
        }
        try self.init(
            parseDocument: data,
            sourceURL: url,
            parsingConfiguration: parsingConfiguration,
            logger: effectiveLogger
        )
    }
    #endif

    private init(createDocument rootElementName: String, rootNamespace: XMLNamespace?, logger: Logger) throws {
        LibXML2.ensureInitialized()

        self.logger = logger

        let documentPointer = LibXML2.withXMLCharPointer("1.0") { versionPointer in
            xmlNewDoc(versionPointer)
        }
        guard let documentPointer = documentPointer else {
            throw XMLParsingError.documentCreationFailed(message: "Unable to allocate XML document.")
        }

        guard let rootElement = try XMLDocument.makeNode(named: rootElementName, namespace: rootNamespace) else {
            xmlFreeDoc(documentPointer)
            throw XMLParsingError.nodeCreationFailed(name: rootElementName, message: "Unable to create root element.")
        }

        xmlDocSetRootElement(documentPointer, rootElement)
        self.storage = Storage(documentPointer: documentPointer)
    }

    private init(
        parseDocument data: Data,
        sourceURL: URL?,
        parsingConfiguration: ParsingConfiguration,
        logger: Logger
    ) throws {
        LibXML2.ensureInitialized()

        self.logger = logger

        let options = parsingConfiguration.libxmlOptions
        let byteCount = try XMLInteropBounds.checkedNonNegativeInt32Length(
            data.count,
            code: "XML6_2H_INT32_INPUT_LENGTH",
            context: "xmlReadMemory input"
        )

        let documentPointer: xmlDocPtr? = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            // libxml2 expects a C char buffer; we pass bytes and length.
            let bufferPointer = baseAddress.assumingMemoryBound(to: CChar.self)

            if let sourceURL = sourceURL {
                return sourceURL.absoluteString.withCString { urlCString in
                    xmlReadMemory(bufferPointer, byteCount, urlCString, nil, options)
                }
            } else {
                return xmlReadMemory(bufferPointer, byteCount, nil, nil, options)
            }
        }

        guard let documentPointer = documentPointer else {
            // Best-effort: attempt to read libxml2's last error.
            let lastErrorPointer = xmlGetLastError()
            let message: String?
            if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = nil
            }

            logger.debug("XML parse failed", metadata: [
                "byteCount": "\(data.count)"
            ])
            throw XMLParsingError.parseFailed(message: message)
        }

        self.storage = Storage(documentPointer: documentPointer)
    }

    public func rootElement() -> XMLNode? {
        guard let nodePointer = xmlDocGetRootElement(storage.documentPointer) else {
            return nil
        }
        return XMLNode(nodePointer: nodePointer)
    }

    #if swift(>=6.0)
    public func xpathFirstNode(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws(XMLParsingError) -> XMLNode? {
        do {
            return try xpathFirstNodeImpl(expression, namespaces: namespaces)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XPath evaluation error.")
        }
    }
    #else
    public func xpathFirstNode(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws -> XMLNode? {
        try xpathFirstNodeImpl(expression, namespaces: namespaces)
    }
    #endif

    private func xpathFirstNodeImpl(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws -> XMLNode? {
        #if swift(>=6.0)
        logger.trace("Evaluating XPath expression", metadata: [
            "expression": "\(expression)"
        ])

        let nodeResult: XMLNode?? = try SwiftXMLCoderOwnership6.withOwnedXPathContextPointer(
            documentPointer: storage.documentPointer
        ) { contextPointer in
            try registerNamespaces(namespaces, expression: expression, contextPointer: contextPointer)

            let resultPointer = LibXML2.withXMLCharPointer(expression) { expressionPointer in
                xmlXPathEvalExpression(expressionPointer, contextPointer)
            }
            guard let resultPointer = resultPointer else {
                let lastErrorPointer = xmlGetLastError()
                let message: String?
                if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                    message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    message = nil
                }
                throw XMLParsingError.xpathFailed(expression: expression, message: message)
            }

            let resolvedNodeResult: XMLNode?? = SwiftXMLCoderOwnership6.withOwnedXPathObjectPointer(resultPointer) { resultPointer in
                guard let nodeSetPointer = resultPointer.pointee.nodesetval else {
                    return nil
                }

                let nodeCount = Int(nodeSetPointer.pointee.nodeNr)
                guard nodeCount > 0 else {
                    return nil
                }

                guard let nodePointer = nodeSetPointer.pointee.nodeTab[0] else {
                    return nil
                }

                return XMLNode(nodePointer: nodePointer)
            }
            return resolvedNodeResult ?? nil
        }

        guard let nodeResult = nodeResult else {
            throw XMLParsingError.xpathFailed(expression: expression, message: "Unable to create XPath context.")
        }

        return nodeResult
        #else
        logger.trace("Evaluating XPath expression", metadata: [
            "expression": "\(expression)"
        ])

        let contextPointer = xmlXPathNewContext(storage.documentPointer)
        guard let contextPointer = contextPointer else {
            throw XMLParsingError.xpathFailed(expression: expression, message: "Unable to create XPath context.")
        }
        defer { xmlXPathFreeContext(contextPointer) }

        try registerNamespaces(namespaces, expression: expression, contextPointer: contextPointer)

        let resultPointer = LibXML2.withXMLCharPointer(expression) { expressionPointer in
            xmlXPathEvalExpression(expressionPointer, contextPointer)
        }
        guard let resultPointer = resultPointer else {
            let lastErrorPointer = xmlGetLastError()
            let message: String?
            if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = nil
            }
            throw XMLParsingError.xpathFailed(expression: expression, message: message)
        }
        defer { xmlXPathFreeObject(resultPointer) }

        guard let nodeSetPointer = resultPointer.pointee.nodesetval else {
            return nil
        }

        let nodeCount = Int(nodeSetPointer.pointee.nodeNr)
        guard nodeCount > 0 else {
            return nil
        }

        guard let nodePointer = nodeSetPointer.pointee.nodeTab[0] else {
            return nil
        }

        return XMLNode(nodePointer: nodePointer)
        #endif
    }

    #if swift(>=6.0)
    public func xpathNodes(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws(XMLParsingError) -> [XMLNode] {
        do {
            return try xpathNodesImpl(expression, namespaces: namespaces)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XPath evaluation error.")
        }
    }
    #else
    public func xpathNodes(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws -> [XMLNode] {
        try xpathNodesImpl(expression, namespaces: namespaces)
    }
    #endif

    private func xpathNodesImpl(
        _ expression: String,
        namespaces: [String: String] = [:]
    ) throws -> [XMLNode] {
        #if swift(>=6.0)
        let resolvedNodes: [XMLNode]? = try SwiftXMLCoderOwnership6.withOwnedXPathContextPointer(
            documentPointer: storage.documentPointer
        ) { contextPointer in
            try registerNamespaces(namespaces, expression: expression, contextPointer: contextPointer)

            let resultPointer = LibXML2.withXMLCharPointer(expression) { expressionPointer in
                xmlXPathEvalExpression(expressionPointer, contextPointer)
            }
            guard let resultPointer = resultPointer else {
                let lastErrorPointer = xmlGetLastError()
                let message: String?
                if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                    message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    message = nil
                }
                throw XMLParsingError.xpathFailed(expression: expression, message: message)
            }

            let resolvedNodes: [XMLNode]? = SwiftXMLCoderOwnership6.withOwnedXPathObjectPointer(resultPointer) { resultPointer in
                guard let nodeSetPointer = resultPointer.pointee.nodesetval else {
                    return []
                }

                let nodeCount = Int(nodeSetPointer.pointee.nodeNr)
                guard nodeCount > 0 else {
                    return []
                }

                return (0..<nodeCount).compactMap { index in
                    guard let nodePointer = nodeSetPointer.pointee.nodeTab[index] else {
                        return nil
                    }
                    return XMLNode(nodePointer: nodePointer)
                }
            }

            guard let resolvedNodes = resolvedNodes else {
                throw XMLParsingError.xpathFailed(
                    expression: expression,
                    message: "Unable to evaluate XPath expression."
                )
            }

            return resolvedNodes
        }

        guard let resolvedNodes = resolvedNodes else {
            throw XMLParsingError.xpathFailed(expression: expression, message: "Unable to create XPath context.")
        }

        return resolvedNodes
        #else
        let contextPointer = xmlXPathNewContext(storage.documentPointer)
        guard let contextPointer = contextPointer else {
            throw XMLParsingError.xpathFailed(expression: expression, message: "Unable to create XPath context.")
        }
        defer { xmlXPathFreeContext(contextPointer) }

        try registerNamespaces(namespaces, expression: expression, contextPointer: contextPointer)

        let resultPointer = LibXML2.withXMLCharPointer(expression) { expressionPointer in
            xmlXPathEvalExpression(expressionPointer, contextPointer)
        }
        guard let resultPointer = resultPointer else {
            let lastErrorPointer = xmlGetLastError()
            let message: String?
            if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = nil
            }
            throw XMLParsingError.xpathFailed(expression: expression, message: message)
        }
        defer { xmlXPathFreeObject(resultPointer) }

        guard let nodeSetPointer = resultPointer.pointee.nodesetval else {
            return []
        }

        let nodeCount = Int(nodeSetPointer.pointee.nodeNr)
        guard nodeCount > 0 else {
            return []
        }

        return (0..<nodeCount).compactMap { index in
            guard let nodePointer = nodeSetPointer.pointee.nodeTab[index] else {
                return nil
            }
            return XMLNode(nodePointer: nodePointer)
        }
        #endif
    }

    #if swift(>=6.0)
    public func serializedData(encoding: String = "UTF-8", prettyPrinted: Bool = false) throws(XMLParsingError) -> Data {
        do {
            return try serializedDataImpl(encoding: encoding, prettyPrinted: prettyPrinted)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML serialization error.")
        }
    }
    #else
    public func serializedData(encoding: String = "UTF-8", prettyPrinted: Bool = false) throws -> Data {
        try serializedDataImpl(encoding: encoding, prettyPrinted: prettyPrinted)
    }
    #endif

    private func serializedDataImpl(encoding: String = "UTF-8", prettyPrinted: Bool = false) throws -> Data {
        var bufferPointer: UnsafeMutablePointer<xmlChar>?
        var size: Int32 = 0
        let format: Int32 = prettyPrinted ? 1 : 0

        encoding.withCString { encodingCString in
            xmlDocDumpFormatMemoryEnc(storage.documentPointer, &bufferPointer, &size, encodingCString, format)
        }

        guard let bufferPointer = bufferPointer, size >= 0 else {
            let lastErrorPointer = xmlGetLastError()
            let message: String?
            if let lastErrorPointer = lastErrorPointer, let errorMessagePointer = lastErrorPointer.pointee.message {
                message = String(cString: errorMessagePointer).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = nil
            }
            throw XMLParsingError.other(underlyingError: nil, message: message ?? "XML serialization failed.")
        }

        let serializedData = LibXML2.withOwnedXMLCharPointer(bufferPointer, { pointer in
            Data(bytes: pointer, count: Int(size))
        })
        guard let serializedData = serializedData else {
            throw XMLParsingError.other(underlyingError: nil, message: "XML serialization failed.")
        }
        return serializedData
    }

    #if swift(>=6.0)
    public func createElement(named name: String, namespace: XMLNamespace? = nil) throws(XMLParsingError) -> XMLNode {
        do {
            return try createElementImpl(named: name, namespace: namespace)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML node creation error.")
        }
    }
    #else
    public func createElement(named name: String, namespace: XMLNamespace? = nil) throws -> XMLNode {
        try createElementImpl(named: name, namespace: namespace)
    }
    #endif

    private func createElementImpl(named name: String, namespace: XMLNamespace? = nil) throws -> XMLNode {
        guard let nodePointer = try XMLDocument.makeNode(named: name, namespace: namespace) else {
            throw XMLParsingError.nodeCreationFailed(name: name, message: "Unable to create XML element.")
        }
        return XMLNode(nodePointer: nodePointer)
    }

    #if swift(>=6.0)
    public func appendChild(_ child: XMLNode, to parent: XMLNode) throws(XMLParsingError) {
        do {
            try appendChildImpl(child, to: parent)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML child append error.")
        }
    }
    #else
    public func appendChild(_ child: XMLNode, to parent: XMLNode) throws {
        try appendChildImpl(child, to: parent)
    }
    #endif

    private func appendChildImpl(_ child: XMLNode, to parent: XMLNode) throws {
        try parent.addChild(child)
    }

    private func registerNamespaces(
        _ namespaces: [String: String],
        expression: String,
        contextPointer: xmlXPathContextPtr
    ) throws {
        for (prefix, uri) in namespaces {
            try LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                try LibXML2.withXMLCharPointer(uri) { uriPointer in
                    let result = xmlXPathRegisterNs(contextPointer, prefixPointer, uriPointer)
                    if result != 0 {
                        throw XMLParsingError.xpathFailed(
                            expression: expression,
                            message: "Unable to register namespace prefix '\(prefix)'."
                        )
                    }
                }
            }
        }
    }

    private static func makeNode(named name: String, namespace: XMLNamespace?) throws -> xmlNodePtr? {
        let nodePointer = LibXML2.withXMLCharPointer(name) { namePointer in
            xmlNewNode(nil, namePointer)
        }

        guard let nodePointer = nodePointer else {
            return nil
        }

        if let namespace = namespace {
            if namespace.prefix != nil && namespace.uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                xmlFreeNode(nodePointer)
                throw XMLParsingError.invalidNamespaceConfiguration(prefix: namespace.prefix, uri: namespace.uri)
            }

            let namespacePointer = LibXML2.withXMLCharPointer(namespace.uri) { uriPointer -> xmlNsPtr? in
                if let prefix = namespace.prefix {
                    return LibXML2.withXMLCharPointer(prefix) { prefixPointer in
                        xmlNewNs(nodePointer, uriPointer, prefixPointer)
                    }
                } else {
                    return xmlNewNs(nodePointer, uriPointer, nil)
                }
            }

            guard let namespacePointer = namespacePointer else {
                xmlFreeNode(nodePointer)
                throw XMLParsingError.nodeOperationFailed(
                    message: "Unable to assign namespace '\(namespace.uri)' to element '\(name)'."
                )
            }

            xmlSetNs(nodePointer, namespacePointer)
        }

        return nodePointer
    }

    private static func defaultLogger() -> Logger {
        Logger(label: "com.swift-xml-coder.SwiftXMLCoder")
    }
}
// swiftlint:enable type_body_length
