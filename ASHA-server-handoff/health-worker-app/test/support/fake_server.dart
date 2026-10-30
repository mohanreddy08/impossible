import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A small in-memory model of the backend's documented sync contract (docs/API_CONTRACT.md). It is used to test client
/// behaviour deterministically; the REAL backend is exercised separately by test/integration/real_backend_test.dart.
class FakeServer {
  final Map<String, Map<String, dynamic>> seenOps =
      {}; // op_id -> stored result (idempotency)
  final Map<String, int> versions = {};
  final List<Map<String, dynamic>> applied =
      []; // ops that actually changed server state (no duplicates)
  bool down = false; // simulate: no network
  bool dropResponses = false; // request reaches the server and is processed, but the client never gets the answer
  int httpStatus = 200;
  String? httpErrorBody;
  final Map<String, Map<String, dynamic>> forceResult =
      {}; // op_id -> result override (CONFLICT / REJECTED / FAILED_RETRYABLE)
  Map<String, List<Map<String, dynamic>>> pullData = {};
  int pushCalls = 0;
  final List<String?> pullSince = [];
  int qaCalls = 0;
  // optional AI route (POST /health-qa/llm)
  String? llmText = 'Please take her to the health centre now.';
  Duration llmDelay = Duration.zero;
  int llmStatus = 200;
  String llmErrorCode = 'LLM_UNAVAILABLE'; // the error code the AI routes answer with when llmStatus != 200
  final List<Map<String, dynamic>> llmBodies = [];
  int ragCalls = 0, ragStatus = 200;
  Map<String, dynamic>? ragReply;
  final List<Map<String, dynamic>> explainBodies =
      []; // POST /health-qa/explain: question + passages + safety_status
  Map<String, dynamic>?
  qaQuery; // JSON the server returns for POST /health-qa/query
  Map<String, dynamic>? qaRetrieve; // ... and /health-qa/retrieve
  Map<String, dynamic>? reportJson;
  List<int> reportCsv = utf8.encode('field,value\nfacility_id,FAC-1\n');
  List<int> reportPdf = utf8.encode('%PDF-1.4 fake');
  List<Map<String, dynamic>> protocolDocs = [];
  Map<String, List<Map<String, dynamic>>> protocolPassages = {};
  // offline Telugu speech model pack: file name -> bytes. Empty = the server has no pack (404).
  final Map<String, List<int>> speechFiles = {};
  String? speechShaOverride; // serve a manifest whose checksum does not match (damaged download)
  int speechFileCalls = 0;
  final List<String?> speechRanges = [];
  final List<String> requestPaths = [];
  final List<Map<String, String>> requestHeaders = [];

