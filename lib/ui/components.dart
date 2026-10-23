import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Two uppercase letters for avatar discs.
String initialsOf(String text) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.take(2).toString().toUpperCase();
  return (words.first.characters.first + words[1].characters.first).toUpperCase();
}

/// Groups rows that share a date string, keeping their order, so a list can
/// show the mock's date caption over each card of rows.
List<(String, List<T>)> groupByDate<T>(List<T> rows, String Function(T) dateOf) {
  final out = <(String, List<T>)>[];
  for (final r in rows) {
    final d = dateOf(r);
    if (out.isNotEmpty && out.last.$1 == d) {
      out.last.$2.add(r);
    } else {
      out.add((d, [r]));
    }
  }
  return out;
}

/// Bold section title with an optional trailing widget and muted action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.actionLabel, this.onAction});
  final String title;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: skin.muted,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

/// The mock's two-line greeting: ink line over muted line, both heavy.
class HeroHeader extends StatelessWidget {
  const HeroHeader(this.line, this.mutedLine, {super.key});
  final String line;
  final String mutedLine;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final style = Theme.of(context).textTheme.displaySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line, style: style),
          Text(mutedLine, style: style?.copyWith(color: skin.muted)),
        ],
      ),
    );
  }
}

/// A circular header action: solid ink, or paper with an ink glyph.
class CircleActionButton extends StatelessWidget {
  const CircleActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.solid = true,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final bool solid;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style:
          IconButton.styleFrom(
            backgroundColor: solid ? scheme.onSurface : scheme.surface,
            foregroundColor: solid ? skin.canvas : scheme.onSurface,
            shape: const CircleBorder(),
            fixedSize: const Size(40, 40),
          ).merge(
            buttonDepth(
              const CircleBorder(),
              solid ? scheme.primary.withValues(alpha: 0.4) : const Color(0x26000000),
            ),
          ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// Small white tile: muted label with a trailing arrow, heavy value.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.hint});
  final String label;
  final String value;
  final IconData? icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final tile = Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) Icon(icon, size: 16, color: skin.muted),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700).merge(tabular)),
            ),
          ],
        ),
      ),
    );
    return hint == null ? tile : Hint(hint!, child: tile);
  }
}

/// Rounded icon square: soft tint with a primary glyph, or solid primary.
class IconSquare extends StatelessWidget {
  const IconSquare(this.icon, {super.key, this.solid = false, this.size = 48});
  final IconData icon;
  final bool solid;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? scheme.primary : skin.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: size * 0.46, color: solid ? scheme.onPrimary : skin.onSoft),
    );
  }
}

/// Initials disc for people and payees.
class DiscAvatar extends StatelessWidget {
  const DiscAvatar(this.text, {super.key, this.size = 40, this.color, this.foreground});
  final String text;
  final double size;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color ?? skin.surfaceSoft,
      child: Text(
        text,
        style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w600, color: foreground ?? skin.muted),
      ),
    );
  }
}

/// A transaction row in the mock's style: disc, title and caption, trailing
/// amount with a status caption under it.
class TxRow extends StatelessWidget {
  const TxRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.caption,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading ?? DiscAvatar(initialsOf(title)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ?trailing,
                if (caption != null)
                  Text(
                    caption!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: skin.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded progress track with an optional set of dot markers.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.height = 8, this.dots = const [], this.width});
  final double value;
  final double height;
  final List<double> dots;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(color: skin.soft, borderRadius: BorderRadius.circular(height / 2)),
          ),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
          for (final d in dots)
            Positioned(
              left: null,
              right: null,
              child: Align(
                alignment: Alignment(d.clamp(0.0, 1.0) * 2 - 1, 0),
                child: Container(
                  width: height + 2,
                  height: height + 2,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Deep-fill celebration banner with white text and a trailing widget.
class BannerPill extends StatelessWidget {
  const BannerPill({super.key, required this.child, this.trailing});
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    return Container(
      decoration: BoxDecoration(color: skin.primaryDeep, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF)),
              child: child,
            ),
          ),
          if (trailing != null) const SizedBox(width: 8),
          ?trailing,
        ],
      ),
    );
  }
}

/// Stats card from the mock's Target screen: icon disc, label, heavy value.
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.solid = false,
    this.hint,
  });
  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final bool solid;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final scheme = Theme.of(context).colorScheme;
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: solid ? scheme.primary : skin.soft, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: solid ? scheme.onPrimary : skin.onSoft),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.muted),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700).merge(tabular)),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: skin.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
    return hint == null ? card : Hint(hint!, child: card);
  }
}
