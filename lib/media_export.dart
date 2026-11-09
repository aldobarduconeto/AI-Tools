import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lame/flutter_lame.dart';
import 'package:image/image.dart' as image;

import 'attachment.dart';
import 'desktop_media.dart';
import 'wav.dart';

class MediaExport {
  static const _channel = MethodChannel('ai_tools/media');
  static bool get supportsAudio =>
      DesktopMedia.supported || Attachment.nativeExportSupported || _isIOS;
  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get supportsImages => supportsAudio;
  static bool get supportsVideo => supportsAudio;
  static bool get usesDesktopEncoder => DesktopMedia.supported;

  static Future<bool> posterVideo(String text, double seconds) async {
    final png = await poster(text);
    if (DesktopMedia.supported) return DesktopMedia.posterVideo(png, seconds);
    return await _channel.invokeMethod<bool>('posterVideo', {
          'png': png,
          'seconds': seconds,
        }) ??
        false;
  }

  static Future<bool> saveNarration(String text, int bitrate) async {
    if (DesktopMedia.supported) {
      return DesktopMedia.saveNarration(text, bitrate);
    }
    if (_isIOS) {
      final wav = await _channel.invokeMethod<Uint8List>('speech', text);
      if (wav == null) throw StateError('A narração não retornou áudio.');
      return saveMp3(wav, bitrate, 'narracao.mp3');
    }
    return saveMp3(await _narrate(text), bitrate, 'narracao.mp3');
  }

  static Future<Uint8List> _narrate(String text) async {
    final limit = await _channel.invokeMethod<int>('speechLimit');
    if (limit == null || limit < 2) {
      throw StateError('O sintetizador de voz está indisponível.');
    }
    final whitespace = RegExp(r'\s');
    final audio = WavSequence();
    var start = 0;
    while (start < text.length) {
      var end = math.min(start + limit, text.length);
      if (end < text.length) {
        final space = text.lastIndexOf(whitespace, end - 1);
        if (space > start) {
          end = space + 1;
        } else if (text.codeUnitAt(end) & 0xfc00 == 0xdc00) {
          end--;
        }
      }
      final segment = text.substring(start, end).trim();
      if (segment.isNotEmpty) {
        final wav = await _channel.invokeMethod<Uint8List>('speech', segment);
        if (wav == null) throw StateError('A narração não retornou áudio.');
        audio.add(wav);
      }
      start = end;
    }
    return audio.finish();
  }

  static Future<bool> videoClip(Attachment video, double? end) async {
    if (DesktopMedia.supported) {
      final path = video.path;
      if (path == null) throw StateError('Selecione o vídeo novamente.');
      return DesktopMedia.videoClip(path, end);
    }
    if (_isIOS) {
      return await _channel.invokeMethod<bool>('clip', {
            'path': video.path,
            'end': end,
          }) ??
          false;
    }
    return await _channel.invokeMethod<bool>('clip', {'end': end}) ?? false;
  }

  static Future<bool> saveMp3(Uint8List wav, int bitrate, String name) async {
    if (DesktopMedia.supported) return DesktopMedia.saveMp3(wav, bitrate, name);
    if (_isIOS) {
      return save(await _encodePcm(wav, bitrate), name, 'audio/mpeg');
    }
    final mp3 = await _channel.invokeMethod<Uint8List>('mp3', {
      'wav': wav,
      'bitrate': bitrate,
    });
    if (mp3 == null) {
      throw StateError('A conversão para MP3 não retornou áudio.');
    }
    return save(mp3, name, 'audio/mpeg');
  }

  static Future<Uint8List> _encodePcm(Uint8List wav, int bitrate) async {
    final bytes = ByteData.sublistView(wav);
    final chunks = wavChunks(bytes).where((chunk) => chunk.tag == 'data');
    if (chunks.isEmpty || chunks.first.end > wav.length) {
      throw const FormatException('Faixa PCM inválida.');
    }
    final (:start, :end, tag: _) = chunks.first;
    final encoder = LameMp3Encoder(
      numChannels: 1,
      sampleRate: 16000,
      bitRate: bitrate,
    );
    final mp3 = BytesBuilder(copy: false);
    try {
      for (var offset = start; offset + 1 < end;) {
        final samples = Int16List(math.min(8192, (end - offset) ~/ 2));
        for (var index = 0; index < samples.length; index++, offset += 2) {
          samples[index] = bytes.getInt16(offset, Endian.little);
        }
        mp3.add(await encoder.encode(leftChannel: samples));
      }
      mp3.add(await encoder.flush());
      return mp3.takeBytes();
    } finally {
      await encoder.close();
    }
  }

  static Future<bool> save(Uint8List bytes, String name, String mime) async {
    if (DesktopMedia.supported) return DesktopMedia.save(bytes, name);
    return await _channel.invokeMethod<bool>('export', {
          'bytes': bytes,
          'name': name,
          'mime': mime,
        }) ??
        false;
  }

  static Future<bool> saveJpeg(Uint8List png, String name) async {
    if (!Attachment.nativeExportSupported) {
      final decoded = image.decodePng(png);
      if (decoded == null) throw const FormatException('Imagem PNG inválida.');
      return save(image.encodeJpg(decoded, quality: 92), name, 'image/jpeg');
    }
    return await _channel.invokeMethod<bool>('exportJpeg', {
          'bytes': png,
          'name': name,
          'mime': 'image/jpeg',
        }) ??
        false;
  }

  static Future<Uint8List> poster(String text) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(960, 540);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff15261c), Color(0xff365c39)],
        ).createShader(rect),
    );
    canvas.drawRect(
      const Rect.fromLTWH(62, 70, 90, 8),
      Paint()..color = const Color(0xffbdf977),
    );
    final paragraph = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 52,
          height: 1.12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 5,
      ellipsis: '…',
    )..layout(maxWidth: 836);
    paragraph.paint(canvas, Offset(62, (540 - paragraph.height) / 2));
    paragraph.dispose();
    return _png(recorder, 960, 540);
  }

  static Future<Uint8List> grayscale(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImage(
          image,
          Offset.zero,
          Paint()
            ..colorFilter = const ColorFilter.matrix([
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
        );
        return await _png(recorder, image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static Future<Uint8List> _png(
    ui.PictureRecorder recorder,
    int width,
    int height,
  ) async {
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static Uint8List normalizeWav(Uint8List source) {
    final output = Uint8List.fromList(source);
    final bytes = ByteData.sublistView(output);
    for (final (:tag, :start, :end) in wavChunks(bytes)) {
      if (end > output.length) break;
      if (tag == 'data') {
        var peak = 0;
        for (var position = start; position + 1 < end; position += 2) {
          peak = math.max(peak, bytes.getInt16(position, Endian.little).abs());
        }
        if (peak == 0) return output;
        for (var position = start; position + 1 < end; position += 2) {
          final value = bytes.getInt16(position, Endian.little);
          bytes.setInt16(
            position,
            (value * 31000 / peak).round(),
            Endian.little,
          );
        }
        return output;
      }
    }
    throw const FormatException('A faixa PCM do WAV não foi encontrada.');
  }
}
