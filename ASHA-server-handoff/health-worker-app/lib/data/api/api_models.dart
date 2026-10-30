// Typed views of the backend's JSON (see health-worker-backend/docs/openapi.json). Parsing is strict: a missing or
// mistyped required field throws, which the client reports as InvalidResponse (never a half-filled object).
import '../models/household.dart';
import '../models/referral.dart';
import '../models/visit.dart';

class Citation {
  const Citation({
    required this.passageId,
    required this.documentId,
    this.documentTitle,
    this.sectionId,
    this.sectionHeading,
    this.pageNumber,
    this.sourceVersion,
    required this.relevanceScore,
    required this.verificationStatus,
  });
  final String passageId, documentId, verificationStatus;
  final String? documentTitle, sectionId, sectionHeading, sourceVersion;
  final int? pageNumber;
  final double relevanceScore;

  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
    passageId: j['passage_id'] as String,
    documentId: j['document_id'] as String,
    documentTitle: j['document_title'] as String?,
    sectionId: j['section_id'] as String?,
    sectionHeading: j['section_heading'] as String?,
    pageNumber: j['page_number'] as int?,
    sourceVersion: j['source_version'] as String?,
    relevanceScore: (j['relevance_score'] as num).toDouble(),
    verificationStatus: j['source_verification_status'] as String,
  );
}

class SafetyInfo {
  const SafetyInfo({
    required this.status,
    required this.ruleIds,
    required this.reasons,
    required this.rulesetVersion,
    required this.reviewStatus,
    required this.clinicallyValidated,
    required this.needsHumanReview,
  });
  final String status, rulesetVersion, reviewStatus;
  final List<String> ruleIds, reasons;
  final bool clinicallyValidated, needsHumanReview;

  factory SafetyInfo.fromJson(Map<String, dynamic> j) => SafetyInfo(
    status: j['status'] as String,
    ruleIds: List<String>.from(j['rule_ids'] as List),
    reasons: List<String>.from(j['reasons'] as List),
    rulesetVersion: j['ruleset_version'] as String,
    reviewStatus: j['ruleset_review_status'] as String,
    clinicallyValidated: (j['clinically_validated'] as bool?) ?? false,
    needsHumanReview: j['needs_human_review'] as bool,
  );
}

class QaResponse {
  const QaResponse({
    required this.outcome,
    required this.message,
    this.answerText,
    required this.citations,
    required this.safety,
    this.retrievalStatus,
  });
  final String outcome, message;
  final String? answerText, retrievalStatus;
  final List<Citation> citations;
  final SafetyInfo safety;

  factory QaResponse.fromJson(Map<String, dynamic> j) => QaResponse(
    outcome: j['outcome'] as String,
    message: j['message'] as String,
    answerText: j['answer_text'] as String?,
    citations: [
      for (final c in j['citations'] as List)
        Citation.fromJson(c as Map<String, dynamic>),
    ],
    safety: SafetyInfo.fromJson(j['safety'] as Map<String, dynamic>),
    retrievalStatus: j['retrieval_status'] as String?,
  );
}

class RetrievedPassage {
  const RetrievedPassage(this.citation, this.text);
  final Citation citation;
  final String text;
}

class RetrieveResponse {
  const RetrieveResponse(this.status, this.matches);
  final String status;
  final List<RetrievedPassage> matches;
  factory RetrieveResponse.fromJson(Map<String, dynamic> j) =>
      RetrieveResponse(j['status'] as String, [
        for (final m in j['matches'] as List)
          RetrievedPassage(
            Citation.fromJson(m as Map<String, dynamic>),
            m['text'] as String,
          ),
      ]);
}

class PullResponse {
  const PullResponse({
    required this.serverTime,
    this.households,
    this.visits,
    this.referrals,
  });
  final String serverTime;
  final List<Household>? households;
  final List<Visit>? visits;
  final List<Referral>? referrals;

