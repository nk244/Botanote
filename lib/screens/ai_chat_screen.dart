import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/ai_chat_message.dart';
import '../providers/ai_provider.dart';
import '../providers/plant_provider.dart';
import '../providers/settings_provider.dart';

/// パーソナル植物コーチのチャット画面
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  String? _pendingImageBase64;

  @override
  void initState() {
    super.initState();
    // 画面表示時にチャット履歴をクリア
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AiProvider>().clearMessages();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() => _pendingImageBase64 = base64Encode(bytes));
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _pendingImageBase64 == null) return;

    final apiKey =
        context.read<SettingsProvider>().settings.claudeApiKey;
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定からClaude APIキーを設定してください')),
      );
      return;
    }

    final imageBase64 = _pendingImageBase64;
    _textController.clear();
    setState(() => _pendingImageBase64 = null);

    final plantProvider = context.read<PlantProvider>();
    final allLogs = await plantProvider.getAllLogsForCoach();

    if (!mounted) return;
    await context.read<AiProvider>().sendMessage(
          apiKey: apiKey,
          text: text.isEmpty ? '（画像を送りました）' : text,
          imageBase64: imageBase64,
          plants: plantProvider.plants,
          recentLogs: allLogs,
        );

    // 最下部にスクロール
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('植物コーチ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '会話をリセット',
            onPressed: () => context.read<AiProvider>().clearMessages(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Consumer<AiProvider>(
      builder: (context, aiProvider, _) {
        final messages = aiProvider.messages;

        if (messages.isEmpty && !aiProvider.isLoading) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length +
              (aiProvider.isLoading ? 1 : 0) +
              (aiProvider.error != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < messages.length) {
              return _buildMessageBubble(messages[index]);
            }
            if (aiProvider.isLoading) {
              return _buildTypingIndicator();
            }
            if (aiProvider.error != null) {
              return _buildErrorBubble(aiProvider.error!);
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eco_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            '植物のことを何でも相談してください',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage message) {
    final isUser = message.isUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.imageBase64 != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(message.imageBase64!),
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              if (message.imageBase64 != null && message.text.isNotEmpty)
                const SizedBox(height: 8),
              if (message.text.isNotEmpty)
                SelectableText(
                  message.text,
                  style: TextStyle(
                    color: isUser
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8, height: 8,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('考え中...'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBubble(String error) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImageBase64 != null) _buildPendingImage(),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: _pickImage,
                  tooltip: '画像を添付',
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                Consumer<AiProvider>(
                  builder: (context, ai, _) => IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: ai.isLoading ? null : _send,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingImage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(_pendingImageBase64!),
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            style: IconButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
              padding: EdgeInsets.zero,
              minimumSize: const Size(24, 24),
            ),
            onPressed: () => setState(() => _pendingImageBase64 = null),
          ),
        ],
      ),
    );
  }
}
