import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import Synchronization

/// Summary of a recording made by `FrameRecorder`.
public struct FrameRecordingReport: Codable, Sendable {
    public let directory: String
    public let width: Int
    public let height: Int
    public let requestedFps: Int
    public let durationSeconds: Double
    /// Sample buffers ScreenCaptureKit handed over, including the ones that carried no new image.
    public let callbacks: Int
    /// Buffers flagged as complete, i.e. the window server produced a new frame.
    public let framesDelivered: Int
    /// Delivered frames whose pixels differ from the frame before them.
    public let uniqueFrames: Int
    public let framesWritten: Int
    /// Frames skipped because PNG encoding fell too far behind.
    public let framesDropped: Int
    /// Continuous-clock time of frame 0; add it to `t_ms` to compare with other probes.
    public let t0ContinuousMs: Double?
    public let lastFrameMs: Double?
    /// Set when the stream ended before the requested duration or a frame could not be written.
    public let streamError: String?
}

/// Records an `SCStream` as PNG files named after their millisecond timestamp, plus `index.csv`.
public final class FrameRecorder: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
    private struct Entry: Sendable {
        let fileName: String
        let milliseconds: Double
        let contentHash: Int
    }

    private struct State: Sendable {
        var callbacks = 0
        var delivered = 0
        var dropped = 0
        var pendingBytes = 0
        var originAbsoluteMs: Double?
        var width = 0
        var height = 0
        var entries: [Entry] = []
        var failure: String?
    }

    /// Raw frames waiting for PNG encoding may use at most this much memory.
    private static let pendingBytesLimit = 2 << 30

    private let directory: URL
    private let state = Mutex(State())
    private let sampleQueue = DispatchQueue(label: "probekit.frames.samples")
    private let encodeQueue = DispatchQueue(label: "probekit.frames.encode", qos: .userInitiated, attributes: .concurrent)
    private let encoders = DispatchGroup()

    private init(directory: URL) {
        self.directory = directory
    }

    /// Records `target` for `duration` seconds at up to `fps` frames per second into `directory`.
    @MainActor
    public static func record(
        _ target: CaptureTarget, fps: Int, duration: Double, into directory: URL
    ) async throws -> FrameRecordingReport {
        try Permissions.requireScreenCapture()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Frames of an earlier run would be indistinguishable from the new ones.
            guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
                throw ProbeError.usage("\(directory.path) is not empty; record into a new or empty directory")
            }
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.runtime("cannot use \(directory.path): \(error.localizedDescription)")
        }

        let (filter, configuration) = try await ScreenCapture.filterAndConfiguration(for: target)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.queueDepth = 8

        let recorder = FrameRecorder(directory: directory)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
        do {
            try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.sampleQueue)
            try await stream.startCapture()
        } catch {
            throw ProbeError.runtime("ScreenCaptureKit could not start the stream: \(error.localizedDescription)")
        }
        try? await Task.sleep(for: .seconds(duration))
        do {
            try await stream.stopCapture()
        } catch {
            // The system ended the stream first; keep the frames and report why in `streamError`.
            recorder.noteFailure(error.localizedDescription)
        }
        await recorder.waitForEncoders()
        return try recorder.finish(fps: fps, duration: duration)
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let isComplete = Self.isCompleteFrame(sampleBuffer)
        state.withLock { $0.callbacks += 1 }
        guard isComplete, let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let byteCount = width * height * 4
        let absoluteMs = sampleBuffer.presentationTimeStamp.seconds * 1000

        let milliseconds: Double? = state.withLock { state in
            state.delivered += 1
            state.width = width
            state.height = height
            guard state.pendingBytes + byteCount <= Self.pendingBytesLimit else {
                state.dropped += 1
                return nil
            }
            state.pendingBytes += byteCount
            let origin = state.originAbsoluteMs ?? absoluteMs
            state.originAbsoluteMs = origin
            return absoluteMs - origin
        }
        guard let milliseconds, let pixels = Self.copyPixels(of: pixelBuffer) else { return }

        encodeQueue.async(group: encoders) { [self] in
            let fileName = String(format: "%06d.png", Int(milliseconds.rounded()))
            var hasher = Hasher()
            pixels.withUnsafeBytes { hasher.combine(bytes: $0) }
            let entry = Entry(fileName: fileName, milliseconds: milliseconds, contentHash: hasher.finalize())
            let failure = Self.writePNG(pixels, width: width, height: height, to: directory.appendingPathComponent(fileName))
            state.withLock { state in
                state.pendingBytes -= byteCount
                if let failure {
                    state.failure = state.failure ?? failure
                } else {
                    state.entries.append(entry)
                }
            }
        }
    }

    // MARK: SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        noteFailure(error.localizedDescription)
    }

    /// Keeps the first failure: it is the cause, later ones are consequences.
    private func noteFailure(_ description: String) {
        state.withLock { $0.failure = $0.failure ?? description }
    }

    // MARK: Internals

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int
        else { return false }
        return SCFrameStatus(rawValue: rawStatus) == .complete
    }

    /// Copies the BGRA pixels into tightly packed rows so that row padding never reaches the hash.
    private static func copyPixels(of pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetWidth(pixelBuffer) * 4
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var data = Data(capacity: rowBytes * height)
        for row in 0..<height {
            data.append(base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self), count: rowBytes)
        }
        return data
    }

    /// Returns a failure description, or nil when the file was written.
    private static func writePNG(_ pixels: Data, width: Int, height: Int, to url: URL) -> String? {
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: space, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                  shouldInterpolate: false, intent: .defaultIntent
              )
        else { return "cannot build a \(width)x\(height) frame image" }
        do {
            try PNGFile.write(image, to: url)
            return nil
        } catch {
            return (error as? ProbeError)?.message ?? error.localizedDescription
        }
    }

    private func waitForEncoders() async {
        await withCheckedContinuation { continuation in
            encoders.notify(queue: encodeQueue) { continuation.resume() }
        }
    }

    private func finish(fps: Int, duration: Double) throws -> FrameRecordingReport {
        let snapshot = state.withLock { $0 }
        let entries = snapshot.entries.sorted { $0.milliseconds < $1.milliseconds }

        var index = "frame,t_ms\n"
        var uniqueFrames = 0
        var previousHash: Int?
        for entry in entries {
            index += "\(entry.fileName),\(ProbeClock.rounded(entry.milliseconds))\n"
            if entry.contentHash != previousHash { uniqueFrames += 1 }
            previousHash = entry.contentHash
        }
        do {
            try index.write(to: directory.appendingPathComponent("index.csv"), atomically: true, encoding: .utf8)
        } catch {
            throw ProbeError.runtime("cannot write index.csv: \(error.localizedDescription)")
        }

        return FrameRecordingReport(
            directory: directory.path,
            width: snapshot.width,
            height: snapshot.height,
            requestedFps: fps,
            durationSeconds: duration,
            callbacks: snapshot.callbacks,
            framesDelivered: snapshot.delivered,
            uniqueFrames: uniqueFrames,
            framesWritten: entries.count,
            framesDropped: snapshot.dropped,
            t0ContinuousMs: snapshot.originAbsoluteMs.map { ProbeClock.rounded($0 + ProbeClock.absoluteToContinuousOffsetMs()) },
            lastFrameMs: entries.last.map { ProbeClock.rounded($0.milliseconds) },
            streamError: snapshot.failure
        )
    }
}
