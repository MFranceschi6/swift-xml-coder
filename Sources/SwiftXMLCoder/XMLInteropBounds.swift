import Foundation

enum XMLInteropBounds {
    static func checkedNonNegativeInt32Length(
        _ value: Int,
        code: String,
        context: String
    ) throws -> Int32 {
        guard value >= 0 else {
            throw XMLParsingError.parseFailed(
                message: "[\(code)] Negative length is invalid for \(context): \(value)."
            )
        }

        let maxLength = Int(Int32.max)
        guard value <= maxLength else {
            throw XMLParsingError.parseFailed(
                message: "[\(code)] Length for \(context) exceeds Int32 max (\(maxLength)): \(value)."
            )
        }

        return Int32(value)
    }
}
