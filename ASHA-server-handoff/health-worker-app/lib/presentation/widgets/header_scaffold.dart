import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'status_chip.dart';

/// Widest the page content (and the header text) gets; wider screens (tablets, landscape) get empty margins at the sides.
const double maxContentWidth = 840;

/// Screen frame from the reference design: teal-to-mint gradient header, rounded white sheet for content.
class HeaderScaffold extends StatelessWidget {
  const HeaderScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.showBack = false,
    this.actions = const [],
    this.headerExtra,
    this.showStatus = true,
    this.floating,
    this.leading,
    this.eyebrow,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;
  final List<Widget> actions;
  final Widget? headerExtra;
  final bool showStatus;
  final Widget? floating;

  /// Shown at the left of the top row (e.g. the ASHA mark on Home).
  final Widget? leading;

  /// A small line above the title (e.g. greeting + date).
  final Widget? eyebrow;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Tablets and landscape: the content is a centred column at most [maxContentWidth] wide (a full-width paragraph on a 10-inch screen is
    // hard to read), and the header shrinks when the screen is short so it does not take a third of a landscape phone.
    final short = MediaQuery.sizeOf(context).height < 500;
    return Scaffold(
      backgroundColor: Tk.tealDeep,
      floatingActionButton: floating,
      body: Column(
        children: [
          MediaQuery.withClampedTextScaling(
            // header chrome must not eat the screen at large accessibility font sizes; page content below still scales fully
            maxScaleFactor: 1.2,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: Tk.headerGradient),
              child: Stack(
                children: [
                  const Positioned(
                    right: -50,
                    top: -40,
                    child: _Orb(size: 190, alpha: 0.07),
                  ),
                  const Positioned(
                    right: 60,
                    bottom: -70,
                    child: _Orb(size: 130, alpha: 0.05),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: maxContentWidth,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            Tk.s16,
                            Tk.s8,
                            Tk.s16,
                            short
                                ? Tk.s8
                                : MediaQuery.sizeOf(context).height < 640
                                ? Tk.s12
                                : Tk.s24,
                          ),
                          child: short
                              ? Row(
                                  children: [
                                    if (showBack) ...[
                                      _RoundButton(
                                        icon: Icons.arrow_back,
                                        label: l.back,
                                        onTap: () =>
                                            Navigator.of(context).maybePop(),
                                      ),
                                      const SizedBox(width: Tk.s8),
                                    ],
                                    Expanded(
                                      child: Semantics(
                                        header: true,
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (showStatus) const StatusChip(),
                                    ...actions,
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (showBack) ...[
                                          _RoundButton(
                                            icon: Icons.arrow_back,
                                            label: l.back,
                                            onTap: () =>
                                                Navigator.of(context)
                                                    .maybePop(),
                                          ),
                                          const SizedBox(width: Tk.s8),
                                        ],
                                        ?leading,
                                        const Spacer(),
                                        if (showStatus)
                                          const Flexible(
                                            flex: 4,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: StatusChip(),
                                            ),
                                          ),
                                        ...actions,
                                      ],
                                    ),
                                    SizedBox(height: short ? Tk.s4 : Tk.s12),
                                    ?eyebrow,
                                    if (eyebrow != null)
                                      const SizedBox(height: 6),
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontSize: short ? 22 : 27,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3,
                                            ),
                                      ),
                                    ),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ],
                                    ?headerExtra,
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Material(
              // a Material (not a coloured DecoratedBox) so ListTile/InkWell ripples inside the sheet stay visible
              color: Tk.page,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: maxContentWidth,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(Tk.rChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});
  final double size, alpha;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    ),
  );
}
