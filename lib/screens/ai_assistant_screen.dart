import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../state/ai_assistant_provider.dart';
import '../state/store_provider.dart';
import '../state/product_provider.dart';
import '../state/ingredient_provider.dart';
import '../widgets/bounded_content.dart';

/// AI Assistant tab -- owner/admin only (see home_shell.dart's
/// _isAdmin gate). Chat UI over the ai-assistant edge function;
/// history persists locally via AiAssistantProvider.
///
/// NOTE: AppTextStyles.body(...) is assumed to exist alongside the
/// already-confirmed AppTextStyles.mono(...) (used elsewhere in
/// home_shell.dart) for the Manrope body font mentioned in the design
/// system notes. If your app_theme.dart names this differently, swap
/// the call sites below -- everything else is theme-token-only (no
/// hardcoded colors) so it should still match once that's fixed.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<AiAssistantProvider>();
    if (!provider.isLoaded) {
      provider.loadFromDisk();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    final provider = context.read<AiAssistantProvider>();
    _scrollToBottom();
    final creditsRemaining = await provider.sendMessage(text);
    if (creditsRemaining != null && mounted) {
      context.read<StoreProvider>().setAiCreditsRemaining(creditsRemaining);
      // The AI Assistant's edge function can add/update/withdraw products
      // directly against Supabase, bypassing every method on
      // ProductProvider -- which only fetches once on login and never
      // auto-refreshes (see its class doc). Without this, the Products
      // admin screen keeps showing stale data until the next full app
      // restart, even though the AI's own chat reply already confirmed a
      // successful add/update. We don't know locally whether *this*
      // particular turn touched products, so refetch after every
      // successful turn rather than trying to parse the reply for it.
      // Same reasoning applies to ingredients (add_ingredient,
      // update_ingredient, withdraw_inventory can all target them too),
      // and IngredientProvider has the identical fetch-once-on-login
      // load pattern -- see its own class doc.
      unawaited(context.read<ProductProvider>().loadFromSupabase());
      unawaited(context.read<IngredientProvider>().loadFromSupabase());
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<AiAssistantProvider>();
    final store = context.watch<StoreProvider>().store;
    final canSend = store == null || store.canUseAiAssistant;
    final creditsLabel = store == null
        ? null
        : store.isExpired
            ? 'Trial expired · upgrade to continue'
            : '${store.aiCreditsRemaining} credit${store.aiCreditsRemaining == 1 ? '' : 's'} left this month';

    return Container(
      color: AppColors.charcoal,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.slate,
              border: Border(bottom: BorderSide(color: AppColors.charcoal, width: 1)),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: AppColors.ledAmber),
                const SizedBox(width: 8),
                Text(
                  'AI ASSISTANT',
                  style: AppTextStyles.mono(size: 13, weight: FontWeight.w700, letterSpacing: 1),
                ),
                const Spacer(),
                if (creditsLabel != null)
                  Text(
                    creditsLabel,
                    style: AppTextStyles.mono(
                      size: 11,
                      weight: FontWeight.w600,
                      color: (store!.isExpired || store.aiCreditsRemaining == 0)
                          ? AppColors.ledgerRed
                          : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: BoundedContent(
              child: Column(
                children: [
                  Expanded(
                    child: chat.messages.isEmpty
                        ? _EmptyState(canSend: canSend)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, i) => _MessageBubble(message: chat.messages[i]),
                          ),
                  ),
                  if (chat.isSending)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ledAmber),
                      ),
                    ),
                  if (chat.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        chat.error!,
                        style: AppTextStyles.mono(size: 11, color: AppColors.ledgerRed),
                      ),
                    ),
                  _InputBar(
                    controller: _controller,
                    canSend: canSend,
                    isSending: chat.isSending,
                    disabledHint: store == null
                        ? null
                        : store.isExpired
                            ? 'Upgrade your plan to keep using the assistant'
                            : 'Out of credits — resets next cycle',
                    onSend: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool canSend;
  const _EmptyState({required this.canSend});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              canSend
                  ? 'Ask about inventory, sales, or how to use KahaPro.'
                  : 'The assistant is unavailable right now.',
              textAlign: TextAlign.center,
              style: AppTextStyles.mono(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? AppColors.slate : AppColors.charcoal,
          borderRadius: BorderRadius.circular(10),
          border: isUser ? null : Border.all(color: AppColors.ledAmber.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.content,
              style: AppTextStyles.mono(size: 13, color: Colors.white),
            ),
            if (!isUser && message.provider != null) ...[
              const SizedBox(height: 5),
              Text(
                'via ${message.provider}',
                style: AppTextStyles.mono(size: 10, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend; // hard block: plan expired or no credits left this cycle
  final bool isSending; // soft/temporary: a request is currently in flight
  final String? disabledHint;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.isSending,
    required this.disabledHint,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    // Only swap to the full red banner for a real, standing block
    // (expired plan / no credits this cycle) -- never just because a
    // request is mid-flight, or every send would flash a misleading
    // "Out of credits" message for the second or two it takes to get
    // a reply back.
    if (!canSend && disabledHint != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: AppColors.slate,
        child: Text(
          disabledHint!,
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(size: 12, color: AppColors.ledgerRed),
        ),
      );
    }

    final enabled = canSend && !isSending;

    return Container(
      padding: const EdgeInsets.all(10),
      color: AppColors.slate,
      child: Row(
        children: [
          Expanded(
            child: Focus(
              // Plain TextField's onSubmitted never fires here because
              // minLines/maxLines > 1 makes this a multi-line field --
              // Enter just inserts a newline by default. Focus sits
              // above TextField in the same focus chain, so its
              // onKeyEvent gets first look at the raw key: Enter alone
              // sends (and is marked handled, so no newline is typed);
              // Shift+Enter (or any other modifier) is left ignored,
              // so it falls through to the normal newline behavior.
              onKeyEvent: (node, event) {
                final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
                if (isEnter && !shiftHeld && event is KeyDownEvent) {
                  if (enabled) onSend();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                style: AppTextStyles.mono(size: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask the assistant… (Enter to send, Shift+Enter for new line)',
                  hintStyle: AppTextStyles.mono(size: 13, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.charcoal,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => enabled ? onSend() : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: AppColors.ledAmber),
            onPressed: enabled ? onSend : null,
          ),
        ],
      ),
    );
  }
}
