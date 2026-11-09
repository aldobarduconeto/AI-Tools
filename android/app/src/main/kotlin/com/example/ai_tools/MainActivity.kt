package com.example.ai_tools

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var kind = ""
    private var selectedVideo: Uri? = null
    private var exportAction: ((Uri) -> Unit)? = null
    private var speech: TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_tools/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "posterVideo" -> {
                        val png = call.argument<ByteArray>("png")
                        val seconds = call.argument<Double>("seconds")
                        if (png == null || seconds == null) {
                            result.error("video", "Informe o cartaz e a duração.", null)
                        } else {
                            exportVideo(result, "cartaz.mp4") { PosterVideo.render(it, png, seconds) }
                        }
                        return@setMethodCallHandler
                    }
                    "clip" -> {
                        val uri = selectedVideo
                        val end = call.argument<Double>("end")
                        if (uri == null) {
                            result.error("clip", "Selecione o vídeo novamente.", null)
                        } else {
                            exportVideo(result, "video.mp4") { VideoClip.export(this, uri, it, end) }
                        }
                        return@setMethodCallHandler
                    }
                    "speechLimit" -> {
                        result.success(TextToSpeech.getMaxSpeechInputLength())
                        return@setMethodCallHandler
                    }
                    "speech" -> {
                        val text = call.arguments as? String
                        if (text.isNullOrBlank() || text.length > TextToSpeech.getMaxSpeechInputLength()) {
                            result.error("speech", "Use um texto curto para a narração.", null)
                        } else {
                            synthesize(text, result)
                        }
                        return@setMethodCallHandler
                    }
                    "mp3" -> {
                        val wav = call.argument<ByteArray>("wav")
                        val bitrate = call.argument<Int>("bitrate")
                        if (wav == null || bitrate == null) {
                            result.error("mp3", "Informe o áudio e a qualidade.", null)
                        } else {
                            worker.execute {
                                val encoded = runCatching { Mp3Audio.encode(this, wav, bitrate) }
                                runOnUiThread {
                                    encoded.fold(
                                        onSuccess = { result.success(it) },
                                        onFailure = { result.error("mp3", it.message, null) },
                                    )
                                }
                            }
                        }
                        return@setMethodCallHandler
                    }
                    "export", "exportJpeg" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                        val mime = call.argument<String>("mime")
                        val expectedMime = when (name?.substringAfterLast('.')?.lowercase()) {
                            "mp3" -> "audio/mpeg"
                            "png" -> "image/png"
                            "jpg" -> "image/jpeg"
                            "mp4" -> "video/mp4"
                            else -> null
                        }
                        val jpeg = call.method == "exportJpeg"
                        if (bytes == null || name == null || mime == null ||
                            mime != expectedMime || jpeg != (mime == "image/jpeg")) {
                            result.error("export", "Use MP3, PNG, JPG ou MP4.", null)
                        } else {
                            startExport(result, name, mime) { target ->
                                if (jpeg) {
                                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                        ?: error("Não foi possível abrir a imagem.")
                                    try {
                                        output(target).use {
                                            check(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it)) {
                                                "Não foi possível codificar a imagem em JPG."
                                            }
                                        }
                                    } finally {
                                        bitmap.recycle()
                                    }
                                } else {
                                    output(target).use { it.write(bytes) }
                                }
                            }
                        }
                        return@setMethodCallHandler
                    }
                }
                val requested = call.arguments as? String
                if (call.method != "pick" || requested !in listOf("image", "video", "audio")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pending != null) {
                    result.error("busy", "Já existe uma seleção em andamento.", null)
                    return@setMethodCallHandler
                }
                kind = checkNotNull(requested)
                pending = result
                try {
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "$kind/*"
                    }, PICK)
                } catch (error: Exception) {
                    pending = null
                    result.error("picker", error.message, null)
                }
            }
    }

    private fun output(target: Uri) = contentResolver.openOutputStream(target)
        ?: error("Não foi possível abrir o destino.")

    private fun exportVideo(result: MethodChannel.Result, name: String, render: (File) -> Unit) {
        startExport(result, name, "video/mp4") { target ->
            val file = File.createTempFile("video-", ".mp4", cacheDir)
            try {
                render(file)
                file.inputStream().use { input -> output(target).use { input.copyTo(it) } }
            } finally {
                file.delete()
            }
        }
    }

    private fun startExport(
        result: MethodChannel.Result, name: String, mime: String, action: (Uri) -> Unit,
    ) {
        if (pending != null) {
            result.error("export", "Já existe uma operação em andamento.", null)
            return
        }
        pending = result
        exportAction = action
        try {
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, name)
            }, EXPORT)
        } catch (error: Exception) {
            pending = null
            exportAction = null
            result.error("export", error.message, null)
        }
    }
    @Deprecated("FlutterActivity forwards the Android document-picker result here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == EXPORT) {
            val result = pending ?: return
            val action = exportAction
            exportAction = null
            val target = data?.data
            if (resultCode != RESULT_OK || target == null || action == null) {
                pending = null
                result.success(false)
                return
            }
            worker.execute {
                val written = runCatching { action(target) }
                if (written.isFailure) {
                    runCatching { DocumentsContract.deleteDocument(contentResolver, target) }
                }
                runOnUiThread {
                    pending = null
                    written.fold(
                        onSuccess = { result.success(true) },
                        onFailure = { result.error("export", it.message, null) },
                    )
                }
            }
            return
        }
        if (requestCode != PICK) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        val selectedKind = kind
        worker.execute {
            val response = runCatching {
                val name = contentResolver.query(
                    uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                )?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Arquivo"
                val parts = when (selectedKind) {
                    "image" -> listOf(readImage(uri))
                    "video" -> readFrames(uri)
                    else -> listOf(Mp3Audio.decode(this, uri))
                }
                mapOf("name" to name, "parts" to parts)
            }
            runOnUiThread {
                pending = null
                response.fold(
                    onSuccess = {
                        if (selectedKind == "video") selectedVideo = uri
                        result.success(it)
                    },
                    onFailure = { result.error("read", it.message, null) },
                )
            }
        }
    }

    private fun synthesize(text: String, result: MethodChannel.Result) {
        if (speech != null) {
            result.error("speech", "Já existe uma narração em andamento.", null)
            return
        }
        val file = try {
            File.createTempFile("narracao-", ".wav", cacheDir)
        } catch (error: Exception) {
            result.error("speech", error.message, null)
            return
        }
        fun finish(error: String? = null) {
            runOnUiThread {
                val engine = speech ?: return@runOnUiThread
                speech = null
                engine.shutdown()
                try {
                    if (error != null) {
                        result.error("speech", error, null)
                    } else {
                        result.success(file.readBytes())
                    }
                } catch (failure: Exception) {
                    result.error("speech", failure.message, null)
                } finally {
                    file.delete()
                }
            }
        }
        speech = TextToSpeech(this) { status ->
            window.decorView.post {
                val engine = speech ?: return@post
                val voice = if (status == TextToSpeech.SUCCESS) {
                    engine.voices?.firstOrNull {
                        !it.isNetworkConnectionRequired &&
                            it.locale.language == "pt" &&
                            "notInstalled" !in it.features.orEmpty()
                    }
                } else null
                if (voice == null || engine.setVoice(voice) != TextToSpeech.SUCCESS) {
                    finish("Instale uma voz offline em português nas configurações de texto para fala do Android.")
                    return@post
                }
                engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(id: String?) {}
                    override fun onDone(id: String?) = finish()
                    @Deprecated("Android legacy error callback")
                    override fun onError(id: String?) = finish("Falha ao sintetizar a narração.")
                })
                if (engine.synthesizeToFile(text, null, file, "ai-tools") != TextToSpeech.SUCCESS) {
                    finish("O Android recusou a síntese.")
                }
            }
        }
    }

    private fun readImage(uri: Uri): ByteArray {
        val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) {
            decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val (width, height) = scaledSize(info.size.width, info.size.height)
            decoder.setTargetSize(width, height)
        }
        return jpeg(bitmap)
    }

    private fun scaledSize(width: Int, height: Int): Pair<Int, Int> {
        val ratio = minOf(1.0, 768.0 / maxOf(width, height))
        return (width * ratio).toInt().coerceAtLeast(1) to
            (height * ratio).toInt().coerceAtLeast(1)
    }

    private fun readFrames(uri: Uri): List<ByteArray> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(this, uri)
            val duration = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: error("Não foi possível ler a duração do vídeo.")
            val width = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
            )?.toIntOrNull() ?: error("O arquivo não contém vídeo.")
            val height = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
            )?.toIntOrNull() ?: error("O arquivo não contém vídeo.")
            val rotation = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
            )
            val (w, h) = if (rotation == "90" || rotation == "270") {
                scaledSize(height, width)
            } else {
                scaledSize(width, height)
            }
            val frames = listOf(1L, 3L, 5L).mapNotNull { part ->
                retriever.getScaledFrameAtTime(
                    duration * 1000 * part / 6, MediaMetadataRetriever.OPTION_CLOSEST, w, h,
                )?.let(::jpeg)
            }
            check(frames.isNotEmpty()) { "Nenhum quadro pôde ser extraído." }
            return frames
        } finally {
            retriever.release()
        }
    }

    private fun jpeg(bitmap: Bitmap): ByteArray {
        try {
            return ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output))
                output.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    override fun onDestroy() {
        speech?.shutdown()
        worker.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val PICK = 5931
        const val EXPORT = 5932
    }
}






