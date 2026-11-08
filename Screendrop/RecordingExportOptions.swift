//
//  RecordingExportOptions.swift
//  Screendrop
//
//  Export settings are asked for at the moment of export rather than parked
//  in a collapsed inspector section nobody opens. Mirrors the share flow in
//  CloudUploadOptions.swift: a button opens a small options popover, and
//  confirming remembers the choice as the default for next time.
//

import SwiftUI

/// Remembers the last-confirmed export settings so a recording that has never
/// been exported starts from what the user picked previously instead of the
/// factory defaults. Projects that already saved their own settings keep them.
enum RecordingExportPreferences {
    private static let settingsKey = "recordingExportDefaultSettings"
    /// Set once the remembered codec has moved to the HEVC default.
    private static let hevcDefaultKey = "recordingExportDefaultsMovedToHEVC"

    static var lastSettings: VideoCompressionSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  var decoded = try? JSONDecoder().decode(
                    VideoCompressionSettings.self,
                    from: data
                  ) else {
                return VideoCompressionSettings()
            }
            // H.264 was remembered when it was the only default. Move it
            // to HEVC once; choosing H.264 again afterwards sticks.
            if !UserDefaults.standard.bool(forKey: hevcDefaultKey) {
                UserDefaults.standard.set(true, forKey: hevcDefaultKey)
                if decoded.codec == .h264 {
                    decoded.codec = .hevc
                    lastSettings = decoded
                }
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}

/// The options form shown from the Export button: quality, codec, resolution,
/// container, frame rate, motion blur, and audio. Confirming hands back the settings
/// and remembers them.
struct RecordingExportOptionsPopover: View {
    let initialSettings: VideoCompressionSettings
    let onConfirm: (VideoCompressionSettings) -> Void

    @State private var settings: VideoCompressionSettings
    @Environment(\.dismiss) private var dismiss

    init(
        initialSettings: VideoCompressionSettings,
        onConfirm: @escaping (VideoCompressionSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onConfirm = onConfirm
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        InspectorPopover(
            title: "Export Options",
            confirmTitle: "Export",
            onCancel: { dismiss() },
            onConfirm: {
                let confirmed = settings
                RecordingExportPreferences.lastSettings = confirmed
                dismiss()
                onConfirm(confirmed)
            }
        ) {
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                // `container` and the GIF fields are optional on disk for
                // backwards compatibility, but the control always shows a
                // concrete choice.
                segmented(
                    "Format",
                    options: RecordingDeliveryFormat.allCases,
                    selection: Binding(
                        get: { settings.effectiveDeliveryFormat },
                        set: { settings.chooseDeliveryFormat($0) }
                    )
                )

                if settings.effectiveDeliveryFormat == .gif {
                    segmented(
                        "GIF frame rate",
                        options: RecordingGIFFrameRate.allCases,
                        selection: Binding(
                            get: { settings.effectiveGIFFrameRate },
                            set: { settings.gifFrameRate = $0 }
                        )
                    )
                    segmented(
                        "GIF size",
                        options: RecordingGIFSize.allCases,
                        selection: Binding(
                            get: { settings.effectiveGIFSize },
                            set: { settings.gifSize = $0 }
                        )
                    )
                } else {
                    segmented("Quality", options: VideoCompressionQuality.allCases, selection: $settings.quality)
                    segmented("Codec", options: VideoCompressionCodec.allCases, selection: $settings.codec)
                    segmented("Resolution", options: VideoCompressionResolution.allCases, selection: $settings.resolution)
                    segmented(
                        "Frame rate",
                        options: VideoExportFrameRate.allCases,
                        selection: Binding(
                            get: { settings.effectiveFrameRate },
                            set: { settings.frameRate = $0 }
                        )
                    )
                }

                toggle("Motion blur", isOn: Binding(
                    get: { settings.effectiveMotionBlurEnabled },
                    set: { settings.motionBlurEnabled = $0 }
                ))
                .help("Soften motion during zooms and pans. Turn off for faster exports with sharper motion.")

                InspectorHint(formatHint)

                if settings.effectiveDeliveryFormat != .gif {
                    toggle("Include audio", isOn: Binding(
                        get: { !settings.removeAudio },
                        set: { settings.removeAudio = !$0 }
                    ))
                    .padding(.top, 2)
                }
            }
        }
    }

    private var formatHint: String {
        switch settings.effectiveDeliveryFormat {
        case .mov:
            "Native QuickTime format for Apple apps."
        case .mp4:
            "Plays on more platforms, including Windows, browsers, and Slack."
        case .gif:
            "An animated image that loops forever. GIFs are silent and get large quickly; 720p at 15 fps is a good balance."
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        InspectorToggleRow(title, isOn: isOn)
    }

    /// Segmented row matching the inspector's group-label-above-control
    /// rhythm, so the popover reads as the same control system as the panel.
    private func segmented<Option: Hashable & RawRepresentable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>
    ) -> some View where Option.RawValue == String {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorGroupLabel(title)
            InspectorSegmented(
                options: options,
                isSelected: { $0 == selection.wrappedValue },
                onTap: { selection.wrappedValue = $0 },
                label: {
                    Text($0.rawValue)
                        .font(.inspectorSegment)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            )
        }
    }
}

/// Wraps any trigger content in a button that opens the export options
/// popover before firing `onExport`. Drop-in replacement for a plain
/// `Button(action: model.export) { ... }` at an export call site.
struct RecordingExportButton<Label: View>: View {
    let currentSettings: VideoCompressionSettings
    let onExport: (VideoCompressionSettings) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            label()
        }
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            RecordingExportOptionsPopover(
                initialSettings: currentSettings,
                onConfirm: onExport
            )
        }
    }
}
