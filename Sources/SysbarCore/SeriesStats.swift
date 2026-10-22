public struct SeriesStats: Equatable {
    public let min: Double
    public let average: Double
    public let max: Double

    public init(min: Double, average: Double, max: Double) {
        self.min = min
        self.average = average
        self.max = max
    }

    public static func of(_ values: [Double]) -> SeriesStats? {
        guard let first = values.first else { return nil }
        let (low, high) = values.reduce((first, first)) { (Swift.min($0.0, $1), Swift.max($0.1, $1)) }
        return SeriesStats(min: low, average: values.reduce(0, +) / Double(values.count), max: high)
    }
}
