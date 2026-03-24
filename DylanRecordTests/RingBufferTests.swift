import Foundation
import Testing
@testable import DylanRecord

@Suite("RingBuffer")
struct RingBufferTests {
    @Test("Write and read back samples")
    func writeAndRead() {
        let buffer = RingBuffer(capacity: 100)
        let samples: [Int16] = [1, 2, 3, 4, 5]
        samples.withUnsafeBufferPointer { buffer.write($0) }

        var output = [Int16](repeating: 0, count: 10)
        let count = buffer.read(into: &output, maxCount: 10)

        #expect(count == 5)
        #expect(output[0] == 1)
        #expect(output[4] == 5)
    }

    @Test("Read returns zero when empty")
    func readEmpty() {
        let buffer = RingBuffer(capacity: 100)
        var output = [Int16](repeating: 0, count: 10)
        let count = buffer.read(into: &output, maxCount: 10)
        #expect(count == 0)
    }

    @Test("Overflow drops oldest samples")
    func overflow() {
        let buffer = RingBuffer(capacity: 4)
        let samples: [Int16] = [1, 2, 3, 4, 5, 6]
        samples.withUnsafeBufferPointer { buffer.write($0) }

        #expect(buffer.available == 4)

        var output = [Int16](repeating: 0, count: 4)
        let count = buffer.read(into: &output, maxCount: 4)

        #expect(count == 4)
        // Should have the last 4 samples (oldest dropped)
        #expect(output[0] == 3)
        #expect(output[1] == 4)
        #expect(output[2] == 5)
        #expect(output[3] == 6)
    }

    @Test("Write via Data")
    func writeData() {
        let buffer = RingBuffer(capacity: 100)
        let samples: [Int16] = [10, 20, 30]
        let data = samples.withUnsafeBytes { Data($0) }
        buffer.write(data)

        #expect(buffer.available == 3)

        var output = [Int16](repeating: 0, count: 3)
        let count = buffer.read(into: &output, maxCount: 3)
        #expect(count == 3)
        #expect(output == [10, 20, 30])
    }

    @Test("Partial read leaves remaining")
    func partialRead() {
        let buffer = RingBuffer(capacity: 100)
        let samples: [Int16] = [1, 2, 3, 4, 5]
        samples.withUnsafeBufferPointer { buffer.write($0) }

        var output = [Int16](repeating: 0, count: 3)
        let count = buffer.read(into: &output, maxCount: 3)
        #expect(count == 3)
        #expect(output == [1, 2, 3])
        #expect(buffer.available == 2)
    }
}
