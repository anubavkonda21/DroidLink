//
//  VideoDecoder.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Delegate protocol notifying consumers of newly decompressed video frames.
public protocol VideoDecoderDelegate: AnyObject {
    func videoDecoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime)
    func videoDecoder(_ decoder: VideoDecoder, didFailWithError error: Error)
}

/// Hardware-accelerated H.264 / H.265 video decoder using Apple's VideoToolbox.
public final class VideoDecoder: @unchecked Sendable {
    // MARK: - Properties

    public weak var delegate: VideoDecoderDelegate?

    public private(set) var codec: VideoCodec
    public private(set) var videoWidth: Int32 = 0
    public private(set) var videoHeight: Int32 = 0
    public private(set) var isConfigured: Bool = false

    // MARK: - VideoToolbox State

    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    // Parameter sets for H.264
    private var spsData: Data?
    private var ppsData: Data?

    // Parameter sets for H.265 (HEVC)
    private var vpsData: Data?
    private var hevcSpsData: Data?
    private var hevcPpsData: Data?

    private let decoderQueue = DispatchQueue(label: "com.droidlink.videodecoder", qos: .userInteractive)
    private var frameCount: Int64 = 0

    // MARK: - Initialization

    public init(codec: VideoCodec = .h264) {
        self.codec = codec
    }

    deinit {
        invalidateSession()
    }

    // MARK: - Configuration

    /// Updates the target codec and resets existing decompression sessions
    public func setCodec(_ newCodec: VideoCodec) {
        decoderQueue.async { [weak self] in
            guard let self = self else { return }
            self.codec = newCodec
            self.invalidateSession()
        }
    }

    /// Resets the current decompression session
    public func reset() {
        decoderQueue.async { [weak self] in
            self?.invalidateSession()
        }
    }

    // MARK: - Packet Processing

    /// Parses incoming raw Annex B elementary stream data, extracts NAL units, and decodes frames
    public func processRawStreamData(_ data: Data) {
        decoderQueue.async { [weak self] in
            guard let self = self else { return }
            self.parseAnnexBPackets(data)
        }
    }

    /// Decodes a single AVCC / length-prefixed NAL unit
    public func decodeNALUnit(_ nalData: Data, presentationTime: CMTime = .invalid) {
        decoderQueue.async { [weak self] in
            guard let self = self else { return }
            self.handleNALUnit(nalData, presentationTime: presentationTime)
        }
    }

    // MARK: - Annex B Parser

