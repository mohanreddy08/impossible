import 'dart:async';

import '../data/api/api_client.dart';
import '../data/api/api_exceptions.dart';
import '../data/api/api_models.dart';
import '../domain/retrieval/local_retrieval.dart';
import '../domain/safety/safety_engine.dart';
import '../h5/h5_pipeline.dart';
import 'explainer.dart';
import 'record_answers.dart';

/// What the screen may show. `cannotVerifyOffline` is a UI-side state (no backend outcome of that name): the device had
/// no approved evidence and no server was reachable, so NOTHING can be claimed.
enum QaOutcome {
  answeredWithEvidence,
  escalationRequired,
  clarificationRequired,
  outOfScope,
  insufficientEvidence,
  cannotVerifyOffline,
  answeredFromRecords,
}

QaOutcome qaOutcomeFromBackend(String s) => switch (s) {
  'ANSWERED_WITH_EVIDENCE' => QaOutcome.answeredWithEvidence,
  'ESCALATION_REQUIRED' => QaOutcome.escalationRequired,
  'CLARIFICATION_REQUIRED' => QaOutcome.clarificationRequired,
  'OUT_OF_SCOPE' => QaOutcome.outOfScope,
  _ => QaOutcome.insufficientEvidence,
};

class Evidence {
  const Evidence({
    required this.documentTitle,
    required this.documentId,
    this.sectionTitle,
    this.sectionId,
    this.pageNumber,
    this.version,
    required this.verificationStatus,
    required this.passageText,
    this.score,
  });
  final String documentId, verificationStatus, passageText;
  final String? documentTitle, sectionTitle, sectionId, version;
  final int? pageNumber;
  final double? score;

  /// Only VERIFIED evidence may be styled as verified guidance. Anything else (e.g. test fixtures on a dev server) is shown as unverified.
  bool get isVerified => verificationStatus == 'VERIFIED';
}

class QaResult {
  const QaResult({
    required this.outcome,
    required this.message,
    this.evidence = const [],
    this.ruleIds = const [],
    this.reasons = const [],
    required this.rulesetVersion,
    this.clinicallyValidated = false,
    this.needsHumanReview = false,
    required this.fromDevice,
    this.noServerConfigured = false,
    this.records,
  });
  final QaOutcome outcome;
  final String message, rulesetVersion;
  final List<Evidence> evidence;
  final RecordAnswer? records;
  final List<String> ruleIds, reasons;
  final bool clinicallyValidated,
      needsHumanReview,
      fromDevice,
      noServerConfigured;
}

class QuestionInvalid implements Exception {
  QuestionInvalid(this.reason);
  final String reason; // empty | tooLong
}

/// Orchestrates: validate -> LOCAL deterministic safety (always, works offline) -> if not NORMAL stop and show it ->
/// local approved evidence -> else ask the server (which re-runs ITS safety first and may escalate) -> else "cannot verify".
/// [explain] then turns the closest approved passages into a short explanation: by the nearby server's LLM when online, by the
/// phone's own [OfflineExplainer] otherwise or when the server is slow (10 s) or fails. The question text is never stored or logged.
class QaService {
  QaService({
    required this.engine,
    required this.api,
    required this.loadIndex,
    this.h5,
    this.records,
    this.now,
    this.language,
    this.aiAssist,
    this.explainTimeout = defaultExplainTimeout,
    this.minScore = 0.5,
    this.minTerms = 2,
  });
  final SafetyEngine engine;
  final ApiClient api;
  final Future<LocalRetrieval> Function() loadIndex;
  final RecordAnswerer? records;

  /// The protocol-book engine (danger signs, refusal, cited answers, all on the phone). null = not used.
  final Future<H5Assistant> Function()? h5;

  final DateTime Function()? now;

  /// The app language ('en' / 'te'): when two passages are equally good, the one in this language is shown.
  final String Function()? language;

  /// Whether the optional online helpers (server /query fallback, AI box) may be used. null = yes (older callers). When false the
  /// result depends only on the phone's own rules and library, so it is identical online and offline.
  final bool Function()? aiAssist;
  bool get _assist => aiAssist?.call() ?? true;
  final double minScore;
  final int minTerms;

  /// Every request to the server gives up after this long; the phone then explains it itself.
  static const defaultExplainTimeout = Duration(seconds: 10);
  final Duration explainTimeout;

  /// Longest AI text the phone will show.
  static const aiMaxChars = 1500;

  static const _explainer = OfflineExplainer();

