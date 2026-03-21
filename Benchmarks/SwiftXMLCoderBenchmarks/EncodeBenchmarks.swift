import Benchmark
import Foundation
import SwiftXMLCoder

func encodeBenchmarks() {
    let encoder = XMLEncoder()

    Benchmark("Encode/1KB") { benchmark in
        let value = collection1KB
        for _ in benchmark.scaledIterations {
            blackHole(try? encoder.encode(value))
        }
    }

    Benchmark("Encode/10KB") { benchmark in
        let value = collection10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? encoder.encode(value))
        }
    }

    Benchmark("Encode/100KB") { benchmark in
        let value = collection100KB
        for _ in benchmark.scaledIterations {
            blackHole(try? encoder.encode(value))
        }
    }

    Benchmark("Encode/1MB") { benchmark in
        let value = collection1MB
        for _ in benchmark.scaledIterations {
            blackHole(try? encoder.encode(value))
        }
    }

    // Key transformation overhead
    let encoderSnakeCase = XMLEncoder(
        configuration: XMLEncoder.Configuration(keyTransformStrategy: .convertToSnakeCase)
    )

    Benchmark("Encode/10KB/snakeCase") { benchmark in
        let value = collection10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? encoderSnakeCase.encode(value))
        }
    }
}
