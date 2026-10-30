import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// Writes one frame-timing summary per scrolled page to build/PAGE.timeline_summary.json
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final e in data.entries) {
      final timeline = driver.Timeline.fromJson(e.value as Map<String, dynamic>);
      await driver.TimelineSummary.summarize(timeline).writeTimelineToFile(
        e.key,
        pretty: true,
        includeSummary: true,
      );
    }
  },
);
