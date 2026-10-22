/// Immutable fixed-capacity history: `appending` returns a new value and drops the oldest items.
public struct BoundedHistory<Element> {
    public let capacity: Int
    public let items: [Element]

    public init(capacity: Int, items: [Element] = []) {
        self.capacity = capacity
        self.items = Array(items.suffix(capacity))
    }

    public func appending(_ element: Element) -> BoundedHistory {
        BoundedHistory(capacity: capacity, items: items + [element])
    }
}
