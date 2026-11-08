import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records one application's system audio without installing a loopback driver.
/// Intended for clean-room, matched Sunday Keys / StageKeys reference captures.
final class AppAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "StageKeys.AppAudioCapture.writer")
    private var began = false
    private var failure: Error?

    init(url: URL, sampleRate: Int, channels: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .caf)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.unsupportedWriter }
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        queue.sync {
            guard failure == nil else { return }
            if !began {
                guard writer.startWriting() else { failure = writer.error ?? CaptureError.writerFailed; return }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                began = true
            }
            if input.isReadyForMoreMediaData, !input.append(sampleBuffer) {
                failure = writer.error ?? CaptureError.writerFailed
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.sync { failure = error } }

    var capturedAudio: Bool { queue.sync { began } }

    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                if let failure { continuation.resume(throwing: failure); return }
                guard began else { continuation.resume(throwing: CaptureError.noAudio); return }
                input.markAsFinished()
                writer.finishWriting {
                    if self.writer.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: self.writer.error ?? CaptureError.writerFailed) }
                }
            }
        }
    }
}

enum CaptureError: LocalizedError {
    case applicationNotFound(String), displayUnavailable, invalidDuration, noAudio, outputExists
    case startTimedOut, stopTimedOut, unsupportedWriter, writerFailed
    var errorDescription: String? {
        switch self {
        case .applicationNotFound(let id): return "No running application has bundle identifier \(id)."
        case .displayUnavailable: return "No capturable display is available."
        case .invalidDuration: return "Duration must be between 0.25 and 600 seconds."
        case .noAudio: return "The application produced no captured audio. Check Screen Recording permission and play the probe."
        case .outputExists: return "The output path already exists; captures are never overwritten."
        case .startTimedOut: return "ScreenCaptureKit did not start the app-audio capture within 5 seconds."
        case .stopTimedOut: return "ScreenCaptureKit did not stop the app-audio capture within 5 seconds."
        case .unsupportedWriter: return "This system cannot create the requested float PCM CAF."
        case .writerFailed: return "The audio writer failed."
        }
    }
}

private final class CaptureCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ error: Error?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        guard let pending else { return }
        if let error { pending.resume(throwing: error) } else { pending.resume() }
    }
}

private func captureOperation(timeout: CaptureError,
                              _ operation: (@escaping @Sendable (Error?) -> Void) -> Void) async throws {
    try await withCheckedThrowingContinuation { continuation in
        let completion = CaptureCompletion(continuation)
        operation { completion.finish($0) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { completion.finish(timeout) }
    }
}

@main
struct CaptureAppAudio {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("capture-app-audio: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, let duration = Double(arguments[2]), (0.25...600).contains(duration) else {
            FileHandle.standardError.write(Data("usage: capture-app-audio BUNDLE_ID SECONDS OUTPUT.caf\n".utf8))
            throw CaptureError.invalidDuration
        }
        // ScreenCaptureKit has exhibited callbacks that never return after an
        // audio server failure. Keep this command-line calibration tool bounded
        // even if discovery, start or stop ignores its narrower timeout.
        DispatchQueue.global().asyncAfter(deadline: .now() + duration + 7) {
            FileHandle.standardError.write(Data("capture-app-audio: ScreenCaptureKit exceeded the capture deadline.\n".utf8))
            exit(2)
        }
        let bundleID = arguments[1]
        let output = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CaptureError.outputExists }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let application = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
            throw CaptureError.applicationNotFound(bundleID)
        }
        guard let display = content.displays.first else { throw CaptureError.displayUnavailable }
        let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3

        let capture = try AppAudioCapture(url: output, sampleRate: configuration.sampleRate, channels: configuration.channelCount)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: capture)
        try stream.addStreamOutput(capture, type: .audio, sampleHandlerQueue: DispatchQueue(label: "StageKeys.AppAudioCapture.samples"))
        try await captureOperation(timeout: .startTimedOut) { stream.startCapture(completionHandler: $0) }
        try await Task.sleep(for: .seconds(duration))
        // On current macOS builds stopCapture can wait forever when the target
        // emitted no audio sample buffers. Fail on the requested wall-clock
        // deadline instead of leaving calibration automation hung indefinitely.
        guard capture.capturedAudio else { throw CaptureError.noAudio }
        try await captureOperation(timeout: .stopTimedOut) { stream.stopCapture(completionHandler: $0) }
        try await capture.finish()
        print(output.path)
    }
}
