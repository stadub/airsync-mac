import Foundation
import Network
import AVFoundation

final class ScrcpyAudioClient {
    static let shared = ScrcpyAudioClient()
    private let queue = DispatchQueue(label: "com.airsync.scrcpy.audio", qos: .userInteractive)
    private var connection: NWConnection?
    private var generation = UUID()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var queuedFrames = 0
    private var isPrimed = false
    private var playbackGeneration = UUID()
    private var targetBufferFrames = 9600
    private var reportedSignal = false

    func connect(host: String = "127.0.0.1", port: UInt16 = 1234, onSocketReady: @escaping () -> Void) {
        queue.async {
            self.stop()
            let generation = self.generation
            let milliseconds = UserDefaults.standard.object(forKey: "phoneAudioBufferMS") as? Double ?? 200
            self.targetBufferFrames = Int(min(500, max(60, milliseconds)) * 48)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                guard let self, self.generation == generation else { return }
                switch state {
                case .ready:
                    // The server accepts video, audio, then control sockets in that order.
                    DispatchQueue.main.async(execute: onSocketReady)
                    self.readCodec(generation)
                case .failed(let error):
                    print("[phone-audio] Connection failed: \(error)")
                    self.stop()
                default: break
                }
            }
            connection.start(queue: self.queue)
        }
    }

    func disconnect() { queue.async { self.stop() } }

    private func stop() {
        generation = UUID()
        connection?.cancel()
        connection = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        format = nil
        queuedFrames = 0
        isPrimed = false
        playbackGeneration = UUID()
        reportedSignal = false
    }

    private func receive(_ count: Int, _ generation: UUID, completion: @escaping (Data) -> Void) {
        connection?.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            guard let self, self.generation == generation else { return }
            guard error == nil, let data, data.count == count else {
                print("[phone-audio] Audio stream ended: \(String(describing: error))")
                self.stop()
                return
            }
            completion(data)
        }
    }

    private func readCodec(_ generation: UUID) {
        receive(4, generation) { [weak self] data in
            guard let self else { return }
            let codec = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard codec == 0x00726177 else {
                print("[phone-audio] Phone audio unavailable (codec/status \(codec)); video remains active")
                self.stop()
                return
            }
            self.readFrame(generation)
        }
    }

    private func readFrame(_ generation: UUID) {
        receive(12, generation) { [weak self] header in
            guard let self else { return }
            let size = header.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= 65536 else { self.stop(); return }
            let config = header[0] & 0x40 != 0
            self.receive(size, generation) { [weak self] data in
                guard let self else { return }
                if !config { self.play(data, generation) }
                self.readFrame(generation)
            }
        }
    }

    private func play(_ data: Data, _ generation: UUID) {
        guard let samples = ScrcpyPCM.decode(data) else { return }
        if engine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
                self.engine = engine
                self.player = player
                self.format = format
                print("[phone-audio] Playback active on Mac output (48 kHz stereo)")
            } catch {
                print("[phone-audio] Playback could not start: \(error)")
                stop()
                return
            }
        }
        guard let format, let player,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.left.count)),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = buffer.frameCapacity
        for index in samples.left.indices {
            channels[0][index] = samples.left[index]
            channels[1][index] = samples.right[index]
        }
        if !reportedSignal && (samples.left.contains(where: { abs($0) > 0.001 }) || samples.right.contains(where: { abs($0) > 0.001 })) {
            reportedSignal = true
            print("[phone-audio] Non-silent phone audio received")
        }
        // Bound stale audio without dropping arbitrary new packets during normal jitter.
        if queuedFrames > max(48000, targetBufferFrames * 4) {
            playbackGeneration = UUID()
            player.stop()
            queuedFrames = 0
            isPrimed = false
            print("[phone-audio] Trimming stale audio backlog")
        }
        let playbackGeneration = self.playbackGeneration
        let frameCount = samples.left.count
        queuedFrames += frameCount
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == generation,
                      self.playbackGeneration == playbackGeneration else { return }
                self.queuedFrames = max(0, self.queuedFrames - frameCount)
                if self.queuedFrames == 0 && self.isPrimed {
                    self.player?.pause()
                    self.isPrimed = false
                    print("[phone-audio] Network underrun; refilling audio buffer")
                }
            }
        }
        if !isPrimed && queuedFrames >= targetBufferFrames {
            isPrimed = true
            player.play()
            print("[phone-audio] Buffered playback started (target \(targetBufferFrames / 48) ms)")
        }
    }
}
