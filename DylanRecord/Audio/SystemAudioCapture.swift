import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

final class SystemAudioCapture {
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var converter: AudioConverter?
    private var cachedFormat: AVAudioFormat?

    var onAudioData: ((Data) -> Void)?

    func start() throws {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Convert our PID to an AudioObjectID
        let ownAudioObjectID = try pidToAudioObjectID(ownPID)

        // Step 1: Create tap description for all system audio except our own process
        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [ownAudioObjectID]
        )
        tapDescription.muteBehavior = .unmuted
        tapDescription.name = "DylanRecord System Tap"

        // Step 2: Create the process tap
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapObjectID)
        guard status == noErr else {
            throw SystemAudioCaptureError.tapCreationFailed(status)
        }

        // Step 3: Get tap UUID
        let tapUUID = tapDescription.uuid
        let tapUID = tapUUID.uuidString

        // Step 4: Create aggregate device with the tap
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: "com.rasmus.dylanrecord.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey as String: "Dylan Record Tap",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey as String: true
        ]

        status = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw SystemAudioCaptureError.aggregateDeviceFailed(status)
        }

        // Step 5: Read the tap's audio format
        let tapFormat = try getTapFormat()
        cachedFormat = tapFormat
        print("[SystemAudio] Tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

        converter = try AudioConverter(inputFormat: tapFormat)

        // Step 6: Register IOProc callback
        status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateDeviceID,
            nil
        ) { [weak self] _, inputData, _, _, _ in
            self?.handleAudioCallback(inputData)
        }
        guard status == noErr else {
            throw SystemAudioCaptureError.ioProcFailed(status)
        }

        // Step 7: Start capturing
        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            throw SystemAudioCaptureError.startFailed(status)
        }

        print("[SystemAudio] Capture started")
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapObjectID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapObjectID)
            tapObjectID = kAudioObjectUnknown
        }

        converter = nil
        cachedFormat = nil
        print("[SystemAudio] Capture stopped")
    }

    // MARK: - Private

    private func pidToAudioObjectID(_ pid: pid_t) throws -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var pidValue = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &processObjectID
        )
        guard status == noErr else {
            throw SystemAudioCaptureError.propertyReadFailed(status)
        }
        return processObjectID
    }

    private func handleAudioCallback(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let converter, let format = cachedFormat else { return }

        let bufferList = inputData.pointee
        guard bufferList.mNumberBuffers > 0 else { return }

        let buf = bufferList.mBuffers
        guard let dataPtr = buf.mData, buf.mDataByteSize > 0 else { return }

        let bytesPerFrame = UInt32(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }

        let frameCount = buf.mDataByteSize / bytesPerFrame
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }

        pcmBuffer.frameLength = frameCount

        if let destData = pcmBuffer.audioBufferList.pointee.mBuffers.mData {
            memcpy(destData, dataPtr, Int(buf.mDataByteSize))
        }

        do {
            let data = try converter.convert(pcmBuffer)
            if !data.isEmpty {
                onAudioData?(data)
            }
        } catch {
            // Don't spam logs in audio callback — this is called hundreds of times per second
        }
    }

    private func getTapFormat() throws -> AVAudioFormat {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapObjectID, &addr, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw SystemAudioCaptureError.propertyReadFailed(status)
        }

        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioCaptureError.formatError
        }
        return format
    }
}

enum SystemAudioCaptureError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)
    case propertyReadFailed(OSStatus)
    case formatError

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): return "Failed to create audio tap (OSStatus \(s))"
        case .aggregateDeviceFailed(let s): return "Failed to create aggregate device (OSStatus \(s))"
        case .ioProcFailed(let s): return "Failed to create IO proc (OSStatus \(s))"
        case .startFailed(let s): return "Failed to start audio device (OSStatus \(s))"
        case .propertyReadFailed(let s): return "Failed to read tap property (OSStatus \(s))"
        case .formatError: return "Failed to create audio format from tap"
        }
    }
}
