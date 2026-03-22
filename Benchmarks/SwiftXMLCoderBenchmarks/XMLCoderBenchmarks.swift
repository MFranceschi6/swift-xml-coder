import Benchmark

// Entry point discovered by the BenchmarkPlugin.
// Each register function defines Benchmark(...) instances for a specific operation area.
let benchmarks: @Sendable () -> Void = {
    parseBenchmarks()
    encodeBenchmarks()
    decodeBenchmarks()
    canonicalizationBenchmarks()
    streamingBenchmarks()
    richBenchmarks()
    foundationComparison()
}