  static final _dose = RegExp(
    r'\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|ml|g|iu|units?|drops?|tablets?|tabs?|capsules?|sachets?|spoons?|teaspoons?)\b',
    caseSensitive: false,
  );
  static final _medicine = RegExp(
    r'\b(?:tablets?|capsules?|syrup|injection|dosage|doses?|antibiotics?|paracetamol|acetaminophen|ibuprofen|aspirin|amoxicillin|azithromycin|ciprofloxacin|metronidazole|diclofenac|cetirizine|prednisolone)\b|మాత్ర|మోతాదు|సిరప్|ఇంజెక్షన్|యాంటీబయాటిక్',
    caseSensitive: false,
  );

  /// The phone never trusts a server's (or a nearby device's) text: an answer that names a medicine, a dose or a tablet count is dropped
  /// here as well as on the server (defence in depth). The prompt tells the model not to, but a prompt is only a request.
  static bool unsafeAiText(String t) =>
      _dose.hasMatch(t) || _medicine.hasMatch(t);

  /// The Ask pipeline's last step, after the phone's own search found approved passages ([result].evidence):
  ///  * online, AI help on, a server set: send the question and the passages to the server's LLM, waiting at most [timeout];
  ///  * otherwise (offline, AI help off, no server, slow or failing server, unsafe text): the phone's [OfflineExplainer].
  /// Both give the same kind of result (a short explanation), with the severity decided by the phone's rules. Returns null when there
  /// are no approved passages to explain: nothing is explained from nothing. Never throws.
  Future<Explanation?> explain(
    String question,
    QaResult result, {
    bool online = true,
    Duration? timeout,
  }) async {
    if (result.evidence.isEmpty) return null;
    final sev = severityOf(result.outcome);
    final q = validate(question);
    Explanation device([FallbackReason why = FallbackReason.none]) =>
        Explanation(
          text: _explainer.explain(q, result.evidence),
          source: ExplanationSource.device,
          severity: sev,
          fallback: why,
        );
    if (!_assist || !online) return device();
    try {
      if (!await api.hasServer()) return device();
      final status = result.outcome == QaOutcome.escalationRequired
          ? statusEscalation
          : statusNormal;
      var text = await api
          .explain(q, [
            for (final e in result.evidence.take(3))
              (
                id: e.sectionId ?? e.documentId,
                title: e.sectionTitle ?? e.documentTitle,
                text: e.passageText.length > 1500
                    ? e.passageText.substring(0, 1500)
                    : e.passageText,
              ),
          ], status)
          .timeout(timeout ?? explainTimeout);
      if (text.length > aiMaxChars) text = text.substring(0, aiMaxChars);
      // the phone never trusts a server's text: a dose or a medicine name means the phone explains it from the approved text instead
      if (unsafeAiText(text)) return device(FallbackReason.unsafe);
      return Explanation(
        text: text,
        source: ExplanationSource.server,
        severity: sev,
      );
    } on TimeoutException {
      return device(FallbackReason.timeout);
    } on RequestTimeout {
      return device(FallbackReason.timeout);
    } on ServerError catch (e) {
      // the server is there but its guards refused the model's text: say so, not "could not be reached"
      return device(
        _refusedByServer.contains(e.code)
            ? FallbackReason.rejected
            : FallbackReason.unreachable,
      );
    } on Object {
      return device(FallbackReason.unreachable);
    }
  }

  /// The server-side RAG step (Telugu and English). Called AFTER the phone's own rules and search, only when the phone found nothing
  /// or only a weak match and a server is set. The server finds the approved passages with a multilingual embedding model and answers
  /// from them; the result replaces the phone's evidence and explanation. Returns null (the phone's own result stays) when offline,
  /// AI help is off, no server is set, the server is old, slow, refuses, has no approved text, or its text names a dose or medicine.
  /// A danger sign or an unclear description is never sent here: those stay with the phone's own rules. Never throws.
  Future<({QaResult result, Explanation? explanation})?> ragAnswer(
    String question,
    QaResult local, {
    bool online = true,
    Duration? timeout,
  }) async {
    if (!_assist || !online) return null;
    if (local.outcome != QaOutcome.answeredWithEvidence &&
        local.outcome != QaOutcome.insufficientEvidence) {
      return null;
    }
    try {
      final q = validate(question);
      if (!await api.hasServer()) return null;
      final r = await api.rag(q).timeout(timeout ?? explainTimeout);
      if (!r.answered && !r.escalated) return null;
      if (r.escalated) {
        // the server's closest approved passage is a DANGER-SIGN passage although the phone's word rules found no danger phrase
        // (a spelling slip or a spoken variant): show the alert, never "low"
        return (
          result: QaResult(
            outcome: QaOutcome.escalationRequired,
            message: r.message,
            evidence: _ragEvidence(r),
            ruleIds: r.ruleIds,
            rulesetVersion: local.rulesetVersion,
            fromDevice: false,
          ),
          explanation: null,
        );
      }
      var text = r.answer!.trim();
      if (text.length > aiMaxChars) text = text.substring(0, aiMaxChars);
      if (unsafeAiText(text)) return null;
      final evidence = _ragEvidence(r);
      return (
        result: QaResult(
          outcome: QaOutcome.answeredWithEvidence,
          message: '',
          evidence: evidence,
          rulesetVersion: local.rulesetVersion,
          clinicallyValidated: false,
          fromDevice: false,
        ),
        explanation: Explanation(
          text: text,
          source: r.answerSource == 'llm'
              ? ExplanationSource.server
              : ExplanationSource.serverText,
          severity: Severity.low,
        ),
      );
    } on Object {
      return null;
    }
  }

