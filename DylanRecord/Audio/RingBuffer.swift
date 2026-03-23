import Foundation

/// Thread-safe ring buffer for Int16 audio samples.
final class RingBuffer {
    private var buffer: [Int16]
    private let capacity: Int
    private var writeIndex = 0
    private var readIndex = 0
    private var count = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    var available: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func write(_ samples: UnsafeBufferPointer<Int16>) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            if count < capacity {
                count += 1
            } else {
                // Overwrite oldest — advance read index
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    func write(_ data: Data) {
        data.withUnsafeBytes { rawPtr in
            guard let ptr = rawPtr.bindMemory(to: Int16.self).baseAddress else { return }
            let sampleCount = data.count / MemoryLayout<Int16>.size
            let bufferPtr = UnsafeBufferPointer(start: ptr, count: sampleCount)
            write(bufferPtr)
        }
    }

    /// Read up to `maxCount` samples into the output array. Returns actual count read.
    func read(into output: inout [Int16], maxCount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let toRead = min(maxCount, count)
        for i in 0..<toRead {
            output[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= toRead
        return toRead
    }
}
