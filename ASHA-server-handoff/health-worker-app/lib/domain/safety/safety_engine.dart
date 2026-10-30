import 'dart:convert';

/// Dart port of backend `app/services/safety/engine.py`. It reads the SAME `danger_rules.json` file (assets/safety),
/// so rule changes happen in one place, and test/safety_parity_test.dart checks this port against every supplied
/// danger-sign case. Pure Dart: no Flutter, network or storage dependency, so it runs with zero connectivity.
///
/// The ruleset is a software-test lexicon and is NOT CLINICALLY VALIDATED (see ruleset `clinically_validated`).
const statusEscalation = 'ESCALATION_REQUIRED';
const statusClarification = 'CLARIFICATION_REQUIRED';
const statusNormal = 'NORMAL_PROTOCOL_QUERY';
const statusOutOfScope = 'OUT_OF_SCOPE';

class SafetyMatch {
  const SafetyMatch(
    this.ruleId,
    this.label,
    this.context,
    this.kind,
    this.text,
    this.reason,
  );
  final String ruleId, label, context, kind, text, reason;
}

class SafetyDecision {
  const SafetyDecision({
    required this.status,
    required this.ruleIds,
    required this.reasons,
    required this.matches,
    required this.rulesetId,
    required this.rulesetVersion,
    required this.rulesetReviewStatus,
    required this.clinicallyValidated,
    required this.message,
    required this.needsHumanReview,
  });
  final String status, rulesetId, rulesetVersion, rulesetReviewStatus;
  final List<String> ruleIds, reasons;
  final List<SafetyMatch> matches;
  final bool clinicallyValidated, needsHumanReview;
  final String? message;
}

class _Rule {
  _Rule(this.id, this.label, this.patterns, this.mentions);
  final String id, label;
  final List<RegExp> patterns, mentions;
}

