import 'dart:io';

/// One rated take: one engine, one sentence.
class VoiceTestRow {
  const VoiceTestRow({
    required this.session,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.network,
    required this.sentenceId,
    required this.expected,
    required this.engine,
    required this.transcript,
    required this.msAfterStop,
    required this.audioMs,
    required this.endedBy,
    required this.error,
    required this.rating,
    required this.dangerFired,
    required this.dangerOk,
    required this.qaOutcome,
    required this.qaTopSection,
    required this.qaOk,
  });

  final String session, network, sentenceId, expected, engine, transcript;
  final String endedBy, error, rating, dangerFired, qaOutcome, qaTopSection;
  final int startedAtMs, endedAtMs, msAfterStop, audioMs;
  final bool dangerOk, qaOk;

  static const header = [
    'session',
    'started_at_ms',
    'ended_at_ms',
    'network',
    'sentence_id',
    'expected',
    'engine',
    'transcript',
    'ms_after_stop',
    'audio_ms',
    'ended_by',
    'error',
    'rating',
    'danger_fired',
    'danger_ok',
    'qa_outcome',
    'qa_top_section',
    'qa_ok',
  ];

  List<String> get cells => [
    session,
    '$startedAtMs',
    '$endedAtMs',
    network,
    sentenceId,
    expected,
    engine,
    transcript,
    '$msAfterStop',
    '$audioMs',
    endedBy,
    error,
    rating,
    dangerFired,
    dangerOk ? '1' : '0',
    qaOutcome,
    qaTopSection,
    qaOk ? '1' : '0',
  ];

  static VoiceTestRow fromCells(List<String> c) => VoiceTestRow(
    session: c[0],
    startedAtMs: int.tryParse(c[1]) ?? 0,
    endedAtMs: int.tryParse(c[2]) ?? 0,
    network: c[3],
    sentenceId: c[4],
    expected: c[5],
    engine: c[6],
    transcript: c[7],
    msAfterStop: int.tryParse(c[8]) ?? 0,
    audioMs: int.tryParse(c[9]) ?? 0,
    endedBy: c[10],
    error: c[11],
    rating: c[12],
    dangerFired: c[13],
    dangerOk: c[14] == '1',
    qaOutcome: c[15],
    qaTopSection: c[16],
    qaOk: c[17] == '1',
  );
}

String csvCell(String s) =>
    s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;

String csvLine(List<String> cells) => cells.map(csvCell).join(',');

/// Parses CSV text (quoted cells, doubled quotes and line breaks inside quotes) into rows of cells.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Appends rows to voice_test.csv (header written once). The file lives in the app's external files folder so that
/// `adb pull` can fetch it; it only ever holds test sentences and recogniser output, never household data.
class ResultsLog {
  ResultsLog(this.file);
  final File file;

  Future<void> append(VoiceTestRow r) async {
    final fresh = !await file.exists() || await file.length() == 0;
    final sink = file.openWrite(mode: FileMode.append);
    if (fresh) sink.writeln(csvLine(VoiceTestRow.header));
    sink.writeln(csvLine(r.cells));
    await sink.flush();
    await sink.close();
  }

  Future<List<VoiceTestRow>> readAll() async {
    if (!await file.exists()) return [];
    final rows = parseCsv(await file.readAsString());
    return [
      for (final c in rows.skip(1))
        if (c.length >= VoiceTestRow.header.length) VoiceTestRow.fromCells(c),
    ];
  }
}

/// Counts for one engine on one network state.
class EngineSummary {
  EngineSummary(this.engine, this.network);
  final String engine, network;
  int takes = 0, correct = 0, someWrong = 0, wrong = 0, dangerOk = 0, qaOk = 0;
  int _msSum = 0;
  int get avgMs => takes == 0 ? 0 : (_msSum / takes).round();
}

/// The latest rating per (session, sentence, engine) wins, so re-doing a take replaces the earlier one.
List<EngineSummary> summarise(Iterable<VoiceTestRow> rows) {
  final latest = <String, VoiceTestRow>{};
  for (final r in rows) {
    latest['${r.session}|${r.sentenceId}|${r.engine}|${r.network}'] = r;
  }
  final by = <String, EngineSummary>{};
  for (final r in latest.values) {
    final s = by.putIfAbsent('${r.engine}|${r.network}', () => EngineSummary(r.engine, r.network));
    s.takes++;
    s._msSum += r.msAfterStop;
    switch (r.rating) {
      case 'correct':
        s.correct++;
      case 'some_wrong':
        s.someWrong++;
      default:
        s.wrong++;
    }
    if (r.dangerOk) s.dangerOk++;
    if (r.qaOk) s.qaOk++;
  }
  final list = by.values.toList()
    ..sort((a, b) => '${a.network}${a.engine}'.compareTo('${b.network}${b.engine}'));
  return list;
}
