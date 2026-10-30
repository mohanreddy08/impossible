import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../services/record_answers.dart';
import '../widgets/priority_card.dart';
import '../format.dart';
import 'households_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../services/explainer.dart';
import '../../services/qa_service.dart';
import '../../services/settings.dart';
import '../../services/speech_capabilities.dart';
import '../../services/voice_input.dart';
import '../../state/app_services.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';

/// Ask a health question. Safety checks run on the device first. Each outcome has its own, unmistakable presentation:
/// escalation (red, icon, no answer content) | clarification | out of scope | verified evidence | insufficient | cannot verify offline.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, this.launcher});
  final Future<bool> Function(Uri uri)? launcher; // injectable for tests
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _ctl = TextEditingController();
  QaResult? _result;
  bool _loading = false,
      _listening = false,
      _checkingVoice = false,
      _transcribing = false;
  VoiceInput? _activeVoice; // the recogniser used by the current voice session
  VoiceRoute? _voiceRoute; // how the last voice session was recognised
  String? _error, _voiceMsg;
  int _gen = 0; // which Check an explanation belongs to
  _Expl _expl = _Expl.none;
  Explanation? _explanation;
  bool _resultFromVoice =
      false; // the text that was checked was filled in by speech
  String? _voiceLang; // 'en' | 'te' (defaults to the app language)
  String _textBeforeVoice = '';
  String _checkedText = ''; // the text of the last Check: a new voice take after it starts a NEW question
  bool _fromVoice =
      false; // text came from speech: remind the worker to check it

  late final VoiceInput _voice;
  bool _closing =
      false; // the recogniser can call back while the screen is being closed
  bool get _live => mounted && !_closing;

  @override
  void initState() {
    super.initState();
    _voice = context
        .read<AppServices>()
        .voice; // keep a reference: context must not be used in dispose()
  }

  @override
  void dispose() {
    _closing = true;
    _voice.stop();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final fromVoice = _fromVoice;
    final l = AppLocalizations.of(context);
    final qa = context.read<AppServices>().qa;
    FocusScope.of(context).unfocus();
    _checkedText = _ctl.text.trim();
    setState(() {
      _loading = true;
      _fromVoice = false;
      _error = null;
      _result = null;
    });
    final gen = ++_gen;
    setState(() {
      _expl = _Expl.none;
      _explanation = null;
    });
    try {
      // 1. Type or speak: both are the same text box. The phone runs its own safety rules, embeds the text and searches its stored
      //    vectors: all on the phone, at once. A danger sign is never delayed by the network.
      final r = await qa.ask(_ctl.text);
      if (!mounted || gen != _gen) return;
      setState(() {
        _result = r;
        _resultFromVoice = fromVoice;
      });
      // 6. Severity decides the action. High: alert (the red card is already on screen) plus a firm vibration.
      if (severityOf(r.outcome) == Severity.high) {
        unawaited(HapticFeedback.heavyImpact());
      }
      // 4. Explain the closest approved passages: the server's LLM when online (waiting at most 10 s), the phone's own explainer
      //    when offline or when the server is slow or fails. Both end in the same explanation card.
      final s = context.read<AppServices>();
      final online = s.connectivity.online && s.settings.aiAssist;
      // 3b. Online with a server set: the server's retrieval (a multilingual embedding model) finds the approved passages the phone's
      //     own search can miss, above all for Telugu, and answers from them. If it has nothing, the phone's own result stays.
      if (online &&
          (r.outcome == QaOutcome.answeredWithEvidence ||
              r.outcome == QaOutcome.insufficientEvidence)) {
        setState(() => _expl = _Expl.loading);
        final rag = await qa.ragAnswer(_ctl.text, r, online: online);
        if (!mounted || gen != _gen) return;
        if (rag != null) {
          setState(() {
            _result = rag.result;
            _explanation = rag.explanation;
            _expl = rag.explanation == null ? _Expl.none : _Expl.done;
          });
          if (rag.result.outcome == QaOutcome.escalationRequired) {
            unawaited(HapticFeedback.heavyImpact());
          }
          return;
        }
        if (r.evidence.isEmpty) setState(() => _expl = _Expl.none);
      }
      if (r.evidence.isNotEmpty) {
        if (online) setState(() => _expl = _Expl.loading);
        final e = await qa.explain(_ctl.text, r, online: online);
        if (!mounted || gen != _gen) return; // a newer Check replaced this one
        setState(() {
          _explanation = e;
          _expl = e == null ? _Expl.none : _Expl.done;
        });
      }
    } on QuestionInvalid catch (e) {
      _gen++; // an invalid question never shows an explanation
      if (mounted) {
        setState(() => _expl = _Expl.none);
        setState(
          () => _error = e.reason == 'tooLong' ? l.askTooLong : l.askNeedsText,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _problemText(AppLocalizations l, VoiceProblem p) => switch (p) {
    VoiceProblem.permissionDenied => l.voicePermissionDenied,
    VoiceProblem.unavailable => l.voiceUnavailable,
    VoiceProblem.languageMissing =>
      context.read<AppServices>().connectivity.online
          ? l.voiceLanguageMissing
          : l.voiceOfflineLanguage,
    VoiceProblem.noSpeech => l.voiceNoSpeech,
    VoiceProblem.network => l.voiceNetwork,
    VoiceProblem.other => l.voiceOther,
  };

  String _blockText(AppLocalizations l, VoiceDecision d, String lang) {
    final name = lang == 'te' ? l.voiceLangTelugu : l.voiceLangEnglish;
    final base = switch (d.block!) {
      VoiceBlock.noRecognizer => l.voiceUnavailable,
      VoiceBlock.packMissing => l.voicePackMissing(name),
      VoiceBlock.noOfflineEngine => l.voiceNoOfflineEngine(name),
    };
    final withOnline = d.onlineWouldWork
        ? '$base ${l.voiceOnlineOption}'
        : base;
    // Telugu: the app can fetch its own offline model (Settings), so say so
    return lang == 'te' && d.block != VoiceBlock.noRecognizer
        ? '$withOnline ${l.voiceGetTeluguPack}'
        : withOnline;
  }

  Future<void> _toggleVoice(String lang) async {
    final l = AppLocalizations.of(context);
    final voice = context.read<AppServices>().voice;
    if (_transcribing) return;
    if (_listening) {
      final active = _activeVoice ?? voice;
      // the app's own Telugu model recognises after the worker stops, which takes a moment
      final slow = identical(active, context.read<AppServices>().teluguVoice);
      if (slow && mounted) setState(() => _transcribing = true);
      await active.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _transcribing = false;
        });
      }
      return;
    }
    if (_checkingVoice) return;
    FocusScope.of(context).unfocus();
    final s = context.read<AppServices>();
    setState(() {
      _checkingVoice = true;
      _voiceMsg = null;
    });
    final caps = await s.speechProbe.check();
    final appModel = lang == 'te' && await s.teluguModel.isInstalled();
    if (!mounted) return;
    final d = decideVoiceRoute(
      caps,
      lang: lang,
      allowOnline: s.settings.allowOnlineSpeech,
      online: s.connectivity.online,
      appModelReady: appModel,
    );
    if (d.route == VoiceRoute.blocked) {
      setState(() {
        _checkingVoice = false;
        _voiceMsg = _blockText(l, d, lang);
      });
      return;
    }
    // Voice normally adds to what is in the box (dictating a question in parts). But once the box holds a question that was already
    // checked and was not edited, a new take is a new question: adding to it would answer the OLD question again.
    final asked = _ctl.text.trim().isNotEmpty && _ctl.text.trim() == _checkedText;
    if (asked) _ctl.clear();
    _textBeforeVoice = asked ? '' : _ctl.text.trim();
    setState(() {
      _checkingVoice = false;
      _listening = true;
      _voiceRoute = d.route;
      _result = null;
    });
    final engine = d.route == VoiceRoute.appModel ? s.teluguVoice : voice;
    _activeVoice = engine;
    await engine.start(
      // on-device only: the recogniser is created with createOnDeviceSpeechRecognizer, which never sends audio out
      offline: d.route == VoiceRoute.onDevice,
      localeId: d.locale,
      lang: lang,
      onText: (text, isFinal) {
        if (!_live) return;
        _fromVoice = true;
        final joined = _textBeforeVoice.isEmpty
            ? text
            : '$_textBeforeVoice $text';
        _ctl.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
        setState(() {});
      },
      onProblem: (p) {
        if (_live) setState(() => _voiceMsg = _problemText(l, p));
      },
      onDone: () {
        if (_live) setState(() => _listening = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = context.watch<AppSettings>();
    final phone = settings.escalationPhone;
    final lang = _voiceLang ?? settings.language;
    return HeaderScaffold(
      title: l.askTitle,
      subtitle: l.askSafetyOnDevice,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, 120),
        children: [
          TextField(
            key: const Key('question-field'),
            controller: _ctl,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: _listening ? l.voiceListening : l.askHint,
              errorText: _error,
              counterText: '',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Tk.s12),
          AppCard(
            padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Tk.mintSoft,
                    borderRadius: BorderRadius.circular(Tk.rChip),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LangPill(
                          key: const Key('voice-lang-en'),
                          label: 'English',
                          selected: lang == 'en',
                          onTap: _listening
                              ? null
                              : () => setState(() => _voiceLang = 'en'),
                        ),
                      ),
                      Expanded(
                        child: _LangPill(
                          key: const Key('voice-lang-te'),
                          label: 'తెలుగు',
                          selected: lang == 'te',
                          onTap: _listening
                              ? null
                              : () => setState(() => _voiceLang = 'te'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tk.s16),
                Semantics(
                  button: true,
                  label: _listening ? l.voiceStop : l.voiceSpeak,
                  excludeSemantics: true,
                  child: InkWell(
                    key: const Key('mic-button'),
                    customBorder: const CircleBorder(),
                    onTap: () => _toggleVoice(lang),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _listening ? null : Tk.heroGradient,
                        color: _listening ? Tk.danger : null,
                        boxShadow: [
                          BoxShadow(
                            color: (_listening ? Tk.danger : Tk.primary)
                                .withValues(alpha: 0.35),
                            blurRadius: 22,
                            spreadRadius: _listening ? 8 : 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _listening ? Icons.stop_rounded : Icons.mic,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Tk.s12),
                Text(
                  _checkingVoice
                      ? l.voiceChecking
                      : _transcribing
                      ? l.voiceTranscribing
                      : _listening
                      ? l.voiceListening
                      : l.voiceSpeak,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (_voiceMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s12),
              child: Banner2(
                tone: Tone.warn,
                icon: Icons.mic_off,
                text: _voiceMsg!,
              ),
            ),
          if (_fromVoice && !_listening && _voiceMsg == null)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s12),
              child: Banner2(
                tone: Tone.info,
                icon: Icons.edit_note,
                text: l.voiceCheckText,
              ),
            ),
          const SizedBox(height: Tk.s12),
          FilledButton.icon(
            key: const Key('ask-button'),
            onPressed: (_loading || _listening) ? null : _ask,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_loading ? l.askChecking : l.askButton),
          ),
          const SizedBox(height: Tk.s16),
          if (_result != null && severityOf(_result!.outcome) != null) ...[
            _SeverityStrip(severityOf(_result!.outcome)!),
            const SizedBox(height: Tk.s12),
          ],
          if (_result != null &&
              _resultFromVoice &&
              severityOf(_result!.outcome) != Severity.high) ...[
            // a speech recogniser can mishear a key word, so "no danger sign found" must not be taken for granted
            Banner2(
              key: const Key('voice-result-note'),
              tone: Tone.warn,
              icon: Icons.mic,
              text: AppLocalizations.of(context).voiceResultNote,
            ),
            const SizedBox(height: Tk.s12),
          ],
          if (_result != null)
            QaResultView(
              result: _result!,
              escalationPhone: phone,
              launcher: widget.launcher,
              onAddDetail: (t) {
                _ctl.text = '${_ctl.text.trim()} $t';
                _ctl.selection = TextSelection.collapsed(
                  offset: _ctl.text.length,
                );
                _ask();
              },
            ),
          // BELOW the normal result on purpose: an explanation must never push a danger-sign card down the screen
          if (_expl != _Expl.none) ...[
            if (_result != null) const SizedBox(height: Tk.s16),
            _ExplanationCard(
              loading: _expl == _Expl.loading,
              explanation: _explanation,
            ),
          ],
          // The small privacy notes come AFTER the result so a danger-sign card is never pushed down the screen by them.
          const SizedBox(height: Tk.s16),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Tk.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l.askPrivacy,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: context.read<AppServices>().settings,
            builder: (context, _) =>
                context.read<AppServices>().settings.aiAssist
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.cloud_outlined,
                          size: 14,
                          color: Tk.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l.aiPrivacy,
                            key: const Key('ai-privacy'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mic_none, size: 14, color: Tk.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _voiceRoute == VoiceRoute.online
                      ? l.voicePrivacyOnline
                      : _voiceRoute == VoiceRoute.appModel
                      ? l.voicePrivacyAppModel
                      : l.voicePrivacyOnDevice,
                  key: const Key('voice-privacy'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  const _LangPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(Tk.rChip),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Tk.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(Tk.rChip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Tk.text,
          ),
        ),
      ),
    ),
  );
}

class QaResultView extends StatelessWidget {
  const QaResultView({
    super.key,
    required this.result,
    this.escalationPhone = '',
    this.launcher,
    this.onAddDetail,
  });
  final void Function(String text)? onAddDetail;
  final QaResult result;
  final String escalationPhone;
  final Future<bool> Function(Uri uri)? launcher;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // An active escalation is never answered or reassured. Approved protocol text (if any is loaded) appears below the urgent steps; otherwise the card says none is loaded.
    final body = switch (result.outcome) {
      QaOutcome.escalationRequired => _Escalation(
        result: result,
        phone: escalationPhone,
        launcher: launcher,
      ),
      QaOutcome.clarificationRequired => _Notice(
        tone: Tone.warn,
        icon: Icons.help_outline,
        title: l.clarifyTitle,
        body: _placeholderAware(l, result.message),
        result: result,
        onAddDetail: onAddDetail,
      ),
      QaOutcome.outOfScope => _Notice(
        tone: Tone.neutral,
        icon: Icons.block,
        title: l.outOfScopeTitle,
        body: l.outOfScopeBody,
        result: result,
      ),
      QaOutcome.insufficientEvidence => _Notice(
        tone: Tone.neutral,
        icon: Icons.search_off,
        title: l.insufficientTitle,
        body: l.insufficientBody,
        result: result,
      ),
      QaOutcome.cannotVerifyOffline => _Notice(
        tone: Tone.warn,
        icon: Icons.cloud_off,
        title: l.cannotVerifyTitle,
        body: result.noServerConfigured
            ? l.noServerForAnswer
            : l.cannotVerifyBody,
        result: result,
      ),
      QaOutcome.answeredWithEvidence => _Evidence(result: result),
      QaOutcome.answeredFromRecords => _Records(result: result),
    };
    return Semantics(liveRegion: true, child: body);
  }

  // The safety engine's wording is English. In Telugu the same decision is shown with Telugu text (a draft: see the notes
  // elsewhere); English keeps the engine's own text unchanged.
  String _placeholderAware(AppLocalizations l, String m) =>
      l.localeName == 'te' && result.outcome == QaOutcome.clarificationRequired
      ? l.safetyMsgClarification
      : m;
}

/// The message to show for a safety decision, in the app's language.
String safetyMessage(AppLocalizations l, QaResult r) =>
    l.localeName == 'te' && r.outcome == QaOutcome.escalationRequired
    ? l.safetyMsgEscalation
    : r.message;

String _ruleName(AppLocalizations l, String id) => switch (id) {
  'DSR-BLEEDING-SEVERE' => l.ruleBleeding,
  'DSR-FITS' => l.ruleFits,
  'DSR-BREATHING' => l.ruleBreathing,
  'DSR-UNCONSCIOUS' => l.ruleUnconscious,
  'DSR-FEVER-HIGH' => l.ruleFever,
  'DSR-NOT-FEEDING' => l.ruleNotFeeding,
  'DSR-AMBIGUOUS' => l.ruleAmbiguous,
  'DSR-OUT-OF-SCOPE' => l.ruleOutOfScope,
  _ => l.ruleOther,
};

/// Why the safety check reacted, one line per rule. English keeps the engine's own sentences; Telugu builds each line from the
/// rule that matched (the engine's sentences are English only).
List<String> safetyReasons(AppLocalizations l, QaResult r) {
  if (l.localeName != 'te') return r.reasons;
  final lines = <String>[
    for (final id in r.ruleIds)
      r.outcome == QaOutcome.escalationRequired
          ? l.reasonMatched(_ruleName(l, id))
          : l.reasonNeedsContext(_ruleName(l, id)),
  ];
  if (r.reasons.any((e) => e.startsWith('message too short'))) {
    lines.add(l.reasonShortMessage);
  }
  return lines;
}

class _ValidationFooter extends StatelessWidget {
  const _ValidationFooter({required this.result});
  final QaResult result;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Tk.s12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (!result.clinicallyValidated)
            StatusBadge(
              tone: Tone.warn,
              icon: Icons.rule,
              label: l.notClinicallyValidated,
              dense: true,
            ),
          if (result.needsHumanReview)
            StatusBadge(
              tone: Tone.warn,
              icon: Icons.person_search_outlined,
              label: l.reviewNeeded,
              dense: true,
            ),
          StatusBadge(
            tone: Tone.neutral,
            icon: Icons.tag,
            label: l.rulesetLabel(result.rulesetVersion),
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _Escalation extends StatelessWidget {
  const _Escalation({required this.result, required this.phone, this.launcher});
  final QaResult result;
  final String phone;
  final Future<bool> Function(Uri uri)? launcher;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      key: const Key('escalation-card'),
      // a Material (not a coloured DecoratedBox) so the expandable "why" tile keeps working ripples
      color: Tk.dangerBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tk.rCard),
        side: const BorderSide(color: Tk.danger, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Tk.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Tk.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.escalationTitle,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Tk.danger,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.escalationLead,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Tk.text),
            ),
            const SizedBox(height: 12),
            if (phone.isNotEmpty)
              FilledButton.icon(
                key: const Key('call-supervisor'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tk.danger,
                  minimumSize: const Size.fromHeight(60),
                ),
                onPressed: () => (launcher ?? launchUrl)(
                  Uri(
                    scheme: 'tel',
                    path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
                  ),
                ),
                icon: const Icon(Icons.call),
                label: Text('${l.callSupervisor}  $phone'),
              )
            else
              Text(
                l.noContactConfigured,
                key: const Key('no-contact'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Tk.rButton),
                border: Border.all(color: Tk.danger.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safetyMessage(l, result),
                    key: const Key('escalation-message'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Tk.warn),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.escalationPlaceholderNote,
                          style: const TextStyle(
                            color: Tk.warn,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: Tk.s16),
            if (result.evidence.isNotEmpty) ...[
              Text(
                result.evidence.every((e) => e.isVerified)
                    ? l.escalationGuidanceHeading
                    : l.escalationSampleHeading,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tk.s8),
              _Evidence(result: result, showFooter: false),
            ] else
              Row(
                key: const Key('no-approved-guidance'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    size: 20,
                    color: Tk.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.escalationNoGuidance,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            if (safetyReasons(l, result).isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  l.whyShown,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                children: [
                  for (final r in safetyReasons(l, result))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $r'),
                      ),
                    ),
                ],
              ),
            ],
            _ValidationFooter(result: result),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    required this.result,
    this.onAddDetail,
  });
  final void Function(String text)? onAddDetail;
  final Tone tone;
  final IconData icon;
  final String title, body;
  final QaResult result;
  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Container(
      key: Key('notice-${result.outcome.name}'),
      padding: const EdgeInsets.all(Tk.s16),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: c.fg.withValues(alpha: 0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 30, color: c.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: c.fg),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
          if (safetyReasons(AppLocalizations.of(context), result).isNotEmpty &&
              result.outcome == QaOutcome.clarificationRequired) ...[
            for (final r in safetyReasons(AppLocalizations.of(context), result))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• $r',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          if (result.outcome == QaOutcome.clarificationRequired &&
              onAddDetail != null) ...[
            const SizedBox(height: Tk.s12),
            Text(
              AppLocalizations.of(context).clarifyAddTitle,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Tk.s8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _clarifyChips(AppLocalizations.of(context)))
                  ActionChip(
                    key: Key('clarify-${c.$1}'),
                    label: Text(c.$2),
                    onPressed: () => onAddDetail!(c.$3),
                  ),
              ],
            ),
          ],
          _ValidationFooter(result: result),
        ],
      ),
    );
  }

  /// (key, label, words appended to the question). The words follow the language of the screen so the safety rules can read them.
  List<(String, String, String)> _clarifyChips(AppLocalizations l) {
    final te = l.localeName == 'te';
    return [
      ('now', l.clarifyChipNow, te ? 'ఇప్పుడు' : 'right now'),
      ('severe', l.clarifyChipSevere, te ? 'తీవ్రంగా' : 'severe'),
      (
        'pregnant',
        l.clarifyChipPregnant,
        te ? 'గర్భిణీ స్త్రీ' : 'pregnant woman',
      ),
      ('child', l.clarifyChipChild, te ? 'పసిబిడ్డ' : 'baby'),
    ];
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.result});
  final QaResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = result.records!;
    void open(String id) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HouseholdDetailScreen(householdId: id),
      ),
    );
    final heading = switch (r.intent) {
      RecordIntent.priority =>
        r.count == 0 ? l.recordsNone : l.recordsPriority(r.count),
      RecordIntent.overdue =>
        r.count == 0 ? l.recordsNone : l.recordsOverdue(r.count),
      RecordIntent.dueToday =>
        r.count == 0 ? l.recordsNone : l.recordsDueToday(r.count),
      RecordIntent.openReferrals =>
        r.count == 0 ? l.recordsNone : l.recordsReferrals(r.count),
      RecordIntent.householdCount => l.householdsCount(r.count),
      RecordIntent.household =>
        r.household == null
            ? l.recordsHouseholdMissing(r.householdId ?? '')
            : '${r.householdId}: ${l.recordsHouseholdInfo(householdStatusName(l, r.household!.recordStatus), fmtDate(context, r.household!.nextVisitDueDate), fmtDate(context, r.household!.lastVisitDate))}',
    };
    final cards = [...r.items, if (r.urgency != null) r.urgency!];
    return Container(
      key: const Key('notice-answeredFromRecords'),
      padding: const EdgeInsets.all(Tk.s16),
      decoration: BoxDecoration(
        color: Tk.infoBg,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: Tk.info.withValues(alpha: 0.4), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_rounded, size: 28, color: Tk.info),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l.recordsTitle,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: Tk.info),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            heading,
            key: const Key('records-heading'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          for (final u in cards) ...[
            const SizedBox(height: Tk.s12),
            PriorityCard(item: u, onTap: () => open(u.householdId)),
          ],
          const SizedBox(height: Tk.s12),
          Text(l.recordsFooter, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({required this.result, this.showFooter = true});
  final QaResult result;
  final bool showFooter;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in result.evidence)
          Padding(
            padding: const EdgeInsets.only(bottom: Tk.s12),
            child: Container(
              key: Key(
                e.isVerified ? 'evidence-verified' : 'evidence-unverified',
              ),
              padding: const EdgeInsets.all(Tk.s16),
              decoration: BoxDecoration(
                color: e.isVerified ? Tk.okBg : Tk.warnBg,
                borderRadius: BorderRadius.circular(Tk.rCard),
                border: Border.all(
                  color: (e.isVerified ? Tk.ok : Tk.warn).withValues(
                    alpha: 0.6,
                  ),
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        e.isVerified
                            ? Icons.verified_outlined
                            : Icons.report_gmailerrorred,
                        color: e.isVerified ? Tk.ok : Tk.warn,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            e.isVerified ? l.verifiedTitle : l.unverifiedTitle,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: e.isVerified ? Tk.ok : Tk.warn,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _meta(
                    context,
                    l.sourceDocument,
                    e.documentTitle ?? e.documentId,
                  ),
                  if (e.sectionTitle != null || e.sectionId != null)
                    _meta(
                      context,
                      l.sourceSection,
                      e.sectionTitle ?? e.sectionId!,
                    ),
                  if (e.pageNumber != null)
                    _meta(context, l.sourcePage, '${e.pageNumber}'),
                  if (e.version != null)
                    _meta(context, l.sourceVersion, e.version!),
                  _meta(context, l.sourceStatus, e.verificationStatus),
                  const SizedBox(height: 10),
                  Text(
                    l.passageHeading,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(Tk.rButton),
                      border: Border.all(color: Tk.border),
                    ),
                    child: SelectableText(
                      e.passageText,
                      key: const Key('passage-text'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        result.fromDevice
                            ? Icons.smartphone
                            : Icons.dns_outlined,
                        size: 14,
                        color: Tk.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          result.fromDevice
                              ? l.answeredOnDevice
                              : l.answeredByServer,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (showFooter) _ValidationFooter(result: result),
      ],
    );
  }

  Widget _meta(BuildContext c, String k, String v) =>
      KeyValue(k, v, labelWidth: 92);
}

enum _Expl { none, loading, done }

/// Severity as decided by the phone's own rules, with the action it asks for. One short line so it never pushes the alert down.
class _SeverityStrip extends StatelessWidget {
  const _SeverityStrip(this.severity);
  final Severity severity;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (title, action, color, icon) = switch (severity) {
      Severity.high => (
        l.sevHighTitle,
        l.sevHighAction,
        Tk.danger,
        Icons.warning_amber_rounded,
      ),
      Severity.medium => (
        l.sevMediumTitle,
        l.sevMediumAction,
        Tk.warn,
        Icons.help_outline,
      ),
      Severity.low => (
        l.sevLowTitle,
        l.sevLowAction,
        Tk.info,
        Icons.info_outline,
      ),
    };
    return Semantics(
      container: true,
      child: Container(
        key: Key('severity-${severity.name}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Tk.s12,
          vertical: Tk.s8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Tk.rCard),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: Tk.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                  Text(action, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The explanation of the question, from the AI server or from the phone's own explainer: the same card either way, with the source
/// and any fallback said plainly.
class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.loading, required this.explanation});
  final bool loading;
  final Explanation? explanation;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final e = explanation;
    final server =
        e?.source == ExplanationSource.server ||
        e?.source == ExplanationSource.serverText;
    final note = switch (e?.fallback) {
      FallbackReason.timeout => l.explNoteTimeout,
      FallbackReason.unreachable => l.explNoteUnreachable,
      FallbackReason.unsafe => l.explNoteUnsafe,
      FallbackReason.rejected => l.explNoteRejected,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Tk.s16),
      child: Container(
        key: const Key('explanation'),
        width: double.infinity,
        padding: const EdgeInsets.all(Tk.s16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Tk.rCard),
          border: Border.all(
            color: Tk.info.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: loading
            ? Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.explAsking,
                      key: const Key('explanation-loading'),
                      style: t.bodyMedium,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        server ? Icons.auto_awesome : Icons.phone_android,
                        size: 22,
                        color: Tk.info,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l.explTitle,
                            style: t.titleMedium?.copyWith(
                              color: Tk.info,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e?.source == ExplanationSource.serverText
                        ? l.explFromServerText
                        : server
                        ? l.explFromServer
                        : l.explFromDevice,
                    key: const Key('explanation-source'),
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    e?.text ?? '',
                    key: const Key('explanation-text'),
                    style: t.bodyLarge,
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      note,
                      key: const Key('explanation-note'),
                      style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Tk.warn),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          // word for word from the approved text is not "written by an AI", even when the server found it
                          e?.source == ExplanationSource.server
                              ? l.explDisclaimerServer
                              : l.explDisclaimerDevice,
                          style: const TextStyle(
                            color: Tk.warn,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
