import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/keyboard_settings.dart';
import '../widgets/common.dart';
import '../widgets/header_scaffold.dart';

/// Step-by-step help for the other way to speak Telugu: the Google keyboard's own voice typing. It is the phone's service, not this
/// app's, so the screen says plainly that it normally needs internet and that audio goes to Google.
class TeluguKeyboardHelpScreen extends StatefulWidget {
  const TeluguKeyboardHelpScreen({super.key});
  @override
  State<TeluguKeyboardHelpScreen> createState() =>
      _TeluguKeyboardHelpScreenState();
}

class _TeluguKeyboardHelpScreenState extends State<TeluguKeyboardHelpScreen> {
  bool _failed = false;

  Future<void> _open() async {
    final ok = await KeyboardSettings.open();
    if (mounted) setState(() => _failed = !ok);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final steps = [
      (l.altStep1Title, l.altStep1Body),
      (l.altStep2Title, l.altStep2Body),
      (l.altStep3Title, l.altStep3Body),
      (l.altStep4Title, l.altStep4Body),
      (l.altStep5Title, l.altStep5Body),
      (l.altStep6Title, l.altStep6Body),
      (l.altStep7Title, l.altStep7Body),
    ];
    return HeaderScaffold(
      title: l.altVoiceTitle,
      showBack: true,
      child: ListView(
        key: const Key('telugu-keyboard-help'),
        padding: const EdgeInsets.fromLTRB(Tk.s16, Tk.s16, Tk.s16, Tk.s32),
        children: [
          Text(l.altVoiceIntro, style: t.bodyLarge),
          const SizedBox(height: Tk.s16),
          for (var i = 0; i < steps.length; i++)
            Padding(
              key: Key('alt-step-${i + 1}'),
              padding: const EdgeInsets.only(bottom: Tk.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Tk.primary,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: Tk.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].$1,
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: Tk.s4),
                        Text(steps[i].$2, style: t.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          FilledButton.icon(
            key: const Key('alt-open-keyboard-settings'),
            onPressed: _open,
            icon: const Icon(Icons.keyboard_alt_outlined),
            label: Text(l.altOpenKeyboardSettings),
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: Tk.s12),
              child: Text(
                l.altOpenFailed,
                key: const Key('alt-open-failed'),
                style: t.bodySmall?.copyWith(color: Tk.danger),
              ),
            ),
          const SizedBox(height: Tk.s16),
          Banner2(
            key: const Key('alt-voice-note'),
            tone: Tone.warn,
            icon: Icons.info_outline,
            text: l.altVoiceNote,
          ),
        ],
      ),
    );
  }
}
