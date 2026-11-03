/*
 * DroidLink Android Companion Application
 * Copyright (c) 2026 DroidLink Project. All rights reserved.
 *
 * Configuration settings for screen recording, video encoding, and audio streaming.
 */

package com.droidlink.companion.models

import android.os.Parcel
import android.os.Parcelable
import com.droidlink.companion.utils.Constants
import kotlinx.serialization.Serializable

/**
 * Screen capture and video encoder configuration parameters.
 *
 * @property width Video frame width in pixels (must be positive and divisible by 2).
 * @property height Video frame height in pixels (must be positive and divisible by 2).
 * @property fps Target capture and encoder frame rate (15 to 120).
 * @property codec MIME type of the video encoder (e.g. video/avc, video/hevc).
 * @property bitrate Encoding bitrate in bits per second (e.g. 8_000_000 for 8 Mbps).
 * @property audioEnabled Whether device internal audio capture is enabled.
 */
@Serializable
data class MirrorConfig(
    val width: Int = Constants.DEFAULT_VIDEO_WIDTH,
    val height: Int = Constants.DEFAULT_VIDEO_HEIGHT,
    val fps: Int = Constants.DEFAULT_VIDEO_FPS,
    val codec: String = Constants.DEFAULT_CODEC,
    val bitrate: Int = Constants.DEFAULT_VIDEO_BITRATE,
    val audioEnabled: Boolean = true
) : Parcelable {

    constructor(parcel: Parcel) : this(
        parcel.readInt(),
        parcel.readInt(),
        parcel.readInt(),
        parcel.readString() ?: Constants.DEFAULT_CODEC,
        parcel.readInt(),
        parcel.readByte() != 0.toByte()
    )

    init {
        require(width > 0 && width % 2 == 0) { "Width must be positive and even (got $width)" }
        require(height > 0 && height % 2 == 0) { "Height must be positive and even (got $height)" }
        require(fps in 15..120) { "FPS must be between 15 and 120 (got $fps)" }
        require(bitrate in 500_000..50_000_000) { "Bitrate must be between 500 kbps and 50 Mbps (got $bitrate)" }
    }

    override fun writeToParcel(parcel: Parcel, flags: Int) {
        parcel.writeInt(width)
        parcel.writeInt(height)
        parcel.writeInt(fps)
        parcel.writeString(codec)
        parcel.writeInt(bitrate)
        parcel.writeByte(if (audioEnabled) 1 else 0)
    }

    override fun describeContents(): Int = 0

    companion object CREATOR : Parcelable.Creator<MirrorConfig> {
        override fun createFromParcel(parcel: Parcel): MirrorConfig {
            return MirrorConfig(parcel)
        }

        override fun newArray(size: Int): Array<MirrorConfig?> {
            return arrayOfNulls(size)
        }

        /**
         * Preset profile for 1080p 60fps high quality stream.
         */
        val HD_1080P_60FPS = MirrorConfig(
            width = 1920,
            height = 1080,
            fps = 60,
            bitrate = 8_000_000
        )

        /**
         * Preset profile for 720p 60fps standard stream.
         */
        val HD_720P_60FPS = MirrorConfig(
            width = 1280,
            height = 720,
            fps = 60,
            bitrate = 4_500_000
        )

        /**
         * Preset profile for 2K high resolution display mirroring.
         */
        val QUAD_HD_2K = MirrorConfig(
            width = 2560,
            height = 1440,
            fps = 60,
            bitrate = 14_000_000
        )
    }
}
