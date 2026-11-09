import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAi {
  static const file = 'gemma-4-E2B-it.litertlm';
  static const _linkedModelPathKey = 'linked_gemma_model_path';
  static const url =
      'https://huggingface.co/litert-community/'
      'gemma-4-E2B-it-litert-lm/resolve/'
      'b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/$file';

  bool get supported => true;
  bool get installed => _ready && FlutterEdgeAi.activeModelSpec?.name == file;
  bool _ready = false;
  Future<void>? _initialization;
  final _preferences = SharedPreferencesAsync();

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await (_initialization ??= _initializeModel());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initializeModel() async {
    await FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    try {
      if (FlutterEdgeAi.activeModelSpec?.name == file) return;
      final path = await _preferences.getString(_linkedModelPathKey);
      if (path != null) await _activateLinkedModel(path);
    } finally {
      _ready = true;
    }
  }

  Future<void> install(void Function(double) progress) async {
    await initialize();
    if (installed) {
      progress(1);
      return;
    }
    await _gemmaInstaller()
        .fromNetwork(url)
        .withProgress((value) => progress(value / 100))
        .install();
    await _preferences.remove(_linkedModelPathKey);
  }

  Future<void> reuse(String path) async {
    await initialize();
    await _activateLinkedModel(path);
    await _preferences.setString(_linkedModelPathKey, path);
  }

  Future<void> _activateLinkedModel(String path) async {
    await _gemmaInstaller().fromFile(path).install();
  }

  InferenceInstallationBuilder _gemmaInstaller() => FlutterEdgeAi.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );

  Future<void> remove() async {
    await FlutterEdgeAi.uninstallModel(file);
    await _preferences.remove(_linkedModelPathKey);
  }

  Stream<String> generate(
    String instruction,
    String input, {
    List<Uint8List> images = const [],
    Uint8List? audio,
  }) async* {
    final model = await FlutterEdgeAi.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
      supportImage: images.isNotEmpty,
      supportAudio: audio != null,
    );
    final session = await model.createSession();
    try {
      final text = '$instruction\n\nSolicitação:\n$input';
      final message = audio != null
          ? Message.withAudio(text: text, audioBytes: audio, isUser: true)
          : images.isNotEmpty
          ? Message.withImages(text: text, imageBytes: images, isUser: true)
          : Message.text(text: text, isUser: true);
      await session.addQueryChunk(message);
      yield* session.getResponseAsync();
    } finally {
      await session.close();
    }
  }
}
