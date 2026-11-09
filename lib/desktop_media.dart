import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

class DesktopMedia {
  static bool get supported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<bool> save(Uint8List bytes, String name) async {
    final path = await _destination(name);
    if (path == null) return false;
    await File(path).writeAsBytes(bytes);
    return true;
  }

  static Future<bool> posterVideo(Uint8List png, double seconds) =>
      _convert('cartaz.mp4', (directory) async {
        final input = await _input(directory, 'cartaz.png', png);
        return [
          '-loop',
          '1',
          '-framerate',
          '15',
          '-pattern_type',
          'none',
          '-i',
          input,
          '-t',
          seconds.toString(),
          ..._videoOptions,
        ];
      });

  static Future<bool> videoClip(String input, double? end) => _convert(
    'video.mp4',
    (_) async => [
      '-i',
      input,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      if (end != null) ...['-t', end.toString()],
      ..._videoOptions,
      '-c:a',
      'aac',
    ],
  );

  static const _videoOptions = [
    '-vf',
    'pad=ceil(iw/2)*2:ceil(ih/2)*2',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
  ];

  static Future<bool> saveMp3(Uint8List wav, int bitrate, String name) =>
      _convert(name, (directory) async {
        final input = await _input(directory, 'audio.wav', wav);
        return _mp3Options(input, bitrate);
      });

  static Future<Uint8List> decodeAudio(String path) async {
    final directory = await Directory.systemTemp.createTemp('ai_tools_audio_');
    try {
      final output = File.fromUri(directory.uri.resolve('audio.wav'));
      await _ffmpeg([
        '-i',
        path,
        '-map',
        '0:a:0',
        '-ar',
        '16000',
        '-ac',
        '1',
        '-c:a',
        'pcm_s16le',
        output.path,
      ]);
      return await output.readAsBytes();
    } finally {
      await directory.delete(recursive: true);
    }
  }

  static Future<bool> saveNarration(String text, int bitrate) =>
      _convert('narracao.mp3', (directory) async {
        final script = File.fromUri(directory.uri.resolve('texto.txt'));
        await script.writeAsString(text);
        final voice = directory.uri
            .resolve(Platform.isMacOS ? 'voz.aiff' : 'voz.wav')
            .toFilePath();
        if (Platform.isWindows) {
          await _run(
            'powershell.exe',
            ['-NoProfile', '-NonInteractive', '-Command', _windowsSpeech],
            environment: {
              'AI_TOOLS_SPEECH_TEXT': script.path,
              'AI_TOOLS_SPEECH_OUTPUT': voice,
            },
          );
        } else if (Platform.isMacOS) {
          await _run('/usr/bin/say', ['-f', script.path, '-o', voice]);
        } else {
          await _run('espeak-ng', [
            '-v',
            'pt-br',
            '-f',
            script.path,
            '-w',
            voice,
          ]);
        }
        return _mp3Options(voice, bitrate);
      });

  static const _windowsSpeech = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $pt = $voice.GetInstalledVoices() | Where-Object {
    $_.Enabled -and $_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq 'pt'
  } | Select-Object -First 1
  if ($pt) { $voice.SelectVoice($pt.VoiceInfo.Name) }
  $voice.SetOutputToWaveFile($env:AI_TOOLS_SPEECH_OUTPUT)
  $voice.Speak([IO.File]::ReadAllText($env:AI_TOOLS_SPEECH_TEXT))
} finally {
  $voice.Dispose()
}
''';

  static List<String> _mp3Options(String input, int bitrate) => [
    '-i',
    input,
    '-map',
    '0:a:0',
    '-c:a',
    'libmp3lame',
    '-b:a',
    '${bitrate}k',
  ];

  static Future<String?> _destination(String name) async {
    final extension = name.split('.').last;
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(
          label: extension.toUpperCase(),
          extensions: [extension],
          uniformTypeIdentifiers: [
            switch (extension) {
              'png' => 'public.png',
              'jpg' => 'public.jpeg',
              'mp3' => 'public.mp3',
              'mp4' => 'public.mpeg-4',
              _ => throw ArgumentError.value(name, 'name'),
            },
          ],
        ),
      ],
    );
    final path = location?.path;
    if (path != null && !path.toLowerCase().endsWith('.$extension')) {
      throw FormatException('Salve o arquivo com a extensão .$extension.');
    }
    return path;
  }

  static Future<bool> _convert(
    String name,
    Future<List<String>> Function(Directory) arguments,
  ) async {
    final path = await _destination(name);
    if (path == null) return false;
    final temp = await Directory.systemTemp.createTemp('ai_tools_media_');
    try {
      final output = File.fromUri(temp.uri.resolve(name));
      await _ffmpeg([...await arguments(temp), output.path]);
      await output.copy(path);
      return true;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  static Future<void> _ffmpeg(List<String> arguments) => _run(
    Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg',
    ['-nostdin', '-hide_banner', '-loglevel', 'error', '-y', ...arguments],
  );

  static Future<String> _input(
    Directory directory,
    String name,
    Uint8List bytes,
  ) async {
    final file = File.fromUri(directory.uri.resolve(name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> _run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        executable,
        arguments,
        environment: environment,
      );
    } on ProcessException {
      throw StateError(
        'Não foi possível iniciar $executable. Verifique se está disponível no sistema.',
      );
    }
    if (result.exitCode != 0) {
      throw StateError(
        '$executable falhou: ${result.stderr.toString().trim()}',
      );
    }
  }
}
