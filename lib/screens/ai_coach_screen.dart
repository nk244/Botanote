import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ai_service.dart';

/// AI パーソナルコーチ画面。
///
/// チャット形式で植物育成に関する質問ができる。
/// ユーザーが育てている植物情報をコンテキストとして Gemini API に渡す。
class AiCoachScreen extends StatefulWidget {
  const AiCoachScreen({super.key});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  final List<ChatMessage> _history = [];
  final List<_UiMessage> _uiMessages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 育てている植物のコンテキスト文字列を生成する。
  String _buildPlantContext() {
    final plants = context.read<PlantProvider>().plants;
    if (plants.isEmpty) return '';
    final lines = plants.map((p) {
      final parts = <String>[p.name];
      if (p.variety != null) parts.add('（${p.variety}）');
      if (p.wateringIntervalDays != null) {
        parts.add('水やり${p.wateringIntervalDays}日ごと');
      }
      return parts.join(' ');
    });
    return lines.join('\n');
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final apiKey = context.read<SettingsProvider>().geminiApiKey;
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini APIキーが設定されていません。設定画面で入力してください。'),
        ),
      );
      return;
    }

    // UIにユーザーメッセージを追加する
    setState(() {
      _uiMessages.add(_UiMessage(text: text, isUser: true));
      _history.add(ChatMessage(role: 'user', text: text));
      _isLoading = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final plantContext = _buildPlantContext();
      final response = await AiService().chat(
        messages: List.from(_history)..removeLast(), // 送信前の履歴
        userMessage: text,
        plantContext: plantContext.isNotEmpty ? plantContext : null,
        apiKey: apiKey,
      );

      if (mounted) {
        setState(() {
          _uiMessages.add(_UiMessage(text: response, isUser: false));
          _history.add(ChatMessage(role: 'model', text: response));
        });
        _scrollToBottom();
      }
    } on AiServiceException catch (e) {
      if (mounted) {
        setState(() {
          _uiMessages.add(_UiMessage(
            text: 'エラー: ${e.message}',
            isUser: false,
            isError: true,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uiMessages.add(_UiMessage(
            text: 'エラーが発生しました: $e',
            isUser: false,
            isError: true,
          ));
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 会話をリセットする。
  void _clearConversation() {
    setState(() {
      _history.clear();
      _uiMessages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome,
                color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            const Text('AIコーチ'),
          ],
        ),
        actions: [
          if (_uiMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '会話をリセット',
              onPressed: _clearConversation,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _uiMessages.isEmpty
                ? _buildWelcomeView()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _uiMessages.length,
                    itemBuilder: (context, index) {
                      return _MessageBubble(message: _uiMessages[index]);
                    },
                  ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('考え中...',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          // 入力エリア
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _isLoading ? null : _sendMessage(),
                      decoration: InputDecoration(
                        hintText: '植物の育て方を聞いてみよう...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isLoading ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 会話が空の場合に表示するウェルカムビュー
  Widget _buildWelcomeView() {
    final plants = context.watch<PlantProvider>().plants;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 72,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'AIパーソナルコーチ',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '植物の育て方、水やりのタイミング、病気の対処法など\n何でも聞いてみてください。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (plants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'あなたの植物 ${plants.length} 件の情報をもとにアドバイスします。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 24),
            // サジェスト質問チップ
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestChip(
                  label: '水やりの頻度は？',
                  onTap: () {
                    _inputController.text = '水やりの適切な頻度を教えてください';
                    _sendMessage();
                  },
                ),
                _SuggestChip(
                  label: '葉が黄色くなった',
                  onTap: () {
                    _inputController.text = '葉が黄色くなってきました。原因と対処法を教えてください';
                    _sendMessage();
                  },
                ),
                _SuggestChip(
                  label: '肥料のタイミング',
                  onTap: () {
                    _inputController.text = '肥料を与えるタイミングと量を教えてください';
                    _sendMessage();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// チャットメッセージのUIデータクラス。
class _UiMessage {
  final String text;
  final bool isUser;
  final bool isError;

  const _UiMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });
}

/// チャットバブルウィジェット。
class _MessageBubble extends StatelessWidget {
  final _UiMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome,
                  size: 16, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: message.isError
                    ? colorScheme.errorContainer
                    : isUser
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: message.isError
                      ? colorScheme.onErrorContainer
                      : isUser
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(Icons.person,
                  size: 16, color: colorScheme.onSecondaryContainer),
            ),
          ],
        ],
      ),
    );
  }
}

/// サジェスト質問チップウィジェット。
class _SuggestChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.chat_bubble_outline, size: 16),
    );
  }
}
