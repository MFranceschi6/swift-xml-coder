import Benchmark
import Foundation
import SwiftXMLCoder

func canonicalizationBenchmarks() {
    let canonicalizer = XMLDefaultCanonicalizer()
    let options = XMLNormalizationOptions()
    let transforms: XMLTransformPipeline = []

    Benchmark("Canonicalize/1KB") { benchmark in
        let doc = parsedDoc1KB
        for _ in benchmark.scaledIterations {
            blackHole(try? canonicalizer.canonicalView(for: doc, options: options, transforms: transforms))
        }
    }

    Benchmark("Canonicalize/10KB") { benchmark in
        let doc = parsedDoc10KB
        for _ in benchmark.scaledIterations {
            blackHole(try? canonicalizer.canonicalView(for: doc, options: options, transforms: transforms))
        }
    }

    Benchmark("Canonicalize/100KB") { benchmark in
        let doc = parsedDoc100KB
        for _ in benchmark.scaledIterations {
            blackHole(try? canonicalizer.canonicalView(for: doc, options: options, transforms: transforms))
        }
    }
}
