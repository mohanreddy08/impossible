import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The shared rule words (assets/h5/rules.json, exported from the Python lexicon): the regex sources are already folded, so Dart compiles
/// them as they are.
class H5Rules {
  H5Rules._(this.concepts, this.expand, this.stop);
  final Map<String, List<RegExp>> concepts;
  final Map<String, List<String>> expand;
  final Set<String> stop;

  factory H5Rules.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return H5Rules._(
      {
        for (final e in (j['concepts'] as Map<String, dynamic>).entries)
          e.key: [for (final p in (e.value as List)) RegExp(p as String)],
      },
      {
        for (final e in (j['expand'] as Map<String, dynamic>).entries) e.key: [for (final w in (e.value as List)) w as String],
      },
      {for (final w in (j['stop'] as List)) w as String},
    );
  }

  static Future<H5Rules> load() async => H5Rules.fromJson(await rootBundle.loadString('assets/h5/rules.json'));
}
