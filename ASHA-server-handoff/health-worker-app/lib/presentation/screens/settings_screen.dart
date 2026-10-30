import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../voice_test/enabled.dart';
import '../../voice_test/voice_test_screen.dart';
import '../../core/theme/tokens.dart';
import '../../data/api/api_exceptions.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/settings.dart';
import '../../services/speech_capabilities.dart';
import '../../services/telugu_voice.dart';
import '../../state/app_services.dart';
import '../error_text.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';
import 'telugu_keyboard_help_screen.dart';

const appVersion = '1.0.0+1';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url, _key, _phone;
  String? _urlError, _msg, _connMsg;
  bool _connOk = false, _busy = false;
  Map<String, int> _counts = {};
  int _approved = 0;
  Future<SpeechCapabilities>? _speechCaps;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppServices>().settings;
    _url = TextEditingController(text: st.baseUrl);
    _key = TextEditingController();
    _phone = TextEditingController(text: st.escalationPhone);
    _loadCounts();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final s = context.read<AppServices>();
    final c = await s.store.rowCounts();
    final a = await s.library.approvedPassageCount();
    if (mounted) {
      setState(() {
        _counts = c;
        _approved = a;
      });
    }
  }

  bool _validUrl(String v) {
    final u = Uri.tryParse(v.trim());
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty;
  }

  Future<void> _saveServer() async {
    final l = AppLocalizations.of(context);
    final st = context.read<AppServices>().settings;
    final v = _url.text.trim();
    if (v.isNotEmpty && !_validUrl(v)) {
      setState(() => _urlError = l.invalidUrl);
      return;
    }
    setState(() {
      _urlError = null;
    });
    await st.setBaseUrl(v);
    if (_key.text.trim().isNotEmpty) {
      await st.setApiKey(_key.text);
      _key.clear();
      setState(() => _msg = l.apiKeySaved);
    }
  }

  Future<void> _test() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    await _saveServer();
    setState(() {
      _busy = true;
      _connMsg = null;
    });
    try {
      await s.api.health();
      if (mounted) {
        setState(() {
          _connOk = true;
          _connMsg = l.connectionOk;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connOk = false;
          _connMsg = '${l.connectionFailed}: ${apiErrorText(l, e)}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final st = context.watch<AppSettings>();
    return HeaderScaffold(
      title: l.settingsTitle,
      showBack: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 60),
        children: [
          Banner2(tone: Tone.warn, icon: Icons.rule, text: l.validationNote),
          SectionHeader(l.languageLabel),
          Row(
            children: [
              Expanded(
                child: _LangButton(
                  key: const Key('lang-en'),
                  label: l.langEnglish,
                  selected: st.language == 'en',
                  onTap: () => st.setLanguage('en'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LangButton(
                  key: const Key('lang-te'),
                  label: l.langTelugu,
                  selected: st.language == 'te',
                  onTap: () => st.setLanguage('te'),
                ),
              ),
            ],
          ),
          SectionHeader(l.serverSection),
          TextField(
            key: const Key('server-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.serverUrl,
              hintText: l.serverUrlHint,
              errorText: _urlError,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (AppSettings.isInsecureRemote(_url.text))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Banner2(
                tone: Tone.warn,
                icon: Icons.lock_open,
                text: l.insecureWarning,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('api-key'),
            controller: _key,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.apiKey,
              helperText: st.hasApiKey ? '${l.apiKeySaved} ✓' : l.apiKeyHint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('save-server'),
                  onPressed: _saveServer,
                  child: Text(l.save),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('test-connection'),
                  onPressed: _busy ? null : _test,
                  child: Text(l.testConnection),
                ),
              ),
            ],
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _msg!,
                style: const TextStyle(
                  color: Tk.ok,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (_connMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Banner2(
                tone: _connOk ? Tone.ok : Tone.danger,
                icon: _connOk
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                text: _connMsg!,
              ),
            ),
          SwitchListTile(
            key: const Key('ai-assist-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.aiAssistTitle),
            subtitle: Text(l.aiAssistHelp),
            value: st.aiAssist,
            onChanged: (on) => st.setAiAssist(on),
          ),
          SwitchListTile(
            key: const Key('online-speech-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.onlineSpeechTitle),
            subtitle: Text(l.onlineSpeechHelp),
            value: st.allowOnlineSpeech,
            onChanged: (on) => st.setAllowOnlineSpeech(on),
          ),
          FutureBuilder<SpeechCapabilities>(
            future: _speechCaps ??= s.speechProbe.check(),
            builder: (context, snap) {
              final c = snap.data;
              String state(String lang) => c == null || c.installed == null
                  ? l.speechUnknown
                  : c.installedLocale(lang) != null && c.onDeviceAvailable
                  ? l.speechYes
                  : l.speechNo;
              return ListTile(
                key: const Key('speech-caps'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mic_none),
                title: Text(l.speechCapsLabel),
                subtitle: Text(l.speechCapsLine(state('en'), state('te'))),
              );
            },
          ),
          const _TeluguModelCard(),
          OutlinedButton.icon(
            key: const Key('alt-voice-button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TeluguKeyboardHelpScreen(),
              ),
            ),
            icon: const Icon(Icons.keyboard_voice_outlined),
            label: Text(l.altVoiceButton),
          ),
          SectionHeader(l.alertsTitle),
          SwitchListTile(
            key: const Key('alerts-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.alertsTitle),
            subtitle: Text(l.alertsHelp),
            value: st.alertsEnabled,
            onChanged: (on) async {
              if (on && !await s.notifier.requestPermission()) {
                if (mounted) setState(() => _msg = l.alertsPermissionDenied);
              }
              await st.setAlertsEnabled(on);
            },
          ),
          SectionHeader(l.escalationContact),
          TextField(
            key: const Key('escalation-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              helperText: l.escalationContactHelp,
              prefixIcon: const Icon(Icons.call),
            ),
            onChanged: st.setEscalationPhone,
          ),
          SectionHeader(l.protocolSection),
          Text(
            _approved == 0 ? l.protocolNone : l.protocolCountN(_approved),
            key: const Key('protocol-status'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('refresh-protocols'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      final n = await s.library.refreshFromServer();
                      if (mounted) {
                        setState(() => _msg = l.protocolRefreshed(n));
                      }
                    } catch (e) {
                      if (mounted) setState(() => _msg = apiErrorText(l, e));
                    } finally {
                      await _loadCounts();
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            icon: const Icon(Icons.download_outlined),
            label: Text(l.refreshProtocols),
          ),
          SectionHeader(l.demoSection),
          Text(l.demoExplain, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('load-demo-settings'),
            onPressed: () async {
              final r = await s.demo.load();
              await st.setUseDemoDate(true);
              s.bus.changed();
              await _loadCounts();
              if (mounted) setState(() => _msg = l.demoLoadedN(r.households));
            },
            icon: const Icon(Icons.science_outlined),
            label: Text(l.loadDemo),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.useDemoDate),
            value: st.useDemoDate,
            onChanged: (v) async {
              await st.setUseDemoDate(v);
              s.bus.changed();
            },
          ),
          SectionHeader(l.privacyTitle),
          Text(l.privacyBody, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('clear-data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Tk.danger,
              side: const BorderSide(color: Tk.danger),
            ),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  content: Text(l.clearConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(l.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Tk.danger),
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(l.discard),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await s.store.wipe();
                await s.maps.remove();
                s.bus.changed();
                await s.sync.refresh();
                await _loadCounts();
                if (mounted) setState(() => _msg = l.clearDone);
              }
            },
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(l.clearData),
          ),
          SectionHeader(l.aboutTitle),
          // Hidden: long-press the version line to open the Voice Test screen (debug builds or --dart-define=VOICE_TEST=true only)
          GestureDetector(
            onLongPress: voiceTestEnabled
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const VoiceTestScreen()),
                  )
                : null,
            child: _diag(context, l.appVersion, appVersion),
          ),
          _diag(context, l.dbSchema, '${AppDatabase.schemaVersion}'),
          _diag(
            context,
            l.safetyRulesLabel,
            '${s.safety.version}${s.safety.clinicallyValidated ? '' : ' (${l.notValidatedShort})'}',
          ),
          for (final e in _counts.entries)
            _diag(context, _tableName(l, e.key), '${e.value}'),
          const SizedBox(height: 8),
          Text(l.diagnosticsNote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _diag(BuildContext c, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(k)),
        const SizedBox(width: 12),
        Flexible(
          flex: 2,
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _LangButton extends StatelessWidget {
  const _LangButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(Tk.rButton),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Tk.minTouch),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Tk.primaryDark : Colors.white,
          borderRadius: BorderRadius.circular(Tk.rButton),
          border: Border.all(
            color: selected ? Tk.primaryDark : Tk.border,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Icon(Icons.check, color: Colors.white, size: 18),
            if (selected) const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Tk.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _tableName(AppLocalizations l, String t) => switch (t) {
  'households' => l.tblHouseholds,
  'visits' => l.tblVisits,
  'referrals' => l.tblReferrals,
  'protocol_passages' => l.tblProtocolPassages,
  'sync_outbox' => l.tblSyncOutbox,
  _ => t,
};

/// Download-once card for the app's own offline Telugu speech model. Nothing downloads until the worker taps the button.
class _TeluguModelCard extends StatefulWidget {
  const _TeluguModelCard();
  @override
  State<_TeluguModelCard> createState() => _TeluguModelCardState();
}

class _TeluguModelCardState extends State<_TeluguModelCard> {
  bool? _installed;
  bool _busy = false;
  ModelProgress? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final v = await context.read<AppServices>().teluguModel.isInstalled();
    if (mounted) setState(() => _installed = v);
  }

  Future<void> _download() async {
    final l = AppLocalizations.of(context);
    final s = context.read<AppServices>();
    final cfg = await s.settings.apiConfig();
    if (cfg == null || cfg.baseUrl.trim().isEmpty) {
      if (mounted) setState(() => _error = l.teluguModelNeedServer);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await s.teluguModel.download(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } on ModelDownloadFailed catch (e) {
      if (mounted) {
        setState(
          () => _error = e.reason == 'checksum'
              ? l.teluguModelFailedSum
              : l.teluguModelFailedNet,
        );
      }
    } on NotFoundError {
      if (mounted) setState(() => _error = l.teluguModelNotOnServer);
    } on ApiException {
      if (mounted) setState(() => _error = l.teluguModelFailedNet);
    } on Object {
      if (mounted) setState(() => _error = l.teluguModelFailedNet);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    int mb(int b) => (b / 1000000).round();
    return Padding(
      key: const Key('telugu-model'),
      padding: const EdgeInsets.only(top: Tk.s8, bottom: Tk.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_outlined),
              const SizedBox(width: Tk.s12),
              Expanded(child: Text(l.teluguModelTitle, style: t.titleMedium)),
            ],
          ),
          const SizedBox(height: Tk.s8),
          Text(l.teluguModelHelp, style: t.bodySmall),
          const SizedBox(height: Tk.s8),
          if (_busy) ...[
            LinearProgressIndicator(
              key: const Key('telugu-model-progress'),
              value: _progress?.fraction,
            ),
            const SizedBox(height: Tk.s4),
            Text(
              l.teluguModelProgress(
                mb(_progress?.doneBytes ?? 0).toString(),
                mb(_progress?.totalBytes ?? 0),
              ),
              style: t.bodySmall,
            ),
          ] else if (_installed == true) ...[
            Text(l.teluguModelReady, key: const Key('telugu-model-ready')),
            TextButton(
              key: const Key('telugu-model-remove'),
              onPressed: () async {
                await context.read<AppServices>().teluguModel.delete();
                await _refresh();
              },
              child: Text(l.teluguModelRemove),
            ),
          ] else if (_installed == false)
            FilledButton.icon(
              key: const Key('telugu-model-download'),
              onPressed: _download,
              icon: const Icon(Icons.download),
              label: Text(l.teluguModelDownload),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s8),
              child: Text(
                _error!,
                key: const Key('telugu-model-error'),
                style: t.bodySmall?.copyWith(color: Tk.danger),
              ),
            ),
        ],
      ),
    );
  }
}
