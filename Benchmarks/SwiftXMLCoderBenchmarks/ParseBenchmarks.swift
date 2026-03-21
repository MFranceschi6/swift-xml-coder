import Benchmark
import Foundation
import SwiftXMLCoder

func parseBenchmarks() {
    let parser = XMLTreeParser()

    Benchmark("Parse/1KB") { benchmark in
        let data = xmlData1KB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }

    Benchmark("Parse/10KB") { benchmark in
        let data = xmlData10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }

    Benchmark("Parse/100KB") { benchmark in
        let data = xmlData100KB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }

    Benchmark("Parse/1MB") { benchmark in
        let data = xmlData1MB
        for _ in benchmark.scaledIterations {
            blackHole(try? parser.parse(data: data))
        }
    }
}
