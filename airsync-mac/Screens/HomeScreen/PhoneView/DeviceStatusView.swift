//
//  DeviceStatusView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//

import SwiftUI
import AppKit
import Combine

struct DeviceStatusView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingVolumePopover = false
    @State private var tempVolume: Double = 100
    @State private var isDragging = false
    @State private var showingPlusPopover = false
    var showMediaToggle: Bool = true
    var useGlass: Bool = true
    var compact: Bool = false
    var showMediaCard: Bool = true
    var showBattery: Bool = true
    var showSound: Bool = true

    var body: some View {

        VStack {
            if let music = appState.status?.music {
                let title = music.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty && !appState.isMusicCardHidden && showMediaToggle && showMediaCard {
                    MediaPlayerView(music: music)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack(spacing: 8) {
                let batteryLevel = appState.status?.battery.level ?? 100
                let batteryIsCharging = appState.status?.battery.isCharging ?? false


                if showBattery {
                if compact {
                    VStack(spacing: 0) {
                        Image(systemName: batteryIcon(for: batteryLevel, isCharging: batteryIsCharging))
                            .font(.system(size: 11))
                            .contentTransition(.symbolEffect)
                        Text("\(batteryLevel)%")
                            .font(.system(size: 8))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                    .help("Battery: \(batteryLevel)%")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Battery: \(batteryLevel)%")
                } else {
                HStack{
                    Image(systemName: batteryIcon(for: batteryLevel, isCharging: batteryIsCharging))
                        .help("\(batteryLevel)%")
                        .contentTransition(.symbolEffect)
                    Text("\(batteryLevel)%")
                        .font(.caption2)
                }
                .padding(.leading, 4)

                }

                }

                let volume = appState.status?.music?.volume ?? 100
                let isMuted = appState.status?.music?.isMuted ?? false

                if showSound {
                GlassButtonView(
                    label: "Music Player",
                    systemImage: volumeIcon(for: volume, isMuted: isMuted),
                    iconOnly: true,
                    primary: false,
                    action: {
                        if AppState.shared.isPlus && AppState.shared.licenseCheck {
                            if let currentVolume = appState.status?.music?.volume {
                                tempVolume = Double(currentVolume)
                            }
                            showingVolumePopover.toggle()
                        } else {
                            showingPlusPopover = true
                        }
                    }
                )
                .help(isMuted ? "Muted" : "\(volume)%")
                .contentTransition(.symbolEffect)
                    .popover(isPresented: $showingVolumePopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            MirrorAudioRoutePicker()
                            Divider()
                            HStack {
                                Image(systemName: "speaker.fill")

                                Slider(
                                    value: $tempVolume,
                                    in: 0...100,
                                    onEditingChanged: { editing in
                                        if !editing {
                                            WebSocketServer.shared.setVolume(Int(tempVolume))
                                        }
                                        if editing {
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                        } else {
                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                                        }
                                        isDragging = editing
                                    }
                                )
                                .focusable(false)
                                .onChange(of: tempVolume) { oldValue, newValue in
                                    guard isDragging else { return }
                                    let lastTick = floor(oldValue / 5.0) * 5.0
                                    let currentTick = floor(newValue / 5.0) * 5.0
                                    if currentTick != lastTick {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                                    }
                                }

                                Image(systemName: "speaker.wave.3.fill")
                            }
                        }
                        .padding()
                        .frame(width: 260)
                    }
                    .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                        PlusFeaturePopover(message: "Control volume with AirSync+")
                    }
 
                }
                if let music = appState.status?.music {
                    let title = music.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty && showMediaToggle {
                        GlassButtonView(
                            label: "Music Player",
                            systemImage: music.isPlaying == true ? "play.rectangle" : "music.note",
                            iconOnly: true,
                            primary: false,
                            action: {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    appState.isMusicCardHidden.toggle()
                                }
                            }
                        )
                        .help(appState.isMusicCardHidden ? "Show player" : "Hide player")
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .padding(.bottom, compact || appState.isMusicCardHidden ? 0 : 8)

        }
        .padding(compact ? 0 : 4)
        .applyGlassViewIfAvailable(enabled: useGlass)
        .animation(
            .easeInOut(duration: 0.25),
            value: "\(appState.status?.battery.level ?? 0)-\(appState.status?.music?.volume ?? 0)"
        )
        .onAppear {
            // Ensure media card is collapsed at startup if no media is present
            checkAndCollapseIfNoMedia()
        }
        .onChange(of: appState.status?.music?.title) { _, newTitle in
            // Auto-collapse music card when there's no media playing
            checkAndCollapseIfNoMedia()
        }
        .onChange(of: appState.status?.music?.artist) { _, newArtist in
            // Also check when artist changes (could become empty)
            checkAndCollapseIfNoMedia()
        }
    }
    
    // Helper function to check if there's valid media info and collapse if not
    private func checkAndCollapseIfNoMedia() {
        let hasValidMedia = {
            // Check if we have status and music info
            guard let music = appState.status?.music else {
                return false
            }
            
            // Check if title and artist are non-empty after trimming
            let title = music.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = music.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return !title.isEmpty && !artist.isEmpty
        }()
        
        // If no valid media info and card is currently expanded, collapse it
        if !hasValidMedia && !appState.isMusicCardHidden {
            withAnimation(.easeInOut(duration: 0.28)) {
                appState.isMusicCardHidden = true
            }
        }
    }

    // Battery icon helper
    private func batteryIcon(for level: Int, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch level {
        case 0...10: return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default: return "battery.100"
        }
    }

    // Volume icon helper
    private func volumeIcon(for volume: Int, isMuted: Bool) -> String {
        if isMuted || volume == 0 {
            return "speaker.slash"
        } else if volume <= 25 {
            return "speaker.wave.1"
        } else if volume <= 50 {
            return "speaker.wave.2"
        } else {
            return "speaker.wave.3"
        }
    }
}

#Preview {
    DeviceStatusView()
}

struct MirrorAudioRoutePicker: View {
    @AppStorage("noAudio") private var noAudio = false
    @AppStorage("keepPhoneAudio") private var keepPhoneAudio = true
    @ObservedObject private var routing = MirrorAudioRouting.shared
    var compact = false

    private var route: AudioRoute { noAudio ? .phone : (keepPhoneAudio ? .both : .mac) }
    private var title: String { noAudio ? "Phone" : (keepPhoneAudio ? "Both" : "Mac") }
    private var selection: Binding<AudioRoute> {
        Binding(get: { route }, set: { if $0 != route { routing.select($0) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if compact {
                Menu {
                    Picker("Play sound on", selection: selection) {
                        Text("Phone").tag(AudioRoute.phone)
                        Text("Mac").tag(AudioRoute.mac)
                        Text("Both").tag(AudioRoute.both)
                    }
                } label: {
                    Label(routing.isChanging ? "Switching…" : title, systemImage: "speaker.wave.2")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Play phone sound on Phone, Mac, or Both")
            } else {
                Text("Play sound on").font(.caption).foregroundStyle(.secondary)
                Picker("Play sound on", selection: selection) {
                    Text("Phone").tag(AudioRoute.phone)
                    Text("Mac").tag(AudioRoute.mac)
                    Text("Both").tag(AudioRoute.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(routing.isChanging ? "Reconnecting mirror…" : "Applies while mirroring. Mirror windows reopen automatically when changed.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = routing.error {
                Text(error).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(routing.isChanging)
    }
}
