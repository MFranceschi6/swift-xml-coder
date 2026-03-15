import Foundation

public enum XMLTreeNode: Sendable, Equatable, Codable {
    case element(XMLTreeElement)
    case text(String)
    case cdata(String)
    case comment(String)
}
