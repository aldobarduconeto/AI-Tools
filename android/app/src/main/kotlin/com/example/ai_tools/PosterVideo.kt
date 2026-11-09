package com.example.ai_tools

import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

object PosterVideo {
    fun render(file: File, png: ByteArray, seconds: Double) {
        require(seconds.isFinite() && seconds >= 1.0 / 15 && seconds < Long.MAX_VALUE / 1_000_000.0) { "Informe uma duração válida." }
        val frameCount = kotlin.math.ceil(seconds * 15).toLong()
        val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size)
            ?: error("Não foi possível ler o cartaz.")
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        try {
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        } finally {
            bitmap.recycle()
        }
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            val formats = encoder.codecInfo.getCapabilitiesForType(
                MediaFormat.MIMETYPE_VIDEO_AVC
            ).colorFormats
            val planar = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
            val semi = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
            val color = listOf(planar, semi).firstOrNull { it in formats }
                ?: error("O codificador H.264 do dispositivo não aceita o formato do cartaz.")
            val frame = yuv(pixels, width, height, color == planar)
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, color)
            format.setInteger(MediaFormat.KEY_BIT_RATE, 1_500_000)
            format.setInteger(MediaFormat.KEY_FRAME_RATE, 15)
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val info = MediaCodec.BufferInfo()
                var frameIndex = 0L
                var track = -1
                var finished = false
                var lastProgress = android.os.SystemClock.elapsedRealtime()
                while (!finished) {
                    check(android.os.SystemClock.elapsedRealtime() - lastProgress < 30_000) {
                        "O codificador demorou demais para finalizar."
                    }
                    if (frameIndex <= frameCount) {
                        val index = encoder.dequeueInputBuffer(5000)
                        if (index >= 0) {
                            val end = frameIndex == frameCount
                            if (!end) encoder.getInputBuffer(index)!!.apply { clear(); put(frame) }
                            encoder.queueInputBuffer(
                                index, 0, if (end) 0 else frame.size, (frameIndex / 15) * 1_000_000L + (frameIndex % 15) * 1_000_000L / 15,
                                if (end) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                            )
                            frameIndex++
                            lastProgress = android.os.SystemClock.elapsedRealtime()
                        }
                    }
                    when (val index = encoder.dequeueOutputBuffer(info, 5000)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            track = muxer.addTrack(encoder.outputFormat)
                            muxer.start()
                        }
                        else -> if (index >= 0) {
                            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                muxer.writeSampleData(track, encoder.getOutputBuffer(index)!!, info)
                            }
                            lastProgress = android.os.SystemClock.elapsedRealtime()
                            finished = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            encoder.releaseOutputBuffer(index, false)
                        }
                    }
                }
                muxer.stop()
            } finally {
                muxer.release()
            }
        } finally {
            encoder.release()
        }
    }

    private fun yuv(pixels: IntArray, width: Int, height: Int, planar: Boolean): ByteArray {
        require(width % 2 == 0 && height % 2 == 0)
        val area = width * height
        val data = ByteArray(area * 3 / 2)
        for (y in 0 until height) for (x in 0 until width) {
            val pixel = pixels[y * width + x]
            val r = (pixel shr 16) and 255
            val g = (pixel shr 8) and 255
            val b = pixel and 255
            data[y * width + x] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
            if (y % 2 == 0 && x % 2 == 0) {
                val chroma = y / 2 * (width / 2) + x / 2
                val u = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte()
                val v = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte()
                val position = area + if (planar) chroma else 2 * chroma
                data[position] = u
                data[position + if (planar) area / 4 else 1] = v
            }
        }
        return data
    }
}


