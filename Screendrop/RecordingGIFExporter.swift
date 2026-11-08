//
//  RecordingGIFExporter.swift
//  Screendrop
//
//  Converts a rendered recording into an animated GIF. GIF export reuses the
//  normal video exporter for everything the studio draws (zooms, pointer,
//  camera, captions) and then samples that movie at the GIF's frame rate.
//  Sampling after the render keeps the GIF pipeline independent of the video
//  writer, which is tuned for long 30/60 fps movies, not palettized frames.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum RecordingGIFExporter {
    enum GIFError: LocalizedError {
        case noVideoTrack
        case emptyRecording
        case destinationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "The recording has no video track."
            case .emptyRecording:
                "The recording is too short to export as a GIF."
            case .destinationFailed:
                "The GIF file could not be created."
            case .writeFailed:
                "Writing the GIF failed."
            }
        }
    }

    /// Renders `videoURL` into a looping GIF at `to`. `maximumPixelSize` caps
    /// the long side; AVAssetImageGenerator preserves the aspect ratio.
    ///
    /// `@concurrent` keeps ImageIO's frame encoding and AVFoundation's frame
    /// seeking off the main actor, where the caller lives.
    @concurrent
    static func write(
        from videoURL: URL,
        to outputURL: URL,
        frameRate: Double,
        maximumPixelSize: CGFloat,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        precondition(frameRate > 0)

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw GIFError.emptyRecording
        }
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw GIFError.noVideoTrack
        }

        let frameCount = max(1, Int((duration * frameRate).rounded()))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        // Half a GIF frame of slack keeps seeking quick without changing which
        // source frame is shown at each tick.
        let tolerance = CMTime(seconds: 0.5 / frameRate, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw GIFError.destinationFailed
        }

        let delay = 1 / frameRate
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]
        ]

        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        for index in 0..<frameCount {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(index) / frameRate, preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
            progress(Double(index + 1) / Double(frameCount))
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFError.writeFailed
        }
        completed = true
    }
}
