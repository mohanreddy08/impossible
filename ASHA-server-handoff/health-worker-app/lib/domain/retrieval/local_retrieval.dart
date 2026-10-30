import 'dart:math' as math;

import 'dart:typed_data';

import '../safety/safety_engine.dart' show normalizeText;
import 'embedder.dart';

/// On-device protocol retrieval over APPROVED passages only (no model, no network). Same scoring idea as the backend:
/// relevance = IDF-weighted share of query terms found in the passage; thresholded so weak matches return nothing.
class LocalPassage {
  const LocalPassage({
    required this.passageId,
    required this.documentId,
    this.documentTitle,
    this.documentVersion,
    this.sectionId,
    this.sectionTitle,
    this.pageNumber,
    required this.text,
    required this.verificationStatus,
    this.language,
  });
  final String passageId, documentId, text, verificationStatus;
  final String? documentTitle, documentVersion, sectionId, sectionTitle;

  /// 'en' or 'te' when known (protocol documents come in language pairs).
  final String? language;
  final int? pageNumber;
}

class LocalMatch {
  const LocalMatch(this.passage, this.score, this.matchedTerms);
  final LocalPassage passage;
  final double score;
  final List<String> matchedTerms;
}

final _token = RegExp(r'[0-9A-Za-zÀ-ɏఀ-౿]+');

const _stop = {
  'the',
  'a',
  'an',
  'is',
  'are',
  'to',
  'of',
  'and',
  'or',
  'in',
  'on',
  'for',
  'do',
  'does',
  'how',
  'what',
  'when',
  'which',
  'should',
  'i',
  'we',
  'it',
  'be',
  'can',
  'my',
  'this',
  'that',
  'with',
  'at',
  'by',
  'if',
  'after',
  'per',
  'ఏ',
  'ఏం',
  'ఎలా',
  'ఎప్పుడు',
  'ఎన్ని',
  'ఏది',
  'ఎంత',
  'చేయాలి',
  'చేయాలా',
  'ఉంది',
  'ఉన్న',
  'ఏమిటి',
  'ఏమి',
  'ఏంటి',
  'ఎందుకు',
  'ఎవరు',
  'ఎక్కడ',
  'అంటే',
  'అయితే',
  'వస్తే',
  'చేయాలో',
  'చేయాలని',
  'అని',
  'కి',
  'ki',
  'ela',
  'em',
  'ye',
  'enni',
  'cheyali',
  'eppudu',
  'enta',
  'undi',
};

/// Words too common to say what a question is about (the same list the search ignores).
bool isStopWord(String token) => _stop.contains(token);

List<String> tokenizeText(String s) =>
    _token.allMatches(normalizeText(s)).map((m) => m.group(0)!).toList();

class LocalRetrieval {
  LocalRetrieval(
    Iterable<LocalPassage> passages, {
    this.eligible = const {'VERIFIED'},
    this.vectors,
    this.aliases,
  }) {
    for (final p in passages) {
      if (!eligible.contains(p.verificationStatus) || p.text.isEmpty) {
        continue; // only approved evidence is searchable
      }
      final toks = {
        ...tokenizeText(p.text),
        ...tokenizeText(p.sectionTitle ?? ''),
      };
      _passages.add(p);
      _tokens.add(toks);
      for (final t in toks) {
        _df[t] = (_df[t] ?? 0) + 1;
      }
    }
  }
  final Set<String> eligible;

  /// passage id -> stored 8-bit vector. When present, search is HYBRID: keyword score and vector similarity together.
  final Map<String, Int8List>? vectors;
  final AliasExpander? aliases;
  static const _embedder = HashingEmbedder();

  /// Hybrid search tuning (calibrated on asha-data/questions; see test/data_eval_test.dart).
  static const vectorMin = 0.14; // below this a vector match is ignored
  static const hybridMin = 0.07; // 0.5 * cosine at the floor
  static const langBonus = 0.02; // tie-break only
  final List<LocalPassage> _passages = [];
  final List<Set<String>> _tokens = [];
  final Map<String, int> _df = {};

  int get size => _passages.length;
  List<LocalPassage> get passages => List.unmodifiable(_passages);
  bool get isEmpty => _passages.isEmpty;

  static bool _telugu(String t) =>
      t.isNotEmpty && t.codeUnitAt(0) >= 0x0C00 && t.codeUnitAt(0) <= 0x0C7F;

