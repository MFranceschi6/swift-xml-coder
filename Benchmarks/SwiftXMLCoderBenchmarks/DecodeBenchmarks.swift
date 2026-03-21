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

    // Parse-only vs full decode comparison
    let parser = XMLTreeParser()

    Benchmark("ParseOnly/10KB") { benchmark in
        let data = xmlData10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }
}
