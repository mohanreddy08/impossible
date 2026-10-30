/// "Today" for the app. The synthetic data is anchored at 2026-10-13, so demo mode can pin the date.
class AppClock {
  AppClock({DateTime Function()? now, this.demoDate})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? demoDate;

  /// Date-only (local) value used for every due/overdue calculation.
  DateTime today() {
    final d = demoDate ?? _now();
    return DateTime(d.year, d.month, d.day);
  }

  DateTime nowUtc() => _now().toUtc();

  /// Phone-local current date and time (for a visit's time of day).
  DateTime localNow() => _now();
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final p = s.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}
