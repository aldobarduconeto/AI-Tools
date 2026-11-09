package com.example.ai_tools

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import java.io.File
import java.nio.ByteBuffer

object VideoClip {
    fun export(context: Context, uri: Uri, file: File, endSeconds: Double?) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val tracks = mutableMapOf<Int, Int>()
                var hasVideo = false
                for (index in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(index)
                    val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                    if (!mime.startsWith("audio/") && !mime.startsWith("video/")) continue
                    tracks[index] = muxer.addTrack(format)
                    extractor.selectTrack(index)
                    if (mime.startsWith("video/")) {
                        hasVideo = true
                        if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                            muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                        }
                    }
                }
                require(hasVideo) { "O arquivo não contém uma faixa de vídeo compatível." }
                muxer.start()
                var buffer = ByteBuffer.allocate(1024 * 1024)
                val info = MediaCodec.BufferInfo()
                val endUs = endSeconds?.let { (it * 1_000_000).toLong() }
                while (extractor.sampleTrackIndex >= 0 &&
                    (endUs == null || extractor.sampleTime < endUs)) {
                    val track = tracks.getValue(extractor.sampleTrackIndex)
                    val sampleSize = extractor.sampleSize
                    require(sampleSize in 0..Int.MAX_VALUE.toLong()) { "Amostra de vídeo inválida." }
                    if (sampleSize > buffer.capacity()) buffer = ByteBuffer.allocate(sampleSize.toInt())
                    buffer.clear()
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                        MediaCodec.BUFFER_FLAG_KEY_FRAME
                    } else 0
                    info.set(0, size, extractor.sampleTime, flags)
                    muxer.writeSampleData(track, buffer, info)
                    if (!extractor.advance()) break
                }
                muxer.stop()
            } finally {
                muxer.release()
            }
        } finally {
            extractor.release()
        }
    }
}

