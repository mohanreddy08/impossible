// On-device scroll performance of every page. Run in PROFILE mode (debug builds are much slower than real use):
//   flutter drive --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart --profile -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/main.dart' as app;
import 'package:health_companion/state/app_services.dart';
import 'package:provider/provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester t, [int ms = 1200]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder verticalScrollable() => find.byWidgetPredicate(
  (w) =>
      w is Scrollable &&
      (w.axisDirection == AxisDirection.down ||
          w.axisDirection == AxisDirection.up),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll every page', (t) async {
    // Onboarding is covered by its own tests and by hand; here it is marked done so the run does not wait on the system
    // notification-permission dialog that "Get started" raises (nobody taps Allow in an automated run).
    await (await SharedPreferences.getInstance()).setBool(
      'onboarding_done',
      true,
    );
    await app.main();
    await settle(t, 3000); // the ASHA splash
    // a fresh install shows the first-run onboarding: click through it (language page, then the info pages)
    for (
      var i = 0;
      i < 9 && find.byKey(const Key('ob-next')).evaluate().isNotEmpty;
      i++
    ) {
      await t.tap(find.byKey(const Key('ob-next')));
      await settle(t, 900);
    }
    await settle(t, 1500);
    // ignore: avoid_print
    print(
      'PERF-STATE onboarding=${find.byKey(const Key('ob-next')).evaluate().isNotEmpty} nav=${find.byKey(const ValueKey('nav-0')).evaluate().isNotEmpty} texts=${t.widgetList<Text>(find.byType(Text)).map((e) => e.data).take(8).toList()}',
    );
    // Optional: sync real data from a backend first (e.g. all 500 households across 3 villages with an admin key):
    //   --dart-define=PERF_SERVER=http://10.0.2.2:8791 --dart-define=PERF_KEY=<key>
    const server = String.fromEnvironment('PERF_SERVER');
    const key = String.fromEnvironment('PERF_KEY');
    if (server.isNotEmpty && key.isNotEmpty) {
      final services = Provider.of<AppServices>(
        t.element(find.byType(Scaffold).first),
        listen: false,
      );
      await services.settings.setBaseUrl(server);
      await services.settings.setApiKey(key);
      await t.runAsync(() => services.sync.syncNow());
      services.bus.changed();
      await settle(t, 3000);
    } else if (find.byKey(const Key('load-demo')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('load-demo')));
      await settle(t, 4000);
    }

    Future<void> scrollPage(String name) async {
      await settle(t);
      final f = verticalScrollable();
      if (f.evaluate().isEmpty) return;
      await binding.traceAction(() async {
        for (var i = 0; i < 4; i++) {
          await t.fling(f.first, const Offset(0, -500), 1800);
          await settle(t, 600);
          await t.fling(f.first, const Offset(0, 500), 1800);
          await settle(t, 600);
        }
      }, reportKey: name);
    }

    Future<void> tab(int i, String name) async {
      await t.tap(find.byKey(ValueKey('nav-$i')));
      await settle(t);
      await scrollPage(name);
    }

    Future<void> safe(String name, Future<void> Function() step) async {
      try {
        await step();
      } on Object catch (e) {
        // ignore: avoid_print
        print('PERF-STEP-FAILED $name: $e');
      }
    }

    await safe('home', () => scrollPage('home'));
    await safe('visits', () => tab(1, 'visits'));
    await safe('ask', () => tab(2, 'ask'));
    await safe('households', () => tab(3, 'households'));
    await safe('more', () => tab(4, 'more'));

    // pages opened from More and from Home
    Future<void> openFromMore(String text, String name) async {
      await t.tap(find.byKey(const ValueKey('nav-4')));
      await settle(t);
      final item = find.text(text);
      if (item.evaluate().isEmpty) return;
      await t.tap(item.first);
      await settle(t, 1500);
      await scrollPage(name);
      final back = find.text('Back'); // the app's own back button
      if (back.evaluate().isNotEmpty) await t.tap(back.first);
      await settle(t);
    }

    await safe('referrals', () => openFromMore('Referrals', 'referrals'));
    await safe('reports', () => openFromMore('Reports', 'reports'));
    await safe('sync', () => openFromMore('Sync centre', 'sync'));
    await safe('settings', () => openFromMore('Settings', 'settings'));

    // the household list again, after a filter, and a household's detail page
    await safe('households_filtered', () async {
      await t.tap(find.byKey(const ValueKey('nav-3')));
      await settle(t);
      // the filter row: Status, Category, Village. Pick the first village, then scroll the filtered list
      final menus = find.byType(PopupMenuButton<String>);
      if (menus.evaluate().length >= 3) {
        await t.tap(menus.last);
        await settle(t, 600);
        await t.tap(find.byType(PopupMenuItem<String>).at(1));
        await settle(t, 1500);
        await scrollPage('households_village_filter');
        // and a status filter on top
        await t.tap(menus.first);
        await settle(t, 600);
        await t.tap(find.byType(PopupMenuItem<String>).at(1));
        await settle(t, 1500);
        await scrollPage('households_two_filters');
      }
    });
  });
}
