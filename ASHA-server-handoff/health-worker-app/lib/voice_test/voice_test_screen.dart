import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/qa_service.dart';
import '../services/telugu_voice.dart';
import '../services/voice_input.dart';
import '../state/app_services.dart';
import 'results_log.dart';
import 'test_sentences.dart';

const _pkg = 'in.healthcompanion.health_companion';

/// What the app did with a transcript: did the right danger rule fire, did Q&A return the right passage.
class Verdict {
  const Verdict({
    required this.dangerFired,
    required this.dangerOk,
    required this.qaOutcome,
    required this.qaTopSection,
    required this.qaOk,
  });
  final String dangerFired, qaOutcome, qaTopSection;
  final bool dangerOk, qaOk;
}

/// Scores a transcript against what the sentence should do. Pure, so it can be unit tested.
Verdict judge(TestSentence s, QaResult? r) {
  if (r == null) {
    return const Verdict(
      dangerFired: '',
      dangerOk: false,
      qaOutcome: 'empty',
      qaTopSection: '',
      qaOk: false,
    );
  }
  final escalated = r.outcome == QaOutcome.escalationRequired;
  final top = r.evidence.isEmpty ? '' : (r.evidence.first.sectionTitle ?? '');
  final dangerOk = s.expect == 'ESCALATION'
      ? escalated && r.ruleIds.contains(s.rule)
      : !escalated;
  final qaOk = switch (s.expect) {
    'ESCALATION' => escalated,
    'OUT_OF_SCOPE' => r.outcome == QaOutcome.outOfScope,
    _ =>
      r.outcome == QaOutcome.answeredWithEvidence &&
          top.toLowerCase().contains(s.section.toLowerCase()),
  };
  return Verdict(
    dangerFired: escalated ? r.ruleIds.join('+') : '',
    dangerOk: dangerOk,
    qaOutcome: r.outcome.name,
    qaTopSection: top,
    qaOk: qaOk,
  );
}

class _Take {
  bool listening = false, busy = false;
  String transcript = '', error = '', rating = '', endedBy = '';
  int startedAt = 0, endedAt = 0, msAfterStop = 0, audioMs = 0;
  bool done = false;
  Verdict? verdict;
  String? note;
  void reset() {
    listening = busy = done = false;
    transcript = error = rating = endedBy = '';
    startedAt = endedAt = msAfterStop = audioMs = 0;
    verdict = null;
    note = null;
  }
}

class VoiceTestScreen extends StatefulWidget {
  const VoiceTestScreen({super.key});
  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

/// One engine card: the phone's online speech, or the app's own offline Telugu model. Both are plain [VoiceInput]s, so one code path times and
/// scores them the same way.
class _Rec {
  _Rec(this.key, this.title, this.voice, {required this.offline});
  final String key, title;
  final VoiceInput Function() voice;
  final bool offline;
  final take = _Take();
  String last = '';
  int tapStop = 0;
  Timer? fallback;
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  final _session = '${DateTime.now().millisecondsSinceEpoch}';
  late final List<_Rec> _engines = [
    _Rec('online', 'Online phone speech', () => _s.voice, offline: false),
    _Rec('offline_app', "App's own offline Telugu model", () => _s.teluguVoice, offline: true),
  ];

  List<TestSentence> _sentences = const [];
  int _i = 0;
  String? _fatal;
  bool _ownModelInstalled = false;
  ResultsLog? _log;
  String _wavNote = '';

  AppServices get _s => context.read<AppServices>();
  TestSentence get _cur => _sentences[_i];
  String get _network => _s.connectivity.online ? 'online' : 'offline';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    for (final r in _engines) {
      r.fallback?.cancel();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      _log = ResultsLog(File('${dir.path}/voice_test.csv'));
      final custom = File('${dir.path}/voice_test_sentences.json');
      final text = await custom.exists()
          ? await custom.readAsString()
          : await rootBundle.loadString('assets/voice_test/sentences.json');
      _sentences = parseSentences(text);
      _ownModelInstalled = await _s.teluguModel.isInstalled();
    } on Object catch (e) {
      _fatal = '$e';
    }
    if (mounted) setState(() {});
  }

  // ---------- recording (same path for both engines) ----------

