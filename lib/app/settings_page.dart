import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/finance/domain/ledger.dart' show basePrefKey;
import '../modules/finance/insights/assistant.dart' show assistantKeyName;
import '../modules/finance/ui/assistant_page.dart' show askForKey, assistantKeyProvider;
import '../modules/finance/ui/common.dart';
import '../ui/theme.dart';
import 'appearance.dart';
import 'providers.dart';

final _fxProvider = FutureProvider<({bool auto, String? last})>((ref) async {
  ref.watch(revisionProvider);
  final db = ref.watch(sessionProvider).db;
  return (auto: await db.localSetting('fx.auto') != 'off', last: await db.localSetting('fx.last'));
});

final _worldSettingProvider = FutureProvider<bool>((ref) async {
  ref.watch(revisionProvider);
  return await ref.watch(sessionProvider).db.localSetting('world.auto') != 'off';
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(setupProvider).value;
    return PageScaffold(
      title: 'Settings',
      children: [
        const SectionCard(title: 'Appearance', hint: 'settings.appearance', child: _AppearancePicker()),
        SectionCard(
          title: 'Base currency',
          hint: 'settings.base',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Totals, reports and charts are shown in ${base ?? '–'}. Accounts keep their own currency.',
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: base == null ? null : () => _changeBase(context, ref, base),
                child: Text(base ?? '–'),
              ),
            ],
          ),
        ),
        const HintsCard(),
        SectionCard(
          title: 'Exchange rates',
          hint: 'settings.fx',
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncView(
            ref.watch(_fxProvider),
            builder: (fx) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('Update daily'),
                  subtitle: const Text(
                    'Fetches European Central Bank reference rates from frankfurter.dev once a day. Only '
                    'currency codes are sent.',
                  ),
                  value: fx.auto,
                  onChanged: (v) async {
                    await ref.read(sessionProvider).db.setLocalSetting('fx.auto', v ? 'on' : 'off');
                    ref.invalidate(_fxProvider);
                  },
                ),
                ListTile(
                  title: const Text('Last updated'),
                  subtitle: Text(fx.last == null ? 'Never' : niceDate(fx.last!)),
                  trailing: OutlinedButton(
                    onPressed: base == null ? null : () => _refreshRates(context, ref, base),
                    child: const Text('Update now'),
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionCard(
          title: 'News and rates',
          hint: 'settings.world',
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncView(
            ref.watch(_worldSettingProvider),
            builder: (on) => SwitchListTile(
              title: const Text('Fetch news and rates'),
              subtitle: const Text(
                'Downloads Bank Rate, inflation and headlines from the Bank of England, ONS, HMRC, FCA, '
                'MoneySavingExpert and BBC at most every 6 hours when you open Insights. Nothing about you is sent.',
              ),
              value: on,
              onChanged: (v) async {
                await ref.read(sessionProvider).db.setLocalSetting('world.auto', v ? 'on' : 'off');
                ref.invalidate(_worldSettingProvider);
              },
            ),
          ),
        ),
        SectionCard(
          title: 'Ask Artha',
          hint: 'settings.assistant',
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncView(
            ref.watch(assistantKeyProvider),
            builder: (key) => ListTile(
              title: Text(key == null ? 'Off' : 'On, using your Anthropic key'),
              subtitle: const Text(
                'Answers questions with Claude and web search. Each question sends a rounded summary of your '
                'finances (no payees, account names or numbers); see it under the eye icon. Billed to your '
                'Anthropic account. The key stays in this device\'s keychain.',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => askForKey(context, ref),
                    child: Text(key == null ? 'Add key' : 'Replace'),
                  ),
                  if (key != null)
                    TextButton(
                      onPressed: () async {
                        await ref.read(sessionProvider).keys.store.delete(assistantKeyName);
                        ref.invalidate(assistantKeyProvider);
                      },
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ),
          ),
        ),
        const AppLockCard(),
        const SyncCard(),
        const SecurityCard(
          network: 'Nothing leaves the device unless you sign in to sync, fetch exchange rates, news and rates, or ask a question with your own key.',
        ),
        const AboutCard(description: 'Personal finance and investments.'),
      ],
    );
  }

  Future<void> _changeBase(BuildContext context, WidgetRef ref, String current) async {
    var picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Base currency'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CurrencyField(value: picked, label: 'Currency', onChanged: (c) => setState(() => picked = c)),
                const SizedBox(height: 12),
                const Text(
                  'Reports are converted at stored exchange rates. Existing categories stay in their '
                  'currency; new ones use the new base. Synced devices switch too.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: picked == current ? null : () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await guarded(context, () => ref.mutate((s) => s.ledger.setPref(basePrefKey, picked))) &&
        context.mounted) {
      await _refreshRates(context, ref, picked);
    }
  }

  Future<void> _refreshRates(BuildContext context, WidgetRef ref, String base) async {
    var stored = 0;
    final ok = await guarded(context, () async {
      stored = await ref.mutate((s) => refreshRates(s, base));
    });
    if (ok && context.mounted) {
      showMessage(context, stored == 0 ? 'Rates are up to date.' : 'Stored $stored exchange rates.');
    }
  }
}

/// The theme manager: brightness mode and a palette card per shipped theme.
class _AppearancePicker extends ConsumerWidget {
  const _AppearancePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).value ?? Appearance.fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {appearance.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setAppearance(ref, mode: s.first),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final p in arthaPalettes)
              _PaletteCard(
                palette: p,
                selected: p.id == appearance.themeId,
                onTap: () => setAppearance(ref, themeId: p.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.palette, required this.selected, required this.onTap});
  final ArthaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final mode = palette.mode(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final swatches = [
      dark ? const Color(0xFF121212) : const Color(0xFFF2F2F2),
      dark ? const Color(0xFF1C1C1F) : const Color(0xFFFFFFFF),
      mode.primary,
      mode.soft,
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? scheme.primary : skin.hairline, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final s in swatches) ...[
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: s,
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.hairline),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                if (selected) Icon(Icons.check_circle, size: 18, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 10),
            Text(palette.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              palette.blurb,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
