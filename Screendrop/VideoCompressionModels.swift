//
//  VideoCompressionModels.swift
//  Screendrop
//

import CoreGraphics
import Foundation

enum VideoCompressionQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var crf: Int {
        switch self {
        case .high:
            20
        case .medium:
            26
        case .low:
            32
        }
    }

    var audioBitrate: String {
        switch self {
        case .high:
            "192k"
        case .medium:
            "128k"
        case .low:
            "96k"
        }
    }
}

enum VideoCompressionSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case ultrafast = "Ultrafast"
    case fast = "Fast"
    case medium = "Medium"
    case slow = "Slow"

    var id: String { rawValue }

    var ffmpegPreset: String {
        rawValue.lowercased()
    }
}

enum VideoCompressionCodec: String, CaseIterable, Identifiable, Codable, Sendable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }

    var encoder: String {
        switch self {
        case .h264:
            "libx264"
        case .hevc:
            "libx265"
        }
    }
}

enum VideoCompressionResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }

    var scaleFilter: String? {
        switch self {
        case .original:
            nil
        case .p1080:
            "-2:1080"
        case .p720:
            "-2:720"
        case .p480:
            "-2:480"
        }
    }
}

/// Delivery container for exported recordings. The encoded video and audio
/// are identical either way - only the wrapper differs.
enum VideoExportContainer: String, CaseIterable, Identifiable, Codable, Sendable {
    /// What capture already writes, so a plain recording exports as a
    /// copy-on-write clone with no rewrite at all.
    case mov = "MOV"
    /// Plays outside Apple platforms - Slack, Discord, browsers, Windows.
    /// Costs a container rewrite when the source is a QuickTime master.
    case mp4 = "MP4"

    nonisolated static let `default` = VideoExportContainer.mov

    var id: String { rawValue }

    var fileExtension: String { rawValue.lowercased() }

    init?(fileExtension: String) {
        guard let match = Self.allCases.first(where: {
            $0.fileExtension == fileExtension.lowercased()
        }) else { return nil }
        self = match
    }
}

nonisolated enum VideoExportFrameRate: String, CaseIterable, Identifiable, Codable, Sendable {
    case fps30 = "30 fps"
    case fps60 = "60 fps"

    var id: String { rawValue }
    var framesPerSecond: Double { self == .fps30 ? 30 : 60 }
}

/// What the Studio's Export button delivers. MOV and MP4 are the video
/// containers; GIF re-encodes the rendered cut as an animated image, so it
/// has its own frame rate and size instead of codec/quality settings.
nonisolated enum RecordingDeliveryFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case mov = "MOV"
    case mp4 = "MP4"
    case gif = "GIF"

    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }

    /// The container the video exporter should write. GIF has none: it is
    /// rendered as an intermediate movie and then converted.
    var videoContainer: VideoExportContainer? {
        switch self {
        case .mov: .mov
        case .mp4: .mp4
        case .gif: nil
        }
    }
}

/// GIF playback rates. Video renders at 30 or 60 fps; GIFs are sampled down
/// to one of these, because every frame is a full palettized image.
nonisolated enum RecordingGIFFrameRate: String, CaseIterable, Identifiable, Codable, Sendable {
    case fps10 = "10 fps"
    case fps15 = "15 fps"
    case fps20 = "20 fps"
    case fps30 = "30 fps"

    var id: String { rawValue }
    var framesPerSecond: Double {
        switch self {
        case .fps10: 10
        case .fps15: 15
        case .fps20: 20
        case .fps30: 30
        }
    }
}

/// The long side of a GIF. Animated images grow quickly, so "Original"
/// resolution is deliberately not offered.
nonisolated enum RecordingGIFSize: String, CaseIterable, Identifiable, Codable, Sendable {
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }
    var maximumPixelSize: CGFloat {
        switch self {
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }

    var videoResolution: VideoCompressionResolution {
        switch self {
        case .p1080: .p1080
        case .p720: .p720
        case .p480: .p480
        }
    }
}

nonisolated struct VideoCompressionSettings: Codable, Equatable, Sendable {
    var quality: VideoCompressionQuality = .medium
    var speed: VideoCompressionSpeed = .fast
    /// HEVC: the hardware encoder runs it ~1.7x faster than H.264 at Retina
    /// sizes, and exports are bound by the encoder.
    var codec: VideoCompressionCodec = .hevc
    var resolution: VideoCompressionResolution = .original
    var removeAudio = false
    /// Optional so projects saved before the format picker keep decoding.
    /// A synthesized `Codable` decoder ignores property defaults and throws
    /// on a missing key, and `loadEditDocument` swallows that with `try?` -
    /// a non-optional field here would silently discard the whole project.
    var container: VideoExportContainer?
    /// Studio delivery options. Missing keys preserve the historical render
    /// for existing projects, preferences, and cached-deliverable stamps.
    var frameRate: VideoExportFrameRate?
    var motionBlurEnabled: Bool?
    /// GIF delivery. All optional for the same reason as `container`: an
    /// older project must decode instead of silently losing its edits.
    var deliveryFormat: RecordingDeliveryFormat?
    var gifFrameRate: RecordingGIFFrameRate?
    var gifSize: RecordingGIFSize?

    var effectiveContainer: VideoExportContainer { container ?? .default }
    var effectiveFrameRate: VideoExportFrameRate { frameRate ?? .fps60 }
    var effectiveMotionBlurEnabled: Bool { motionBlurEnabled ?? true }

    /// `container` is the historical source of truth. New exports write
    /// `deliveryFormat` and keep `container` in step for the video paths that
    /// still ask for a container.
    var effectiveDeliveryFormat: RecordingDeliveryFormat {
        if let deliveryFormat { return deliveryFormat }
        return effectiveContainer == .mp4 ? .mp4 : .mov
    }

    var effectiveGIFFrameRate: RecordingGIFFrameRate { gifFrameRate ?? .fps15 }
    var effectiveGIFSize: RecordingGIFSize { gifSize ?? .p720 }

    /// Selecting a video format also updates the container so Share, Copy,
    /// and the session's cached deliverable keep producing that container.
    mutating func chooseDeliveryFormat(_ format: RecordingDeliveryFormat) {
        deliveryFormat = format
        if let container = format.videoContainer {
            self.container = container
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.quality == rhs.quality && lhs.speed == rhs.speed && lhs.codec == rhs.codec
            && lhs.resolution == rhs.resolution && lhs.removeAudio == rhs.removeAudio
            && lhs.container == rhs.container
            && lhs.effectiveFrameRate == rhs.effectiveFrameRate
            && lhs.effectiveMotionBlurEnabled == rhs.effectiveMotionBlurEnabled
            && lhs.effectiveDeliveryFormat == rhs.effectiveDeliveryFormat
            && lhs.effectiveGIFFrameRate == rhs.effectiveGIFFrameRate
            && lhs.effectiveGIFSize == rhs.effectiveGIFSize
    }
}

struct VideoCompressionResult: Sendable {
    let outputURL: URL
    let inputSize: Int64
    let outputSize: Int64

    var reduction: Double? {
        guard inputSize > 0 else { return nil }
        return 1 - Double(outputSize) / Double(inputSize)
    }
}
