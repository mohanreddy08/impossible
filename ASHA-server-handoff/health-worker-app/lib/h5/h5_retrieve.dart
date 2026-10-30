import 'dart:math' as math;

import 'h5_rules.dart';
import 'h5_text.dart';

/// One leaf section of the protocol book (### ANC-1.2 ...), with its quotable sentences. Read from assets/h5/protocols.json.
class H5Section {
  H5Section(this.id, this.doc, this.title, this.group, this.text, this.units);
  final String id, doc, title, group, text;
  final List<String> units;
}

final RegExp _tok = RegExp(r'[a-z]+|\d+(?:\.\d+)?');
final RegExp _allDigits = RegExp(r'^\d+$');
final RegExp _range = RegExp(r'(\d+(?:\.\d+)?)\s*(?:months?|years?|weeks?|days?|g/dl|mg/dl|cm)?\s*(?:to|up to|[-–])\s*(\d+(?:\.\d+)?)');

String _stem(String w) {
  if (_allDigits.hasMatch(w) || w.contains('.')) return w;
  for (final suf in const ['ing', 'es', 'ed', 's']) {
    if (w.length > suf.length + 3 && w.endsWith(suf) && !w.endsWith('ss')) return w.substring(0, w.length - suf.length);
  }
  return w;
}

/// How many of the question's numbers fall inside an 'A-B' / 'A to B' range written in this sentence.
int rangeHits(String unitText, List<double> numbers) {
  var hits = 0;
  for (final m in _range.allMatches(unitText.replaceAll('–', '-'))) {
    final lo = double.parse(m.group(1)!), hi = double.parse(m.group(2)!);
    if (lo < hi && numbers.any((n) => lo <= n && n <= hi)) hits++;
  }
  return hits;
}

class H5Unit {
  H5Unit(this.sid, this.text, this.tokens);
  final String sid, text;
  final List<String> tokens;
}

int _cmpDesc((double, String) a, (double, String) b) {
  final c = b.$1.compareTo(a.$1);
  return c != 0 ? c : b.$2.compareTo(a.$2);
}

/// BM25 over the 107 sections and their sentences, with the Hinglish -> English expansion. The twin of retrieve.py; no model, no download.
class H5Index {
  H5Index(this.rules, List<H5Section> list, Map<String, String> localTerms) {
    for (final s in list) {
      sections[s.id] = s;
    }
    ids = sections.keys.toList();
    for (final e in localTerms.entries) {
      for (final part in e.key.split(RegExp(r'[/,]'))) {
        final term = normalizeText(part).trim();
        if (term.isNotEmpty) local[term] = tokenize(normalizeText(e.value));
      }
    }
    for (final sid in ids) {
      final s = sections[sid]!;
      final t = <String>[];
      final title = tokenize(normalizeText(s.title));
      for (var i = 0; i < 3; i++) {
        t.addAll(title);
      }
      t
        ..addAll(tokenize(normalizeText(s.group)))
        ..addAll(tokenize(normalizeText(s.text)))
        ..addAll(tokenize(normalizeText(sid.replaceAll('-', ' ').replaceAll('.', ' '))));
      docs.add(t);
    }
    for (final sid in ids) {
      final s = sections[sid]!;
      final head = tokenize(normalizeText(s.title));
      for (final u in s.units) {
        unitDocs.add(H5Unit(sid, u, [...head, ...tokenize(normalizeText(u))]));
      }
    }
    tf = [for (final d in docs) _count(d)];
    avg = docs.fold<int>(0, (a, d) => a + d.length) / docs.length;
    idf = _idf([for (final d in docs) d]);
    utf = [for (final u in unitDocs) _count(u.tokens)];
    uavg = unitDocs.fold<int>(0, (a, u) => a + u.tokens.length) / math.max(1, unitDocs.length);
    uidf = _idf([for (final u in unitDocs) u.tokens]);
  }

  final H5Rules rules;
  final Map<String, H5Section> sections = {};
  late final List<String> ids;
  final double k1 = 1.4, b = 0.55;
  final List<List<String>> docs = [];
  final List<H5Unit> unitDocs = [];
  final Map<String, List<String>> local = {};
  late final List<Map<String, int>> tf, utf;
  late final double avg, uavg;
  late final Map<String, double> idf, uidf;

  static Map<String, int> _count(List<String> d) {
    final m = <String, int>{};
    for (final t in d) {
      m[t] = (m[t] ?? 0) + 1;
    }
    return m;
  }

