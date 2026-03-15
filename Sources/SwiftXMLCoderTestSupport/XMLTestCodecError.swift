import Foundation

public enum XMLTestCodecError: Error, Equatable {
    case forcedFailure(message: String)
    case invalidStubbedValue(expectedType: String, actualType: String)
}
