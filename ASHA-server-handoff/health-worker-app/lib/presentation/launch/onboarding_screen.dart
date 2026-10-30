import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/settings.dart';
import 'asha_logo.dart';

/// First-run flow: language first (so everything after it is in the worker's language), then four short pages. Every page can be
/// skipped except the language choice, and nothing here needs internet.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when the worker finishes or skips. The caller marks onboarding done and asks for the notification permission.
  final Future<void> Function() onDone;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = 5; // language + 4 info pages
  final _ctl = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _go(int p) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctl.jumpToPage(p);
    } else {
      await _ctl.animateToPage(
        p,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final last = _page == _pages - 1;
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) _go(_page - 1);
      },
      child: Scaffold(
        backgroundColor: Tk.page,
        body: SafeArea(
          child: Column(
            children: [
              // top bar: logo + skip (not on the language page: that choice is needed to continue)
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2, // chrome: stays one line at large accessibility text sizes
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s8, Tk.s8, 0),
                  child: Row(
                    children: [
                      const AshaLogo(size: 30),
                      const SizedBox(width: 8),
                      const Text(
                        'ASHA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Tk.primaryDark,
                        ),
                      ),
                      const Spacer(),
                      if (_page > 0 && !last)
                        TextButton(
                          key: const Key('ob-skip'),
                          onPressed: _finish,
                          child: Text(l.obSkip),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _ctl,
                  onPageChanged: (p) => setState(() => _page = p),
                  children: [
                    const _LanguagePage(),
                    _InfoPage(
                      icon: Icons.event_note_rounded,
                      title: l.ob1Title,
                      body: l.ob1Body,
                    ),
                    _InfoPage(
                      icon: Icons.cloud_off_rounded,
                      title: l.ob2Title,
                      body: l.ob2Body,
                    ),
                    _InfoPage(
                      icon: Icons.health_and_safety_rounded,
                      title: l.ob3Title,
                      body: l.ob3Body,
                      tone: Tk.warn,
                      toneBg: Tk.warnBg,
                    ),
                    _PermissionsPage(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tk.s24,
                  Tk.s8,
                  Tk.s24,
                  Tk.s24,
                ),
                child: Column(
                  children: [
                    Semantics(
                      label: l.obStep(_page + 1, _pages),
                      excludeSemantics: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _pages; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 26 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? Tk.primary : Tk.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Tk.s16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('ob-next'),
                        onPressed: _finishing
                            ? null
                            : (last ? _finish : () => _go(_page + 1)),
                        child: Text(
                          last
                              ? l.obGetStarted
                              : (_page == 0 ? l.obContinue : l.obNext),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final st = context.watch<AppSettings>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Tk.s24, Tk.s24, Tk.s24, Tk.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: _HeroIcon(
              child: Icon(
                Icons.translate_rounded,
                size: 44,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: Tk.s24),
          Semantics(
            header: true,
            child: Text(
              l.obChooseLanguage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          // shown in BOTH languages so a worker who cannot read the current one still knows what to do
          Text(
            'Choose your language  ·  మీ భాషను ఎంచుకోండి',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Tk.s24),
          _LangCard(
            key: const Key('ob-lang-te'),
            label: 'తెలుగు',
            sub: 'Telugu',
            selected: st.language == 'te',
            onTap: () => st.setLanguage('te'),
          ),
          const SizedBox(height: Tk.s12),
          _LangCard(
            key: const Key('ob-lang-en'),
            label: 'English',
            sub: 'ఇంగ్లీష్',
            selected: st.language == 'en',
            onTap: () => st.setLanguage('en'),
          ),
          const SizedBox(height: Tk.s16),
          Text(
            l.obChooseLanguageHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    super.key,
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label, $sub',
    excludeSemantics: true,
    child: Material(
      color: selected ? Tk.primary : Colors.white,
      borderRadius: BorderRadius.circular(Tk.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tk.rCard),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(
            horizontal: Tk.s20,
            vertical: Tk.s16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tk.rCard),
            border: Border.all(
              color: selected ? Tk.primary : Tk.border,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : Tk.text,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 14,
                        color: selected ? Colors.white : Tk.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 30,
                color: selected ? Colors.white : Tk.textMuted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    width: 104,
    height: 104,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: color == null ? Tk.heroGradient : null,
      color: color,
      boxShadow: Tk.cardShadow,
    ),
    child: child,
  );
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({
    required this.icon,
    required this.title,
    required this.body,
    this.tone,
    this.toneBg,
  });
  final IconData icon;
  final String title, body;
  final Color? tone, toneBg;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(Tk.s24, Tk.s32, Tk.s24, Tk.s16),
    child: Column(
      children: [
        _HeroIcon(
          color: tone,
          child: Icon(icon, size: 48, color: Colors.white),
        ),
        const SizedBox(height: Tk.s32),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: Tk.s16),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    ),
  );
}

class _PermissionsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget row(IconData i, String t) => Padding(
      padding: const EdgeInsets.only(bottom: Tk.s12),
      child: Container(
        padding: const EdgeInsets.all(Tk.s16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Tk.rCard),
          border: Border.all(color: Tk.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Tk.mintSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(i, color: Tk.primaryDark),
            ),
            const SizedBox(width: Tk.s12),
            Expanded(
              child: Text(t, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Tk.s24, Tk.s32, Tk.s24, Tk.s16),
      child: Column(
        children: [
          const _HeroIcon(
            child: Icon(
              Icons.verified_user_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: Tk.s24),
          Semantics(
            header: true,
            child: Text(
              l.ob4Title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: Tk.s24),
          row(Icons.mic_rounded, l.ob4Mic),
          row(Icons.notifications_active_rounded, l.ob4Notif),
          row(Icons.sync_rounded, l.ob4Server),
        ],
      ),
    );
  }
}
