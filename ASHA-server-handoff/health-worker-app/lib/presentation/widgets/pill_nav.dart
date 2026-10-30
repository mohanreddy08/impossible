import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// Capsule bottom navigation from the reference image (mint pill, active item in a white circle). Labels are always shown.
class PillNav extends StatelessWidget {
  const PillNav({super.key, required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // a landscape phone is short: icon and label side by side, so the bar takes a single row of height
    final short = MediaQuery.sizeOf(context).height < 500;
    final items = [
      (Icons.home_outlined, Icons.home_rounded, l.navHome),
      (Icons.event_note_outlined, Icons.event_note, l.navVisits),
      (Icons.forum_outlined, Icons.forum, l.navAsk),
      (Icons.house_outlined, Icons.house, l.navHouseholds),
      (Icons.grid_view_outlined, Icons.grid_view_rounded, l.navMore),
    ];
    return MediaQuery.withClampedTextScaling(
      // the capsule is chrome: keep it compact at large font sizes
      maxScaleFactor: 1.15,
      child: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          label: l.semBottomNav,
          child: Container(
            margin: const EdgeInsets.fromLTRB(Tk.s12, 0, Tk.s12, Tk.s8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Tk.rChip),
              border: Border.all(color: Tk.border),
              boxShadow: Tk.cardShadow,
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].$3,
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('nav-$i'),
                        customBorder: const StadiumBorder(),
                        onTap: () => onChanged(i),
                        child: Container(
                          constraints: BoxConstraints(
                            minHeight: short ? 44 : 56,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          decoration: i == index
                              ? BoxDecoration(
                                  color: Tk.primary,
                                  borderRadius: BorderRadius.circular(Tk.rChip),
                                )
                              : null,
                          child: Flex(
                            direction: short ? Axis.horizontal : Axis.vertical,
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                i == index ? items[i].$2 : items[i].$1,
                                size: 24,
                                color: i == index ? Colors.white : Tk.textMuted,
                              ),
                              SizedBox(
                                height: short ? 0 : 2,
                                width: short ? 6 : 0,
                              ),
                              Flexible(
                                child: Text(
                                  items[i].$3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: i == index
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: i == index
                                        ? Colors.white
                                        : Tk.textMuted,
                                  ),
                                ),
                              ),
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
      ),
    );
  }
}
