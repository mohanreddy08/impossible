import '../domain/retrieval/local_retrieval.dart';
import 'qa_service.dart';

/// How serious the phone's own rules say the situation is. It is decided ONLY by the deterministic safety rules (never by an AI):
///   high   - a possible danger sign: show the alert and the escalation steps
///   medium - the description is unclear: ask for the missing details
///   low    - no danger sign found in what was written: show the information
/// "low" is not a medical all-clear: the rules are drafts and say so on screen.
enum Severity { low, medium, high }

/// What the screen does about it.
enum SeverityAction { showInfo, askForDetails, alertAndEscalate }

Severity? severityOf(QaOutcome o) => switch (o) {
  QaOutcome.escalationRequired => Severity.high,
  QaOutcome.clarificationRequired => Severity.medium,
  QaOutcome.answeredWithEvidence => Severity.low,
  _ => null,
};

SeverityAction actionFor(Severity s) => switch (s) {
  Severity.low => SeverityAction.showInfo,
  Severity.medium => SeverityAction.askForDetails,
  Severity.high => SeverityAction.alertAndEscalate,
};

/// Where the explanation text came from. Both give the same kind of output: a short explanation of the question.
/// `serverText` = the server's retrieval found the answer and it is the approved passage itself, word for word.
enum ExplanationSource { server, serverText, device }

/// Why the phone used its own explainer although the AI server was meant to be asked (nothing is shown for the normal offline case).
/// `rejected` = the server answered but refused its own text (wrong language, left the passages, or named a dose/medicine).
enum FallbackReason { none, timeout, unreachable, unsafe, rejected }

class Explanation {
  const Explanation({
    required this.text,
    required this.source,
    this.severity,
    this.fallback = FallbackReason.none,
  });
  final String text;
  final ExplanationSource source;
  final Severity? severity;
  final FallbackReason fallback;
}

/// The lightweight explainer that runs on the phone with no network. It does not generate text: it picks the sentences of the
/// closest approved passages that best match the question and lays them out as a short list. Every word is therefore taken from
/// approved text; nothing is invented, and it works the same with or without internet.
class OfflineExplainer {
  const OfflineExplainer({this.maxSentences = 3, this.maxChars = 600});
  final int maxSentences, maxChars;

  static final _split = RegExp(r'(?<=[.!?।])\s+|\n+');

  /// "" when there are no passages.
  String explain(String question, List<Evidence> evidence) {
    if (evidence.isEmpty) return '';
    final q = tokenizeText(question)
        .where((t) => !isStopWord(t) && t.length > 1)
        .toSet();
    final lines = <String>[];
    for (var i = 0; i < evidence.length && i < 2; i++) {
      final sentences = [
        for (final s in evidence[i].passageText.split(_split))
          if (s.trim().length > 1) s.trim(),
      ];
      if (sentences.isEmpty) continue;
      final scored = [
        for (var k = 0; k < sentences.length; k++)
          (index: k, score: _score(q, sentences[k])),
      ];
      final take = i == 0
          ? maxSentences - 1
          : 1; // the best passage gets most of the room
      final best = [...scored.where((e) => e.score > 0)]
        ..sort(
          (a, b) => b.score != a.score
              ? b.score.compareTo(a.score)
              : a.index.compareTo(b.index),
        );
      var chosen = [for (final e in best.take(take)) e.index];
      if (chosen.isEmpty && i == 0) {
        chosen = [for (var k = 0; k < sentences.length && k < take; k++) k];
      }
      chosen.sort(); // keep the order of the original text
      for (final k in chosen) {
        if (!lines.contains(sentences[k])) lines.add(sentences[k]);
      }
    }
    final body = StringBuffer();
    for (final l in lines.take(maxSentences)) {
      final next = '• $l';
      if (body.isNotEmpty && body.length + next.length + 1 > maxChars) break;
      if (body.isNotEmpty) body.write('\n');
      body.write(next.length > maxChars ? next.substring(0, maxChars) : next);
    }
    final title = evidence.first.sectionTitle?.trim();
    return title == null || title.isEmpty ? '$body' : '$title\n$body';
  }

  /// How many question words the sentence contains. A shared start of 4+ letters counts (plurals, Telugu word endings).
  static int _score(Set<String> q, String sentence) {
    final words = tokenizeText(sentence).toSet();
    var n = 0;
    for (final w in q) {
      final hit = words.any((x) {
        if (x == w) return true;
        final m = x.length < w.length ? x.length : w.length;
        return m >= 4 && (x.startsWith(w) || w.startsWith(x));
      });
      if (hit) n++;
    }
    return n;
  }
}