  Future<void> _start(_Rec r) async {
    final t = r.take..reset();
    t.listening = true;
    t.startedAt = DateTime.now().millisecondsSinceEpoch;
    r.last = '';
    r.tapStop = 0;
    r.fallback?.cancel();
    setState(() {});
    await r.voice().start(
      lang: 'te',
      offline: r.offline,
      onText: (text, isFinal) {
        r.last = text;
        if (isFinal) _finish(r, text, null);
      },
      onProblem: (p) => _finish(r, r.last, p.name),
      onDone: () {
        if (t.listening && !t.done) {
          r.fallback?.cancel();
          r.fallback = Timer(const Duration(seconds: 3), () => _finish(r, r.last, null));
        }
      },
    );
  }

  Future<void> _stop(_Rec r) async {
    r.tapStop = DateTime.now().millisecondsSinceEpoch;
    r.fallback?.cancel();
    r.fallback = Timer(const Duration(seconds: 8), () => _finish(r, r.last, 'no_final_result'));
    await r.voice().stop();
  }

  void _finish(_Rec r, String text, String? error) {
    final t = r.take;
    if (t.done || !mounted) return;
    r.fallback?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    t
      ..done = true
      ..listening = false
      ..endedAt = now
      ..endedBy = r.tapStop == 0 ? 'auto' : 'user'
      ..msAfterStop = r.tapStop == 0 ? 0 : now - r.tapStop
      ..audioMs = now - t.startedAt
      ..transcript = text
      ..error = error ?? '';
    setState(() {});
    unawaited(_score(t, text));
  }

  /// Runs files/test.wav (16 kHz mono 16-bit WAV, copied with adb) through the offline model: a test without speaking.
  Future<void> _runWav() async {
    setState(() => _wavNote = 'running...');
    try {
      final ext = await getExternalStorageDirectory();
      final dir = await _s.teluguModel.dir();
      final r = await NativeTeluguAsrEngine.recogniseWav(dir.path, '${ext!.path}/test.wav');
      _wavNote = '${r.ms} ms: ${r.text}';
      await File('${ext.path}/test_out.txt').writeAsString('${r.ms}\n${r.text}\n');
    } on Object catch (e) {
      _wavNote = 'failed: $e';
    }
    if (mounted) setState(() {});
  }

  // ---------- scoring and saving ----------

  Future<void> _score(_Take t, String text) async {
    QaResult? r;
    if (text.trim().isNotEmpty) {
      try {
        r = await _s.qa.ask(text);
      } on Object {
        r = null;
      }
    }
    t.verdict = judge(_cur, r);
    if (mounted) setState(() {});
  }

  Future<void> _rate(String engine, _Take t, String rating) async {
    final v = t.verdict;
    final log = _log;
    if (v == null || log == null) return;
    t.rating = rating;
    setState(() {});
    await log.append(
      VoiceTestRow(
        session: _session,
        startedAtMs: t.startedAt,
        endedAtMs: t.endedAt,
        network: _network,
        sentenceId: _cur.id,
        expected: _cur.expectedLabel,
        engine: engine,
        transcript: t.transcript,
        msAfterStop: t.msAfterStop,
        audioMs: t.audioMs,
        endedBy: t.endedBy,
        error: t.error,
        rating: rating,
        dangerFired: v.dangerFired,
        dangerOk: v.dangerOk,
        qaOutcome: v.qaOutcome,
        qaTopSection: v.qaTopSection,
        qaOk: v.qaOk,
      ),
    );
  }

  void _go(int d) {
    final n = _i + d;
    if (n < 0 || n >= _sentences.length) return;
    for (final r in _engines) {
      r.fallback?.cancel();
      unawaited(r.voice().stop());
      r.take.reset();
    }
    setState(() => _i = n);
  }