  MockClient client() => MockClient((req) async {
    requestPaths.add('${req.method} ${req.url.path}');
    requestHeaders.add(req.headers);
    if (down) throw http.ClientException('connection failed');
    if (httpStatus != 200) {
      return http.Response(
        httpErrorBody ??
            jsonEncode({
              'error': {'code': 'X', 'message': 'boom', 'details': null},
            }),
        httpStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    final path = req.url.path;
    if (path == '/health') return _json({'status': 'ok'});
    if (path == '/api/v1/speech-models/te') {
      if (speechFiles.isEmpty) {
        return http.Response(
          '{"error":{"code":"NOT_FOUND","message":"none"}}',
          404,
        );
      }
      return _json({
        'id': 'test-pack',
        'files': [
          for (final e in speechFiles.entries)
            {
              'name': e.key,
              'size': e.value.length,
              'sha256': speechShaOverride ?? sha256.convert(e.value).toString(),
              'url': '/api/v1/speech-models/te/files/${e.key}',
            },
        ],
      });
    }
    if (path.startsWith('/api/v1/speech-models/te/files/')) {
      speechFileCalls++;
      final bytes = speechFiles[path.split('/').last];
      if (bytes == null) return http.Response('{}', 404);
      final range = req.headers['Range'] ?? req.headers['range'];
      speechRanges.add(range);
      if (range != null) {
        final from = int.parse(
          RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
        );
        return http.Response.bytes(bytes.sublist(from), 206);
      }
      return http.Response.bytes(bytes, 200);
    }
    if (path == '/api/v1/sync/push') return _push(req);
    if (path == '/api/v1/sync/pull') return _pull(req);
    if (path == '/api/v1/health-qa/llm' ||
        path == '/api/v1/health-qa/explain') {
      final body =
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      (path.endsWith('/explain') ? explainBodies : llmBodies).add(body);
      if (llmDelay > Duration.zero) await Future<void>.delayed(llmDelay);
      if (llmStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': {'code': llmErrorCode, 'message': 'x', 'details': null},
          }),
          llmStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/explain')) {
        return _json({
          'explanation': llmText,
          'model': 'test',
          'provider': 'test',
          'clinically_validated': false,
          'disclaimer': 'x',
        });
      }
      return _json({
        'answer': llmText,
        'model': 'test',
        'clinically_validated': false,
        'disclaimer': 'x',
      });
    }
    if (path == '/api/v1/health-qa/rag') {
      ragCalls++;
      if (ragStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'NOT_FOUND', 'message': 'x', 'details': null},
          }),
          ragStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return _json(ragReply ?? {'outcome': 'NO_APPROVED_TEXT', 'sources': []});
    }
    if (path == '/api/v1/health-qa/query') {
      qaCalls++;
      return _json(qaQuery ?? {});
    }
    if (path == '/api/v1/health-qa/retrieve') return _json(qaRetrieve ?? {});
    if (path == '/api/v1/reports/summary') return _json(reportJson ?? {});
    if (path.startsWith('/api/v1/reports/')) {
      final fmt = req.url.queryParameters['format'];
      return http.Response.bytes(
        fmt == 'pdf' ? reportPdf : reportCsv,
        200,
        headers: {
          'content-type': fmt == 'pdf'
              ? 'application/pdf'
              : 'text/csv; charset=utf-8',
        },
      );
    }
    if (path == '/api/v1/protocols') {
      return _json({
        'items': protocolDocs,
        'total': protocolDocs.length,
        'limit': 50,
        'offset': 0,
      });
    }
    if (path.startsWith('/api/v1/protocols/') && path.endsWith('/passages')) {
      final l = protocolPassages[path.split('/')[4]] ?? [];
      return _json({'items': l, 'total': l.length, 'limit': 100, 'offset': 0});
    }
    return http.Response(
      '{"error":{"code":"NOT_FOUND","message":"nf","details":null}}',
      404,
      headers: {'content-type': 'application/json'},
    );
  });

  http.Response _json(Object o, [int status = 200]) => http.Response(
    jsonEncode(o),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _push(http.Request req) {
    pushCalls++;
    final body = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
    final ops = (body['operations'] as List).cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    var acked = 0;
    for (final op in ops) {
      final id = op['op_id'] as String;
      Map<String, dynamic> res;
      if (seenOps.containsKey(id) && seenOps[id]!['status'] == 'ACKNOWLEDGED') {
        res = {...seenOps[id]!, 'duplicate': true};
      } else if (forceResult.containsKey(id)) {
        res = {
          'op_id': id,
          'status': 'ACKNOWLEDGED',
          'acknowledged': false,
          'duplicate': false,
          'server_version': null,
          'error_code': null,
          'error_message': null,
          'conflict': null,
          'warnings': <String>[],
          ...forceResult[id]!,
        };
      } else {
        final key = '${op['entity_type']}:${op['entity_id']}';
        final cur =
            versions[key] ??
            (op['op_type'] == 'create' ? 0 : (op['base_version'] as int? ?? 1));
        final ver = cur + 1;
        versions[key] = ver;
        applied.add(op);
        res = {
          'op_id': id,
          'status': 'ACKNOWLEDGED',
          'acknowledged': true,
          'duplicate': false,
          'server_version': ver,
          'error_code': null,
          'error_message': null,
          'conflict': null,
          'warnings': <String>[],
        };
        seenOps[id] = res;
        acked++;
      }
      results.add(res);
    }
    if (dropResponses) {
      throw http.ClientException('connection reset after processing');
    }
    return _json({
      'received': ops.length,
      'acknowledged_count': acked,
      'results': results,
      'note': 'n',
    });
  }

  http.Response _pull(http.Request req) {
    pullSince.add(req.url.queryParameters['since']);
    final types = (req.url.queryParameters['entity_types'] ?? '').split(',');
    final out = <String, dynamic>{
      'server_time': '2026-10-13T10:00:00',
      'households': null,
      'visits': null,
      'referrals': null,
    };
    for (final t in types) {
      final key = switch (t) {
        'household' => 'households',
        'visit' => 'visits',
        _ => 'referrals',
      };
      out[key] = pullData[key] ?? <Map<String, dynamic>>[];
    }
    return _json(out);
  }
}

Map<String, dynamic> conflictResult(
  String opId, {
  int serverVersion = 3,
  Map<String, dynamic>? server,
  Map<String, dynamic>? client,
}) => {
  'op_id': opId,
  'status': 'CONFLICT',
  'acknowledged': false,
  'error_code': 'VERSION_CONFLICT',
  'error_message': 'stale update touches protected fields; not applied',
  'conflict': {
    'server_version': serverVersion,
    'base_version': 1,
    'fields': (server ?? {'referral_status': 'ATTENDANCE_CONFIRMED'}).keys
        .toList(),
    'server_values': server ?? {'referral_status': 'ATTENDANCE_CONFIRMED'},
    'client_values': client ?? {'referral_status': 'PLANNED'},
    'resolution': 'NOT_APPLIED_FLAGGED_FOR_REVIEW',
  },
};

Map<String, dynamic> qaJson(
  String outcome, {
  String message = '',
  String? answer,
  List<Map<String, dynamic>> citations = const [],
  String safety = 'NORMAL_PROTOCOL_QUERY',
  String? retrieval,
}) => {
  'query_id': 'q1',
  'outcome': outcome,
  'original_question': 'x',
  'message': message,
  'answer_text': answer,
  'citations': citations,
  'retrieval_status': retrieval,
  'safety': {
    'status': safety,
    'rule_ids': safety == 'ESCALATION_REQUIRED'
        ? ['DSR-BLEEDING-SEVERE']
        : <String>[],
    'reasons': <String>[],
    'ruleset_version': '0.1.0-draft',
    'ruleset_review_status': 'DRAFT_UNREVIEWED_NOT_CLINICALLY_APPROVED',
    'clinically_validated': false,
    'needs_human_review': false,
  },
};

Map<String, dynamic> citationJson({
  String status = 'VERIFIED',
  String doc = 'DOC-1',
  String title = 'Sample Protocol',
  String section = '2.1',
  String heading = 'Visit schedule',
  int page = 12,
  String version = 'v3',
}) => {
  'passage_id': '$doc-0001',
  'document_id': doc,
  'document_title': title,
  'section_id': section,
  'section_heading': heading,
  'page_number': page,
  'source_version': version,
  'relevance_score': 0.9,
  'source_verification_status': status,
};
