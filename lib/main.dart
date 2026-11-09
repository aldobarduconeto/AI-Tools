import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attachment.dart';
import 'local_ai.dart';
import 'media_export.dart';
import 'studio_hero.dart';

void main() => runApp(const AiTools());

const mint = Color(0xffbdf977);
const background = Color(0xff111411);
const surface = Color(0xff1b201a);

enum ModelAction { download, link, remove }

enum Tool {
  chat(
    'Assistente',
    'Pergunte, explore e organize ideias.',
    Icons.forum_outlined,
    'Responda à solicitação com clareza, em português quando adequado.',
  ),
  write(
    'Gerar texto',
    'Crie textos a partir de uma ideia.',
    Icons.draw_outlined,
    'Escreva um texto pronto para uso no formato, idioma e tom solicitados.',
  ),
  summary(
    'Resumo',
    'Extraia os pontos principais de um texto.',
    Icons.subject,
    'Resuma o texto preservando os fatos. Destaque os pontos principais.',
  ),
  translate(
    'Tradução',
    'Traduza preservando o sentido e o tom.',
    Icons.translate,
    'Traduza para o idioma indicado. Se não houver indicação, use português do Brasil. Retorne a tradução.',
  ),
  revise(
    'Editar texto',
    'Melhore clareza, gramática e estilo.',
    Icons.spellcheck,
    'Revise gramática, clareza e fluidez. Preserve o sentido e o idioma. Retorne o texto revisado.',
  ),
  verifyText(
    'Verificar texto',
    'Confira clareza, gramática e coerência.',
    Icons.fact_check_outlined,
    'Revise gramática, clareza e coerência. Cite os trechos problemáticos e sugira correções. Identifique alegações que precisam de fontes externas.',
  ),
  mediaGenerate(
    'Criar conceito visual',
    'Gere prompts de imagem e roteiros de vídeo.',
    Icons.movie_creation_outlined,
    'Crie um prompt visual detalhado ou um roteiro de vídeo com cenas e duração, conforme o pedido.',
  ),
  imageEdit(
    'Planejar edição de imagem',
    'Receba instruções de edição para sua imagem.',
    Icons.tune,
    'Observe a imagem anexada e proponha ajustes concretos conforme a solicitação.',
  ),
  videoEdit(
    'Planejar edição de vídeo',
    'Receba sugestões de montagem a partir de quadros.',
    Icons.video_settings,
    'Analise os quadros em ordem e proponha ajustes de montagem. Indique que a análise se limita aos quadros e evite inferir o áudio.',
  ),
  imageVerify(
    'Verificar imagem',
    'Analise conteúdo, legibilidade e detalhes visíveis.',
    Icons.image_search,
    'Descreva o que está visível e avalie os critérios solicitados. Separe observação de inferência. Não certifique autenticidade.',
  ),
  videoVerify(
    'Verificar vídeo',
    'Inspecione até três quadros do vídeo.',
    Icons.video_camera_back_outlined,
    'Analise os quadros em ordem e relate problemas visuais observáveis. Explique que a avaliação cobre apenas os quadros amostrados.',
  ),
  audioGenerate(
    'Criar roteiro de áudio',
    'Escreva narração, locução ou roteiro de podcast.',
    Icons.mic_none,
    'Escreva um roteiro de áudio pronto para narrar, com pausas e tom quando solicitados.',
  ),
  audioEdit(
    'Planejar edição de áudio',
    'Receba sugestões de corte, ritmo e clareza.',
    Icons.graphic_eq,
    'Analise o clipe e proponha melhorias de edição. Distingua o que ouviu de sugestões gerais.',
  ),
  audioVerify(
    'Verificar áudio',
    'Analise a gravação ou solicite uma transcrição.',
    Icons.hearing,
    'Analise inteligibilidade e ruídos perceptíveis. Se solicitado, transcreva e marque trechos incertos.',
  ),
  ideas(
    'Brainstorm',
    'Explore ideias e compare caminhos.',
    Icons.lightbulb_outline,
    'Gere ideias variadas e concretas. Agrupe por abordagem e dê um primeiro passo para cada ideia.',
  ),
  extract(
    'Extrair informações',
    'Organize nomes, datas e ações de um texto.',
    Icons.data_object,
    'Extraia os dados solicitados em tópicos ou tabela. Use somente informações explícitas no texto.',
  ),
  captions(
    'Legendas e descrição',
    'Crie legendas ou texto alternativo para imagens.',
    Icons.closed_caption_outlined,
    'Descreva os elementos visíveis. Crie texto alternativo acessível ou uma legenda conforme o pedido. Evite inferências desnecessárias.',
  ),
  code(
    'Código',
    'Gere, revise ou explique código.',
    Icons.code,
    'Ajude com programação. Use a linguagem solicitada e explique as decisões relevantes.',
  );

  const Tool(this.title, this.description, this.icon, this.instruction);
  final String title, description, instruction;
  final IconData icon;
  int get category => switch (this) {
    mediaGenerate ||
    imageEdit ||
    videoEdit ||
    imageVerify ||
    videoVerify ||
    captions => 1,
    audioGenerate || audioEdit || audioVerify => 2,
    _ => 0,
  };

