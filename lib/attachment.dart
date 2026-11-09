import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import 'desktop_media.dart';
import 'wav.dart';

enum AttachmentKind {
  image(
    XTypeGroup(
      label: 'Imagens',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
      uniformTypeIdentifiers: ['public.image'],
    ),
  ),
  video(
    XTypeGroup(
      label: 'Vídeos',
      extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'],
      uniformTypeIdentifiers: ['public.movie'],
    ),
  ),
  audio(
    XTypeGroup(
      label: 'Áudio',
      extensions: ['wav', 'wave', 'mp3', 'm4a', 'aac', 'flac'],
      uniformTypeIdentifiers: ['public.audio'],
    ),
  ),
  document(
    XTypeGroup(
      label: 'Documentos',
      extensions: ['txt', 'md', 'csv', 'tsv', 'json', 'docx'],
      mimeTypes: [
        'text/plain',
        'text/markdown',
        'text/csv',
        'text/tab-separated-values',
        'application/json',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ],
      uniformTypeIdentifiers: [
        'public.plain-text',
        'public.json',
        'public.comma-separated-values-text',
        'public.tab-separated-values-text',
        'org.openxmlformats.wordprocessingml.document',
      ],
    ),
  );

  const AttachmentKind(this.type);
  final XTypeGroup type;
}

class Attachment {
  const Attachment(this.name, this.kind, this.parts, {this.path, this.text});

  final String name;
  final AttachmentKind kind;
  final List<Uint8List> parts;
  final String? path;
  final String? text;

  List<Uint8List> get images =>
      kind == AttachmentKind.image || kind == AttachmentKind.video
      ? parts
      : const [];
  Uint8List? get audio => kind == AttachmentKind.audio ? parts.single : null;

  String withDocument(String prompt) {
    final content = text;
    return content == null
        ? prompt
        : '$prompt\n\nDocumento anexado:\n${jsonEncode({'nome': name, 'texto': content})}';
  }

  static bool get nativeExportSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  static const _channel = MethodChannel('ai_tools/media');

  static Future<Attachment?> pick(AttachmentKind kind) async {
    if (nativeExportSupported && kind != AttachmentKind.document) {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pick',
        kind.name,
      );
      if (result == null) return null;
      final parts = (result['parts'] as List).cast<Uint8List>();
      if (kind == AttachmentKind.audio) _validateWav(parts.single);
      return Attachment(result['name'] as String, kind, parts);
    }

    final file = await openFile(acceptedTypeGroups: [kind.type]);
    if (file == null) return null;
    if (kind == AttachmentKind.document) {
      return Attachment(
        file.name,
        kind,
        const [],
        text: await _readDocument(file),
      );
    }
    final bytes = switch (kind) {
      AttachmentKind.image => await _readImage(file),
      AttachmentKind.video => await _readVideoFrame(file),
      AttachmentKind.audio => await _readAudio(file),
      AttachmentKind.document => throw StateError('Documento já processado.'),
    };
    return Attachment(file.name, kind, [bytes], path: file.path);
  }

  static Future<Uint8List> _readImage(XFile file) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      final codec = await descriptor.instantiateCodec(
        targetWidth: width >= height && width > 768 ? 768 : null,
        targetHeight: height > width && height > 768 ? 768 : null,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) {
            throw const FormatException('Não foi possível ler a imagem.');
          }
          return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<Uint8List> _readVideoFrame(XFile file) async {
    final frame = await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: file.path,
      width: 768,
      height: 768,
    );
    if (frame == null || frame.isEmpty) {
      throw const FormatException(
        'Nenhum quadro pôde ser extraído deste vídeo.',
      );
    }
    return frame;
  }

  static Future<Uint8List> _readAudio(XFile file) async {
    if (RegExp(r'\.wave?$', caseSensitive: false).hasMatch(file.name)) {
      final bytes = await file.readAsBytes();
      try {
        _validateWav(bytes);
        return bytes;
      } on FormatException {
        // The platform decoder can resample WAVs in other PCM formats.
      }
    }
    final wav = DesktopMedia.supported
        ? await DesktopMedia.decodeAudio(file.path)
        : await _channel.invokeMethod<Uint8List>('decodeAudio', file.path);
    if (wav == null) {
      throw const FormatException('O áudio não pôde ser decodificado.');
    }
    _validateWav(wav);
    return wav;
  }

  static Future<String> _readDocument(XFile file) async {
    const limit = 8 * 1024 * 1024;
    if (await file.length() > limit) {
      throw const FormatException('Selecione um documento de até 8 MiB.');
    }
    final bytes = await file.readAsBytes();
    String text;
    if (file.name.toLowerCase().endsWith('.docx')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final body = archive.findFile('word/document.xml');
      if (body == null || body.size > limit) {
        throw const FormatException('Documento DOCX inválido ou muito grande.');
      }
      final xml = XmlDocument.parse(utf8.decode(body.content));
      const word =
          'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
      text = xml
          .findAllElements('p', namespaceUri: word)
          .map(
            (paragraph) => paragraph
                .findAllElements('t', namespaceUri: word)
                .map((element) => element.innerText)
                .join(),
          )
          .join('\n');
    } else {
      text = utf8.decode(bytes);
    }
    text = text.trim();
    if (text.isEmpty) throw const FormatException('O documento está vazio.');
    if (text.length > 6000) {
      throw const FormatException(
        'Selecione um documento com até 6.000 caracteres de texto.',
      );
    }
    return text;
  }

  static void _validateWav(Uint8List bytes) {
    if (bytes.length < 44 ||
        !_tag(bytes, 0, 'RIFF') ||
        !_tag(bytes, 8, 'WAVE')) {
      throw const FormatException('Selecione um arquivo WAV.');
    }
    final data = ByteData.sublistView(bytes);
    var formatOk = false;
    var dataOk = false;
    for (final (:tag, :start, :end) in wavChunks(data)) {
      final size = end - start;
      if (end > bytes.length) {
        throw const FormatException('Arquivo WAV incompleto.');
      }
      if (tag == 'fmt ' && size >= 16) {
        final encoding = data.getUint16(start, Endian.little);
        const pcmGuid = [
          1,
          0,
          0,
          0,
          0,
          0,
          16,
          0,
          128,
          0,
          0,
          170,
          0,
          56,
          155,
          113,
        ];
        final pcm =
            encoding == 1 ||
            (encoding == 0xfffe &&
                size >= 40 &&
                listEquals(
                  Uint8List.sublistView(bytes, start + 24, start + 40),
                  pcmGuid,
                ));
        formatOk =
            pcm &&
            data.getUint16(start + 2, Endian.little) == 1 &&
            data.getUint32(start + 4, Endian.little) == 16000 &&
            data.getUint16(start + 14, Endian.little) == 16;
      }
      if (tag == 'data') {
        dataOk = size >= 2 && size.isEven;
      }
    }
    if (!formatOk || !dataOk) {
      throw const FormatException('Use WAV PCM de 16 bits, mono, 16 kHz.');
    }
  }

  bool get audioFitsModel {
    if (kind != AttachmentKind.audio) return true;
    final wav = parts.single;
    return wav.length <= 1024 * 1024 &&
        wavChunks(ByteData.sublistView(wav))
            .where((chunk) => chunk.tag == 'data')
            .every((chunk) => chunk.end - chunk.start <= 960000);
  }

  static bool _tag(Uint8List bytes, int offset, String tag) =>
      String.fromCharCodes(bytes.getRange(offset, offset + 4)) == tag;
}
