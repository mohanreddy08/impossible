import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'asha_logo.dart';

/// Shown for a moment every time the app opens: the ASHA logo and name on the brand colour. It starts on the same colour as
/// the Android launch screen, so there is no flash between the two.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final Animation<double> _logo = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, .55, curve: Curves.easeOutBack),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, .35, curve: Curves.easeOut),
  );
  late final Animation<double> _name = CurvedAnimation(
    parent: _c,
    curve: const Interval(.4, .8, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _tag = CurvedAnimation(
    parent: _c,
    curve: const Interval(.6, 1, curve: Curves.easeOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_c.isAnimating && _c.value == 0) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value =
            1; // "remove animations" is on: show the finished splash at once
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Tk.primary,
      body: Semantics(
        label: 'ASHA. ${l.splashTagline}',
        child: ExcludeSemantics(
          child: Stack(
            children: [
              const Positioned(
                right: -70,
                top: -50,
                child: _Orb(size: 240, alpha: .07),
              ),
              const Positioned(
                left: -60,
                bottom: -80,
                child: _Orb(size: 220, alpha: .06),
              ),
              Center(
                child: FittedBox(
                  // very large accessibility text on a tiny screen: shrink the whole group instead of overflowing
                  fit: BoxFit.scaleDown,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: _logoFade.value,
                          child: Transform.scale(
                            scale: .7 + .3 * _logo.value,
                            child: Container(
                              width: 132,
                              height: 132,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: .14),
                              ),
                              child: const AshaLogo(size: 84),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Opacity(
                          opacity: _name.value,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - _name.value)),
                            child: const Text(
                              'ASHA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 46,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Opacity(
                          opacity: _tag.value,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              l.splashTagline,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});
  final double size, alpha;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}
