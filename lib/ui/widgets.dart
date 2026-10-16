import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'format.dart';
import 'hints.dart';
import 'theme.dart';

/// Tabular figures keep columns of numbers aligned.
const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Loading, error (with retry) and data states of an async value.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  // Keeps showing the last data while a write makes the provider load again.
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    data: builder,
    error: (error, _) => ErrorPanel(describeError(error), onRetry: onRetry),
    loading: () => const Center(
      child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: StatusColors.critical, size: 40),
          const SizedBox(height: 12),
          SelectableText(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

/// A page with its own app bar, the sync indicator and an optional hint banner
/// above scrolling content limited to a readable width.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.banner,
    this.actions = const [],
    this.children,
    this.body,
    this.fab,
    this.bottom,
  }) : assert((children == null) != (body == null));

  final String title;
  final String? banner;
  final List<Widget> actions;
  final List<Widget>? children;
  final Widget? body;
  final Widget? fab;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [...actions, const SyncIndicator(), const SizedBox(width: 8)],
      bottom: bottom,
    ),
    floatingActionButton: fab,
    body:
        body ??
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [if (banner != null) HintBanner(banner!), ...children!],
                ),
              ),
            ),
          ],
        ),
  );
}

/// Content constrained to a readable width, for pages that build their own list.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: child),
  );
}

/// A titled card. [hint] adds an info icon with that hint.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });
  final String title;
  final String? hint;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                      if (hint != null)
                        Hint(
                          hint!,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    ),
  );
}

/// One headline number.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.caption,
    this.status,
  });
  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final String? caption;

  /// Shown as a coloured icon next to the caption (never colour alone).
  final ({Color color, IconData icon})? status;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final tile = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: t.labelLarge?.copyWith(color: muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: t.headlineSmall?.merge(tabular)),
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (status != null) ...[
                    Icon(status!.icon, size: 16, color: status!.color),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      caption!,
                      style: t.bodySmall?.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    return hint == null ? tile : Hint(hint!, child: tile);
  }
}

/// Lays tiles out in as many columns as fit, each at least [minWidth] wide.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minWidth = 200});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length);
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      },
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
  });
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
          ],
        ],
      ),
    );
  }
}

/// A status shown with its icon and label.
class StatusLabel extends StatelessWidget {
  const StatusLabel(this.status, this.label, {super.key});
  final Status status;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(status.icon, size: 16, color: status.color),
      const SizedBox(width: 4),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

enum Status {
  good(StatusColors.good, Icons.check_circle_outline),
  warning(StatusColors.warning, Icons.warning_amber_rounded),
  serious(StatusColors.serious, Icons.report_outlined),
  critical(StatusColors.critical, Icons.error_outline),
  info(null, Icons.info_outline);

  const Status(this._color, this.icon);
  final Color? _color;
  final IconData icon;
  Color get color => _color ?? const Color(0xFF898781);
}

/// Money in a colour that says direction: income green, spending default.
class Amount extends StatelessWidget {
  const Amount(this.minor, this.currency, {super.key, this.signed = false, this.style, this.flow = false});
  final int minor;
  final String currency;
  final bool signed;
  final TextStyle? style;

  /// Colour money in (positive) as income.
  final bool flow;

  @override
  Widget build(BuildContext context) {
    final good = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4CC38A)
        : const Color(0xFF0B7A3E);
    return Text(
      money(minor, currency, signed: signed),
      style: (style ?? const TextStyle()).merge(tabular).copyWith(color: flow && minor > 0 ? good : null),
    );
  }
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

void showError(BuildContext context, Object error) => ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(describeError(error)),
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    showCloseIcon: true,
  ),
);

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs [action], showing any error; returns whether it succeeded.
Future<bool> guarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// A date field that opens the date picker. Value is yyyy-MM-dd.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.parse(value),
        firstDate: DateTime(1970),
        lastDate: DateTime(now.year + 5),
      );
      if (picked != null) {
        onChanged(
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}',
        );
      }
    },
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined)),
      child: Text(niceDate(value)),
    ),
  );
}

/// Small sync state icon for app bars; opens Settings' sync section on tap.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncProvider);
    final (icon, label) = switch (s.phase) {
      SyncPhase.signedOut => (Icons.cloud_off_outlined, 'Sync is off'),
      SyncPhase.running => (Icons.cloud_sync_outlined, 'Syncing…'),
      SyncPhase.failed => (Icons.sync_problem_outlined, 'Sync failed: ${s.error}'),
      SyncPhase.idle => (Icons.cloud_done_outlined, 'Synced'),
    };
    return IconButton(
      tooltip: label,
      onPressed: s.phase == SyncPhase.signedOut ? null : () => ref.read(syncProvider.notifier).run(),
      icon: Icon(icon, color: s.phase == SyncPhase.failed ? StatusColors.critical : null),
    );
  }
}
