import Foundation
import SwiftXMLCoder

public struct XMLTestRecordingTransform: XMLTransform {
    public let token: String
    public let recorder: XMLTestCallRecorder

    public init(token: String, recorder: XMLTestCallRecorder) {
        self.token = token
        self.recorder = recorder
    }

    public func apply(
        to document: XMLTreeDocument,
        options _: XMLNormalizationOptions
    ) throws -> XMLTreeDocument {
        recorder.record(token)
        return appendingTraceToken(token, to: document)
    }

    private func appendingTraceToken(_ token: String, to document: XMLTreeDocument) -> XMLTreeDocument {
        let traceName = XMLQualifiedName(localName: "trace")
        var attributes = document.root.attributes

        if let existingIndex = attributes.firstIndex(where: { $0.name == traceName }) {
            let previousValue = attributes[existingIndex].value
            attributes[existingIndex] = XMLTreeAttribute(
                name: traceName,
                value: previousValue + token
            )
        } else {
            attributes.append(XMLTreeAttribute(name: traceName, value: token))
        }

        let root = XMLTreeElement(
            name: document.root.name,
            attributes: attributes,
            namespaceDeclarations: document.root.namespaceDeclarations,
            children: document.root.children,
            metadata: document.root.metadata
        )
        return XMLTreeDocument(root: root, metadata: document.metadata)
    }
}
