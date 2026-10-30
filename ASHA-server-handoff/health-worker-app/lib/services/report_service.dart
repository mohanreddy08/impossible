import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/clock.dart';
import '../data/api/api_client.dart';
import '../data/api/api_models.dart';
import '../data/local/local_store.dart';
import '../domain/rules/report_rules.dart';

abstract class FileSharer {
  Future<void> shareFile(String path, {required String mime, String? subject});
}

class PlatformFileSharer implements FileSharer {
  @override
  Future<void> shareFile(
    String path, {
    required String mime,
    String? subject,
  }) => SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: mime)],
      subject: subject,
    ),
  );
}

class ReportService {
  ReportService(
    this.store,
    this.api,
    this.clock,
    this.sharer, {
    Future<Directory> Function()? tempDir,
  }) : _tempDir = tempDir ?? getTemporaryDirectory;
  final LocalStore store;
  final ApiClient api;
  final AppClock clock;
  final FileSharer sharer;
  final Future<Directory> Function() _tempDir;

  /// Computed ONLY from records on this phone: works with no network.
  Future<({ReportSummary summary, String freshness, String? lastSyncAt})>
  localSummary(String facilityId, DateTime start, DateTime end) async {
    final refs = await store.referralsBetween(facilityId, start, end);
    final last = await store.meta('last_sync_at');
    final s = aggregateReferrals(refs, facilityId, start, end);
    return (
      summary: s,
      freshness: freshnessLabel(
        last == null ? null : DateTime.parse(last),
        clock.nowUtc(),
      ),
      lastSyncAt: last,
    );
  }

  Future<ServerReport> serverReport(
    String facilityId,
    DateTime start,
    DateTime end,
  ) async {
    final last = await store.meta('last_sync_at');
    return api.reportSummary(
      facilityId: facilityId,
      periodStart: isoDate(start),
      periodEnd: isoDate(end),
      lastSyncAt: last,
    );
  }

  Future<File> _write(String name, List<int> bytes) async {
    final dir = await _tempDir();
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// format csv|pdf from the server (stored report). The temp file holds only aggregate counts.
  Future<void> shareServerFile(
    String reportId,
    String format, {
    String subject = 'Referral summary',
  }) async {
    final Uint8List bytes = await api.reportFile(reportId, format);
    final f = await _write('$reportId.$format', bytes);
    await sharer.shareFile(
      f.path,
      mime: format == 'pdf' ? 'application/pdf' : 'text/csv',
      subject: subject,
    );
  }

  Future<void> shareLocalCsv(
    ReportSummary s,
    String freshness,
    String? lastSyncAt, {
    String subject = 'Referral summary (this device)',
  }) async {
    final csv = summaryToCsv(
      s,
      freshness,
      '${clock.nowUtc().toIso8601String().split('.').first}Z',
      lastSyncAt,
    );
    final f = await _write(
      'local_${s.facilityId}_${isoDate(s.periodEnd)}.csv',
      csv.codeUnits,
    );
    await sharer.shareFile(f.path, mime: 'text/csv', subject: subject);
  }
}
