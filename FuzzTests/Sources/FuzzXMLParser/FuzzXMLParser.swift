import Foundation
import SwiftXMLCoder

// Fuzz harness for XMLTreeParser.parse(data:).
//
// libFuzzer calls LLVMFuzzerTestOneInput repeatedly with generated inputs.
// Invariant: any byte sequence must either produce a valid XMLTreeDocument
// or throw a typed XMLParsingError — never crash, abort, or leak memory.
//
// Build + run via: FuzzTests/run_fuzzer.sh FuzzXMLParser
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzXMLParser(_ start: UnsafePointer<UInt8>?, _ count: Int) -> Int32 {
    guard let start, count > 0 else { return 0 }
    let data = Data(bytes: start, count: count)
    _ = try? XMLTreeParser().parse(data: data)
    return 0
}
