import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

typedef WavChunk = ({String tag, int start, int end});

Iterable<WavChunk> wavChunks(ByteData bytes) sync* {
  for (var offset = 12; offset <= bytes.lengthInBytes - 8;) {
    final tag = String.fromCharCodes(
      Uint8List.sublistView(bytes, offset, offset + 4),
    );
    final size = bytes.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    final end = start + size;
    yield (tag: tag, start: start, end: end);
    if (end > bytes.lengthInBytes) return;
    offset = end + size % 2;
  }
}

class WavSequence {
  final _pcm = BytesBuilder(copy: false);
  Uint8List? _format;

  void add(Uint8List wav) {
    Uint8List? format;
    Uint8List? samples;
    for (final (:tag, :start, :end) in wavChunks(ByteData.sublistView(wav))) {
      if (end > wav.length) break;
      if (tag == 'fmt ') format = Uint8List.sublistView(wav, start, end);
      if (tag == 'data') samples = Uint8List.sublistView(wav, start, end);
    }
    if (format == null || format.length < 16 || samples == null) {
      throw const FormatException('A narração retornou áudio incompleto.');
    }
    if (_format != null && !listEquals(_format, format)) {
      throw const FormatException('A voz mudou de formato durante a narração.');
    }
    _format ??= Uint8List.fromList(format);
    _pcm.add(samples);
  }

  Uint8List finish() {
    final format = _format;
    if (format == null || _pcm.isEmpty) {
      throw const FormatException('A narração não retornou áudio.');
    }
    final dataOffset = 20 + format.length + format.length % 2;
    final output = Uint8List(dataOffset + 8 + _pcm.length + _pcm.length % 2);
    final header = ByteData.sublistView(output);
    output.setAll(0, 'RIFF'.codeUnits);
    header.setUint32(4, output.length - 8, Endian.little);
    output.setAll(8, 'WAVEfmt '.codeUnits);
    header.setUint32(16, format.length, Endian.little);
    output.setAll(20, format);
    output.setAll(dataOffset, 'data'.codeUnits);
    header.setUint32(dataOffset + 4, _pcm.length, Endian.little);
    output.setAll(dataOffset + 8, _pcm.takeBytes());
    return output;
  }
}
