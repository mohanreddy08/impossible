import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../data/api/api_client.dart';
import '../data/local/local_store.dart';
import '../domain/retrieval/embedder.dart';
import '../domain/retrieval/local_retrieval.dart';

/// Keeps APPROVED protocol passages on the phone so Q&A can work offline. Only documents the server marks
/// approved_for_retrieval AND VERIFIED are stored; anything else (unverified imports, test fixtures) is ignored.
/// Until official protocols are imported on the server this library is empty and the app says so.
class ProtocolLibrary {
  ProtocolLibrary(
    this.store,
    this.api, {
    this.allowSamples,
    Future<String> Function()? aliasLoader,
  }) : _aliasLoader =
           aliasLoader ??
           (() => rootBundle.loadString('assets/data/aliases.json'));
  final Future<String> Function() _aliasLoader;
  static const _embedder = HashingEmbedder();
  final LocalStore store;
  final ApiClient api;

  /// True while demo mode is on: then the FICTIONAL sample passages (status TEST_FIXTURE_ONLY) are searchable too, always shown as
  /// unverified. Never true for real use.
  final bool Function()? allowSamples;

  Future<LocalRetrieval> loadIndex() async {
    final samples = allowSamples?.call() ?? false;
    final rows = await store.db.rawQuery(
      '''SELECT p.*, d.title AS d_title, d.version AS d_version, v.embedder_id AS v_emb, v.text_hash AS v_hash, v.vec AS v_vec
         FROM protocol_passages p
         JOIN protocol_documents d ON d.document_id = p.document_id
         LEFT JOIN passage_vectors v ON v.passage_id = p.passage_id
         WHERE p.approved_for_retrieval = 1 AND d.approved_for_retrieval = 1
           AND ((p.source_verification_status = 'VERIFIED' AND d.source_verification_status = 'VERIFIED')
             OR (? = 1 AND p.source_verification_status = 'TEST_FIXTURE_ONLY' AND d.source_verification_status = 'TEST_FIXTURE_ONLY' AND d.document_id LIKE 'SAMPLE-%'))''',
      [samples ? 1 : 0],
    );
    final vectors = <String, Int8List>{};
    final toStore = <String, Int8List>{};
    final hashes = <String, String>{};
    for (final r in rows) {
      final id = r['passage_id']! as String;
      final stored = r['v_vec'] as Uint8List?;
      final text = '${r['passage_text']} ${r['section_title'] ?? ''}';
      final hash = md5.convert(utf8.encode(text)).toString();
      if (stored != null &&
          r['v_emb'] == HashingEmbedder.embedderId &&
          r['v_hash'] == hash &&
          stored.length == HashingEmbedder.dim) {
        vectors[id] = stored.buffer.asInt8List(
          stored.offsetInBytes,
          stored.length,
        );
      } else {
        // a passage with no vector yet, or whose text or method changed: build it now and keep it
        final v = _embedder.quantize(_embedder.embed(text));
        vectors[id] = v;
        toStore[id] = v;
        hashes[id] = hash;
      }
    }
    if (toStore.isNotEmpty) {
      await store.db.transaction((txn) async {
        final b = txn.batch();
        toStore.forEach((id, v) {
          b.insert('passage_vectors', {
            'passage_id': id,
            'embedder_id': HashingEmbedder.embedderId,
            'text_hash': hashes[id],
            'vec': Uint8List.view(v.buffer, v.offsetInBytes, v.length),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
        await b.commit(noResult: true);
      });
    }
    final eligible = samples
        ? const {'VERIFIED', 'TEST_FIXTURE_ONLY'}
        : const {'VERIFIED'};
    return LocalRetrieval(
      eligible: eligible,
      vectors: vectors,
      aliases: await _aliases(),
      [
        for (final r in rows)
          LocalPassage(
            passageId: r['passage_id']! as String,
            documentId: r['document_id']! as String,
            documentTitle: r['d_title'] as String?,
            documentVersion: r['d_version'] as String?,
            sectionId: r['section_id'] as String?,
            sectionTitle: r['section_title'] as String?,
            pageNumber: r['page_number'] as int?,
            text: r['passage_text']! as String,
            verificationStatus: r['source_verification_status']! as String,
            language: r['language'] as String?,
          ),
      ],
    );
  }

  AliasExpander? _aliasCache;
  Future<AliasExpander?> _aliases() async {
    if (_aliasCache != null) return _aliasCache;
    try {
      return _aliasCache = AliasExpander.fromJson(await _aliasLoader());
    } on Object {
      return null; // no alias file: search still works, just without cross-language expansion
    }
  }

  Future<int> approvedPassageCount() async =>
      Sqflite.firstIntValue(
        await store.db.rawQuery(
          "SELECT COUNT(*) FROM protocol_passages WHERE approved_for_retrieval=1 AND source_verification_status='VERIFIED'",
        ),
      ) ??
      0;

  /// Downloads approved documents + passages. Returns the number of passages stored.
  Future<int> refreshFromServer() async {
    final keepDocs = <String>[];
    var stored = 0;
    for (var off = 0; ; off += 50) {
      final page = await api.protocolDocuments(limit: 50, offset: off);
      for (final d in page.items) {
        if (!(d.approved && d.verificationStatus == 'VERIFIED')) continue;
        final passages = <Map<String, Object?>>[];
        for (var po = 0; ; po += 100) {
          final pp = await api.protocolPassages(
            d.documentId,
            limit: 100,
            offset: po,
          );
          for (final p in pp.items) {
            if (p.verificationStatus != 'VERIFIED') continue;
            passages.add({
              'passage_id': p.passageId,
              'document_id': p.documentId,
              'section_id': p.sectionId,
              'section_title': p.sectionTitle,
              'page_number': p.pageNumber,
              'passage_text': p.text,
              'language': p.language,
              'approved_for_retrieval': 1,
              'source_verification_status': 'VERIFIED',
            });
          }
          if (po + 100 >= pp.total) break;
        }
        await store.db.transaction((txn) async {
          await txn.delete(
            'protocol_passages',
            where: 'document_id = ?',
            whereArgs: [d.documentId],
          );
          await txn.insert('protocol_documents', {
            'document_id': d.documentId,
            'title': d.title,
            'issuing_authority': d.issuingAuthority,
            'version': d.version,
            'publication_date': d.publicationDate,
            'language': d.language,
            'source_verification_status': 'VERIFIED',
            'approved_for_retrieval': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          final b = txn.batch();
          for (final row in passages) {
            b.insert('protocol_passages', row);
          }
          await b.commit(noResult: true);
        });
        keepDocs.add(d.documentId);
        stored += passages.length;
      }
      if (off + 50 >= page.total) break;
    }
    // documents no longer approved on the server must disappear from the device
    final marks = keepDocs.isEmpty
        ? ''
        : 'WHERE document_id NOT IN (${List.filled(keepDocs.length, '?').join(',')})';
    // (the bundled FICTIONAL demo sample, ids 'SAMPLE-%', is not a server document and is left alone)
    final notKept = keepDocs.isEmpty
        ? "document_id NOT LIKE 'SAMPLE-%'"
        : "document_id NOT IN (${List.filled(keepDocs.length, '?').join(',')}) AND document_id NOT LIKE 'SAMPLE-%'";
    await store.db.delete(
      'protocol_passages',
      where: notKept,
      whereArgs: keepDocs.isEmpty ? null : keepDocs,
    );
    await store.db.delete(
      'protocol_documents',
      where: notKept,
      whereArgs: keepDocs.isEmpty ? null : keepDocs,
    );
    await store.db.delete(
      'passage_vectors',
      where: 'passage_id NOT IN (SELECT passage_id FROM protocol_passages)',
    );
    assert(marks.isEmpty || marks.isNotEmpty);
    return stored;
  }
}
