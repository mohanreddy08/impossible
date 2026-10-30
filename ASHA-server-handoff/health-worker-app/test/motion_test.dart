import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/core/theme/app_theme.dart';
import 'package:health_companion/presentation/widgets/reveal.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: buildTheme(),
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: c!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('Reveal starts invisible, eases in, and ends fully visible', (
    t,
  ) async {
    await t.pumpWidget(host(const Reveal(index: 2, child: Text('hello'))));
    double opacity() => t
        .widget<FadeTransition>(find.byType(FadeTransition).last)
        .opacity
        .value;
    expect(opacity(), 0);
    await t.pump(const Duration(milliseconds: 250));
    expect(opacity(), inExclusiveRange(0, 1));
    await t.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets(
    'with "reduce motion" on, Reveal shows the content at once with no animation',
    (t) async {
      await t.pumpWidget(
        host(const Reveal(child: Text('hello')), reduceMotion: true),
      );
      expect(find.byType(FadeTransition), findsNothing);
      expect(find.text('hello'), findsOneWidget);
    },
  );

  testWidgets('opening a page fades and rises in, and going back reverses it', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme().copyWith(platform: TargetPlatform.android),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('second page')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final fade = t.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('second page'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(
      fade.opacity.value,
      inExclusiveRange(0, 1),
      reason: 'mid-transition: partly visible',
    );
    await t.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);
    Navigator.of(t.element(find.text('second page'))).pop();
    await t.pumpAndSettle();
    expect(find.text('second page'), findsNothing);
  });
}
