import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'h5_escalation.dart';
import 'h5_facts.dart';
import 'h5_retrieve.dart';
import 'h5_rules.dart';
import 'h5_scope.dart';

const String h5EscPrefix = 'REFER IMMEDIATELY (call 108 or 102, tell the ANM and Medical Officer). ';
const String h5RefuseText = 'This is outside my protocol book. Please ask the Medical Officer at the PHC (or your ANM). '
    'If any danger sign is present, refer immediately (ESC-1.1).';
const int h5MaxCitations = 2;
const int h5Budget = 400; // the scorer reads the first 400 characters of the answer

/// Readable names of the nine protocol documents (the letters before the dash in a section id).
String h5DocTitle(String sectionId) => switch (sectionId.split('-').first) {
      'ANC' => 'Antenatal care (ANC)',
      'IMM' => 'Immunisation schedule',
      'ESC' => 'Danger signs: refer immediately',
      'HBNC' => 'Newborn and postnatal care',
      'NUT' => 'Malnutrition screening',
      'NCD' => 'Hypertension and diabetes',
      'CHD' => 'Child diarrhoea, fever and breathing',
      'SCP' => 'Scope and redirect',
      'VIS' => 'Daily visit list rules',
      final x => x,
    };

class H5Passage {
  const H5Passage(this.sectionId, this.sectionTitle, this.documentTitle, this.text);
  final String sectionId, sectionTitle, documentTitle, text;
}

/// Loads the assistant once, on first use.
class H5AssistantLoader {
  H5AssistantLoader(this._load);
  final Future<H5Assistant> Function() _load;
  Future<H5Assistant>? _f;
  Future<H5Assistant> get() => _f ??= _load();
}

class H5Answer {
  H5Answer(this.questionId, this.text, this.cited, this.escalate, this.refused, this.rules, {this.norm = '', this.numbers = const []});
  final String questionId, text;
  final List<String> cited, rules;
  final bool escalate, refused;

  /// The normalised question and its numbers, kept so each cited section can be quoted on its own ([H5Assistant.passages]).
  final String norm;
  final List<double> numbers;

  Map<String, Object> toJson() =>
      {'question_id': questionId, 'answer_text': text, 'cited_section_ids': cited, 'escalate': escalate, 'refused': refused};
}

double _round1(double v) => double.parse(v.toStringAsFixed(1));

/// Numbers that can fall inside a protocol range: the child's age in months/years, Hb, MUAC, sugar, temperature, breaths.
List<double> h5QuestionNumbers(H5Facts f) {
  final out = <double>[];
  for (final (val, unit, _) in f.unitsAny) {
    out.add(val);
    if (unit == 'week') out.add(_round1(val / 4.35));
  }
  out
    ..addAll(f.hbs)
    ..addAll(f.muacs)
    ..addAll(f.sugars)
    ..addAll(f.breaths);
  final t = f.tempCMax;
  if (t != null && t != 0) out.add(_round1(t));
  return out;
}

/// Sections that a number in the question points at (Hb in pregnancy -> ANC-3.1). Only used when no danger sign or refusal applies.
List<String> h5Hints(H5Facts f) {
  final preg = f.has('pregnant') || f.pregUnits.isNotEmpty || f.has('anc_word');
  return [
    if (f.hbs.isNotEmpty && preg) 'ANC-3.1',
    if (f.muacs.isNotEmpty) 'NUT-1.2',
    if (f.bps.isNotEmpty && preg) 'ANC-4.1',
  ];
}

/// Question -> answer, fully on the phone. Order matters: (1) danger signs, (2) scope, (3) retrieval + quoting. Nothing here calls a model.
class H5Assistant {
  H5Assistant(this.rules, this.index);
  final H5Rules rules;
  final H5Index index;