  factory PullResponse.fromJson(Map<String, dynamic> j) => PullResponse(
    serverTime: j['server_time'] as String,
    households: (j['households'] as List?)
        ?.map((e) => Household.fromJson(e as Map<String, dynamic>))
        .toList(),
    visits: (j['visits'] as List?)
        ?.map((e) => Visit.fromJson(e as Map<String, dynamic>))
        .toList(),
    referrals: (j['referrals'] as List?)
        ?.map((e) => Referral.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class PushResult {
  const PushResult({
    this.opId,
    required this.status,
    required this.acknowledged,
    required this.duplicate,
    this.serverVersion,
    this.errorCode,
    this.errorMessage,
    this.conflict,
    required this.warnings,
  });
  final String? opId, errorCode, errorMessage;
  final String status; // ACKNOWLEDGED | REJECTED | CONFLICT | FAILED_RETRYABLE
  final bool acknowledged, duplicate;
  final int? serverVersion;
  final Map<String, dynamic>? conflict;
  final List<String> warnings;

  factory PushResult.fromJson(Map<String, dynamic> j) => PushResult(
    opId: j['op_id'] as String?,
    status: j['status'] as String,
    acknowledged: j['acknowledged'] as bool,
    duplicate: j['duplicate'] as bool,
    serverVersion: j['server_version'] as int?,
    errorCode: j['error_code'] as String?,
    errorMessage: j['error_message'] as String?,
    conflict: j['conflict'] as Map<String, dynamic>?,
    warnings: List<String>.from(j['warnings'] as List),
  );
}

class PushResponse {
  const PushResponse(this.received, this.acknowledgedCount, this.results);
  final int received, acknowledgedCount;
  final List<PushResult> results;
  factory PushResponse.fromJson(Map<String, dynamic> j) =>
      PushResponse(j['received'] as int, j['acknowledged_count'] as int, [
        for (final r in j['results'] as List)
          PushResult.fromJson(r as Map<String, dynamic>),
      ]);
}

class ServerReport {
  const ServerReport({
    required this.reportId,
    required this.facilityId,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAt,
    this.dataAsOf,
    this.lastSyncAt,
    required this.freshness,
    required this.recommended,
    required this.planned,
    required this.attendanceConfirmed,
    required this.total,
    required this.byCategory,
    required this.excluded,
    required this.followUpsDue,
    required this.followUpsCompleted,
    required this.privacyNotice,
    this.supersededBy,
    required this.duplicateOfExisting,
  });
  final String reportId,
      facilityId,
      periodStart,
      periodEnd,
      generatedAt,
      freshness,
      privacyNotice;
  final String? dataAsOf, lastSyncAt, supersededBy;
  final int recommended,
      planned,
      attendanceConfirmed,
      total,
      followUpsDue,
      followUpsCompleted;
  final Map<String, int> byCategory, excluded;
  final bool duplicateOfExisting;

  factory ServerReport.fromJson(Map<String, dynamic> j) {
    final c = j['counts'] as Map<String, dynamic>;
    final f = j['follow_ups'] as Map<String, dynamic>;
    Map<String, int> ints(Object? o) => {
      for (final e in (o as Map<String, dynamic>).entries)
        e.key: e.value as int,
    };
    return ServerReport(
      reportId: j['report_id'] as String,
      facilityId: j['facility_id'] as String,
      periodStart: j['period_start'] as String,
      periodEnd: j['period_end'] as String,
      generatedAt: j['generated_at'] as String,
      dataAsOf: j['data_as_of'] as String?,
      lastSyncAt: j['last_sync_at'] as String?,
      freshness: j['data_freshness_label'] as String,
      recommended: c['recommended'] as int,
      planned: c['planned'] as int,
      attendanceConfirmed: c['attendance_confirmed'] as int,
      total: c['total_included'] as int,
      byCategory: ints(j['counts_by_service_category']),
      excluded: ints(j['excluded_counts']),
      followUpsDue: f['due'] as int,
      followUpsCompleted: f['completed_in_period'] as int,
      privacyNotice: j['privacy_notice'] as String,
      supersededBy: j['superseded_by'] as String?,
      duplicateOfExisting: (j['duplicate_of_existing'] as bool?) ?? false,
    );
  }
}

class ProtocolDocInfo {
  const ProtocolDocInfo({
    required this.documentId,
    this.title,
    this.issuingAuthority,
    this.version,
    required this.verificationStatus,
    required this.approved,
    this.language,
    this.publicationDate,
  });
  final String documentId, verificationStatus;
  final String? title, issuingAuthority, version, language, publicationDate;
  final bool approved;
  factory ProtocolDocInfo.fromJson(Map<String, dynamic> j) => ProtocolDocInfo(
    documentId: j['document_id'] as String,
    title: j['title'] as String?,
    issuingAuthority: j['issuing_authority'] as String?,
    version: j['version'] as String?,
    verificationStatus: j['source_verification_status'] as String,
    approved: j['approved_for_retrieval'] as bool,
    language: j['language'] as String?,
    publicationDate: j['publication_date'] as String?,
  );
}

class ProtocolPassageInfo {
  const ProtocolPassageInfo({
    required this.passageId,
    required this.documentId,
    this.sectionId,
    this.sectionTitle,
    this.pageNumber,
    required this.text,
    required this.verificationStatus,
    this.language,
  });
  final String passageId, documentId, text, verificationStatus;
  final String? sectionId, sectionTitle, language;
  final int? pageNumber;
  factory ProtocolPassageInfo.fromJson(Map<String, dynamic> j) =>
      ProtocolPassageInfo(
        passageId: j['passage_id'] as String,
        documentId: j['document_id'] as String,
        sectionId: j['section_id'] as String?,
        sectionTitle: j['section_title'] as String?,
        pageNumber: j['page_number'] as int?,
        text: j['passage_text'] as String,
        verificationStatus: j['source_verification_status'] as String,
        language: j['language'] as String?,
      );
}

class Page<T> {
  const Page(this.items, this.total, this.limit, this.offset);
  final List<T> items;
  final int total, limit, offset;
}
