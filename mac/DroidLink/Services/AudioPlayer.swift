//
//  AudioPlayer.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AVFoundation
import AudioToolbox
import Observation

/// Low-latency real-time audio playback engine for Android audio forwarding.
@Observable
public final class AudioPlayer: @unchecked Sendable {
    // MARK: - Observable State

    public var isPlaying: Bool = false
    public var isMuted: Bool = false {
        didSet {
            playerNode.volume = isMuted ? 0.0 : volume
        }
    }
    public var volume: Float = 1.0 {
        didSet {
            if !isMuted {
                playerNode.volume = max(0.0, min(1.0, volume))
            }
        }
    }

    // MARK: - Audio Engine Pipeline

    private let audioEngine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let audioFormat: AVAudioFormat

    private let audioQueue = DispatchQueue(label: "com.droidlink.audioplayer", qos: .userInteractive)
    private var isEngineRunning: Bool = false

    // MARK: - Initialization

    public init(sampleRate: Double = 48000.0, channels: AVAudioChannelCount = 2) {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            fatalError("Failed to create standard AVAudioFormat for AudioPlayer")
        }
        self.audioFormat = format

        setupEngine()
    }

    deinit {
        stop()
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        playerNode.volume = volume
    }

    // MARK: - Lifecycle Controls

    public func start() {
        audioQueue.async { [weak self] in
            guard let self = self, !self.isEngineRunning else { return }
            do {
                try self.audioEngine.start()
                self.playerNode.play()
                self.isEngineRunning = true
                DispatchQueue.main.async {
                    self.isPlaying = true
                }
            } catch {
                print("Failed to start AVAudioEngine: \(error)")
            }
        }
    }

    public func stop() {
        audioQueue.async { [weak self] in
            guard let self = self, self.isEngineRunning else { return }
            self.playerNode.stop()
            self.audioEngine.stop()
            self.isEngineRunning = false
            DispatchQueue.main.async {
                self.isPlaying = false
            }
        }
    }

    public func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Packet Ingestion

    /// Schedules raw interleaved 16-bit PCM samples received from the device stream
    public func scheduleRawPCM16(data: Data) {
        guard isEngineRunning, !data.isEmpty else { return }

        audioQueue.async { [weak self] in
            guard let self = self else { return }

            let channelCount = Int(self.audioFormat.channelCount)
            let sampleSize = MemoryLayout<Int16>.size
            let frameCount = AVAudioFrameCount(data.count / (channelCount * sampleSize))

            guard frameCount > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.audioFormat, frameCapacity: frameCount) else {
                return
            }

            pcmBuffer.frameLength = frameCount

            data.withUnsafeBytes { rawBytes in
                guard let int16Ptr = rawBytes.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

                // De-interleave and convert Int16 [-32768, 32767] to Float32 [-1.0, 1.0]
                if let floatChannels = pcmBuffer.floatChannelData {
                    for frame in 0..<Int(frameCount) {
                        for channel in 0..<channelCount {
                            let sampleInt16 = int16Ptr[frame * channelCount + channel]
                            let sampleFloat = Float(sampleInt16) / 32768.0
                            floatChannels[channel][frame] = sampleFloat
                        }
                    }
                }
            }

            self.playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
    }

    /// Schedules pre-decoded float PCM buffers
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isEngineRunning else { return }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Handles compressed Opus packet parsing (companion app stream)
    public func handleOpusPacket(_ data: Data) {
        // TODO: Integrate libopus or AudioConverter for hardware-assisted Opus decoding.
        // For standard scrcpy audio streaming, raw PCM audio forward or AAC is typically used.
        // If raw PCM:
        scheduleRawPCM16(data: data)
    }
}
