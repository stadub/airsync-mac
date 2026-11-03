With Swift 6.2 or newer (Xcode 26+), run `swift test` from the repository root on macOS. The package compiles the same
mirroring services used by the app, with no third-party package dependencies.

Coverage includes startup cancellation/completion ownership, Close during audio
restart, continuous bounded process logging, audio flags, persisted phone/desktop
preferences, layout ordering, coordinating native/external audio restarts, and
AppKit hit dispatch between the name drag surface and an adjacent button.
Process creation and audio sessions are injected so tests need no Android device.

These tests do not replace an Xcode app build or live verification of ADB discovery,
keyboard input, sound playback, window dragging, and button interaction.
