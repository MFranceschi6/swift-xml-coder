import Benchmark
import Foundation
import SwiftXMLCoder

func decodeBenchmarks() {
    let decoder = XMLDecoder()

    Benchmark("Decode/1KB") { benchmark in
        let data = xmlData1KB
        for _ in benchmark.scaledIterations {
            blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
        }
    }

    Benchmark("Decode/10KB") { benchmark in
        let data = xmlData10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
        }
    }

    Benchmark("Decode/100KB") { benchmark in
        let data = xmlData100KB
        for _ in benchmark.scaledIterations {
            blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
        }
    }

    Benchmark("Decode/1MB") { benchmark in
        let data = xmlData1MB
        for _ in benchmark.scaledIterations {
            blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
        }
    }

    // Decode at various sizes (streaming SAX path)
    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB),
        ("1MB", xmlData1MB), ("10MB", xmlData10MB)
    ] {
        Benchmark("Decode/SAX/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
            }
        }
    }

    // Parse-only vs full decode comparison
    let parser = XMLTreeParser()

    Benchmark("ParseOnly/10KB") { benchmark in
        let data = xmlData10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }
}
