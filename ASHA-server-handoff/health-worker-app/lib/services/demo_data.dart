import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart' show rootBundle;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/local/local_store.dart';
import '../data/models/household.dart';
import '../data/models/referral.dart';
import '../data/models/visit.dart';

/// Loads the bundled SYNTHETIC demo records (derived from the project's generated datasets; same ids/versions as the backend import).
class DemoData {
  DemoData(
    this.store, {
    Future<String> Function()? loader,
    Future<String> Function()? protocolLoader,
    Future<void> Function()? installMap,
    // ignore: prefer_initializing_formals
  }) : _installMap = installMap,
       _load =
           loader ??
           (() => rootBundle.loadString('assets/demo/demo_seed.json')),
       _loadProtocol =
           protocolLoader ??
           (() => rootBundle.loadString('assets/data/passages.json'));
  final LocalStore store;
  final Future<String> Function() _load;
  final Future<String> Function() _loadProtocol;
  final Future<void> Function()? _installMap;

  /// FICTIONAL sample protocol documents (asha-data/protocols, built into assets/data/passages.json). Stored with the status given in each
  /// document's header (TEST_FIXTURE_ONLY), so they can never be mistaken for approved guidance: the library only offers them while demo
  /// mode is on, and the screen labels them.
  Future<int> _loadSampleProtocol() async {
    try {
      final j = jsonDecode(await _loadProtocol()) as Map<String, dynamic>;
      final docs = (j['documents'] as List).cast<Map<String, dynamic>>();
      final ps = (j['passages'] as List).cast<Map<String, dynamic>>();
      await store.db.transaction((txn) async {
        for (final doc in docs) {
          final id = doc['document_id'];
          await txn.delete(
            'protocol_passages',
            where: 'document_id = ?',
            whereArgs: [id],
          );
          final titles = doc['titles'] as Map<String, dynamic>;
          await txn.insert('protocol_documents', {
            'document_id': id,
            'title': titles['en'] ?? titles.values.first,
            'issuing_authority': doc['issuing_authority'],
            'version': doc['version'],
            'publication_date': null,
            'language': (doc['languages'] as List).join('/'),
            'source_verification_status': doc['status'],
            'approved_for_retrieval': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final status = {for (final d in docs) d['document_id']: d['status']};
        final b = txn.batch();
        for (final p in ps) {
          b.insert('protocol_passages', {
            'passage_id': p['passage_id'],
            'document_id': p['document_id'],
            'section_id': p['section_id'],
            'section_title': p['section_title'],
            'page_number': p['page_number'],
            'passage_text': p['passage_text'],
            'language': p['language'],
            'approved_for_retrieval': 1,
            'source_verification_status': status[p['document_id']],
          });
        }
        await b.commit(noResult: true);
      });
      return ps.length;
    } on Object {
      return 0; // no sample file: the rest of the demo still loads
    }
  }

  /// After an app update the bundled sample text may be newer than what an already-loaded demo holds: reload just the sample
  /// protocol (never the records) when its version differs from the one stored.
  Future<void> refreshSampleIfStale() async {
    try {
      if (await store.meta('demo_loaded') != '1') return;
      final raw = await _loadProtocol();
      final ver = sha256.convert(utf8.encode(raw)).toString();
      if (await store.meta('sample_protocol_ver') == ver) return;
      await store.db.delete(
        'protocol_passages',
        where:
            "document_id LIKE 'SAMPLE-%' OR document_id LIKE 'DEMO-SAMPLE-%'",
      );
      await store.db.delete(
        'protocol_documents',
        where: "document_id LIKE 'DEMO-SAMPLE-%'",
      );
      if (await _loadSampleProtocol() > 0) {
        await store.setMeta('sample_protocol_ver', ver);
      }
    } on Object {
      /* the sample is a bonus: never block start-up */
    }
  }

  Future<void> _saveGeo(List<Household> hh) => store.setGeo({
    for (final h in hh)
      if (h.lat != null && h.lng != null) h.householdId: (h.lat!, h.lng!),
  });

  /// The demo map pack stands in for "download the village map": it is copied to the phone's own storage, so the map then works offline.
  Future<void> _installDemoMap() async {
    try {
      await _installMap?.call();
    } on Object {
      /* a missing map never blocks the demo */
    }
  }

  /// After an app update, a phone that already holds the demo gets the house positions and the map pack too (nothing else is touched).
  Future<void> ensureMap() async {
    try {
      if (await store.meta('demo_loaded') != '1' || await store.geoCount() > 0) {
        return;
      }
      final j = jsonDecode(await _load()) as Map<String, dynamic>;
      await _saveGeo([
        for (final e in j['households'] as List)
          Household.fromJson(e as Map<String, dynamic>),
      ]);
      await _installDemoMap();
    } on Object {
      /* optional extra: never block start-up */
    }
  }

  Future<({int households, int visits, int referrals})> load() async {
    final j = jsonDecode(await _load()) as Map<String, dynamic>;
    final hh = [
      for (final e in j['households'] as List)
        Household.fromJson(e as Map<String, dynamic>),
    ];
    final vs = [
      for (final e in j['visits'] as List)
        Visit.fromJson(e as Map<String, dynamic>),
    ];
    final rs = [
      for (final e in j['referrals'] as List)
        Referral.fromJson(e as Map<String, dynamic>),
    ];
    await store.upsertHouseholds(hh, respectPending: false);
    await _saveGeo(hh);
    await store.upsertVisits(vs, respectPending: false);
    await store.upsertReferrals(rs, respectPending: false);
    await _installDemoMap();
    await _loadSampleProtocol();
    await store.setMeta('sample_protocol_ver', null);
    await store.setMeta('demo_loaded', '1');
    await store.setMeta('demo_worker', j['worker_id'] as String);
    return (households: hh.length, visits: vs.length, referrals: rs.length);
  }
}
