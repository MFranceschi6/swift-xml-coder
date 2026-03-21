import Foundation
import SwiftXMLCoder

// Fuzz harness for the full XMLDecoder pipeline (parse → tree → Codable).
//
// The payload type intentionally uses Optional fields so the decoder can
// exercise both the "key found" and "key absent → nil" paths without
// throwing on missing keys.
//
// Invariant: any byte sequence must produce either a decoded FuzzPayload
// or a typed XMLParsingError — never crash, abort, or leak memory.
//
// Build + run via: FuzzTests/run_fuzzer.sh FuzzXMLDecoder

private struct FuzzNested: Decodable {
    let x: Double?
    let flag: Bool?
}

private struct FuzzPayload: Decodable {
    let id: String?
    let value: Int?
    let items: [String]?
    let nested: FuzzNested?
}

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzXMLDecoder(_ start: UnsafePointer<UInt8>?, _ count: Int) -> Int32 {
    guard let start, count > 0 else { return 0 }
    let data = Data(bytes: start, count: count)
    let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
    _ = try? decoder.decode(FuzzPayload.self, from: data)
    return 0
}