  List<Evidence> _ragEvidence(RagResponse r) => [
    for (final s in r.sources)
      Evidence(
        documentTitle: s.documentTitle,
        documentId: s.documentId,
        sectionTitle: s.sectionHeading,
        sectionId: s.sectionId,
        pageNumber: s.pageNumber,
        version: s.sourceVersion,
        verificationStatus: s.verificationStatus,
        passageText: s.text,
        score: s.score,
      ),
  ];

  static const _refusedByServer = {
    'LLM_WRONG_LANGUAGE',
    'LLM_NOT_GROUNDED',
    'LLM_UNSAFE_OUTPUT',
  };

  static String validate(String q) {
    final t = q
        .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
        .trim();
    if (t.isEmpty) throw QuestionInvalid('empty');
    if (t.length > 2000) throw QuestionInvalid('tooLong');
    return t;
  }

  static const h5Version = 'h5-protocol-book-1.0';

  /// The protocol-book engine's answer, or null when it is off or fails. Never throws; the phone's other rules still apply.
  Future<(H5Assistant, H5Answer)?> _h5Answer(String q) async {
    if (h5 == null) return null;
    try {
      final a = await h5!();
      return (a, a.answer('ask', q));
    } on Object {
      return null;
    }
  }

  List<Evidence> _h5Evidence(H5Assistant a, H5Answer r) => [
    for (final p in a.passages(r))
      Evidence(
        documentTitle: p.documentTitle,
        documentId: p.sectionId.split('-').first,
        sectionTitle: p.sectionTitle,
        sectionId: p.sectionId,
        verificationStatus: 'VERIFIED', // the official protocol pack
        passageText: p.text,
      ),
  ];

