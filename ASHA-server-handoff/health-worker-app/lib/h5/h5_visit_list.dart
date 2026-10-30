// Daily visit list from the household register, exactly as written in the VIS protocol (VIS-1 to VIS-6): the Dart twin of
// health-worker-backend/h5/visit_list.py. Pure functions over plain maps (register column -> text); the parity test checks both give the
// same rows for all 2,234 members.

// VIS-1.3 counting conventions [block rule]
const int upcomingHorizonDays = 6;
const int graceDays = 28;
const int followupIntervalDays = 30;
const int td2GapDays = 28;
const int vaccineListAgeToDays = 2554;
const int hbncAgeToDays = 42;
const int muacAgeFromDays = 184;
const int muacAgeToDays = 1824;
const int muacConsiderFromDays = 178; // VIS-5.2: a child turning 184 days within 6 days is listed as due_this_week

// VIS-5.1 thresholds
const double hbBelow = 7.0;
const int systolicAtOrAbove = 140;
const int diastolicAtOrAbove = 90;
const double muacBelowCm = 11.5;

// VIS-2.1 ANC windows: item -> (opens, closes) in days since LMP
const Map<int, (int, int)> ancWindows = {1: (0, 84), 2: (98, 182), 3: (196, 238), 4: (252, 280)};

/// VIS-3.1 vaccine table: item -> (due from age, not after age, previous dose needed, minimum gap in days)
const Map<String, (int, int, String?, int)> vaccines = {
  'BCG': (0, 365, null, 0),
  'HepB-0': (0, 0, null, 0),
  'OPV-0': (0, 15, null, 0),
  'OPV-1': (42, 1825, null, 0),
  'OPV-2': (70, 1825, 'OPV-1', 28),
  'OPV-3': (98, 1825, 'OPV-2', 28),
  'Penta-1': (42, 365, null, 0),
  'Penta-2': (70, 365, 'Penta-1', 28),
  'Penta-3': (98, 365, 'Penta-2', 28),
  'RVV-1': (42, 365, null, 0),
  'RVV-2': (70, 365, 'RVV-1', 28),
  'RVV-3': (98, 365, 'RVV-2', 28),
  'fIPV-1': (42, 365, null, 0),
  'fIPV-2': (98, 365, 'fIPV-1', 56),
  'fIPV-3': (276, 729, 'fIPV-2', 56),
  'PCV-1': (42, 365, null, 0),
  'PCV-2': (98, 729, 'PCV-1', 60),
  'PCV-B': (276, 729, 'PCV-2', 60),
  'MR-1': (276, 1825, null, 0),
  'MR-2': (490, 1825, 'MR-1', 28),
  'OPV-B': (490, 1825, 'OPV-3', 180),
  'DPT-B1': (490, 2554, 'Penta-3', 180),
  'DPT-B2': (1827, 2554, 'DPT-B1', 0),
};

/// VIS-4.1 HBNC visit days
const List<int> _hbncInstitution = [3, 7, 14, 21, 28, 42];
const List<int> _hbncHome = [1, 3, 7, 14, 21, 28, 42];

/// A calendar day (no time, no time zone).
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
DateTime plus(DateTime d, int days) => d.add(Duration(days: days));
int daysBetween(DateTime later, DateTime earlier) => later.difference(earlier).inDays;
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final RegExp _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