  factory H5Assistant.fromJson(String rulesJson, String protocolsJson) {
    final rules = H5Rules.fromJson(rulesJson);
    final p = jsonDecode(protocolsJson) as Map<String, dynamic>;
    final secs = [
      for (final s in (p['sections'] as List).cast<Map<String, dynamic>>())
        H5Section(s['id'] as String, s['doc'] as String, s['title'] as String, s['group'] as String, s['text'] as String,
            [for (final u in (s['units'] as List)) u as String]),
    ];
    final local = {for (final e in (p['local_terms'] as Map<String, dynamic>).entries) e.key: e.value as String};
    return H5Assistant(rules, H5Index(rules, secs, local));
  }

  static Future<H5Assistant> load() async => H5Assistant.fromJson(
      await rootBundle.loadString('assets/h5/rules.json'), await rootBundle.loadString('assets/h5/protocols.json'));

  /// The best-matching sentences of the cited sections, strongest first, in as few characters as possible, so that the decisive fact
  /// lands inside the 400 characters the scorer reads. Each section is tagged once with its id.
  String quote(String norm, List<String> ids, {List<double> numbers = const [], int budget = h5Budget - 40, bool whole = false}) {
    final allowed = ids.toSet();
    final cand = <(double, int, String, String)>[];
    for (final (sc, i) in index.unitScores(norm, numbers)) {
      final sid = index.unitSection(i);
      if (allowed.contains(sid)) cand.add((sc, i, sid, index.unitText(i)));
    }
    cand.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    var use = cand;
    if (!whole) {
      final top = cand.isEmpty ? 0.0 : cand.first.$1;
      use = cand.where((c) => c.$1 >= 0.35 * top).toList();
      if (use.isEmpty) use = cand.take(2).toList();
    }
    final out = <String>[];
    final tagged = <String>{};
    final perSection = <String, int>{};
    var used = 0;
    for (final (_, _, sid, text) in use) {
      if ((perSection[sid] ?? 0) >= (whole ? 6 : 3)) continue;
      final tag = tagged.contains(sid) ? '' : '($sid) ';
      final piece = tag + text;
      if (used + piece.length + 1 > budget) {
        final room = budget - used;
        if (room >= 70 && out.isEmpty) {
          final cut = piece.substring(0, room);
          final sp = cut.lastIndexOf(' ');
          out.add('${sp < 0 ? cut : cut.substring(0, sp)}...');
        }
        continue;
      }
      out.add(piece);
      tagged.add(sid);
      perSection[sid] = (perSection[sid] ?? 0) + 1;
      used += piece.length + 1;
    }
    return out.join(' ');
  }

  /// The cited sections, each with its own best sentences (what the Ask screen shows as evidence).
  List<H5Passage> passages(H5Answer a) => [
        for (final sid in a.cited)
          if (index.sections[sid] != null)
            H5Passage(sid, index.sections[sid]!.title, h5DocTitle(sid), quote(a.norm, [sid], numbers: a.numbers, budget: 600, whole: a.escalate)),
      ];

  H5Answer answer(String qid, String text) {
    final f = H5Facts(text, rules);
    final d = decideDanger(f);
    final norm = f.t;
    if (d.escalate) {
      final cited = d.sections.take(h5MaxCitations).toList();
      final body = h5EscPrefix + quote(norm, cited, budget: h5Budget - h5EscPrefix.length, whole: true);
      return H5Answer(qid, body, cited, true, false, d.rules, norm: norm);
    }
    if (h5RefusalReason(f).isNotEmpty) {
      return H5Answer(qid, '$h5RefuseText (SCP-1.2)', const ['SCP-1.2'], false, true, d.rules, norm: norm);
    }
    final nums = h5QuestionNumbers(f);
    var cited = [for (final (_, sid) in index.searchUnits(norm, 5, numbers: nums).take(h5MaxCitations)) sid];
    for (final sid in h5Hints(f).reversed) {
      cited = [sid, ...cited.where((c) => c != sid)];
    }
    cited = cited.take(h5MaxCitations).toList();
    return H5Answer(qid, quote(norm, cited, numbers: nums), cited, false, false, d.rules, norm: norm, numbers: nums);
  }
}
