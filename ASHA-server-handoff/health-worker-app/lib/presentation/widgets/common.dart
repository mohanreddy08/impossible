import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

enum Tone { danger, warn, ok, info, neutral }

({Color fg, Color bg}) toneColors(Tone t) => switch (t) {
  Tone.danger => (fg: Tk.danger, bg: Tk.dangerBg),
  Tone.warn => (fg: Tk.warn, bg: Tk.warnBg),
  Tone.ok => (fg: Tk.ok, bg: Tk.okBg),
  Tone.info => (fg: Tk.info, bg: Tk.infoBg),
  Tone.neutral => (fg: Tk.neutral, bg: Tk.neutralBg),
};

/// Status pill. The meaning is carried by the ICON and the WORDS; colour only reinforces it.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    this.dense = false,
  });
  final Tone tone;
  final IconData icon;
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        // a Row gives non-flex children unbounded width: cap it so long (Telugu / large-font) labels wrap instead of overflowing
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.6,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(Tk.rChip),
          border: Border.all(color: c.fg.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: dense ? 14 : 16, color: c.fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: c.fg,
                  fontWeight: FontWeight.w700,
                  fontSize: dense ? 12 : 13.5,
                ),
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Tk.s16),
    this.color,
    this.border,
    this.semanticLabel,
    this.margin,
    this.gradient,
  });
  final Gradient? gradient;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final Color? color;
  final Color? border;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Tk.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: gradient != null
            ? null
            : Border.all(color: border ?? Tk.border),
        boxShadow: Tk.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Tk.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tk.rCard),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return semanticLabel == null
        ? box
        : Semantics(
            container: true,
            label: semanticLabel,
            button: onTap != null,
            child: box,
          );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, Tk.s20, 4, Tk.s8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.1),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: AppLocalizations.of(context).loading,
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Tk.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Tk.mintSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: Tk.primaryDark),
            ),
          ),
          const SizedBox(height: Tk.s16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (body != null) ...[
            const SizedBox(height: Tk.s8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Tk.textMuted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: Tk.s16), action!],
        ],
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: message,
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).retry),
          ),
  );
}

/// Banner for inline messages (success / info / warning / error) with icon + text.
class Banner2 extends StatelessWidget {
  const Banner2({
    super.key,
    required this.tone,
    required this.icon,
    required this.text,
    this.action,
  });
  final Tone tone;
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      padding: const EdgeInsets.all(Tk.s12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Tk.rButton),
        border: Border.all(color: c.fg.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.fg, size: 22),
          const SizedBox(width: Tk.s12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.fg,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.count,
    required this.label,
    required this.icon,
    required this.tone,
    this.onTap,
  });
  final int count;
  final String label;
  final IconData icon;
  final Tone tone;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return AppCard(
      onTap: onTap,
      color: c.bg,
      border: c.fg.withValues(alpha: 0.18),
      padding: const EdgeInsets.all(Tk.s12),
      semanticLabel: '$label: $count',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: c.fg),
                ),
                const Spacer(),
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: c.fg,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tk.s8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.first,
    this.last,
    this.fieldKey,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;
  final DateTime? first, last;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = value == null ? l.chooseDate : _fmt(context, value!);
    return Semantics(
      button: true,
      label:
          '$label: ${value == null ? l.notSet : shown}${errorText == null ? '' : '. $errorText'}',
      excludeSemantics: true,
      child: InkWell(
        key: fieldKey,
        borderRadius: BorderRadius.circular(Tk.rButton),
        onTap: () async {
          final now = value ?? DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate:
                value ?? (first != null && now.isBefore(first!) ? first! : now),
            firstDate: first ?? DateTime(2020),
            lastDate: last ?? DateTime(2035),
            helpText: label,
          );
          if (d != null) onChanged(DateTime(d.year, d.month, d.day));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(shown, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }

  String _fmt(BuildContext c, DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Two-column grid whose rows are as tall as their tallest tile (no fixed aspect ratio, so large fonts and
/// longer Telugu labels can never overflow).
class TwoColumnGrid extends StatelessWidget {
  const TwoColumnGrid({
    super.key,
    required this.children,
    this.spacing = Tk.s12,
  });
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              SizedBox(width: spacing),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < children.length) rows.add(SizedBox(height: spacing));
    }
    return Column(children: rows);
  }
}

/// Label/value pair. Side by side when there is room, stacked when there is not (large fonts, long Telugu words),
/// so a fixed-width label column can never overflow.
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.labelWidth = 118});
  final String label, value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final k = Text(label, style: t.bodySmall);
    final v = Text(
      value,
      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (c, box) {
          final scale = MediaQuery.textScalerOf(c).scale(14) / 14;
          final stacked = box.maxWidth < 280 || scale > 1.4;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [k, v],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: labelWidth, child: k),
                    Expanded(child: v),
                  ],
                );
        },
      ),
    );
  }
}