DateTime? parseDate(String? s) {
  final m = _iso.firstMatch((s ?? '').trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  return (dt.year == y && dt.month == mo && dt.day == d) ? dt : null; // 2026-02-30 is not a date
}

/// 'Penta-3', 'PENTA 3', 'penta3' -> 'penta3' (VIS-1.4: vaccine codes are written many ways).
String vaccineKey(String code) => code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

final Map<String, String> _vaccineByKey = {for (final k in vaccines.keys) vaccineKey(k): k};

/// '154/90' -> (154, 90). '0/0', blanks and rubbish mean 'not recorded' (VIS-1.4).
(int, int)? parseBp(String? s) {
  final m = RegExp(r'^\s*(\d{2,3})\s*/\s*(\d{2,3})\s*$').firstMatch(s ?? '');
  if (m == null) return null;
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  return (a == 0 && b == 0) ? null : (a, b);
}

bool bpIsHigh((int, int)? bp) => bp != null && (bp.$1 >= systolicAtOrAbove || bp.$2 >= diastolicAtOrAbove);

double? _float(String? s) => double.tryParse((s ?? '').trim());

String _s(Map<String, String> r, String k) => r[k] ?? '';
bool _yes(Map<String, String> r, String k) => _s(r, k).trim().toUpperCase() == 'Y';

/// 'BCG:2026-09-27;penta1:2026-10-01' -> {BCG: date, Penta-1: date}. Duplicates count once (earliest date).
Map<String, DateTime?> parseDoses(String cell, Map<String, String> tableKeys) {
  final out = <String, DateTime?>{};
  for (var part in cell.split(';')) {
    part = part.trim();
    if (part.isEmpty) continue;
    final i = part.indexOf(':');
    final code = i < 0 ? part : part.substring(0, i);
    final canon = tableKeys[vaccineKey(code)];
    if (canon == null) continue;
    final dt = parseDate(i < 0 ? '' : part.substring(i + 1));
    if (!out.containsKey(canon) || (dt != null && (out[canon] == null || dt.isBefore(out[canon]!)))) out[canon] = dt;
  }
  return out;
}

String? _status(DateTime due, DateTime today, [DateTime? overdueAfter]) {
  final lastOk = overdueAfter ?? plus(due, graceDays);
  if (due.isAfter(plus(today, upcomingHorizonDays))) return null;
  if (due.isAfter(today)) return 'due_this_week';
  return today.isAfter(lastOk) ? 'overdue' : 'due_today';
}

class H5Item {
  const H5Item(this.item, this.status, this.due);
  final String item, status;
  final DateTime due;
}

/// One row of the visit list.
class H5VisitRow {
  const H5VisitRow(this.memberId, this.item, this.priority, this.status, this.dueDate);
  final String memberId, item, status, dueDate;
  final int priority;
  List<Object> toList() => [memberId, item, priority, status, dueDate];
}

bool isHighRisk(Map<String, String> r, DateTime today, int? ageDays) {
  if (_yes(r, 'pregnant')) {
    final hb = _float(_s(r, 'last_hb_gdl'));
    if ((hb != null && hb < hbBelow) || bpIsHigh(parseBp(_s(r, 'last_anc_bp')))) return true;
  }
  if (ageDays != null && ageDays >= 0 && ageDays <= hbncAgeToDays) return true;
  if (ageDays != null && ageDays >= muacAgeFromDays && ageDays <= muacAgeToDays) {
    final muac = _float(_s(r, 'last_muac_cm'));
    if ((muac != null && muac < muacBelowCm) || _yes(r, 'bilateral_pitting_oedema')) return true;
  }
  if (_s(r, 'ncd_condition').trim().isNotEmpty && bpIsHigh(parseBp(_s(r, 'last_bp_reading')))) return true;
  return false;
}

/// All (item, status, due date) for one register row, before priorities.
List<H5Item> memberItems(Map<String, String> r, DateTime today) {
  final items = <H5Item>[];
  void add(String item, DateTime due, {DateTime? overdueAfter}) {
    final st = _status(due, today, overdueAfter);
    if (st != null) items.add(H5Item(item, st, due));
  }

  final dob = parseDate(_s(r, 'dob'));
  final age = dob == null ? null : daysBetween(today, dob);

  // ---- VIS-2 pregnant women
  if (_yes(r, 'pregnant')) {
    final lmp = parseDate(_s(r, 'lmp_date'));
    final ancDates = <DateTime>{
      for (final x in _s(r, 'anc_visit_dates').split(';'))
        if (parseDate(x) != null) parseDate(x)!,
    }.toList()
      ..sort();
    if (lmp != null) {
      final k = ancDates.length + 1;
      final w = ancWindows[k];
      if (w != null) add('ANC-$k', plus(lmp, w.$1), overdueAfter: plus(lmp, w.$2));
    }
    // Td (VIS-2.2): Td-1 (or Td-BST) is due on the date of the first recorded ANC check-up
    if (ancDates.isNotEmpty) {
      final td = parseDoses(_s(r, 'td_doses'), {for (final c in const ['Td-1', 'Td-2', 'Td-BST']) vaccineKey(c): c});
      final first = ancDates.first;
      if (_yes(r, 'td_booster_eligible')) {
        if (!td.containsKey('Td-BST')) add('Td-BST', first);
      } else {
        if (!td.containsKey('Td-1')) add('Td-1', first);
        if (td.containsKey('Td-1') && !td.containsKey('Td-2') && td['Td-1'] != null) add('Td-2', plus(td['Td-1']!, td2GapDays));
      }
    }
    // VIS-2.3 high-risk follow-up: on every day's list, due_today
    final hb = _float(_s(r, 'last_hb_gdl'));
    if ((hb != null && hb < hbBelow) || bpIsHigh(parseBp(_s(r, 'last_anc_bp')))) items.add(H5Item('HRP-followup', 'due_today', today));
  }

  // ---- VIS-3 vaccines
  if (age != null && age >= 0 && age <= vaccineListAgeToDays) {
    final given = parseDoses(_s(r, 'child_vaccines'), _vaccineByKey);
    for (final e in vaccines.entries) {
      final (fromAge, notAfter, prev, gap) = e.value;
      if (given.containsKey(e.key) || age > notAfter) continue;
      var due = plus(dob!, fromAge);
      if (prev != null) {
        if (!given.containsKey(prev)) continue;
        final pd = given[prev];
        if (pd == null) continue;
        final earliest = plus(pd, gap);
        if (earliest.isAfter(due)) due = earliest;
      }
      if (daysBetween(due, dob) > notAfter) continue; // its due date falls after its "not after" age
      final a = plus(due, graceDays), b = plus(dob, notAfter - 1);
      add(e.key, due, overdueAfter: a.isBefore(b) ? a : b);
    }
  }

  // ---- VIS-4 newborn HBNC home visits
  if (age != null && age >= 0 && age <= hbncAgeToDays) {
    final place = _s(r, 'place_of_delivery').trim().toLowerCase();
    final days = place == 'home' ? _hbncHome : _hbncInstitution;
    final done = {for (final m in RegExp(r'\d+').allMatches(_s(r, 'hbnc_visits_done'))) int.parse(m.group(0)!)};
    final sched = [for (final d in days) (d, plus(dob!, d - 1))];
    final past = [for (final s in sched) if (!s.$2.isAfter(today)) s];
    var listed = false;
    if (past.isNotEmpty) {
      final (d, dt) = past.last;
      if (!done.contains(d)) {
        items.add(H5Item('HBNC-D$d', dt == today ? 'due_today' : 'overdue', dt));
        listed = true;
      }
    }
    if (!listed) {
      final future = [for (final s in sched) if (s.$2.isAfter(today)) s];
      if (future.isNotEmpty) {
        final (d, dt) = future.first;
        if (daysBetween(dt, today) <= upcomingHorizonDays && !done.contains(d)) items.add(H5Item('HBNC-D$d', 'due_this_week', dt));
      }
    }
  }

  // ---- VIS-5.2 MUAC check
  if (age != null && age >= muacConsiderFromDays && age <= muacAgeToDays) {
    final last = parseDate(_s(r, 'last_muac_date'));
    add('MUAC-check', last != null ? plus(last, followupIntervalDays) : plus(dob!, muacAgeFromDays));
  }

  // ---- VIS-5.3 NCD follow-up
  final ncd = _s(r, 'ncd_condition').toUpperCase();
  for (final (cond, item, col) in const [('HTN', 'BP-followup', 'last_bp_check_date'), ('DM', 'Sugar-followup', 'last_sugar_check_date')]) {
    if (ncd.contains(cond)) {
      final last = parseDate(_s(r, col));
      if (last == null) {
        items.add(H5Item(item, 'overdue', today)); // no check date recorded: overdue
      } else {
        add(item, plus(last, followupIntervalDays));
      }
    }
  }
  return items;
}

List<H5VisitRow> buildVisitList(Iterable<Map<String, String>> register, DateTime today) {
  final rows = <H5VisitRow>[];
  for (final r in register) {
    final dob = parseDate(_s(r, 'dob'));
    final age = dob == null ? null : daysBetween(today, dob);
    final high = isHighRisk(r, today, age);
    for (final it in memberItems(r, today)) {
      final priority = (it.status == 'overdue' || it.status == 'due_today') ? (high ? 1 : 2) : 3;
      rows.add(H5VisitRow(r['member_id']!, it.item, priority, it.status, isoDate(it.due)));
    }
  }
  return rows;
}
