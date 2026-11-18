import Foundation

/// Outcome of a per-pixel comparison. A pixel's delta is its largest channel difference (0–255).
public struct ImageDiffResult: Codable, Sendable, Equatable {
    public struct PixelRect: Codable, Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let w: Int
        public let h: Int
    }

    public struct Size: Codable, Sendable, Equatable {
        public let width: Int
        public let height: Int
    }

    public let a: Size
    public let b: Size
    /// The region actually compared: the full image, or the shared top-left area when cropping.
    public let compared: Size
    public let threshold: Int
    /// Pixels whose delta exceeds the threshold.
    public let differingPixels: Int
    public let differingPercent: Double
    /// Mean delta over every compared pixel.
    public let meanDelta: Double
    public let maxDelta: Int
    /// Smallest rectangle containing every differing pixel; nil when none differ.
    public let boundingBox: PixelRect?
}

public enum ImageDiff {
    public static func compare(_ a: Bitmap, _ b: Bitmap, threshold: Int = 2, cropCommon: Bool = false) throws -> ImageDiffResult {
        try analyse(a, b, threshold: threshold, cropCommon: cropCommon, wantsHeatmap: false).result
    }

    /// Same comparison plus a picture of it: matching pixels become a dimmed greyscale copy of A,
    /// differing pixels turn red, brighter the larger the delta.
    public static func compareWithHeatmap(
        _ a: Bitmap, _ b: Bitmap, threshold: Int = 2, cropCommon: Bool = false
    ) throws -> (result: ImageDiffResult, heatmap: Bitmap) {
        let analysis = try analyse(a, b, threshold: threshold, cropCommon: cropCommon, wantsHeatmap: true)
        let heatmap = try Bitmap(width: analysis.result.compared.width, height: analysis.result.compared.height, pixels: analysis.heatmap)
        return (analysis.result, heatmap)
    }

    private static func analyse(
        _ a: Bitmap, _ b: Bitmap, threshold: Int, cropCommon: Bool, wantsHeatmap: Bool
    ) throws -> (result: ImageDiffResult, heatmap: [UInt8]) {
        guard cropCommon || (a.width == b.width && a.height == b.height) else {
            throw ProbeError.runtime(
                "image sizes differ (\(a.width)x\(a.height) vs \(b.width)x\(b.height)); pass --crop-common to compare the shared top-left region"
            )
        }
        let width = min(a.width, b.width)
        let height = min(a.height, b.height)
        var differing = 0
        var deltaSum = 0
        var maxDelta = 0
        var minX = width, minY = height, maxX = -1, maxY = -1
        var heatmap = [UInt8](repeating: 255, count: wantsHeatmap ? width * height * 4 : 0)

        a.pixels.withUnsafeBufferPointer { pixelsA in
            b.pixels.withUnsafeBufferPointer { pixelsB in
                heatmap.withUnsafeMutableBufferPointer { output in
                    for y in 0..<height {
                        var offsetA = y * a.width * 4
                        var offsetB = y * b.width * 4
                        var offsetOut = y * width * 4
                        for x in 0..<width {
                            var delta = 0
                            for channel in 0..<4 {
                                delta = max(delta, abs(Int(pixelsA[offsetA + channel]) - Int(pixelsB[offsetB + channel])))
                            }
                            deltaSum += delta
                            maxDelta = max(maxDelta, delta)
                            let differs = delta > threshold
                            if differs {
                                differing += 1
                                minX = min(minX, x)
                                maxX = max(maxX, x)
                                minY = min(minY, y)
                                maxY = max(maxY, y)
                            }
                            if wantsHeatmap {
                                if differs {
                                    output[offsetOut] = UInt8(96 + delta * 159 / 255)
                                    output[offsetOut + 1] = 0
                                    output[offsetOut + 2] = 0
                                } else {
                                    let luma = (Int(pixelsA[offsetA]) * 77 + Int(pixelsA[offsetA + 1]) * 150 + Int(pixelsA[offsetA + 2]) * 29) >> 8
                                    let dimmed = UInt8(luma / 3)
                                    output[offsetOut] = dimmed
                                    output[offsetOut + 1] = dimmed
                                    output[offsetOut + 2] = dimmed
                                }
                                offsetOut += 4
                            }
                            offsetA += 4
                            offsetB += 4
                        }
                    }
                }
            }
        }

        let total = width * height
        let result = ImageDiffResult(
            a: .init(width: a.width, height: a.height),
            b: .init(width: b.width, height: b.height),
            compared: .init(width: width, height: height),
            threshold: threshold,
            differingPixels: differing,
            differingPercent: Double(differing) * 100 / Double(total),
            meanDelta: Double(deltaSum) / Double(total),
            maxDelta: maxDelta,
            boundingBox: differing == 0 ? nil : .init(x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
        )
        return (result, heatmap)
    }
}