String normalizeText(String s) {
  var t = s.replaceAll(RegExp('[​‌‍⁠﻿]'), '');
  t = t
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

class SafetyEngine {
  SafetyEngine._(this._cfg)
    : _split = RegExp((_cfg['cues'] as Map)['clause_split'] as String),
      _neg = _normSet((_cfg['cues'] as Map)['negation_tokens'] as List),
      _negAfter = _normSet(
        (_cfg['cues'] as Map)['negation_after_tokens'] as List,
      ),
      _nb = (_cfg['cues'] as Map)['negation_window_before'] as int,
      _na = (_cfg['cues'] as Map)['negation_window_after'] as int,
      _hist = _normList((_cfg['cues'] as Map)['history_phrases'] as List),
      _cur = _normList((_cfg['cues'] as Map)['current_phrases'] as List),
      _hyp = _normList((_cfg['cues'] as Map)['hypothetical_phrases'] as List),
      _amb = _rx(_cfg['ambiguous_patterns'] as List),
      _oos = _rx(_cfg['out_of_scope_patterns'] as List),
      _shortMax = _cfg['short_message_max_tokens'] as int,
      _rules = [
        for (final r in _cfg['rules'] as List)
          _Rule(
            (r as Map)['rule_id'] as String,
            r['label'] as String,
            _rx(r['patterns'] as List),
            _rx(r['mentions'] as List),
          ),
      ];

  factory SafetyEngine.fromJsonString(String raw) =>
      SafetyEngine._(jsonDecode(raw) as Map<String, dynamic>);

  final Map<String, dynamic> _cfg;
  final RegExp _split;
  final Set<String> _neg, _negAfter;
  final int _nb, _na, _shortMax;
  final List<String> _hist, _cur, _hyp;
  final List<RegExp> _amb, _oos;
  final List<_Rule> _rules;

  String get version => _cfg['version'] as String;
  bool get clinicallyValidated =>
      (_cfg['clinically_validated'] as bool?) ?? false;

  static Set<String> _normSet(List l) => {
    for (final e in l) normalizeText(e as String),
  };
  static List<String> _normList(List l) => [
    for (final e in l) normalizeText(e as String),
  ];
  static List<RegExp> _rx(List l) => [for (final e in l) RegExp(e as String)];

  // Same semantics as the Python engine: substring test on the space-padded clause.
  static bool _has(String clause, List<String> phrases) {
    final padded = ' $clause ';
    return phrases.any(padded.contains);
  }

  static final _tok = RegExp(r'\S+');
  static const _strip = '.,;:!?()"\'[]';

  static String _trim(String t) {
    var a = 0, b = t.length;
    while (a < b && _strip.contains(t[a])) {
      a++;
    }
    while (b > a && _strip.contains(t[b - 1])) {
      b--;
    }
    return t.substring(a, b);
  }

  bool _negated(String clause, int s, int e) {
    final toks = _tok.allMatches(clause).toList();
    final idx = [
      for (var i = 0; i < toks.length; i++)
        if (toks[i].end > s && toks[i].start < e) i,
    ];
    if (idx.isEmpty) return false;
    final lo = idx.first, hi = idx.last;
    final before = toks.sublist(lo - _nb < 0 ? 0 : lo - _nb, lo);
    final afterEnd = hi + 1 + _na;
    final after = toks.sublist(
      hi + 1 > toks.length ? toks.length : hi + 1,
      afterEnd > toks.length ? toks.length : afterEnd,
    );
    return before.any((m) => _neg.contains(_trim(m.group(0)!))) ||
        after.any((m) => _negAfter.contains(_trim(m.group(0)!)));
  }

  String _context(String clause, int s, int e) {
    if (_negated(clause, s, e)) return 'NEGATED';
    if (_has(clause, _hyp)) return 'HYPOTHETICAL';
    if (_has(clause, _hist) && !_has(clause, _cur)) return 'HISTORICAL';
    return 'CURRENT';
  }

  SafetyDecision evaluate(String text) {
    final norm = normalizeText(text);
    final clauses = norm
        .split(_split)
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    final matches = <SafetyMatch>[];
    for (final clause in clauses) {
      for (final rule in _rules) {
        var severe = false;
        for (final rx in rule.patterns) {
          for (final m in rx.allMatches(clause)) {
            severe = true;
            matches.add(
              SafetyMatch(
                rule.id,
                rule.label,
                _context(clause, m.start, m.end),
                'SEVERE_PATTERN',
                m.group(0)!,
                '${rule.label} phrase matched',
              ),
            );
          }
        }
        if (!severe) {
          for (final rx in rule.mentions) {
            final m = rx.firstMatch(clause);
            if (m != null) {
              matches.add(
                SafetyMatch(
                  rule.id,
                  rule.label,
                  _context(clause, m.start, m.end),
                  'BARE_MENTION',
                  m.group(0)!,
                  '${rule.label} mentioned without severity or context',
                ),
              );
              break;
            }
          }
        }
      }
      for (final rx in _amb) {
        final m = rx.firstMatch(clause);
        if (m != null) {
          matches.add(
            SafetyMatch(
              'DSR-AMBIGUOUS',
              'Unclear complaint',
              'CURRENT',
              'AMBIGUOUS',
              m.group(0)!,
              'complaint too vague to classify',
            ),
          );
          break;
        }
      }
    }
    final oos = <SafetyMatch>[
      for (final rx in _oos)
        if (rx.firstMatch(norm) case final m?)
          SafetyMatch(
            'DSR-OUT-OF-SCOPE',
            'Unsupported medical request',
            'CURRENT',
            'OUT_OF_SCOPE',
            m.group(0)!,
            'dosage/prescribing/treatment request',
          ),
    ];
    final ntok = _tok.allMatches(norm).length;
    final severeCur = matches
        .where((m) => m.kind == 'SEVERE_PATTERN' && m.context == 'CURRENT')
        .toList();
    final bareCur = matches
        .where((m) => m.kind == 'BARE_MENTION' && m.context == 'CURRENT')
        .toList();
    final amb = matches.where((m) => m.kind == 'AMBIGUOUS').toList();
    final short = ntok > 0 && ntok <= _shortMax;
    String status;
    List<SafetyMatch> used;
    var human = false;
    if (severeCur.isNotEmpty && !short) {
      status = statusEscalation;
      used = severeCur;
    } else if (oos.isNotEmpty) {
      status = statusOutOfScope;
      used = oos.take(1).toList();
    } else if (severeCur.isNotEmpty || bareCur.isNotEmpty || amb.isNotEmpty) {
      status = statusClarification;
      used = [...severeCur, ...bareCur, ...amb];
      human = severeCur.isNotEmpty;
    } else {
      status = statusNormal;
      used = const [];
    }
    final reasons = [
      for (final m in used) '${m.reason} (${m.context.toLowerCase()})',
    ];
    if (status == statusClarification && severeCur.isNotEmpty) {
      reasons.add(
        'message too short to establish context; short-message policy routes to clarification',
      );
    }
    final msgs = _cfg['messages'] as Map<String, dynamic>;
    return SafetyDecision(
      status: status,
      ruleIds: ({for (final m in used) m.ruleId}.toList()..sort()),
      reasons: reasons,
      matches: [...matches, ...oos],
      rulesetId: _cfg['ruleset_id'] as String,
      rulesetVersion: version,
      rulesetReviewStatus: _cfg['review_status'] as String,
      clinicallyValidated: clinicallyValidated,
      message: msgs[status] as String?,
      needsHumanReview: human,
    );
  }
}
