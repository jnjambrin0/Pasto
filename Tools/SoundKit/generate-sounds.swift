// Generates Pasto's two feedback sounds from code, so no audio file has to be hand-made or
// borrowed: `swift Tools/SoundKit/generate-sounds.swift [output-directory]`
// (default: Pasto/Sounds). Both are synthesized tones with an exponential decay: two rising notes
// for copy (0.21 s) and a single short tap for paste (0.08 s).

import AVFoundation
import Foundation

struct Partial {
    var frequency: Double
    var amplitude: Double
    /// Seconds after the start of the sound at which this partial begins.
    var onset: Double
    /// Time constant of its exponential decay, in seconds.
    var decay: Double
}

func render(duration: Double, partials: [Partial], sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let attack = 0.004
    let release = 0.012
    for frame in 0..<Int(frameCount) {
        let time = Double(frame) / sampleRate
        var sample = 0.0
        for partial in partials where time >= partial.onset {
            let local = time - partial.onset
            let envelope = min(local / attack, 1) * exp(-local / partial.decay)
            sample += partial.amplitude * envelope * sin(2 * .pi * partial.frequency * local)
        }
        // Fade the tail so the file never ends on a click.
        sample *= min((duration - time) / release, 1)
        for channel in 0..<2 {
            buffer.floatChannelData![channel][frame] = Float(sample)
        }
    }
    return buffer
}

func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: buffer.format.sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: true,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Pasto/Sounds", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Copy: two soft rising notes, like something being picked up.
let copy = render(duration: 0.21, partials: [
    Partial(frequency: 740, amplitude: 0.22, onset: 0, decay: 0.045),
    Partial(frequency: 1480, amplitude: 0.05, onset: 0, decay: 0.03),
    Partial(frequency: 1109, amplitude: 0.24, onset: 0.07, decay: 0.05),
    Partial(frequency: 2218, amplitude: 0.05, onset: 0.07, decay: 0.03),
])
// Paste: one short, lower tap, like something being set down.
let paste = render(duration: 0.08, partials: [
    Partial(frequency: 587, amplitude: 0.26, onset: 0, decay: 0.022),
    Partial(frequency: 1174, amplitude: 0.07, onset: 0, decay: 0.012),
])

try write(copy, to: outputDirectory.appendingPathComponent("PastoCopy.aiff"))
try write(paste, to: outputDirectory.appendingPathComponent("PastoPaste.aiff"))
print("Wrote PastoCopy.aiff and PastoPaste.aiff to \(outputDirectory.path)")
