package com.example.ai_tools

import android.content.Context
import android.net.Uri
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import java.io.File

object Mp3Audio {
    fun decode(context: Context, uri: Uri): ByteArray {
        val input = File.createTempFile("audio-import-", ".bin", context.cacheDir)
        try {
            val source = context.contentResolver.openInputStream(uri)
                ?: error("Não foi possível abrir o áudio.")
            source.use { stream -> input.outputStream().use { stream.copyTo(it) } }
            return convert(context, input, ".wav", arrayOf("-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le"))
        } finally {
            input.delete()
        }
    }

    fun encode(context: Context, wav: ByteArray, bitrate: Int): ByteArray {
        require(bitrate in listOf(64, 96, 128, 160))
        val input = File.createTempFile("pcm-", ".wav", context.cacheDir)
        try {
            input.writeBytes(wav)
            return convert(context, input, ".mp3", arrayOf("-c:a", "libmp3lame", "-b:a", "${bitrate}k"))
        } finally {
            input.delete()
        }
    }

    private fun convert(context: Context, input: File, extension: String, options: Array<String>): ByteArray {
        val output = File.createTempFile("audio-", extension, context.cacheDir)
        try {
            val session = FFmpegKit.executeWithArguments(arrayOf(
                "-nostdin", "-y", "-i", input.path, "-map", "0:a:0", *options, output.path,
            ))
            check(ReturnCode.isSuccess(session.returnCode) && output.length() > 0) {
                "Não foi possível converter o áudio."
            }
            return output.readBytes()
        } finally {
            output.delete()
        }
    }
}
