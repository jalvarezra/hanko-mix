import Atomics

/// Single-producer / single-consumer triple buffer. The writer never blocks the
/// reader; the reader (real-time thread) only performs atomic operations.
/// `T` should be a trivial value type so reading it does no ARC traffic.
public final class ParameterSlot<T>: @unchecked Sendable {
    private static var dirtyBit: UInt8 { 0b100 }
    private let buffers: UnsafeMutablePointer<T>
    private let middle: ManagedAtomic<UInt8>   // bits 0-1: index, bit 2: new data
    private var writeIndex: UInt8 = 0           // writer-owned
    private var readIndex: UInt8 = 2            // reader-owned

    public init(_ initial: T) {
        buffers = .allocate(capacity: 3)
        buffers.initialize(repeating: initial, count: 3)
        middle = ManagedAtomic(1)
    }

    deinit {
        buffers.deinitialize(count: 3)
        buffers.deallocate()
    }

    public func publish(_ value: T) {
        buffers[Int(writeIndex)] = value
        let previous = middle.exchange(writeIndex | Self.dirtyBit, ordering: .acquiringAndReleasing)
        writeIndex = previous & 0b11
    }

    public func consumeLatest() -> T {
        if middle.load(ordering: .acquiring) & Self.dirtyBit != 0 {
            let previous = middle.exchange(readIndex, ordering: .acquiringAndReleasing)
            readIndex = previous & 0b11
        }
        return buffers[Int(readIndex)]
    }
}