  Future<void> _showSummary() async {
    final rows = await _log?.readAll() ?? const <VoiceTestRow>[];
    final sums = summarise(rows);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Summary'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: sums.isEmpty
              ? const Text('Nothing rated yet.')
              : DataTable(
                  columnSpacing: 14,
                  columns: const [
                    DataColumn(label: Text('Engine')),
                    DataColumn(label: Text('Net')),
                    DataColumn(label: Text('Takes'), numeric: true),
                    DataColumn(label: Text('Correct'), numeric: true),
                    DataColumn(label: Text('Some wrong'), numeric: true),
                    DataColumn(label: Text('Wrong'), numeric: true),
                    DataColumn(label: Text('Avg ms'), numeric: true),
                    DataColumn(label: Text('Danger ok'), numeric: true),
                    DataColumn(label: Text('Q&A ok'), numeric: true),
                  ],
                  rows: [
                    for (final s in sums)
                      DataRow(cells: [
                        DataCell(Text(s.engine)),
                        DataCell(Text(s.network)),
                        DataCell(Text('${s.takes}')),
                        DataCell(Text('${s.correct}')),
                        DataCell(Text('${s.someWrong}')),
                        DataCell(Text('${s.wrong}')),
                        DataCell(Text('${s.avgMs}')),
                        DataCell(Text('${s.dangerOk}/${s.takes}')),
                        DataCell(Text('${s.qaOk}/${s.takes}')),
                      ]),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        ],
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_sentences.isEmpty ? 'Voice Test' : 'Voice Test  ${_i + 1}/${_sentences.length}'),
        actions: [
          TextButton(onPressed: _showSummary, child: const Text('Summary')),
        ],
      ),
      body: _fatal != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text('Could not start: $_fatal'))
          : _sentences.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('network: $_network')),
                    Chip(label: Text(_ownModelInstalled ? 'offline model installed' : 'offline model NOT installed')),
                    Chip(label: Text(_cur.category)),
                  ],
                ),
                if (!_ownModelInstalled)
                  Text('The offline model is not downloaded on this phone (Settings -> Download Telugu voice, about 44 MB), so that card will report languageMissing.', style: TextStyle(color: cs.error)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_cur.text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.4)),
                        const SizedBox(height: 8),
                        Text('Expected: ${_cur.expectedLabel}', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          'Read it once into each engine, one after the other. Tap Record, speak, tap Stop.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                for (final r in _engines) _engineCard(r),
                TextButton(onPressed: _runWav, child: const Text('Run files/test.wav through the offline model')),
                if (_wavNote.isNotEmpty) SelectableText(_wavNote),
                Row(
                  children: [
                    OutlinedButton(onPressed: _i > 0 ? () => _go(-1) : null, child: const Text('Previous')),
                    const Spacer(),
                    FilledButton(onPressed: _i < _sentences.length - 1 ? () => _go(1) : _showSummary, child: Text(_i < _sentences.length - 1 ? 'Next' : 'Finish: summary')),
                  ],
                ),
                const SizedBox(height: 16),
                SelectableText(
                  'Results file: ${_log?.file.path ?? '?'}\n'
                  'Pull it: adb pull /sdcard/Android/data/$_pkg/files/voice_test.csv',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _engineCard(_Rec r) {
    final t = r.take;
    final key = r.key;
    final title = r.title;
    Future<void> start() => _start(r);
    Future<void> stop() => _stop(r);
    final v = t.verdict;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: t.busy ? null : (t.listening ? stop : start),
              icon: Icon(t.listening ? Icons.stop : Icons.mic),
              label: Text(t.busy ? 'Working...' : (t.listening ? 'Stop' : (t.done ? 'Record again' : 'Record'))),
            ),
            if (t.note != null) Text(t.note!, style: Theme.of(context).textTheme.bodySmall),
            if (t.done) ...[
              const SizedBox(height: 8),
              SelectableText(
                t.transcript.isEmpty ? '(no text)' : t.transcript,
                style: const TextStyle(fontSize: 20, height: 1.4),
              ),
              Text(
                '${t.msAfterStop} ms after stop · audio ${t.audioMs} ms${t.error.isEmpty ? '' : ' · error: ${t.error}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (v != null)
                Text(
                  'Danger rule ${v.dangerOk ? 'OK' : 'NOT ok'}${v.dangerFired.isEmpty ? '' : ' (${v.dangerFired})'} · '
                  'Q&A ${v.qaOk ? 'OK' : 'NOT ok'} (${v.qaOutcome}${v.qaTopSection.isEmpty ? '' : ': ${v.qaTopSection}'})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in const [
                    ('correct', 'Correct'),
                    ('some_wrong', 'Some words wrong'),
                    ('wrong', 'Wrong'),
                  ])
                    ChoiceChip(
                      label: Text(r.$2),
                      selected: t.rating == r.$1,
                      onSelected: v == null ? null : (_) => _rate(key, t, r.$1),
                    ),
                ],
              ),
              if (t.rating.isNotEmpty) Text('Saved', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}
