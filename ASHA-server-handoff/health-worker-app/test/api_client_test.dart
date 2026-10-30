import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/data/api/api_client.dart';
import 'package:health_companion/data/api/api_exceptions.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_server.dart';

ApiClient clientFor(
  MockClientHandler h, {
  ApiConfig? cfg,
  List<String>? log,
  Duration timeout = const Duration(seconds: 2),
}) => ApiClient(
  client: MockClient(h),
  config: () async =>
      cfg ?? const ApiConfig('https://api.example.org', 'secret-key-123'),
  timeout: timeout,
  log: log?.add,
);

http.Response jsonResp(Object o, [int code = 200]) => http.Response(
  jsonEncode(o),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> errBody(String code, String msg, [Object? details]) => {
  'error': {'code': code, 'message': msg, 'details': details},
};

void main() {
  group('request shape', () {
    test('sends the key header, JSON body and the documented path; installation id goes in the body, never the URL', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return jsonResp({
          'received': 0,
          'acknowledged_count': 0,
          'results': [],
          'note': '',
        });
      });
      await api.push('install-abc-123456', [
        {'op_id': 'op-1'},
      ]);
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.example.org/api/v1/sync/push');
      expect(seen.headers['X-API-Key'], 'secret-key-123');
      expect(seen.headers['content-type'], startsWith('application/json'));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['installation_id'], 'install-abc-123456');
      expect(seen.url.query, isEmpty);
    });

    test('sync status sends the installation id as a HEADER, not a query parameter', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return jsonResp({'total_operations': 0});
      });
      await api.syncStatus('install-abc-123456');
      expect(seen.headers['X-Installation-Id'], 'install-abc-123456');
      expect(seen.url.query, isEmpty);
      expect(seen.url.toString(), isNot(contains('install-abc')));
    });

    test('pull builds since / entity_types / limit; no key header when none is set; trailing slash on base URL tolerated', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return jsonResp({
          'server_time': '2026-10-13T10:00:00',
          'households': [],
          'visits': null,
          'referrals': null,
        });
      }, cfg: const ApiConfig('http://10.0.2.2:8000/', null));
      final r = await api.pull(
        since: '2026-10-01T00:00:00',
        types: ['household'],
        limit: 50,
      );
      expect(seen.url.path, '/api/v1/sync/pull');
      expect(seen.url.queryParameters, {
        'since': '2026-10-01T00:00:00',
        'entity_types': 'household',
        'limit': '50',
      });
      expect(seen.headers.containsKey('X-API-Key'), isFalse);
      expect(r.households, isEmpty);
      expect(r.visits, isNull);
    });

    test('a base URL path prefix is preserved', () async {
      late http.Request seen;
      final api = clientFor((r) async {
        seen = r;
        return jsonResp({'status': 'ok'});
      }, cfg: const ApiConfig('https://proxy.example.org/health', 'k'));
      await api.health();
      expect(seen.url.path, '/health/health');
    });

    test(
      'Telugu and code-mixed questions are sent as UTF-8 JSON unchanged',
      () async {
        late http.Request seen;
        final api = clientFor((r) async {
          seen = r;
          return jsonResp(qaJson('INSUFFICIENT_EVIDENCE'));
        });
        const q = 'గర్భిణీకి ANC checkup ఎప్పుడు చేయాలి?';
        await api.query(q);
        expect((jsonDecode(utf8.decode(seen.bodyBytes)) as Map)['question'], q);
      },
    );
  });

  group('typed parsing', () {
    test('QA response with citations and safety info', () async {
      final api = clientFor(
        (r) async => jsonResp(
          qaJson(
            'ANSWERED_WITH_EVIDENCE',
            answer: 'a',
            citations: [citationJson()],
            retrieval: 'MATCH_FOUND',
          ),
        ),
      );
      final r = await api.query('q');
      expect(r.outcome, 'ANSWERED_WITH_EVIDENCE');
      expect(r.citations.single.pageNumber, 12);
      expect(r.citations.single.verificationStatus, 'VERIFIED');
      expect(r.safety.clinicallyValidated, isFalse);
      expect(r.safety.rulesetVersion, '0.1.0-draft');
    });

    test('push results incl. conflict details', () async {
      final api = clientFor(
        (r) async => jsonResp({
          'received': 2,
          'acknowledged_count': 1,
          'note': 'n',
          'results': [
            {
              'op_id': 'a',
              'status': 'ACKNOWLEDGED',
              'acknowledged': true,
              'duplicate': false,
              'server_version': 2,
              'error_code': null,
              'error_message': null,
              'conflict': null,
              'warnings': <String>[],
            },
            conflictResult('b')..addAll({
              'duplicate': false,
              'server_version': null,
              'warnings': <String>[],
            }),
          ],
        }),
      );
      final r = await api.push('i', []);
      expect(r.acknowledgedCount, 1);
      expect(r.results[0].acknowledged, isTrue);
      expect(r.results[1].status, 'CONFLICT');
      expect(r.results[1].acknowledged, isFalse);
      expect(r.results[1].conflict!['server_values'], {
        'referral_status': 'ATTENDANCE_CONFIRMED',
      });
    });

    test('report summary parses counts, categories and freshness', () async {
      final api = clientFor(
        (r) async => jsonResp({
          'report_id': 'RPT-1',
          'facility_id': 'F',
          'period_start': '2026-01-01',
          'period_end': '2026-02-01',
          'generated_at': '2026-10-13T09:00:00Z',
          'data_as_of': null,
          'last_sync_at': null,
          'data_freshness_label': 'FRESH',
          'counts': {
            'recommended': 1,
            'planned': 2,
            'attendance_confirmed': 3,
            'total_included': 6,
          },
          'counts_by_service_category': {'ANC': 6},
          'excluded_counts': {},
          'follow_ups': {'due': 0, 'completed_in_period': 1},
          'privacy_notice': 'p',
          'synthetic_data': true,
          'content_hash': 'h',
          'duplicate_of_existing': true,
          'superseded_by': null,
        }),
      );
      final r = await api.reportSummary(
        facilityId: 'F',
        periodStart: '2026-01-01',
        periodEnd: '2026-02-01',
      );
      expect(
        (r.recommended, r.planned, r.attendanceConfirmed, r.total),
        (1, 2, 3, 6),
      );
      expect(r.duplicateOfExisting, isTrue);
    });

    test('report files are checked for the right content type', () async {
      final api = clientFor(
        (r) async => http.Response(
          '<html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      );
      await expectLater(
        api.reportFile('RPT-1', 'pdf'),
        throwsA(isA<InvalidResponse>()),
      );
      final ok = clientFor(
        (r) async => http.Response.bytes(
          [37, 80, 68, 70],
          200,
          headers: {'content-type': 'application/pdf'},
        ),
      );
      expect((await ok.reportFile('RPT-1', 'pdf')).length, 4);
    });
  });

  group('errors become typed exceptions (and never leak the body)', () {
    Future<Object?> fail(MockClientHandler h) async {
      try {
        await clientFor(h).query('q');
      } catch (e) {
        return e;
      }
      return null;
    }

    test(
      '401 -> Unauthorized',
      () async => expect(
        await fail(
          (r) async => jsonResp(
            errBody('UNAUTHORIZED', 'missing or invalid API key'),
            401,
          ),
        ),
        isA<Unauthorized>(),
      ),
    );
    test(
      '403 -> Forbidden',
      () async => expect(
        await fail((r) async => jsonResp(errBody('FORBIDDEN', 'nope'), 403)),
        isA<Forbidden>(),
      ),
    );
    test(
      '404 -> NotFoundError',
      () async => expect(
        await fail((r) async => jsonResp(errBody('NOT_FOUND', 'nf'), 404)),
        isA<NotFoundError>(),
      ),
    );
    test('409 -> ConflictError with the code', () async {
      final e = await fail(
        (r) async => jsonResp(errBody('VERSION_CONFLICT', 'stale'), 409),
      );
      expect(e, isA<ConflictError>());
      expect((e as ConflictError).code, 'VERSION_CONFLICT');
    });
    test('422 -> ValidationFailed with details', () async {
      final e = await fail(
        (r) async => jsonResp(
          errBody('VALIDATION_ERROR', 'bad', [
            {
              'loc': ['body', 'question'],
            },
          ]),
          422,
        ),
      );
      expect(e, isA<ValidationFailed>());
      expect((e as ValidationFailed).details, isNotNull);
    });
    test('500/503 -> ServerError with the status', () async {
      final e = await fail(
        (r) async =>
            jsonResp(errBody('INTERNAL_ERROR', 'unexpected server error'), 503),
      );
      expect(e, isA<ServerError>());
      expect((e as ServerError).status, 503);
    });
    test('non-standard error body (e.g. a proxy HTML page) still gives a typed error', () async {
      expect(
        await fail((r) async => http.Response('<html>Bad gateway</html>', 502)),
        isA<ServerError>(),
      );
    });
    test(
      '200 with non-JSON -> InvalidResponse',
      () async => expect(
        await fail((r) async => http.Response('hello', 200)),
        isA<InvalidResponse>(),
      ),
    );
    test(
      '200 with a JSON array instead of an object -> InvalidResponse',
      () async => expect(
        await fail((r) async => http.Response('[1,2]', 200)),
        isA<InvalidResponse>(),
      ),
    );
    test('200 missing required fields -> InvalidResponse, not a crash or a half-filled object', () async {
      expect(
        await fail(
          (r) async => jsonResp({'outcome': 'ANSWERED_WITH_EVIDENCE'}),
        ),
        isA<InvalidResponse>(),
      );
    });
    test('200 with wrongly typed fields -> InvalidResponse', () async {
      final bad = qaJson('INSUFFICIENT_EVIDENCE')..['citations'] = 'not-a-list';
      expect(await fail((r) async => jsonResp(bad)), isA<InvalidResponse>());
    });
    test(
      'connection failure -> NetworkUnavailable',
      () async => expect(
        await fail((r) async => throw http.ClientException('boom')),
        isA<NetworkUnavailable>(),
      ),
    );
    test('slow server -> RequestTimeout', () async {
      final api = clientFor(
        (r) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 80),
      );
      await expectLater(api.query('q'), throwsA(isA<RequestTimeout>()));
    });

    test('error messages never contain the request body or the key', () async {
      final e = await fail(
        (r) async => jsonResp(errBody('INTERNAL_ERROR', 'boom'), 500),
      );
      expect(e.toString(), isNot(contains('secret-key-123')));
      expect(e.toString(), isNot(contains('"question"')));
    });
  });

  group('configuration', () {
    test(
      'no base URL or an invalid one -> NotConfigured, no request made',
      () async {
        var calls = 0;
        for (final cfg in [
          null,
          const ApiConfig('', 'k'),
          const ApiConfig('not a url', 'k'),
          const ApiConfig('ftp://x.example', 'k'),
          const ApiConfig('http://', 'k'),
        ]) {
          final api = ApiClient(
            client: MockClient((r) async {
              calls++;
              return jsonResp({});
            }),
            config: () async => cfg,
          );
          await expectLater(
            api.health(),
            throwsA(isA<NotConfigured>()),
            reason: '$cfg',
          );
        }
        expect(calls, 0);
      },
    );

    test('the configuration is read per request (changing Settings takes effect immediately)', () async {
      var cfg = const ApiConfig('https://one.example.org', 'k1');
      final hosts = <String>[];
      final api = ApiClient(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          return jsonResp({'status': 'ok'});
        }),
        config: () async => cfg,
      );
      await api.health();
      cfg = const ApiConfig('https://two.example.org', 'k2');
      await api.health();
      expect(hosts, ['one.example.org', 'two.example.org']);
    });
  });

  group('logging', () {
    test(
      'logs only method, path and status: never bodies, query strings or keys',
      () async {
        final log = <String>[];
        final api = clientFor(
          (r) async => r.url.path.contains('pull')
              ? jsonResp({
                  'server_time': '2026-10-13T10:00:00',
                  'households': null,
                  'visits': [],
                  'referrals': null,
                })
              : jsonResp(qaJson('INSUFFICIENT_EVIDENCE')),
          log: log,
        );
        await api.query('zebra-quokka-7731 secret health question');
        await api.pull(since: '2026-10-01T00:00:00', types: ['visit']);
        final all = log.join('\n');
        expect(all, contains('POST /api/v1/health-qa/query -> 200'));
        expect(all, contains('GET /api/v1/sync/pull -> 200'));
        expect(all, isNot(contains('quokka')));
        expect(all, isNot(contains('secret-key-123')));
        expect(all, isNot(contains('since=')));
      },
    );
  });

  group('protocol documents', () {
    test('lists documents and passages with paging fields', () async {
      final api = clientFor((r) async {
        if (r.url.path == '/api/v1/protocols') {
          return jsonResp({
            'items': [
              {
                'document_id': 'D1',
                'title': 'T',
                'issuing_authority': null,
                'version': null,
                'publication_date': null,
                'language': 'en',
                'source_verification_status': 'UNVERIFIED',
                'approved_for_retrieval': false,
              },
            ],
            'total': 1,
            'limit': 50,
            'offset': 0,
          });
        }
        return jsonResp({
          'items': [
            {
              'passage_id': 'P1',
              'document_id': 'D1',
              'section_id': null,
              'section_title': null,
              'page_number': null,
              'passage_text': 'x',
              'language': null,
              'source_verification_status': 'UNVERIFIED',
            },
          ],
          'total': 1,
          'limit': 100,
          'offset': 0,
        });
      });
      final docs = await api.protocolDocuments();
      expect(docs.items.single.approved, isFalse);
      expect(docs.items.single.issuingAuthority, isNull);
      final ps = await api.protocolPassages('D1');
      expect(ps.items.single.pageNumber, isNull);
    });
  });

  test('a response that starts and then stalls times out instead of hanging for ever', () async {
    final stalled = StreamController<List<int>>();
    final client = ApiClient(
      client: MockClient.streaming(
        (req, _) async => http.StreamedResponse(stalled.stream, 200),
      ),
      config: () async => const ApiConfig('https://api.example.org', 'k'),
      timeout: const Duration(seconds: 2),
      bodyTimeout: const Duration(milliseconds: 150),
    );
    await expectLater(
      client.query('hello there'),
      throwsA(isA<RequestTimeout>()),
    );
    await stalled.close();
  });
}
