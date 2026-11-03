//
//  PhoneView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI

struct PhoneView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject private var streamClient = ScrcpyStreamClient.shared
    @State private var displayedImage: NSImage?
    @AppStorage("showEmbeddedMirrorNavigation") private var showEmbeddedMirrorNavigation = true

    private var safeRatio: CGFloat {
        let width = streamClient.videoWidth
        let height = streamClient.videoHeight
        if width > 0 && height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 9.0 / 19.5
    }

    var body: some View {
        GeometryReader { geo in
            let controlsHeight: CGFloat = appState.isSidebarMirroring && showEmbeddedMirrorNavigation ? 52 : 0
            let availableWidth = max(1, geo.size.width - 24)
            let availableHeight = max(1, geo.size.height - controlsHeight - 16)
            let cardWidth: CGFloat = appState.isSidebarMirroring
                ? min(availableWidth, availableHeight * safeRatio) : 220
            let cardHeight: CGFloat = appState.isSidebarMirroring ? (cardWidth / safeRatio) : 460
            let corner: CGFloat = 24
            VStack(spacing: 8) {
                ZStack {
                    // Wallpaper background layer(s) WITH 3D tilt
                    FadingImageView(image: displayedImage, duration: 0.75)
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.35), Color.black.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .opacity(appState.isSidebarMirroring ? 0 : 1)

                    // Seasonal Snowfall Overlay
    //                SnowfallView()

                    // Foreground content
                    if appState.isSidebarMirroring {
                        SidebarMirrorView()
                            .transition(.blurReplace)
                    } else {
                        ScreenView()
                            .padding(.horizontal, 4)
                            .transition(.blurReplace)
                    }

                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 22, x: 0, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: corner))
                .onAppear { updateImage() }
                .onChange(of: appState.status?.music?.isPlaying) { updateImage() }
                .onChange(of: appState.status?.music?.albumArt) { updateImage() }
                .onChange(of: AppState.shared.currentDeviceWallpaperBase64) { updateImage() }
                .onChange(of: appState.isSidebarMirroring) { _, _ in updateImage() }

                if appState.isSidebarMirroring && showEmbeddedMirrorNavigation {
                    MirrorNavigationBar()
                        .frame(width: cardWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateImage() {
        let base64 = (appState.status?.music?.isPlaying ?? false)
            ? appState.status?.music?.albumArt
            : AppState.shared.currentDeviceWallpaperBase64

        guard let base64 = base64,
              let data = Data(base64Encoded: base64.stripBase64Prefix()),
              let nsImage = NSImage(data: data) else { return }
        // Setting displayedImage triggers fade in representable
        displayedImage = nsImage
    }
}

#Preview {
    PhoneView()
}