  /// A question word matches a passage word when they are the same, or (Telugu only) share the same stem: at least 5 letters and
  /// 70% of the shorter word in common at the start. Telugu words take many endings (కడుక్కోవాలి / కడుక్కోండి) and are spelled
  /// in more than one way (గర్భిణీ / గర్భిణి), so exact matching alone misses the same word.
  static bool _tokenMatches(String q, Set<String> passage) {
    if (passage.contains(q)) return true;
    if (!_telugu(q) || q.length < 5) return false;
    for (final p in passage) {
      if (p.length < 5 || !_telugu(p)) continue;
      final m = math.min(q.length, p.length);
      var k = 0;
      while (k < m && q.codeUnitAt(k) == p.codeUnitAt(k)) {
        k++;
      }
      if (k >= 5 && k >= 0.7 * m) return true;
    }
    return false;
  }

  double _idf(String t) {
    final n = _passages.length;
    final d = _df[t];
    if (d == null) return -1;
    return math.log(1 + (n - d + 0.5) / (d + 0.5));
  }

  List<LocalMatch> search(
    String question, {
    int topK = 3,
    double minScore = 0.5,
    int minMatchedTerms = 2,
    String? preferLang,
  }) {
    if (isEmpty) return const [];
    final lexical = _lexical(question, minScore, minMatchedTerms);
    final vs = vectors;
    if (vs == null || vs.isEmpty) return lexical.take(topK).toList();
    return _hybrid(question, lexical, vs, topK, preferLang);
  }

  final Map<int, Set<int>> _groupCache = {};
  Set<int> _groups(int i, AliasExpander ax) => _groupCache.putIfAbsent(
    i,
    () =>
        ax.groupsIn('${_passages[i].text} ${_passages[i].sectionTitle ?? ''}'),
  );

  List<LocalMatch> _hybrid(
    String question,
    List<LocalMatch> lexical,
    Map<String, Int8List> vs,
    int topK,
    String? preferLang,
  ) {
    final expanded = aliases?.expand(question) ?? question;
    final q = _embedder.embed(expanded);
    final lex = {for (final m in lexical) m.passage.passageId: m};
    final ax = aliases;
    final qGroups = ax?.groupsIn(question) ?? const <int>{};
    final scored = <LocalMatch>[];
    for (var i = 0; i < _passages.length; i++) {
      final p = _passages[i];
      final v = vs[p.passageId];
      final cos = v == null ? 0.0 : _embedder.cosine(q, v);
      final l = lex[p.passageId];
      // A vector match counts only if the question and the passage are about the same thing (they share a topic word group):
      // character vectors alone cannot tell an unrelated question from a related one (see asha-data/README.md).
      final onTopic = ax == null || ax.sharesTopic(qGroups, _groups(i, ax));
      if (l == null && !(cos >= vectorMin && onTopic)) continue;
      final s = 0.5 * (l?.score ?? 0.0) + 0.5 * math.max(0.0, cos);
      if (s < hybridMin) continue;
      final bonus = preferLang != null && p.language == preferLang
          ? langBonus
          : 0.0;
      scored.add(LocalMatch(p, s + bonus, l?.matchedTerms ?? const []));
    }
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.passage.passageId.compareTo(b.passage.passageId);
    });
    // one passage per section: the English and Telugu versions of a section are the same answer, so show the better one only
    final seen = <String>{};
    final out = <LocalMatch>[];
    for (final m in scored) {
      final key =
          '${m.passage.documentId}#${m.passage.sectionId ?? m.passage.passageId}';
      if (seen.add(key)) out.add(m);
      if (out.length >= topK) break;
    }
    return out;
  }

  List<LocalMatch> _lexical(
    String question,
    double minScore,
    int minMatchedTerms,
  ) {
    final qt = tokenizeText(question)
        .toSet()
        .where((t) => !_stop.contains(t))
        .toList();
    if (qt.isEmpty) return const [];
    var maxIdf = 0.0;
    for (final t in _df.keys) {
      maxIdf = math.max(maxIdf, _idf(t));
    }
    final w = {for (final t in qt) t: _idf(t) < 0 ? maxIdf : _idf(t)};
    final total = w.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return const [];
    final out = <LocalMatch>[];
    for (var i = 0; i < _passages.length; i++) {
      final hit = qt.where((t) => _tokenMatches(t, _tokens[i])).toList();
      if (hit.length < minMatchedTerms) continue;
      final score = hit.fold<double>(0, (a, t) => a + w[t]!) / total;
      if (score >= minScore) out.add(LocalMatch(_passages[i], score, hit));
    }
    out.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.passage.passageId.compareTo(b.passage.passageId);
    });
    return out;
  }
}
