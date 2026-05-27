@preconcurrency import AVFoundation
import Foundation

final class AudioConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat

    static let targetSampleRate: Double = 16000
    static let targetChannels: AVAudioChannelCount = 1

    init(inputFormat: AVAudioFormat) throws {
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else {
            throw AudioConverterError.formatCreationFailed
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: outFormat) else {
            throw AudioConverterError.converterCreationFailed
        }

        self.inputFormat = inputFormat
        self.outputFormat = outFormat
        self.converter = conv
    }

    /// Convert an input buffer to Int16 16kHz mono and return raw bytes
    func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> Data {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw AudioConverterError.bufferAllocationFailed
        }

        var conversionError: NSError?

        let inputRef = inputBuffer
        nonisolated(unsafe) var consumed = false
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputRef
        }

        if let conversionError {
            throw conversionError
        }

        guard outputBuffer.frameLength > 0 else {
            return Data()
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let ptr = audioBuffer.mData else {
            return Data()
        }

        return Data(bytes: ptr, count: Int(audioBuffer.mDataByteSize))
    }
}

enum AudioConverterError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create output audio format."
        case .converterCreationFailed: return "Failed to create audio converter."
        case .bufferAllocationFailed: return "Failed to allocate output buffer."
        }
    }
}