  String get cardTitle => switch (this) {
    imageEdit => 'Editar imagem',
    videoEdit => 'Editar vídeo',
    _ => title,
  };

  String get cardDescription => switch (this) {
    imageEdit => 'Sugestões e filtro visual.',
    videoEdit => 'Sugestões e cortes.',
    imageVerify => 'Confira detalhes visíveis.',
    _ => description,
  };

  AttachmentKind? get attachmentKind => switch (this) {
    imageEdit || imageVerify || captions => AttachmentKind.image,
    videoEdit || videoVerify => AttachmentKind.video,
    audioEdit || audioVerify => AttachmentKind.audio,
    _ => null,
  };
}

typedef Entry = ({Tool tool, String input, String output});

class AiTools extends StatelessWidget {
  const AiTools({super.key, this.localAi});

  final LocalAi? localAi;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Tools',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.dark,
      ).copyWith(primary: mint, surface: surface),
      scaffoldBackgroundColor: background,
      dividerColor: const Color(0xff30382f),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xff353e33)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xff30382f)),
        ),
      ),
    ),
    home: Workspace(localAi: localAi ?? LocalAi()),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.localAi});

  final LocalAi localAi;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  LocalAi get ai => widget.localAi;
  final prefs = SharedPreferencesAsync();
  int mp3Bitrate = 128;
  int chatContext = 3;
  bool saveHistory = true;
  bool studioMode = false;
  bool welcomeSeen = false;
  static const welcomeKey = 'ai_tools_welcome_seen';
  bool savingSettings = false;
  static const settingsKey = 'ai_tools_settings';
  static const bitrates = [64, 96, 128, 160];
  final input = TextEditingController();
  final history = <Entry>[];
  final favorites = <Tool>{};
  final search = TextEditingController();
  bool onlyFavorites = false;
  bool updatingFavorites = false;
  static const favoritesKey = 'ai_tools_favorites';
  Tool tool = Tool.chat;
  int page = 0;
  Attachment? attachment;
  Attachment? chatAttachment;
  bool picking = false;
  bool exporting = false;
  final chatInput = TextEditingController();
  final turns = <({String question, String answer})>[];
  String pendingQuestion = '';
  String chatAnswer = '';
  String chatError = '';
  bool get busy =>
      generating || changingModel || picking || exporting || savingSettings;
  bool editor = false,
      generating = false,
      changingModel = false,
      loading = true;
  double progress = 0;
  String output = '', failure = '';
  String get exportText {
    final response = output.trim();
    return response.isEmpty ? input.text.trim() : response;
  }

  String? modelFailure;
  static const historyKey = 'ai_tools_history';

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      welcomeSeen = await prefs.getBool(welcomeKey) ?? false;
    } catch (_) {
      notice('Não foi possível carregar o estado das boas-vindas.');
    }
    try {
      final names = await prefs.getStringList(favoritesKey) ?? [];
      favorites.addAll(Tool.values.where((item) => names.contains(item.name)));
    } catch (_) {
      notice('Não foi possível carregar os favoritos.');
    }
    try {
      final stored = await prefs.getString(settingsKey);
      if (stored != null) {
        final settings = jsonDecode(stored) as Map<String, dynamic>;
        final bitrate = settings['mp3Bitrate'];
        final context = settings['chatContext'];
        final historyEnabled = settings['saveHistory'];
        if (bitrate is int && bitrates.contains(bitrate)) mp3Bitrate = bitrate;
        if (context is int && context >= 0 && context <= 5) {
          chatContext = context;
        }
        if (historyEnabled is bool) saveHistory = historyEnabled;
        studioMode = settings['studioMode'] == true;
      }
    } catch (_) {
      notice('Não foi possível carregar as preferências.');
    }
    try {
      final stored = await prefs.getStringList(historyKey) ?? [];
      for (final item in stored) {
        final data = jsonDecode(item) as Map<String, dynamic>;
        history.add((
          tool: Tool.values.byName(data['tool'] as String),
          input: data['input'] as String,
          output: data['output'] as String,
        ));
      }
    } catch (_) {
      notice('Não foi possível ler todo o histórico.');
    }
    try {
      await ai.initialize();
    } catch (_) {
      modelFailure =
          'Não foi possível iniciar o motor local. Tente instalar novamente.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> finishWelcome() async {
    setState(() => welcomeSeen = true);
    try {
      await prefs.setBool(welcomeKey, true);
    } catch (_) {
      notice('Não foi possível salvar as boas-vindas.');
    }
  }

  String qualityInstruction(String instruction) => studioMode
      ? '$instruction\n\nModo Estúdio: produza uma resposta mais cuidadosa '
            'e precisa. Confira detalhes, trate ambiguidades e revise o '
            'resultado antes de responder. Adapte o nível de detalhe à tarefa.'
      : instruction;

  Future<void> persist() async {
    try {
      await prefs.setStringList(
        historyKey,
        history
            .map(
              (entry) => jsonEncode({
                'tool': entry.tool.name,
                'input': entry.input,
                'output': entry.output,
              }),
            )
            .toList(),
      );
    } catch (_) {
      notice('Não foi possível gravar o histórico no dispositivo.');
    }
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void openTool(Tool selected, [Entry? entry]) {
    setState(() {
      tool = selected;
      input.text = entry?.input ?? '';
      output = entry?.output ?? '';
      failure = '';
      page = selected.category;
      attachment = null;
      editor = true;
    });
  }

  Future<void> generate() async {
    final file = attachment;
    final text = input.text.trim();
    final request = text.isEmpty && file != null
        ? 'Analise o arquivo anexado conforme a tarefa.'
        : text;
    if (tool.attachmentKind != null && file == null) return;
    if (request.isEmpty || generating || changingModel || !ai.installed) return;
    if (file?.audioFitsModel == false) {
      setState(
        () => failure =
            'Para análise pelo Gemma, use áudio de até 30 segundos. '
            'A exportação para MP3 aceita o áudio inteiro.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      generating = true;
      output = '';
      failure = '';
    });
    try {
      await for (final chunk in ai.generate(
        qualityInstruction(tool.instruction),
        file?.withDocument(request) ?? request,
        images: file?.images ?? const [],
        audio: file?.audio,
      )) {
        if (!mounted) break;
        setState(() => output += chunk);
      }
      if (!mounted) return;
      if (output.trim().isEmpty) {
        setState(() => failure = 'O modelo retornou uma resposta vazia.');
      } else if (saveHistory) {
        history.insert(0, (tool: tool, input: request, output: output));
        if (history.length > 50) history.removeLast();
        await persist();
      }
    } catch (error) {
      if (mounted) setState(() => failure = 'Falha na geração local.\n$error');
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> changeModel(ModelAction action) async {
    if (changingModel || generating) return;
    if (action == ModelAction.remove &&
        !await confirm(
          'Remover o modelo?',
          'Será necessário baixá-lo novamente para gerar respostas.',
        )) {
      return;
    }
    if (!mounted || changingModel || generating) return;
    setState(() {
      changingModel = true;
      modelFailure = null;
      progress = 0;
    });
    try {
      switch (action) {
        case ModelAction.remove:
          await ai.remove();
        case ModelAction.link:
          final model = await openFile(
            acceptedTypeGroups: const [
              XTypeGroup(label: 'LiteRT-LM', extensions: ['litertlm']),
            ],
          );
          if (model == null || !mounted) return;
          if (model.name != LocalAi.file) {
            throw FormatException('Selecione o arquivo ${LocalAi.file}.');
          }
          await ai.reuse(model.path);
        case ModelAction.download:
          await ai.install((value) {
            if (mounted) setState(() => progress = value.clamp(0.0, 1.0));
          });
      }
    } catch (error) {
      if (mounted) {
        setState(() => modelFailure = 'Falha ao gerenciar o modelo.\n$error');
      }
    } finally {
      if (mounted) setState(() => changingModel = false);
    }
  }

  Future<bool> confirm(String title, String details) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(details),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  void dispose() {
    input.dispose();
    search.dispose();
    chatInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    final wide = window.width >= 900 && window.height >= 440;
    if (!loading && !welcomeSeen) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  StudioHero(
                    title: 'Bem-vindo ao AI Tools',
                    description: 'Crie, revise e explore com o Gemma local.',
                    index: 0,
                    accent: mint,
                    label: 'IA NO DISPOSITIVO',
                  ),
                  const SizedBox(height: 20),
                  const ListTile(
                    leading: Icon(Icons.folder_open),
                    title: Text('Acesso a arquivos'),
                    subtitle: Text(
                      'Ao abrir ou salvar um arquivo, escolha-o na janela do sistema para conceder acesso.',
                    ),
                  ),
                  const ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('Download do modelo'),
                    subtitle: Text(
                      'A conexão é usada quando você escolhe baixar o Gemma.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: finishWelcome,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Começar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: !editor && page < 4 && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) {
          setState(() {
            if (page >= 4) page = 0;
            editor = false;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 4,
          backgroundColor: background,
          leading: editor || page >= 4
              ? IconButton(
                  tooltip: 'Voltar',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (page >= 4) page = 0;
                          editor = false;
                        }),
                  icon: const Icon(Icons.arrow_back),
                )
              : Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      width: 34,
                      height: 34,
                    ),
                  ),
                ),
          title: Text(
            editor ? tool.title : 'AI Tools',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          actions: [
            if (studioMode)
              IconButton(
                tooltip: 'Modo Estúdio ativo',
                onPressed: busy || loading ? null : () => navigate(5),
                icon: const Icon(Icons.auto_awesome, color: mint),
              ),
            IconButton(
              tooltip: 'Histórico',
              onPressed: busy || loading ? null : () => navigate(4),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: 'Configurações',
              onPressed: busy || loading ? null : () => navigate(5),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: SafeArea(
          bottom: wide,
          child: Row(
            children: [
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 0, 18),
                  child: navigation(vertical: true),
                ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: ListView(
                            key: ValueKey((page, editor, tool)),
                            padding: EdgeInsets.fromLTRB(
                              wide ? 28 : 16,
                              14,
                              wide ? 28 : 16,
                              32,
                            ),
                            children: switch (page) {
                              3 => chatView(),
                              4 => historyView(),
                              5 => settingsView(),
                              _ => editor ? toolView() : catalog(),
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: navigation(vertical: false),
              ),
      ),
    );
  }

  Widget navigation({required bool vertical}) {
    const tabs = [
      ('Texto', Icons.notes_rounded),
      ('Mídia', Icons.grid_view_rounded),
      ('Áudio', Icons.graphic_eq_rounded),
      ('Chat', Icons.chat_bubble_outline_rounded),
    ];
    final buttons = [
      for (final (index, (label, icon)) in tabs.indexed)
        Semantics(
          selected: index == page,
          child: TextButton(
            onPressed: busy || loading ? null : () => navigate(index),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              foregroundColor: index == page
                  ? background
                  : const Color(0xffc6cec3),
              backgroundColor: index == page ? mint : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Flex(
              direction: vertical ? Axis.horizontal : Axis.vertical,
              mainAxisSize: MainAxisSize.min,
              spacing: vertical ? 10 : 3,
              children: [
                Icon(icon, size: 19),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: vertical ? 14 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    return Container(
      width: vertical ? 144 : null,
      padding: EdgeInsets.all(vertical ? 8 : 5),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff353e33)),
      ),
      child: vertical
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 6, 9),
                    child: Text(
                      'ESPAÇO DE TRABALHO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: .7,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...buttons,
                ],
              ),
            )
          : Row(
              spacing: 4,
              children: [for (final button in buttons) Expanded(child: button)],
            ),
    );
  }

  void navigate(int index) => setState(() {
    page = index;
    editor = false;
    attachment = null;
  });

  Future<void> pick(AttachmentKind kind, {bool forChat = false}) async {
    setState(() => picking = true);
    try {
      final file = await Attachment.pick(kind);
      if (mounted && file != null) {
        setState(() {
          if (forChat) {
            chatAttachment = file;
            chatError = '';
          } else {
            attachment = file;
            output = '';
            failure = '';
          }
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => attachmentError(
            error.message ?? 'Falha ao abrir o arquivo.',
            forChat,
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => attachmentError(error.message, forChat));
    } catch (_) {
      if (mounted) {
        setState(
          () => attachmentError(
            'Não foi possível abrir ou preparar o arquivo selecionado.',
            forChat,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void attachmentError(String message, bool forChat) {
    if (forChat) {
      chatError = message;
    } else {
      failure = message;
    }
  }

  Future<void> sendChat() async {
    final file = chatAttachment;
    final text = chatInput.text.trim();
    if ((text.isEmpty && file == null) || busy || !ai.installed) return;
    if (file?.audioFitsModel == false) {
      setState(
        () => chatError =
            'Para análise pelo Gemma, use áudio de até 30 segundos.',
      );
      return;
    }
    final request = text.isEmpty ? 'Analise o arquivo anexado.' : text;
    final question = file == null ? request : '$request\n📎 ${file.name}';
    final recent = turns.reversed.take(chatContext).toList().reversed;
    String clip(String text) =>
        text.length <= 420 ? text : text.substring(0, 420);
    final context = jsonEncode([
      for (final turn in recent)
        {'usuario': clip(turn.question), 'assistente': clip(turn.answer)},
    ]);
    setState(() {
      generating = true;
      pendingQuestion = question;
      chatAnswer = '';
      chatError = '';
    });
    try {
      await for (final chunk in ai.generate(
        qualityInstruction(
          'Você é o assistente local do AI Tools. Continue o diálogo em português quando apropriado. '
          'O JSON abaixo contém turnos anteriores como contexto. Responda à solicitação atual.\n$context',
        ),
        file?.withDocument(request) ?? request,
        images: file?.images ?? const [],
        audio: file?.audio,
      )) {
        if (!mounted) break;
        setState(() => chatAnswer += chunk);
      }
      if (!mounted) return;
      if (chatAnswer.trim().isEmpty) {
        setState(() => chatError = 'O modelo retornou uma resposta vazia.');
      } else {
        setState(() {
          turns.add((question: question, answer: chatAnswer));
          chatInput.clear();
          chatAttachment = null;
          pendingQuestion = '';
        });
      }
    } catch (error) {
      if (mounted) setState(() => chatError = 'Falha no chat local.\n$error');
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Widget bubble(String speaker, String text) {
    final fromUser = speaker == 'Você';
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fromUser ? const Color(0xff293827) : surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(fromUser ? 18 : 4),
                bottomRight: Radius.circular(fromUser ? 4 : 18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    speaker,
                    style: const TextStyle(
                      color: mint,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> chatView() => [
    heading(
      'Chat local',
      'Converse com o Gemma. Os turnos recentes dão contexto à próxima resposta.',
    ),
    if (turns.isNotEmpty)
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: busy
              ? null
              : () => setState(() {
                  turns.clear();
                  chatInput.clear();
                  chatAttachment = null;
                  chatError = '';
                }),
          icon: const Icon(Icons.add),
          label: const Text('Nova conversa'),
        ),
      ),
    for (final turn in turns) ...[
      bubble('Você', turn.question),
      bubble('Gemma', turn.answer),
    ],
    if (generating && pendingQuestion.isNotEmpty) ...[
      bubble('Você', pendingQuestion),
      bubble('Gemma', chatAnswer.isEmpty ? 'Pensando…' : chatAnswer),
      const LinearProgressIndicator(),
    ],
    if (chatError.isNotEmpty) errorText(chatError),
    chatComposer(),
  ];

  Widget chatComposer() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (chatAttachment case final file?)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(file.name, overflow: TextOverflow.ellipsis),
                onDeleted: busy
                    ? null
                    : () => setState(() => chatAttachment = null),
              ),
            ),
          TextField(
            controller: chatInput,
            enabled: !busy,
            maxLines: 4,
            minLines: 1,
            maxLength: 2500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Escreva uma mensagem'),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              PopupMenuButton<AttachmentKind>(
                enabled: !busy,
                tooltip: 'Importar arquivo',
                icon: const Icon(Icons.attach_file),
                onSelected: (kind) => pick(kind, forChat: true),
                itemBuilder: (context) => [
                  for (final kind in AttachmentKind.values)
                    PopupMenuItem(
                      value: kind,
                      child: Text(kind.type.label ?? kind.name),
                    ),
                ],
              ),
              if (ai.installed)
                FilledButton.icon(
                  onPressed:
                      busy ||
                          (chatInput.text.trim().isEmpty &&
                              chatAttachment == null)
                      ? null
                      : sendChat,
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => navigate(5),
                  icon: const Icon(Icons.memory),
                  label: const Text('Configurar modelo local'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.1),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  Future<void> toggleFavorite(Tool item) async {
    if (updatingFavorites) return;
    final wasFavorite = favorites.contains(item);
    setState(() {
      updatingFavorites = true;
      if (wasFavorite) {
        favorites.remove(item);
      } else {
        favorites.add(item);
      }
    });
    try {
      await prefs.setStringList(
        favoritesKey,
        favorites.map((tool) => tool.name).toList(),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          if (wasFavorite) {
            favorites.add(item);
          } else {
            favorites.remove(item);
          }
        });
        notice('Não foi possível salvar o favorito.');
      }
    } finally {
      if (mounted) setState(() => updatingFavorites = false);
    }
  }

  List<Widget> catalog() {
    final query = search.text.trim().toLowerCase();
    final items = Tool.values
        .where(
          (item) =>
              item != Tool.chat &&
              (query.isNotEmpty || onlyFavorites || item.category == page) &&
              (!onlyFavorites || favorites.contains(item)) &&
              (query.isEmpty ||
                  '${item.title} ${item.description}'.toLowerCase().contains(
                    query,
                  )),
        )
        .toList();
    final (title, subtitle, accent) = switch (page) {
      1 => (
        'Imagem e vídeo',
        'Conceito, edição e análise visual.',
        const Color(0xffc3b9ff),
      ),
      2 => (
        'Som e voz',
        'Do roteiro à exportação em MP3.',
        const Color(0xffffcb9f),
      ),
      _ => ('Palavra e ideia', 'Escrita, revisão e ideias com IA local.', mint),
    };
    return [
      StudioHero(
        title: title,
        description: subtitle,
        index: page,
        accent: accent,
      ),
      const SizedBox(height: 14),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: busy ? null : () => navigate(5),
          leading: Icon(Icons.memory_rounded, color: accent),
          title: const Text('Gemma 4 E2B'),
          subtitle: Text(
            ai.installed
                ? 'Pronto para usar no dispositivo'
                : 'Configure o modelo local',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar em todas as ferramentas',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: () => setState(search.clear),
                  icon: const Icon(Icons.close),
                ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          FilterChip(
            avatar: Icon(onlyFavorites ? Icons.star : Icons.star_border),
            label: const Text('Favoritos'),
            selected: onlyFavorites,
            onSelected: (value) => setState(() => onlyFavorites = value),
          ),
          Text(
            '${items.length} ferramentas',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (items.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.search_off),
            title: Text('Nenhuma ferramenta encontrada'),
            subtitle: Text('Altere a busca ou o filtro de favoritos.'),
          ),
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 840
              ? 3
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          final height =
              96.0 +
              (MediaQuery.textScalerOf(context).scale(56) - 56).clamp(
                0.0,
                double.infinity,
              );
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  height: height,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      onTap: () => openTool(item),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item.icon, color: accent),
                      ),
                      title: Text(
                        item.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        item.cardDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: favorites.contains(item)
                            ? 'Remover favorito'
                            : 'Favoritar ferramenta',
                        onPressed: updatingFavorites
                            ? null
                            : () => toggleFavorite(item),
                        icon: Icon(
                          favorites.contains(item)
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: favorites.contains(item) ? accent : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  Future<({double? seconds})?> chooseVideoDuration({
    required bool poster,
  }) async {
    var value = '';
    String? error;
    return showDialog<({double? seconds})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(poster ? 'Duração do vídeo' : 'Exportar vídeo'),
          content: TextField(
            autofocus: poster,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) => value = text.trim(),
            decoration: InputDecoration(
              labelText: poster
                  ? 'Duração em segundos'
                  : 'Até o segundo (opcional)',
              helperText: poster
                  ? null
                  : 'Deixe em branco para exportar o vídeo inteiro.',
              helperMaxLines: 2,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final seconds = double.tryParse(value.replaceAll(',', '.'));
                if (!poster && value.isEmpty) {
                  Navigator.pop(context, (seconds: null));
                } else if (seconds == null ||
                    !seconds.isFinite ||
                    seconds < (poster ? 1 / 15 : 0.001)) {
                  refresh(
                    () => error = 'Informe um número positivo em segundos.',
                  );
                } else {
                  Navigator.pop(context, (seconds: seconds));
                }
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> exportMedia({
    bool videoPoster = false,
    bool jpeg = false,
  }) async {
    if (busy) return;
    final file = attachment;
    final text = exportText;
    final selectedTool = tool;
    double? seconds;
    if (videoPoster || selectedTool == Tool.videoEdit) {
      final duration = await chooseVideoDuration(poster: videoPoster);
      if (!mounted || duration == null || busy) return;
      seconds = duration.seconds;
    }
    setState(() {
      exporting = true;
      failure = '';
    });
    try {
      final saved = switch (selectedTool) {
        Tool.mediaGenerate when videoPoster => await MediaExport.posterVideo(
          text,
          seconds!,
        ),
        Tool.videoEdit => await MediaExport.videoClip(file!, seconds),
        Tool.mediaGenerate => await MediaExport.save(
          await MediaExport.poster(text),
          'cartaz.png',
          'image/png',
        ),
        Tool.imageEdit when jpeg => await MediaExport.saveJpeg(
          await MediaExport.grayscale(file!.parts.single),
          'imagem-cinza.jpg',
        ),
        Tool.imageEdit => await MediaExport.save(
          await MediaExport.grayscale(file!.parts.single),
          'imagem-cinza.png',
          'image/png',
        ),
        Tool.audioEdit => await MediaExport.saveMp3(
          MediaExport.normalizeWav(file!.parts.single),
          mp3Bitrate,
          'audio-normalizado.mp3',
        ),
        Tool.audioGenerate => await MediaExport.saveNarration(text, mp3Bitrate),
        _ => throw StateError('Exportação indisponível.'),
      };
      if (saved) notice('Arquivo salvo.');
    } catch (error) {
      if (mounted) setState(() => failure = 'Falha ao exportar.\n$error');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget? exportButton() {
    final hasText = exportText.isNotEmpty;
    final label = switch (tool) {
      Tool.mediaGenerate when hasText && MediaExport.supportsImages =>
        'Criar cartaz PNG com o texto',
      Tool.audioGenerate when hasText && MediaExport.supportsAudio =>
        'Gerar narração MP3 com voz offline',
      Tool.imageEdit when attachment != null && MediaExport.supportsImages =>
        'Salvar imagem em preto e branco (PNG)',
      Tool.videoEdit when attachment != null && MediaExport.supportsVideo =>
        'Exportar vídeo inteiro ou recortar',
      Tool.audioEdit when attachment != null && MediaExport.supportsAudio =>
        'Salvar MP3 com volume normalizado',
      _ => null,
    };
    if (label == null) return null;
    return OutlinedButton.icon(
      onPressed: busy ? null : exportMedia,
      icon: const Icon(Icons.save_alt),
      label: Text(label),
    );
  }

  List<Widget> toolView() => [
    heading(tool.title, tool.description),
    if (tool.attachmentKind == null && input.text.isEmpty)
      Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.lightbulb_outline, size: 18),
          label: const Text('Experimentar um prompt'),
          onPressed: busy
              ? null
              : () => setState(() {
                  input.text = switch (tool) {
                    Tool.write => 'Escreva um e-mail curto convidando a equipe para uma sessão de ideias.',
                    Tool.revise => 'Deixe esta frase mais clara: A gente vai ver isso mais pra frente quando puder.',
                    Tool.summary => 'Resuma em dois tópicos: O projeto terminou na sexta. A equipe vai revisar os resultados na segunda.',
                    Tool.translate => 'Traduza para o inglês: Vamos conversar amanhã sobre os próximos passos.',
                    Tool.verifyText => 'Verifique gramática e coerência: As equipe foram entregar o relatório ontem, mas terminarão hoje.',
                    Tool.code => 'Mostre como remover itens duplicados de uma lista em Dart.',
                    Tool.ideas => 'Sugira cinco temas para uma oficina de criatividade com poucos recursos.',
                    Tool.extract => 'Extraia data e responsável: Ana apresenta o plano no dia 12 de novembro.',
                    Tool.mediaGenerate => 'Crie um roteiro visual curto sobre um café de bairro em uma manhã chuvosa.',
                    Tool.audioGenerate => 'Escreva uma locução de abertura para um podcast de ciência.',
                    _ => 'Explique como dividir um projeto grande em etapas.',
                  };
                }),
        ),
      ),
    if ((tool.attachmentKind ?? AttachmentKind.document) case final kind) ...[
      OutlinedButton.icon(
        onPressed: busy ? null : () => pick(kind),
        icon: const Icon(Icons.attach_file),
        label: Text(
          picking
              ? 'Abrindo arquivo…'
              : switch (kind) {
                  AttachmentKind.image => 'Selecionar imagem',
                  AttachmentKind.video => 'Selecionar vídeo',
                  AttachmentKind.audio => 'Importar áudio',
                  AttachmentKind.document => 'Importar documento',
                },
        ),
      ),
      if (kind == AttachmentKind.audio)
        const Text(
          'Importe áudio para exportar em MP3. A análise pelo Gemma aceita até 30 segundos.',
        ),
      if (kind == AttachmentKind.video)
        Text(
          Attachment.nativeExportSupported
              ? 'A análise usa até três quadros, sem a faixa de áudio.'
              : 'A análise usa um quadro do vídeo, sem a faixa de áudio.',
        ),
      if (attachment case final file?)
        ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(file.name),
          trailing: IconButton(
            onPressed: busy ? null : () => setState(() => attachment = null),
            tooltip: 'Remover arquivo',
            icon: const Icon(Icons.close),
          ),
        ),
      const SizedBox(height: 12),
    ],
    TextField(
      controller: input,
      enabled: !busy,
      minLines: 5,
      maxLines: 10,
      maxLength: 4000,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Sua solicitação',
        alignLabelWithHint: true,
        hintText: tool == Tool.translate
            ? 'Informe o idioma de destino e cole o texto.'
            : 'Digite ou cole o texto aqui.',
      ),
    ),
    const SizedBox(height: 12),
    if (!ai.supported || !ai.installed)
      OutlinedButton.icon(
        onPressed: busy ? null : () => navigate(5),
        icon: const Icon(Icons.memory),
        label: const Text('Configurar modelo local'),
      )
    else
      FilledButton.icon(
        onPressed:
            busy ||
                (tool.attachmentKind != null
                    ? attachment == null
                    : input.text.trim().isEmpty && attachment == null)
            ? null
            : generate,
        icon: const Icon(Icons.auto_awesome),
        label: Text(generating ? 'Gerando no dispositivo…' : 'Gerar resposta'),
      ),
    if (generating)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: LinearProgressIndicator(),
      ),
    if (exporting)
      const ListTile(
        leading: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(),
        ),
        title: Text('Exportando arquivo…'),
      ),
    ?exportButton(),
    if (MediaExport.supportsImages &&
        tool == Tool.imageEdit &&
        attachment != null)
      OutlinedButton.icon(
        onPressed: busy ? null : () => exportMedia(jpeg: true),
        icon: const Icon(Icons.image_outlined),
        label: const Text('Salvar imagem em preto e branco (JPG)'),
      ),
    if (MediaExport.supportsVideo &&
        tool == Tool.mediaGenerate &&
        exportText.isNotEmpty)
      OutlinedButton.icon(
        onPressed: busy ? null : () => exportMedia(videoPoster: true),
        icon: const Icon(Icons.movie_outlined),
        label: const Text('Criar vídeo com o cartaz'),
      ),
    if (failure.isNotEmpty) errorText(failure),
    if (output.isNotEmpty) ...[
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resposta',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar resposta',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: output));
                      notice('Resposta copiada.');
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              SelectableText(output),
            ],
          ),
        ),
      ),
    ],
  ];

  List<Widget> historyView() => [
    heading(
      'Histórico',
      'Até 50 respostas recentes, salvas neste dispositivo.',
    ),
    if (history.isEmpty)
      const Card(
        child: ListTile(
          leading: Icon(Icons.history),
          title: Text('Nenhuma resposta salva'),
        ),
      )
    else ...[
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Limpar histórico'),
          onPressed: () async {
            if (!await confirm(
                  'Limpar histórico?',
                  'As respostas salvas serão apagadas deste dispositivo.',
                ) ||
                !mounted) {
              return;
            }
            setState(history.clear);
            await persist();
          },
        ),
      ),
      for (final entry in history)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: Icon(entry.tool.icon, color: mint),
              title: Text(entry.tool.title),
              subtitle: Text(
                entry.input,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openTool(entry.tool, entry),
            ),
          ),
        ),
    ],
  ];

  Widget errorText(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: SelectableText(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Future<void> updateSettings(VoidCallback update) async {
    if (busy) return;
    final old = (mp3Bitrate, chatContext, saveHistory, studioMode);
    setState(() {
      savingSettings = true;
      update();
    });
    try {
      await prefs.setString(
        settingsKey,
        jsonEncode({
          'mp3Bitrate': mp3Bitrate,
          'chatContext': chatContext,
          'saveHistory': saveHistory,
          'studioMode': studioMode,
        }),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          mp3Bitrate = old.$1;
          chatContext = old.$2;
          saveHistory = old.$3;
          studioMode = old.$4;
        });
      }
      notice('Não foi possível salvar as configurações.');
    } finally {
      if (mounted) setState(() => savingSettings = false);
    }
  }

  Widget settingsSection(String title, List<Widget> items) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (index, item) in items.indexed) ...[
            if (index > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            item,
          ],
        ],
      ),
    ),
  );

  List<Widget> settingsView() => [
    heading(
      'Configurações',
      'Preferências, exportação, privacidade e modelo de IA.',
    ),
    settingsSection('Qualidade da IA', [
      SwitchListTile(
        title: const Text('Modo Estúdio'),
        subtitle: const Text(
          'Pede respostas mais cuidadosas e detalhadas ao Gemma. Pode demorar mais que o modo comum.',
        ),
        value: studioMode,
        onChanged: busy
            ? null
            : (value) => updateSettings(() => studioMode = value),
      ),
    ]),
    settingsSection('Áudio e vídeo', [
      const ListTile(
        leading: Icon(Icons.audio_file_outlined),
        title: Text('Formato de saída'),
        subtitle: Text('Áudio em MP3, imagens em PNG ou JPG e vídeo em MP4.'),
      ),
      if (MediaExport.usesDesktopEncoder)
        const ListTile(
          leading: Icon(Icons.terminal),
          title: Text('Codificação no computador'),
          subtitle: Text(
            'MP3 e MP4 usam o FFmpeg disponível no PATH. '
            'A narração no Linux também usa o eSpeak NG.',
          ),
        ),
      ListTile(
        title: const Text('Qualidade do MP3'),
        trailing: DropdownButton<int>(
          value: mp3Bitrate,
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) updateSettings(() => mp3Bitrate = value);
                },
          items: [
            for (final value in bitrates)
              DropdownMenuItem(value: value, child: Text('$value kbps')),
          ],
        ),
      ),
      const ListTile(
        leading: Icon(Icons.video_file_outlined),
        title: Text('Duração do vídeo'),
        subtitle: Text(
          'Escolha a duração ao criar um cartaz em MP4. Na edição, exporte o vídeo inteiro ou informe o ponto de corte.',
        ),
      ),
    ]),
    settingsSection('Chat e privacidade', [
      ListTile(
        title: const Text('Contexto do chat'),
        subtitle: const Text('Turnos recentes enviados ao Gemma.'),
        trailing: DropdownButton<int>(
          value: chatContext,
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) updateSettings(() => chatContext = value);
                },
          items: [
            for (var value = 0; value <= 5; value++)
              DropdownMenuItem(value: value, child: Text('$value')),
          ],
        ),
      ),
      SwitchListTile(
        title: const Text('Salvar histórico das ferramentas'),
        subtitle: const Text('Guarda as próximas respostas neste dispositivo.'),
        value: saveHistory,
        onChanged: busy
            ? null
            : (value) => updateSettings(() => saveHistory = value),
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Gerenciar histórico'),
        onTap: busy ? null : () => navigate(4),
      ),
    ]),
    ...modelView(),
    const SizedBox(height: 16),
    settingsSection('Preferências do aplicativo', [
      ListTile(
        leading: const Icon(Icons.restore),
        title: const Text('Restaurar configurações padrão'),
        subtitle: const Text(
          'MP3 a 128 kbps, três turnos de contexto, histórico ativado e modo comum.',
        ),
        onTap: busy
            ? null
            : () => updateSettings(() {
                mp3Bitrate = 128;
                chatContext = 3;
                saveHistory = true;
                studioMode = false;
              }),
      ),
    ]),
  ];
  List<Widget> modelView() => [
    heading(
      'Modelo local',
      'Instale o Gemma para gerar respostas no dispositivo.',
    ),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.memory, color: mint, size: 36),
            const SizedBox(height: 12),
            heading('Gemma 4 E2B', 'Flutter Edge AI · LiteRT-LM'),
            Text(
              ai.supported
                  ? 'O download inicial exige internet e espaço para cerca de 2,6 GB. Após a instalação, a geração pode funcionar offline.'
                  : 'A inferência desta versão está disponível nas plataformas nativas.',
            ),
            if (modelFailure case final message?) errorText(message),
            const SizedBox(height: 18),
            if (changingModel) ...[
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 10),
              Text(
                ai.installed
                    ? 'Removendo modelo…'
                    : 'Instalando modelo… ${(progress * 100).round()}%',
              ),
            ] else if (ai.supported && ai.installed) ...[
              const Chip(
                avatar: Icon(Icons.check_circle_outline),
                label: Text('Instalado'),
              ),
              OutlinedButton.icon(
                onPressed: () => changeModel(ModelAction.remove),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover modelo'),
              ),
            ] else if (ai.supported) ...[
              FilledButton.icon(
                onPressed: () => changeModel(ModelAction.download),
                icon: const Icon(Icons.download),
                label: const Text('Baixar modelo'),
              ),
              if (const {
                TargetPlatform.windows,
                TargetPlatform.linux,
                TargetPlatform.macOS,
              }.contains(defaultTargetPlatform))
                OutlinedButton.icon(
                  onPressed: () => changeModel(ModelAction.link),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Usar modelo existente'),
                ),
            ],
          ],
        ),
      ),
    ),
  ];
}
