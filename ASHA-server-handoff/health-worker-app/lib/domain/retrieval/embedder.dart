import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../safety/safety_engine.dart' show normalizeText;

/// The text-to-vector method used for search. It MUST stay identical to `embed()` in asha-data/build_data.py (a test compares
/// them on shared examples). Character 3-5-gram hashing: no model file, works offline, and tolerates spelling variation and
/// Telugu typed in English letters. A neural embedding model can replace it later: change [embedderId] and rebuild.
class HashingEmbedder {
  const HashingEmbedder();
  static const embedderId = 'hashing-ngram-v1';
  static const dim = 512;
  static final _token = RegExp('[0-9A-Za-zÀ-ɏఀ-౿]+');

  static int _fnv1a(String key) {
    var h = 0x811C9DC5;
    for (final b in utf8.encode(key)) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Unit-length vector (all zeros for empty text).
  Float64List embed(String text) {
    final feats = <String, int>{};
    for (final m in _token.allMatches(normalizeText(text))) {
      final tok = m.group(0)!;
      if (tok.length < 3) continue;
      feats['w:$tok'] = (feats['w:$tok'] ?? 0) + 1;
      final padded = '^$tok\$';
      for (final n in const [3, 4, 5]) {
        for (var i = 0; i + n <= padded.length; i++) {
          final k = 'g:${padded.substring(i, i + n)}';
          feats[k] = (feats[k] ?? 0) + 1;
        }
      }
    }
    final v = Float64List(dim);
    feats.forEach((key, count) {
      final h = _fnv1a(key);
      final base = key.startsWith('w:') ? 2.0 : 1.0;
      final w = base * (1.0 + math.log(count));
      v[h % dim] += ((h >> 31) & 1) == 1 ? -w : w;
    });
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    if (s > 0) {
      final norm = math.sqrt(s);
      for (var i = 0; i < dim; i++) {
        v[i] = v[i] / norm;
      }
    }
    return v;
  }

  /// 8-bit form that is stored on the phone (one byte per dimension).
  Int8List quantize(Float64List v) {
    final q = Int8List(dim);
    for (var i = 0; i < dim; i++) {
      q[i] = (v[i] * 127.0 + 0.5).floor().clamp(-127, 127);
    }
    return q;
  }

  /// Cosine of a unit query vector and a stored 8-bit passage vector.
  double cosine(Float64List query, Int8List stored) {
    var dot = 0.0, n = 0.0;
    for (var i = 0; i < dim; i++) {
      final s = stored[i] / 127.0;
      dot += query[i] * s;
      n += s * s;
    }
    return n == 0 ? 0 : dot / math.sqrt(n);
  }
}

/// Adds the other-language forms of the words in a question (see asha-data/lexicon/aliases.json), so a Telugu question, an English
/// one and Telugu typed in English letters all reach the same passages.
class AliasExpander {
  AliasExpander(this._groups, [List<bool>? generic])
    : _generic = generic ?? List.filled(_groups.length, false);

  factory AliasExpander.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final gs = (j['groups'] as List).cast<Map<String, dynamic>>();
    return AliasExpander(
      [
        for (final g in gs)
          [for (final t in g['terms'] as List) normalizeText(t as String)],
      ],
      [for (final g in gs) g['generic'] == true],
    );
  }

  final List<List<String>> _groups;
  final List<bool> _generic;
  static final _telugu = RegExp('[ఀ-౿]');
  static final _words = RegExp('[0-9A-Za-zÀ-ɏఀ-౿]+');

  bool _hit(String term, List<String> tokens, String joined) {
    if (term.contains(' ')) return joined.contains(' $term ');
    if (_telugu.hasMatch(term)) {
      // Telugu words carry suffixes (గర్భిణీకి = గర్భిణీ + కి), so a Telugu term matches the start of a word
      return tokens.any((t) => t.startsWith(term));
    }
    return tokens.contains(term);
  }

  /// Which topic groups the text mentions (by position in the alias list).
  Set<int> groupsIn(String text) {
    final tokens = [
      for (final m in _words.allMatches(normalizeText(text))) m.group(0)!,
    ];
    final joined = ' ${tokens.join(' ')} ';
    return {
      for (var i = 0; i < _groups.length; i++)
        if (_groups[i].any((t) => _hit(t, tokens, joined))) i,
    };
  }

  /// True when the two sets share a group that says WHAT is wrong (not merely who it is about).
  bool sharesTopic(Set<int> a, Set<int> b) =>
      a.any((i) => !_generic[i] && b.contains(i));

  /// The question followed by every term of every group that one of its words belongs to.
  String expand(String question) {
    final tokens = [
      for (final m in _words.allMatches(normalizeText(question))) m.group(0)!,
    ];
    final joined = ' ${tokens.join(' ')} ';
    final extra = <String>[];
    for (final g in _groups) {
      if (g.any((t) => _hit(t, tokens, joined))) extra.addAll(g);
    }
    return extra.isEmpty ? question : '$question ${extra.join(' ')}';
  }
}
