import Foundation
import Testing
@testable import DylanRecord

@Suite("TranscriptDraftStore")
struct TranscriptDraftStoreTests {
    private func makeStore() -> (TranscriptDraftStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (TranscriptDraftStore(directory: dir), dir)
    }

    @Test("Round-trips header and segments")
    func roundTrip() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let start = Date(timeIntervalSince1970: 1_750_000_000)
        store.begin(startDate: start)
        store.append(TranscriptSegment(speaker: .me, text: "Hello", startTime: 1.5, endTime: 2.5))
        store.append(TranscriptSegment(speaker: .them, text: "Hi there", startTime: 3.0, endTime: 4.0))

        let draft = try #require(store.load())
        #expect(abs(draft.startDate.timeIntervalSince(start)) < 0.001)
        #expect(draft.segments.count == 2)
        #expect(draft.segments[0].speaker == .me)
        #expect(draft.segments[0].text == "Hello")
        #expect(draft.segments[1].speaker == .them)
        #expect(draft.segments[1].startTime == 3.0)
    }

    @Test("Empty draft (header only) is not recovered")
    func emptyDraftIgnored() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.begin(startDate: Date())
        #expect(store.load() == nil)
    }

    @Test("Missing file is not recovered")
    func missingFile() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(store.load() == nil)
    }

    @Test("Clear removes the draft")
    func clearRemoves() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.begin(startDate: Date())
        store.append(TranscriptSegment(speaker: .me, text: "Hello", startTime: 0, endTime: 1))
        #expect(store.load() != nil)

        store.clear()
        #expect(store.load() == nil)
    }

    @Test("Begin truncates a previous draft")
    func beginTruncates() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.begin(startDate: Date(timeIntervalSince1970: 1))
        store.append(TranscriptSegment(speaker: .me, text: "Old", startTime: 0, endTime: 1))

        let newStart = Date(timeIntervalSince1970: 2)
        store.begin(startDate: newStart)
        store.append(TranscriptSegment(speaker: .them, text: "New", startTime: 0, endTime: 1))

        let draft = try #require(store.load())
        #expect(draft.segments.count == 1)
        #expect(draft.segments[0].text == "New")
        #expect(abs(draft.startDate.timeIntervalSince(newStart)) < 0.001)
    }

    @Test("Corrupt trailing line is skipped, valid segments survive")
    func corruptLineSkipped() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.begin(startDate: Date())
        store.append(TranscriptSegment(speaker: .me, text: "Good", startTime: 0, endTime: 1))

        // Simulate a crash mid-write: partial JSON on the last line
        let fileURL = dir.appendingPathComponent("draft-transcript.jsonl")
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"speaker\":\"Me\",\"tex".utf8))
        try handle.close()

        let draft = try #require(store.load())
        #expect(draft.segments.count == 1)
        #expect(draft.segments[0].text == "Good")
    }
}