  static Map<String, double> _idf(List<List<String>> docs) {
    final df = <String, int>{};
    for (final d in docs) {
      for (final t in d.toSet()) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final n = docs.length;
    return {for (final e in df.entries) e.key: math.log(1 + (n - e.value + 0.5) / (e.value + 0.5))};
  }

  List<String> tokenize(String normalised) => [
        for (final m in _tok.allMatches(normalised))
          if (!rules.stop.contains(m.group(0)!)) _stem(m.group(0)!),
      ];

  /// (token, weight): the question's own tokens (weight 1) plus the English words they stand for. An expansion is shared among its
  /// words (one that expands into 4 terms gives each 0.25), so a common word cannot outvote a rare, specific one.
  List<(String, double)> expandQuery(String norm) {
    final words = norm.split(' ').where((w) => w.isNotEmpty).toList();
    final out = <(String, double)>[];
    for (var i = 0; i < words.length; i++) {
      final groups = <List<String>>[];
      for (final n in const [3, 2]) {
        if (i + n > words.length) continue;
        final ph = words.sublist(i, i + n).join(' ');
        if (rules.expand.containsKey(ph)) groups.add(rules.expand[ph]!);
      }
      if (rules.expand.containsKey(words[i])) groups.add(rules.expand[words[i]]!);
      for (final g in groups) {
        final toks = <String>[];
        for (final t in g) {
          toks.addAll(tokenize(normalizeText(t)));
        }
        if (toks.isNotEmpty) {
          final wt = 1.0 / toks.length;
          for (final t in toks) {
            out.add((t, wt));
          }
        }
      }
    }
    final base = [for (final t in tokenize(norm)) (t, 1.0)];
    final have = {for (final (t, _) in base) t};
    return [...base, ...out.where((e) => !have.contains(e.$1))];
  }

  List<(String, double)> queryTokens(String norm) {
    final toks = [
      for (final (t, w) in expandQuery(norm))
        (t, (w == 1.0 && (idf[t] ?? 0.0) >= 2.4 && !_allDigits.hasMatch(t)) ? w * 2.0 : w),
    ];
    for (final e in local.entries) {
      if (norm.contains(e.key) && e.value.isNotEmpty) {
        final w = 1.0 / math.pow(e.value.length, 0.5);
        for (final t in e.value) {
          toks.add((t, w));
        }
      }
    }
    return toks;
  }

  Map<String, double> _queryWeights(String norm) {
    final q = <String, double>{};
    for (final (t, w) in queryTokens(norm)) {
      q[t] = (q[t] ?? 0.0) + w;
    }
    return q;
  }

  List<(double, String)> search(String norm, int k) {
    final q = _queryWeights(norm);
    final scores = <(double, String)>[];
    for (var i = 0; i < ids.length; i++) {
      final dl = docs[i].length;
      var s = 0.0;
      for (final e in q.entries) {
        final f = tf[i][e.key];
        if (f == null || f == 0) continue;
        s += idf[e.key]! * f * (k1 + 1) / (f + k1 * (1 - b + b * dl / avg)) * (1 + 0.5 * math.log(1 + e.value));
      }
      scores.add((s, ids[i]));
    }
    scores.sort(_cmpDesc);
    return scores.take(k).toList();
  }

  /// (score, unit index) for every sentence.
  List<(double, int)> unitScores(String norm, List<double> numbers) {
    final q = _queryWeights(norm);
    final out = <(double, int)>[];
    for (var i = 0; i < unitDocs.length; i++) {
      final dl = unitDocs[i].tokens.length;
      var s = 0.0;
      for (final e in q.entries) {
        final f = utf[i][e.key];
        if (f != null && f != 0) {
          s += uidf[e.key]! * f * (k1 + 1) / (f + k1 * (1 - b + b * dl / uavg)) * (1 + 0.5 * math.log(1 + e.value));
        }
      }
      if (s > 0 && numbers.isNotEmpty) s *= 1.0 + 0.35 * rangeHits(unitDocs[i].text, numbers);
      out.add((s, i));
    }
    return out;
  }

  /// Section ranking by its best sentence (decisive facts), plus a share of the whole-section score (topic).
  List<(double, String)> searchUnits(String norm, int k, {double sectionWeight = 0.35, List<double> numbers = const []}) {
    final best = <String, double>{};
    for (final (s, i) in unitScores(norm, numbers)) {
      final sid = unitDocs[i].sid;
      if (s > (best[sid] ?? 0.0)) best[sid] = s;
    }
    final sec = {for (final (sc, sid) in search(norm, ids.length)) sid: sc};
    var topSec = sec.values.reduce(math.max);
    if (topSec == 0) topSec = 1.0;
    var topUnit = best.isEmpty ? 1.0 : best.values.reduce(math.max);
    if (topUnit == 0) topUnit = 1.0;
    final combined = [for (final sid in ids) ((best[sid] ?? 0.0) / topUnit + sectionWeight * (sec[sid] ?? 0.0) / topSec, sid)];
    combined.sort(_cmpDesc);
    return combined.take(k).toList();
  }

  String unitText(int i) => unitDocs[i].text;
  String unitSection(int i) => unitDocs[i].sid;
}