    private func parseAnnexBPackets(_ data: Data) {
        let count = data.count
        guard count >= 4 else { return }

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            var nalStart = -1
            var nalLength = 0
            var i = 0

            while i < count - 3 {
                // Check for 4-byte start code (0x00, 0x00, 0x00, 0x01)
                var startCodeLen = 0
                if ptr[i] == 0 && ptr[i+1] == 0 && ptr[i+2] == 0 && ptr[i+3] == 1 {
                    startCodeLen = 4
                } else if ptr[i] == 0 && ptr[i+1] == 0 && ptr[i+2] == 1 {
                    startCodeLen = 3
                }

                if startCodeLen > 0 {
                    if nalStart != -1 {
                        let nalEnd = i
                        nalLength = nalEnd - nalStart
                        if nalLength > 0 {
                            let nalSubdata = data.subdata(in: nalStart..<nalEnd)
                            self.handleNALUnit(nalSubdata, presentationTime: CMTime(value: self.frameCount, timescale: 60))
                            self.frameCount += 1
                        }
                    }
                    nalStart = i + startCodeLen
                    i += startCodeLen
                } else {
                    i += 1
                }
            }

            // Remainder NAL unit
            if nalStart != -1 && nalStart < count {
                let nalSubdata = data.subdata(in: nalStart..<count)
                self.handleNALUnit(nalSubdata, presentationTime: CMTime(value: self.frameCount, timescale: 60))
                self.frameCount += 1
            }
        }
    }

    // MARK: - NAL Unit Dispatcher

    private func handleNALUnit(_ nalData: Data, presentationTime: CMTime) {
        guard !nalData.isEmpty else { return }

        switch codec {
        case .h264:
            handleH264NAL(nalData, presentationTime: presentationTime)
        case .h265:
            handleHEVCNAL(nalData, presentationTime: presentationTime)
        case .av1:
            // TODO: VideoToolbox AV1 hardware decompression is available on Apple Silicon M3+
            // Fallback or handle via AV1 format description
            break
        }
    }

    // MARK: - H.264 Handler

    private func handleH264NAL(_ nalData: Data, presentationTime: CMTime) {
        let nalType = nalData[0] & 0x1F

        switch nalType {
        case 7: // SPS
            self.spsData = nalData
            checkAndCreateH264Session()
        case 8: // PPS
            self.ppsData = nalData
            checkAndCreateH264Session()
        case 1, 5: // Non-IDR Slice (1) or IDR Keyframe Slice (5)
            feedFrameToDecompressor(nalData: nalData, presentationTime: presentationTime)
        default:
            break
        }
    }

    private func checkAndCreateH264Session() {
        guard let sps = spsData, let pps = ppsData else { return }

        sps.withUnsafeBytes { spsBuffer in
            pps.withUnsafeBytes { ppsBuffer in
                guard let spsPtr = spsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsPtr = ppsBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

                let parameterSetPointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let parameterSetSizes: [Int] = [sps.count, pps.count]

                var newFormatDesc: CMFormatDescription?
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormatDesc
                )

                guard status == noErr, let formatDesc = newFormatDesc else {
                    let err = NSError(domain: "VideoDecoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create H.264 format description"])
                    self.delegate?.videoDecoder(self, didFailWithError: err)
                    return
                }

                self.createDecompressionSession(with: formatDesc)
            }
        }
    }

    // MARK: - H.265 (HEVC) Handler

    private func handleHEVCNAL(_ nalData: Data, presentationTime: CMTime) {
        let nalType = (nalData[0] >> 1) & 0x3F

        switch nalType {
        case 32: // VPS
            self.vpsData = nalData
            checkAndCreateHEVCSession()
        case 33: // SPS
            self.hevcSpsData = nalData
            checkAndCreateHEVCSession()
        case 34: // PPS
            self.hevcPpsData = nalData
            checkAndCreateHEVCSession()
        case 1, 19, 20: // Trailing / IDR slice
            feedFrameToDecompressor(nalData: nalData, presentationTime: presentationTime)
        default:
            break
        }
    }

    private func checkAndCreateHEVCSession() {
        guard let vps = vpsData, let sps = hevcSpsData, let pps = hevcPpsData else { return }

        vps.withUnsafeBytes { vpsBuf in
            sps.withUnsafeBytes { spsBuf in
                pps.withUnsafeBytes { ppsBuf in
                    guard let vpsPtr = vpsBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let spsPtr = spsBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let ppsPtr = ppsBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

                    let pointers = [vpsPtr, spsPtr, ppsPtr]
                    let sizes = [vps.count, sps.count, pps.count]

                    var newFormatDesc: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &newFormatDesc
                    )

                    guard status == noErr, let formatDesc = newFormatDesc else { return }
                    self.createDecompressionSession(with: formatDesc)
                }
            }
        }
    }

    // MARK: - Decompression Session Creation

    private func createDecompressionSession(with formatDesc: CMVideoFormatDescription) {
        invalidateSession()
        self.formatDescription = formatDesc

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        self.videoWidth = dimensions.width
        self.videoHeight = dimensions.height

        let destinationImageBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: Int(dimensions.width),
            kCVPixelBufferHeightKey as String: Int(dimensions.height)
        ]

        var outputCallbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destinationImageBufferAttributes as CFDictionary,
            outputCallback: &outputCallbackRecord,
            decompressionSessionOut: &session
        )

        if status == noErr, let session = session {
            self.decompressionSession = session
            self.isConfigured = true
        } else {
            let error = NSError(domain: "VideoDecoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "VTDecompressionSessionCreate failed with code \(status)"])
            self.delegate?.videoDecoder(self, didFailWithError: error)
        }
    }

    // MARK: - Feed NAL to VideoToolbox

    private func feedFrameToDecompressor(nalData: Data, presentationTime: CMTime) {
        guard let session = decompressionSession, let formatDesc = formatDescription else { return }

        // Convert Annex-B or naked NAL to AVCC format: 4-byte big-endian length prefix followed by NAL data
        var nalLength = UInt32(nalData.count).bigEndian
        var blockData = Data(bytes: &nalLength, count: 4)
        blockData.append(nalData)

        var blockBuffer: CMBlockBuffer?
        let blockStatus = blockData.withUnsafeBytes { rawBuf in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: blockData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: blockData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard blockStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return }

        blockData.withUnsafeBytes { rawBuf in
            if let ptr = rawBuf.baseAddress {
                CMBlockBufferReplaceDataBytes(with: ptr, blockBuffer: bb, offsetIntoDestination: 0, dataLength: blockData.count)
            }
        }

        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray = [blockData.count]
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: presentationTime.isValid ? presentationTime : CMTime(value: frameCount, timescale: 60),
            decodeTimeStamp: CMTime.invalid
        )

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: sampleSizeArray,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sb = sampleBuffer else { return }

        var flags: VTDecodeInfoFlags = []
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sb,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flags
        ) { [weak self] status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
            guard let self = self, status == noErr, let pixelBuffer = imageBuffer else { return }
            self.delegate?.videoDecoder(self, didOutputPixelBuffer: pixelBuffer, presentationTimestamp: presentationTimeStamp)
        }
    }

    private func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
        isConfigured = false
        spsData = nil
        ppsData = nil
        vpsData = nil
        hevcSpsData = nil
        hevcPpsData = nil
    }
}

// MARK: - Global C Callback

private func decompressionOutputCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()

    if status == noErr, let pixelBuffer = imageBuffer {
        decoder.delegate?.videoDecoder(decoder, didOutputPixelBuffer: pixelBuffer, presentationTimestamp: presentationTimeStamp)
    }
}
