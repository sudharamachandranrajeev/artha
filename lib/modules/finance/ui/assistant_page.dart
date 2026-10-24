import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../insights/assistant.dart';
import '../insights/risk.dart';

/// Opens [url] in the browser when it is a web link.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The key saved in the system keychain, or null.
final assistantKeyProvider = FutureProvider<String?>((ref) async {
  ref.watch(revisionProvider);
  final key = await ref.watch(sessionProvider).keys.store.read(assistantKeyName);
  return key == null || key.isEmpty ? null : key;
});

/// What goes with every question, as text the user can read.
final assistantBriefProvider = FutureProvider<String>((ref) async {
  final s = await ref.watch(situationProvider.future);
  final risk = await ref.watch(riskProvider.future);
  final world = await ref.watch(worldProvider.future);
  final facts = (await ref.watch(insightsProvider.future)).facts.where((f) => f.state == 'user');
  final planned = await ref.watch(plannedProvider.future);
  return assistantBrief(
    s: s,
    risk: risk,
    plan: buildPlan(s, risk),
    market: world.market,
    news: world.news,
    today: ref.watch(todayProvider),
    goals: [for (final f in facts) f.title],
    planned: [for (final p in planned) (date: p.date, amount: p.amount)],
  );
});

Future<void> openAssistant(BuildContext context, {String? question}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => AssistantPage(question: question)));

/// Asks for the API key and keeps it in the keychain. True when saved.
Future<bool> askForKey(BuildContext context, WidgetRef ref) async {
  final value = await showDialog<String>(context: context, builder: (_) => const _KeyDialog());
  if (value == null || value.isEmpty || !context.mounted) return false;
  if (value.contains(RegExp(r'\s')) || value.length < 20) {
    showError(context, AssistantException('That does not look like an API key.'));
    return false;
  }
  await ref.read(sessionProvider).keys.store.write(assistantKeyName, value);
  ref.invalidate(assistantKeyProvider);
  return true;
}

class _KeyDialog extends StatefulWidget {
  const _KeyDialog();

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Anthropic API key'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create a key at console.anthropic.com. Questions are billed to your Anthropic account. The key '
            'is kept in this device\'s keychain only: never in the database, never synced.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _key,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'API key', hintText: 'sk-ant-…'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _key.text.trim()), child: const Text('Save')),
    ],
  );
}

class _Turn {
  _Turn(this.question);
  final String question;
  AssistantReply? reply;
  String? error;
}

const _starters = [
  'What is the safest place for my savings right now?',
  'How is the Bank of England decision likely to affect me?',
  'Am I on track for a 6 month emergency fund?',
  'What should I do first to lower my risk?',
];

/// Questions answered by Claude with web search, using the user's own key.
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key, this.question});
  final String? question;

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  Assistant? _assistant;
  String? _forKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _input.text = widget.question ?? '';
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String key) async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy) return;
    if (_forKey != key) {
      _assistant = Assistant(key);
      _forKey = key;
    }
    final turn = _Turn(q);
    setState(() {
      _turns.add(turn);
      _busy = true;
      _input.clear();
    });
    try {
      final brief = await ref.read(assistantBriefProvider.future);
      turn.reply = await _assistant!.ask(q, brief);
    } on AssistantException catch (e) {
      turn.error = e.message;
    } on Object {
      turn.error = 'Something went wrong. Try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Durations.short3,
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(assistantKeyProvider);
    return PageScaffold(
      title: 'Ask Artha',
      actions: [
        IconButton(
          tooltip: 'What is shared',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: _showBrief,
        ),
      ],
      body: AsyncView(
        key,
        onRetry: () => ref.invalidate(assistantKeyProvider),
        builder: (apiKey) => apiKey == null ? _setup() : _chat(apiKey),
      ),
    );
  }

  Widget _setup() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.forum_outlined,
          title: 'Ask questions about your money',
          message:
              'Artha can answer with up-to-date rates and rules from the web, using your own Anthropic '
              'account. It is off until you add a key. Each question sends a short summary of your '
              'finances with rounded totals; no payees, account names or numbers. See exactly what, '
              'any time, with the eye icon.',
          actions: [
            FilledButton.icon(
              onPressed: () => askForKey(context, ref),
              icon: const Icon(Icons.key),
              label: const Text('Add API key'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _chat(String apiKey) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_turns.isEmpty) ...[
                    const Text(
                      'General information, not regulated advice. Answers use the web and can be wrong: '
                      'check sources before acting.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _starters)
                          ActionChip(label: Text(s), onPressed: () => setState(() => _input.text = s)),
                      ],
                    ),
                  ],
                  for (final t in _turns) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, left: 48),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(t.question),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8, right: 24),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: t.error != null
                            ? Text(t.error!, style: TextStyle(color: scheme.error))
                            : t.reply == null
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Thinking and checking sources…'),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(t.reply!.text),
                                  if (t.reply!.sources.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final s in t.reply!.sources.take(6))
                                          ActionChip(
                                            avatar: const Icon(Icons.open_in_new, size: 14),
                                            label: Text(s.title, overflow: TextOverflow.ellipsis),
                                            onPressed: () => openLink(s.url),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(apiKey),
                        decoration: const InputDecoration(hintText: 'Ask about rates, risk, a plan…'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _busy ? null : () => _send(apiKey),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showBrief() async {
    final brief = await ref.read(assistantBriefProvider.future);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sent with every question'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(brief))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}
