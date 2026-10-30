// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exceptions.dart';
import 'api_models.dart';

class ApiConfig {
  const ApiConfig(this.baseUrl, this.apiKey);
  final String baseUrl;
  final String? apiKey;
}

typedef ConfigProvider = Future<ApiConfig?> Function();

/// Typed client for the FastAPI backend (contract: health-worker-backend/docs/API_CONTRACT.md).
/// * base URL and key come from [ConfigProvider] (Settings + secure storage), never from source code;
/// * request/response BODIES, query strings and the API key are never logged: only "METHOD /path -> status";
/// * the installation id travels in the push body or the X-Installation-Id header, never in a URL.
class ApiClient {
  ApiClient({
    required http.Client client,
    required ConfigProvider config,
    this.timeout = const Duration(seconds: 15),
    this.bodyTimeout = const Duration(seconds: 60),
    void Function(String)? log,
  }) : _client = client,
       _config = config,
       _log = log;

  final http.Client _client;
  final ConfigProvider _config;
  final Duration timeout;

  /// Upper limit for reading the response AFTER the server has started answering: a slow 2G download may take a while, but a
  /// connection that stalls part-way must not leave a sync hanging for ever.
  final Duration bodyTimeout;
  final void Function(String)? _log;

  /// A short, one-way tag for "which server + which login" this client uses (never the key itself). The sync engine compares it
  /// with the one used last time: a different login or server means the saved sync position no longer applies.
  Future<String?> identity() async {
    final c = await _config();
    if (c == null || c.baseUrl.trim().isEmpty) return null;
    var h = 0xcbf29ce484222325; // FNV-1a, 64 bit
    for (final u in '${c.baseUrl.trim()}|${c.apiKey ?? ''}'.codeUnits) {
      h = ((h ^ u) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return h.toRadixString(16);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    Duration? timeoutOverride,
  }) async {
    final res = await _raw(
      method,
      path,
      query: query,
      body: body,
      headers: headers,
      timeoutOverride: timeoutOverride,
    );
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const InvalidResponse();
      return decoded;
    } on FormatException {
      throw const InvalidResponse('server did not return JSON');
    }
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    Duration? timeoutOverride,
  }) async {
    final cfg = await _config();
    if (cfg == null || cfg.baseUrl.trim().isEmpty) throw const NotConfigured();
    final base = Uri.tryParse(
      cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
    );
    if (base == null ||
        !(base.scheme == 'http' || base.scheme == 'https') ||
        base.host.isEmpty) {
      throw const NotConfigured();
    }
    final uri = base.replace(
      path: '${base.path}$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    final req = http.Request(method, uri)
      ..headers['accept'] = 'application/json'
      ..headers.addAll(headers ?? const {});
    if (cfg.apiKey != null && cfg.apiKey!.isNotEmpty) {
      req.headers['X-API-Key'] = cfg.apiKey!;
    }
    if (body != null) {
      req.headers['content-type'] = 'application/json; charset=utf-8';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      final streamed = await _client
          .send(req)
          .timeout(timeoutOverride ?? timeout);
      res = await http.Response.fromStream(streamed).timeout(bodyTimeout);
    } on TimeoutException {
      _log?.call('$method $path -> timeout');
      throw const RequestTimeout();
    } on SocketException {
      _log?.call('$method $path -> no network');
      throw const NetworkUnavailable();
    } on http.ClientException {
      _log?.call('$method $path -> client error');
      throw const NetworkUnavailable();
    }
    _log?.call('$method $path -> ${res.statusCode}');
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw _errorFrom(res);
  }

  ApiException _errorFrom(http.Response res) {
    String code = 'HTTP_${res.statusCode}', msg = 'request failed';
    Object? details;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final e = (j as Map<String, dynamic>)['error'] as Map<String, dynamic>;
      code = e['code'] as String;
      msg = e['message'] as String;
      details = e['details'];
    } catch (_) {
      /* non-standard error body: keep generic text */
    }
    switch (res.statusCode) {
      case 401:
        return Unauthorized(msg);
      case 403:
        return Forbidden(msg);
      case 404:
        return NotFoundError(msg);
      case 409:
        return ConflictError(msg, code: code);
      case 422:
        return ValidationFailed(msg, code: code, details: details);
    }
    return ServerError(res.statusCode, msg, code: code);
  }

  T _parse<T>(T Function() f) {
    try {
      return f();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const InvalidResponse();
    }
  }

  // ------------------------------------------------------------------ offline Telugu speech model (downloaded once)
  /// Manifest of the model pack: files with size and SHA-256. The caller verifies every file after download.
  Future<Map<String, dynamic>> speechModelManifest() async {
    final j = await _send(
      'GET',
      '/api/v1/speech-models/te',
      timeoutOverride: const Duration(seconds: 20),
    );
    if (j['files'] is! List) throw const InvalidResponse();
    return j;
  }

  /// Streams one model file to [out], appending when [out] already holds a partial download (HTTP Range), so an interrupted
  /// download on a weak connection continues instead of starting again. [onBytes] gets the total bytes now in [out].
  /// Never held in memory: model files are large.
  Future<void> downloadFile(
    String path,
    File out, {
    void Function(int bytes)? onBytes,
  }) async {
    final cfg = await _config();
    if (cfg == null || cfg.baseUrl.trim().isEmpty) throw const NotConfigured();
    final base = Uri.tryParse(
      cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
    );
    if (base == null ||
        !(base.scheme == 'http' || base.scheme == 'https') ||
        base.host.isEmpty) {
      throw const NotConfigured();
    }
    final have = out.existsSync() ? out.lengthSync() : 0;
    final req = http.Request('GET', base.replace(path: '${base.path}$path'));
    if (cfg.apiKey != null && cfg.apiKey!.isNotEmpty) {
      req.headers['X-API-Key'] = cfg.apiKey!;
    }
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    try {
      final res = await _client.send(req).timeout(timeout);
      _log?.call('GET $path -> ${res.statusCode}');
      if (res.statusCode == 401) throw const Unauthorized('not allowed');
      if (res.statusCode == 404) throw const NotFoundError('not found');
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.stream.drain<void>();
        throw ServerError(res.statusCode, 'download failed');
      }
      // 200 = the server ignored Range: start the file again. 206 = continue from what is already there.
      final append = res.statusCode == 206;
      final sink = out.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      var total = append ? have : 0;
      try {
        await for (final chunk in res.stream.timeout(bodyTimeout)) {
          sink.add(chunk);
          total += chunk.length;
          onBytes?.call(total);
        }
      } finally {
        await sink.close();
      }
    } on TimeoutException {
      throw const RequestTimeout();
    } on SocketException {
      throw const NetworkUnavailable();
    } on http.ClientException {
      throw const NetworkUnavailable();
    }
  }

  // ------------------------------------------------------------------ endpoints
  Future<bool> health() async =>
      (await _send(
        'GET',
        '/health',
        timeoutOverride: const Duration(seconds: 6),
      ))['status'] ==
      'ok';

  Future<QaResponse> query(String question) async {
    final j = await _send(
      'POST',
      '/api/v1/health-qa/query',
      body: {'question': question},
    );
    return _parse(() => QaResponse.fromJson(j));
  }

  /// Online step of the Ask pipeline: sends the question with the closest approved passages (from the phone's own vector search) to
  /// the server, whose LLM (a local model on a nearby server, or a cloud one) writes the explanation. The CALLER enforces the overall
  /// 10-second limit; this call itself gives up waiting for the server to answer after 10 seconds. Throws on any failure.
  Future<String> explain(
    String question,
    List<({String id, String? title, String text})> passages,
    String safetyStatus,
  ) async {
    final j = await _send(
      'POST',
      '/api/v1/health-qa/explain',
      body: {
        'question': question,
        'safety_status': safetyStatus,
        'passages': [
          for (final p in passages)
            {
              'passage_id': p.id,
              if (p.title != null) 'title': p.title,
              'text': p.text,
            },
        ],
      },
      timeoutOverride: const Duration(seconds: 10),
    );
    final a = (j['explanation'] as String?)?.trim() ?? '';
    if (a.isEmpty) throw const InvalidResponse('empty explanation');
    return a;
  }

  /// The server-side RAG answer (Telugu and English): the server finds the approved passages with a multilingual embedding model and
  /// answers from them. Gives up after 10 seconds. Throws on any failure (an old server answers 404).
  Future<RagResponse> rag(String question) async {
    final j = await _send(
      'POST',
      '/api/v1/health-qa/rag',
      body: {'question': question},
      timeoutOverride: const Duration(seconds: 10),
    );
    return _parse(() => RagResponse.fromJson(j));
  }

  /// True when a server address is set (the AI helper needs one).
  Future<bool> hasServer() async {
    final c = await _config();
    return c != null && c.baseUrl.trim().isNotEmpty;
  }

  Future<RetrieveResponse> retrieve(String question) async {
    final j = await _send(
      'POST',
      '/api/v1/health-qa/retrieve',
      body: {'question': question},
    );
    return _parse(() => RetrieveResponse.fromJson(j));
  }

  Future<PullResponse> pull({
    String? since,
    List<String> types = const ['household', 'visit', 'referral'],
    int limit = 500,
  }) async {
    final j = await _send(
      'GET',
      '/api/v1/sync/pull',
      query: {
        'since': ?since,
        'entity_types': types.join(','),
        'limit': '$limit',
      },
    );
    return _parse(() => PullResponse.fromJson(j));
  }

  Future<PushResponse> push(
    String installationId,
    List<Map<String, dynamic>> operations,
  ) async {
    final j = await _send(
      'POST',
      '/api/v1/sync/push',
      body: {'installation_id': installationId, 'operations': operations},
      timeoutOverride: const Duration(seconds: 30),
    );
    return _parse(() => PushResponse.fromJson(j));
  }

  Future<Map<String, dynamic>> syncStatus(String installationId) => _send(
    'GET',
    '/api/v1/sync/status',
    headers: {'X-Installation-Id': installationId},
  );

  Future<ServerReport> reportSummary({
    required String facilityId,
    required String periodStart,
    required String periodEnd,
    String? lastSyncAt,
    List<String>? referralIds,
  }) async {
    final j = await _send(
      'POST',
      '/api/v1/reports/summary',
      body: {
        'facility_id': facilityId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'last_sync_at': ?lastSyncAt,
        'referral_ids': ?referralIds,
      },
    );
    return _parse(() => ServerReport.fromJson(j));
  }

  /// format: csv | pdf
  Future<Uint8List> reportFile(String reportId, String format) async {
    final res = await _raw(
      'GET',
      '/api/v1/reports/$reportId',
      query: {'format': format},
      timeoutOverride: const Duration(seconds: 30),
    );
    final ct = res.headers['content-type'] ?? '';
    if (format == 'pdf' && !ct.contains('pdf')) {
      throw const InvalidResponse('expected a PDF');
    }
    if (format == 'csv' && !ct.contains('csv')) {
      throw const InvalidResponse('expected a CSV');
    }
    return res.bodyBytes;
  }

  Future<Page<ProtocolDocInfo>> protocolDocuments({
    int limit = 50,
    int offset = 0,
  }) async {
    final j = await _send(
      'GET',
      '/api/v1/protocols',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return _parse(
      () => Page(
        [
          for (final e in j['items'] as List)
            ProtocolDocInfo.fromJson(e as Map<String, dynamic>),
        ],
        j['total'] as int,
        j['limit'] as int,
        j['offset'] as int,
      ),
    );
  }

  Future<Page<ProtocolPassageInfo>> protocolPassages(
    String documentId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final j = await _send(
      'GET',
      '/api/v1/protocols/${Uri.encodeComponent(documentId)}/passages',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return _parse(
      () => Page(
        [
          for (final e in j['items'] as List)
            ProtocolPassageInfo.fromJson(e as Map<String, dynamic>),
        ],
        j['total'] as int,
        j['limit'] as int,
        j['offset'] as int,
      ),
    );
  }

  void close() => _client.close();
}

/// One approved passage the server's RAG answer is based on.
class RagSource {
  const RagSource({
    required this.passageId,
    required this.documentId,
    this.documentTitle,
    this.sectionId,
    this.sectionHeading,
    this.pageNumber,
    this.sourceVersion,
    required this.score,
    required this.verificationStatus,
    required this.text,
  });
  factory RagSource.fromJson(Map<String, dynamic> j) => RagSource(
    passageId: j['passage_id'] as String,
    documentId: j['document_id'] as String,
    documentTitle: j['document_title'] as String?,
    sectionId: j['section_id'] as String?,
    sectionHeading: j['section_heading'] as String?,
    pageNumber: (j['page_number'] as num?)?.toInt(),
    sourceVersion: j['source_version'] as String?,
    score: (j['relevance_score'] as num?)?.toDouble() ?? 0,
    verificationStatus: j['source_verification_status'] as String,
    text: j['text'] as String,
  );
  final String passageId, documentId, verificationStatus, text;
  final String? documentTitle, sectionId, sectionHeading, sourceVersion;
  final int? pageNumber;
  final double score;
}

/// The server's /health-qa/rag reply. `outcome` is ANSWERED only when approved passages were found and an answer was written;
/// `answerSource` is "llm" (written by the model, guards passed) or "extract" (the approved passage word for word).
class RagResponse {
  const RagResponse({
    required this.outcome,
    this.answer,
    this.answerSource,
    this.message = '',
    this.ruleIds = const [],
    this.sources = const [],
  });
  factory RagResponse.fromJson(Map<String, dynamic> j) => RagResponse(
    outcome: j['outcome'] as String,
    answer: j['answer'] as String?,
    answerSource: j['answer_source'] as String?,
    message: (j['message'] as String?) ?? '',
    ruleIds: [
      for (final r in ((j['safety'] as Map?)?['rule_ids'] as List? ?? const []))
        r as String,
    ],
    sources: [
      for (final s in (j['sources'] as List? ?? const []))
        RagSource.fromJson(s as Map<String, dynamic>),
    ],
  );
  final String outcome;
  final String? answer, answerSource;
  final String message;
  final List<String> ruleIds;
  final List<RagSource> sources;
  bool get escalated => outcome == 'ESCALATION_REQUIRED' && sources.isNotEmpty;
  bool get answered =>
      outcome == 'ANSWERED' &&
      (answer?.trim().isNotEmpty ?? false) &&
      sources.isNotEmpty;
}
