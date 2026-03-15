import Foundation
import XMLCoderCompatibility

extension XMLCanonicalizationContract {
    public static func transformFailure(
        transformIndex: Int,
        transformType: String,
        underlyingError: XMLAnyError?,
        code: XMLCanonicalizationErrorCode = .transformFailed,
        message: String? = nil
    ) -> XMLCanonicalizationError {
        let resolvedMessage = message ?? """
        [\(code.rawValue)] Transform #\(transformIndex) '\(transformType)' failed.
        """
        return .transformFailed(
            code: code,
            transformIndex: transformIndex,
            transformType: transformType,
            underlyingError: underlyingError,
            message: resolvedMessage
        )
    }

    public static func serializationFailure(
        underlyingError: XMLAnyError?,
        code: XMLCanonicalizationErrorCode = .serializationFailed,
        message: String? = nil
    ) -> XMLCanonicalizationError {
        let resolvedMessage = message ?? """
        [\(code.rawValue)] Unable to serialize canonical XML document.
        """
        return .serializationFailed(
            code: code,
            underlyingError: underlyingError,
            message: resolvedMessage
        )
    }

    public static func unexpectedFailure(
        underlyingError: XMLAnyError?,
        code: XMLCanonicalizationErrorCode = .unexpected,
        message: String? = nil
    ) -> XMLCanonicalizationError {
        let resolvedMessage = message ?? "[\(code.rawValue)] Unexpected canonicalization error."
        return .other(
            code: code,
            underlyingError: underlyingError,
            message: resolvedMessage
        )
    }
}

#if swift(>=6.0)
extension XMLCanonicalizationContract {
    public static func applyTransforms(
        to document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws(XMLCanonicalizationError) -> XMLTreeDocument {
        var transformedDocument = document

        for (transformIndex, transform) in transforms.enumerated() {
            do {
                transformedDocument = try transform.apply(to: transformedDocument, options: options)
            } catch let error as XMLCanonicalizationError {
                throw error
            } catch {
                let transformType = String(reflecting: type(of: transform))
                throw transformFailure(
                    transformIndex: transformIndex,
                    transformType: transformType,
                    underlyingError: error
                )
            }
        }

        return transformedDocument
    }
}
#else
extension XMLCanonicalizationContract {
    public static func applyTransforms(
        to document: XMLTreeDocument,
        options: XMLNormalizationOptions,
        transforms: XMLTransformPipeline
    ) throws -> XMLTreeDocument {
        var transformedDocument = document

        for (transformIndex, transform) in transforms.enumerated() {
            do {
                transformedDocument = try transform.apply(to: transformedDocument, options: options)
            } catch let error as XMLCanonicalizationError {
                throw error
            } catch {
                let transformType = String(reflecting: type(of: transform))
                throw transformFailure(
                    transformIndex: transformIndex,
                    transformType: transformType,
                    underlyingError: error
                )
            }
        }

        return transformedDocument
    }
}
#endif