  Future<QaResult> ask(String question) async {
    final q = validate(question);
    final d = engine.evaluate(q);
    final h = await _h5Answer(q);
    // a danger sign found by the protocol book wins over a 'please add detail' or 'out of scope' from the phone's word rules
    final h5Danger = h != null && h.$2.escalate;
    if (d.status != statusNormal && !(h5Danger && d.status != statusEscalation)) {
      // A danger sign is never answered, but APPROVED protocol text (verified passages only, from the phone's own library)
      // may be shown beside it. If none is loaded the screen says so; nothing is ever made up.
      var support = <Evidence>[];
      if (d.status == statusEscalation && h != null && h.$2.escalate) {
        support = _h5Evidence(h.$1, h.$2);
      } else if (d.status == statusEscalation) {
        try {
          final idx = await loadIndex();
          support = [
            for (final h in idx.search(
              q,
              minScore: minScore,
              minMatchedTerms: minTerms,
              preferLang: language?.call(),
            ))
              _ev(h),
          ];
        } on Object {
          support = [];
        }
      }
      return QaResult(
        evidence: support,
        outcome: switch (d.status) {
          statusEscalation => QaOutcome.escalationRequired,
          statusClarification => QaOutcome.clarificationRequired,
          _ => QaOutcome.outOfScope,
        },
        message: d.message ?? '',
        ruleIds: d.ruleIds,
        reasons: d.reasons,
        rulesetVersion: d.rulesetVersion,
        clinicallyValidated: d.clinicallyValidated,
        needsHumanReview: d.needsHumanReview,
        fromDevice: true,
      );
    }
    if (h != null && h.$2.escalate) {
      // the phone's word rules found nothing, the protocol book's danger-sign layer did: a danger sign is never answered
      return QaResult(
        outcome: QaOutcome.escalationRequired,
        message: h5EscPrefix.trim(),
        evidence: _h5Evidence(h.$1, h.$2),
        ruleIds: h.$2.rules,
        reasons: [for (final r in h.$2.rules) r.replaceAll('-', ' ')],
        rulesetVersion: h5Version,
        fromDevice: true,
      );
    }
    final fromRecords = await records?.answer(q);
    if (fromRecords != null) {
      return QaResult(
        outcome: QaOutcome.answeredFromRecords,
        message: '',
        records: fromRecords,
        rulesetVersion: d.rulesetVersion,
        clinicallyValidated: d.clinicallyValidated,
        fromDevice: true,
      );
    }
    if (h != null && h.$2.refused) {
      return QaResult(
        outcome: QaOutcome.outOfScope,
        message: h5RefuseText,
        ruleIds: const ['SCP-1.2'],
        rulesetVersion: h5Version,
        fromDevice: true,
      );
    }
    if (h != null && h.$2.cited.isNotEmpty) {
      final ev = _h5Evidence(h.$1, h.$2);
      if (ev.isNotEmpty && ev.any((e) => e.passageText.isNotEmpty)) {
        return QaResult(
          outcome: QaOutcome.answeredWithEvidence,
          message: '',
          evidence: ev,
          rulesetVersion: h5Version,
          fromDevice: true,
        );
      }
    }
    final idx = await loadIndex();
    final hits = idx.search(
      q,
      minScore: minScore,
      minMatchedTerms: minTerms,
      preferLang: language?.call(),
    );
    if (hits.isNotEmpty) {
      return QaResult(
        outcome: QaOutcome.answeredWithEvidence,
        message: '',
        evidence: [for (final h in hits) _ev(h)],
        rulesetVersion: d.rulesetVersion,
        clinicallyValidated: d.clinicallyValidated,
        fromDevice: true,
      );
    }
    if (!_assist) {
      // same answer online and offline: no approved passage on the phone means "nothing found", never a network-dependent state
      return QaResult(
        outcome: QaOutcome.insufficientEvidence,
        message: '',
        rulesetVersion: d.rulesetVersion,
        clinicallyValidated: d.clinicallyValidated,
        fromDevice: true,
      );
    }
    try {
      final r = await api.query(q);
      final outcome = qaOutcomeFromBackend(r.outcome);
      var evidence = <Evidence>[];
      if (outcome == QaOutcome.answeredWithEvidence) {
        try {
          final rr = await api.retrieve(q);
          evidence = [
            for (final m in rr.matches) _evServer(m.citation, m.text),
          ];
        } on ApiException {
          // the answer text itself carries the verbatim passage; show it as the single supporting text
          evidence = [
            for (final c in r.citations.take(1))
              _evServer(c, r.answerText ?? ''),
          ];
        }
        if (evidence.isEmpty) {
          return QaResult(
            outcome: QaOutcome.insufficientEvidence,
            message: r.message,
            rulesetVersion: r.safety.rulesetVersion,
            fromDevice: false,
          );
        }
      }
      return QaResult(
        outcome: outcome,
        message: r.message,
        evidence: evidence,
        ruleIds: r.safety.ruleIds,
        reasons: r.safety.reasons,
        rulesetVersion: r.safety.rulesetVersion,
        clinicallyValidated: r.safety.clinicallyValidated,
        needsHumanReview: r.safety.needsHumanReview,
        fromDevice: false,
      );
    } on NotConfigured {
      return _cannot(d, noServer: true);
    } on NetworkUnavailable {
      return _cannot(d);
    } on RequestTimeout {
      return _cannot(d);
    }
  }

  QaResult _cannot(SafetyDecision d, {bool noServer = false}) => QaResult(
    noServerConfigured: noServer,
    outcome: QaOutcome.cannotVerifyOffline,
    message: '',
    rulesetVersion: d.rulesetVersion,
    clinicallyValidated: d.clinicallyValidated,
    fromDevice: true,
  );

  Evidence _ev(LocalMatch m) => Evidence(
    documentTitle: m.passage.documentTitle,
    documentId: m.passage.documentId,
    sectionTitle: m.passage.sectionTitle,
    sectionId: m.passage.sectionId,
    pageNumber: m.passage.pageNumber,
    version: m.passage.documentVersion,
    verificationStatus: m.passage.verificationStatus,
    passageText: m.passage.text,
    score: m.score,
  );

  Evidence _evServer(Citation c, String text) => Evidence(
    documentTitle: c.documentTitle,
    documentId: c.documentId,
    sectionTitle: c.sectionHeading,
    sectionId: c.sectionId,
    pageNumber: c.pageNumber,
    version: c.sourceVersion,
    verificationStatus: c.verificationStatus,
    passageText: text,
    score: c.relevanceScore,
  );
}
