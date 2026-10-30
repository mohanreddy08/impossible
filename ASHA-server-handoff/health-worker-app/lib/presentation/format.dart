import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Indian date style (day first): 13 Oct 2026 / 13 అక్టో 2026, localised to the selected language.
// Creating a DateFormat is slow (it parses the pattern and looks up locale data). Lists format one date per card on every
// redraw, so keep one formatter per pattern and locale instead of building new ones each time.
final _formats = <String, DateFormat>{};
DateFormat _fmt(String pattern, String locale) =>
    _formats.putIfAbsent('$pattern|$locale', () => DateFormat(pattern, locale));

String fmtDate(BuildContext context, DateTime? d) {
  if (d == null) return AppLocalizations.of(context).notSet;
  return _fmt(
    'd MMM yyyy',
    Localizations.localeOf(context).toString(),
  ).format(d);
}

/// 'HH:mm' (24 h) -> "9:05 AM" in the app language.
String fmtVisitTime(BuildContext context, String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 0, m = int.tryParse(p.last) ?? 0;
  return _fmt(
    'h:mm a',
    Localizations.localeOf(context).toString(),
  ).format(DateTime(2000, 1, 1, h, m));
}

String hhmmOf(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// "Wednesday, 14 Oct" (localised), for the Home greeting.
String fmtWeekdayDate(BuildContext context, DateTime d) =>
    _fmt('EEEE, d MMM', Localizations.localeOf(context).toString()).format(d);

String fmtDateTimeIso(BuildContext context, String? iso) {
  if (iso == null) return AppLocalizations.of(context).neverSynced;
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final loc = Localizations.localeOf(context).toString();
  return '${_fmt('d MMM yyyy', loc).format(d)}, ${_fmt('h:mm a', loc).format(d)}';
}

String catName(AppLocalizations l, String c) => switch (c) {
  'ANC' => l.catANC,
  'IMMUNISATION' => l.catIMMUNISATION,
  'NUTRITION' => l.catNUTRITION,
  'HYPERTENSION' => l.catHYPERTENSION,
  'DIABETES' => l.catDIABETES,
  'ROUTINE' => l.catROUTINE,
  'GENERAL' => l.catGENERAL,
  _ => c,
};

String householdStatusName(AppLocalizations l, String s) => switch (s) {
  'UPCOMING' => l.statusUPCOMING,
  'DUE_TODAY' => l.statusDUE_TODAY,
  'OVERDUE' => l.statusOVERDUE,
  'COMPLETED' => l.statusCOMPLETED,
  'NO_VISIT_DUE' => l.statusNO_VISIT_DUE,
  _ => s,
};

String visitStatusName(AppLocalizations l, String s) => switch (s) {
  'PLANNED' => l.visitStatusPLANNED,
  'COMPLETED' => l.visitStatusCOMPLETED,
  'MISSED' => l.visitStatusMISSED,
  'RESCHEDULED' => l.visitStatusRESCHEDULED,
  'CANCELLED' => l.visitStatusCANCELLED,
  _ => s,
};

String freshnessName(AppLocalizations l, String s) => switch (s) {
  'FRESH' => l.freshFRESH,
  'RECENT' => l.freshRECENT,
  'STALE_OFFLINE' => l.freshSTALE_OFFLINE,
  _ => l.freshNOT_PROVIDED,
};
