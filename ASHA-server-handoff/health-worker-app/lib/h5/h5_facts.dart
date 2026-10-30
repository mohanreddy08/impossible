import 'dart:math' as math;

import 'h5_rules.dart';
import 'h5_text.dart';

/// Everything the rules need to know about a question: which concepts it mentions (and whether a mention is negated, as in "pair me
/// sujan ni") and the numbers in it. The Dart twin of health-worker-backend/h5/facts.py; the parity test keeps them identical.
typedef Span = (int, int);

RegExp _rx(String p) => RegExp(foldPattern(p));

String _slice(String s, int a, int b) {
  final x = a < 0 ? 0 : (a > s.length ? s.length : a);
  final y = b < x ? x : (b > s.length ? s.length : b);
  return s.substring(x, y);
}

List<String> _words(String s) {
  final t = s.trim();
  return t.isEmpty ? <String>[] : t.split(RegExp(r'\s+'));
}

final Map<String, RegExp> _unitRx = {
  'year': _rx(r'^(?:sal|saal|years?|yrs?|varsh\w*|vars|vayasu|varshachya)$'),
  'month': _rx(r'^(?:mahin\w*|months?|nelal\w*|mahinya|masa)$'),
  'week': _rx(r'^(?:hafte?|haft\w*|weeks?|hapta|sapt\w*)$'),
  'day': _rx(r'^(?:din|dino|days?|divas\w*|dibas|rojul\w*|dinon)$'),
  'hour': _rx(r'^(?:ghant\w*|hours?|hrs?)$'),
};
const Map<String, double> _daysPer = {'year': 365.0, 'month': 30.4, 'week': 7.0, 'day': 1.0};
final RegExp _numUnit = _rx(
    r'(\d+(?:\.\d+)?)\s*(?:th\s+)?(sal|saal|years?|yrs?|varsh\w*|vars|vayasu|varshachya|mahin\w*|months?|nelal\w*|mahinya|masa|hafte?|haft\w*|weeks?|hapta|sapt\w*|din|dino|days?|divas\w*|dibas|rojul\w*|dinon)\b');
final RegExp _person = _rx(
    r'(?:pillav\w*|bach\w*|baby|babu|navjat\w*|nobojato|beta|beti|bete|ladk\w*|shishu|mulal\w*|amma|chach\w*|aadmi|aurat|mahila|kak[ai]|dad[ai]|nan[ai]|saas|sasur|patient|marij\w*|bahu|ladki)');
final RegExp _personAfter = RegExp(r'^\s*(?:\w+\s+){0,1}' + _person.pattern);
final RegExp _personBefore = RegExp(_person.pattern + r'\s+(?:\w+\s+){0,2}$');
final RegExp _ageWordsAfter = RegExp(r'^\s*(?:ka|ki|ke|old|vala|vali|ho|hu|gaya|gayi|chuka|chuki)\b\s*');
final RegExp _pregAfter = _rx(r'^\s*(?:ki|ka|ke)?\s*(?:pregn\w*|prgn\w*|garbh\w*|gharbh\w*|preg\b)');
final RegExp _childWord = _rx(r'^(?:pillav\w*|babu|bachar|mulal\w*|shishu|bach\w*|baby|navjat\w*)');
final RegExp _babyBefore = RegExp(r'(?:bach\w*|baby|navjat\w*|beta|beti|bete)\s+(?:\w+\s+)?$');
final RegExp _feverCtx = _rx(r'bukh\w*|taap|fever|temperature|temp\b|degree|jvar|daggu|garam|thanda');
final RegExp _tempMark = RegExp(r'\b(?:f|degree|deg|c|fahrenheit|celsius)\b');
final RegExp _tempNum = RegExp(r'(?<![\d/.:])(\d{2,3}(?:\.\d)?)(?![\d/:])');
final RegExp _bpPair = RegExp(r'\b(\d{2,3})\s*/\s*(\d{2,3})\b');

class H5Facts {
  H5Facts(String text, this.rules)
      : raw = text,
        t = normalizeText(text) {
    tokens = _words(t);
    _parseNumbers();
  }

  final H5Rules rules;
  final String raw;
  final String t;
  late final List<String> tokens;
  final Map<String, List<Span>> _cache = {};

  // numbers
  final List<double> ages = [], durations = [], timeagos = [];
  final List<(double, String)> pregUnits = [];
  final List<(double, String, String)> unitsAny = [];
  double? ageDays;
  List<double> breaths = [], weightsKg = [], bpSystolicOnly = [], hbs = [], sugars = [], muacs = [], hours = [], pads = [], padMinutes = [];
  List<double> tempsC = [];
  double? tempCMax, tempFMin;
  List<(int, int)> bps = [];

  // ----------------------------------------------------------------- concepts
  List<Span> spans(String name) {
    final hit = _cache[name];
    if (hit != null) return hit;
    final sp = <Span>[];
    for (final p in rules.concepts[name]!) {
      for (final m in p.allMatches(t)) {
        if (m.end > m.start) sp.add((m.start, m.end));
      }
    }
    return _cache[name] = sp;
  }

  bool has(String name) => spans(name).isNotEmpty;

  static const Set<String> _selfNeg = {
    'not_feeding', 'not_drinking', 'vomit_all', 'movement', 'poor_appetite', 'stroke', 'unconscious', 'hands_feet_only',
    'skin_slow', 'skin_very_slow', 'weak_cry', 'stridor', 'breath_fast', 'blue', 'cold_touch', 'lethargic', 'limp_limbs',
  };

  /// A negation word right after (the next two words) or right before (the previous word): 'sujan ni', 'khun nahi aa raha'.
  bool negated(Span span, [String name = '']) {
    if (_selfNeg.contains(name)) return false;
    final after = _words(t.substring(span.$2)).take(2).join(' ');
    final w = _words(t.substring(0, span.$1));
    final before = w.isEmpty ? '' : w.last;
    final neg = rules.concepts['neg']!;
    return neg.any((p) => p.hasMatch(after)) || neg.any((p) => p.hasMatch(before));
  }

  bool hasPos(String name) => spans(name).any((s) => !negated(s, name));

  bool near(String a, String b, [int window = 40]) {
    for (final s1 in spans(a)) {
      for (final s2 in spans(b)) {
        if (s1 == s2) continue;
        if (s2.$1 - s1.$2 <= window && s1.$1 - s2.$2 <= window) return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------- numbers
  List<double> _floats(String pattern, int group, double lo, double hi) {
    final out = <double>[];
    for (final m in RegExp(foldPattern(pattern)).allMatches(t)) {
      final v = double.tryParse(m.group(group) ?? '');
      if (v != null && v >= lo && v <= hi) out.add(v);
    }
    return out;
  }

  String _unitOf(String word) {
    for (final n in const ['year', 'month', 'week', 'day', 'hour']) {
      if (_unitRx[n]!.hasMatch(word)) return n;
    }
    return '';
  }

  void _parseNumbers() {
    for (final m in _numUnit.allMatches(t)) {
      final val = double.parse(m.group(1)!);
      final unit = _unitOf(m.group(2)!);
      if (unit.isEmpty || unit == 'hour') continue;
      final rest = _words(_slice(t, m.end, m.end + 40));
      final nxt = rest.isNotEmpty ? rest[0] : '';
      final nxt2 = rest.length > 1 ? rest[1] : '';
      final days = val * _daysPer[unit]!;
      unitsAny.add((val, unit, nxt));
      final before = _slice(t, m.start - 14, m.start);
      final beforeWide = _slice(t, m.start - 26, m.start);
      var restText = _slice(t, m.end, m.end + 30);
      if (const ['ka', 'ki', 'ke', 'old', 'vala', 'vali', 'ho', 'hu'].contains(nxt)) {
        restText = restText.replaceFirst(_ageWordsAfter, ' ');
      }
      final pregAfter = _pregAfter.hasMatch(_slice(t, m.end, m.end + 24));
      if (pregAfter && (unit == 'month' || unit == 'week')) {
        pregUnits.add((val, unit));
        continue;
      }
      if (const ['se', 'tak', 'roz'].contains(nxt) || (const ['se', 'tak'].contains(nxt2) && const ['ho', 'chal'].contains(nxt))) {
        durations.add(days);
      } else if (const ['pehle', 'pahle', 'bad', 'baad'].contains(nxt) || (nxt == 'ke' && const ['bad', 'baad', 'pehle'].contains(nxt2))) {
        timeagos.add(days);
      } else if (const ['ka', 'ki', 'ke', 'old', 'vala', 'vali'].contains(nxt) ||
          (const ['ho', 'hu'].contains(nxt) && const ['gaya', 'gayi', 'chuka', 'chuki'].contains(nxt2))) {
        if (_personAfter.hasMatch(restText) || _personBefore.hasMatch(beforeWide)) ages.add(days);
      } else if (const ['hue', 'hu', 'ho'].contains(nxt) && rules.concepts['delivery']!.any((p) => p.hasMatch(before))) {
        timeagos.add(days);
      } else if (_childWord.hasMatch(nxt)) {
        ages.add(days);
      } else if (_babyBefore.hasMatch(before) && const ['hai', 'he'].contains(nxt)) {
        ages.add(days);
      }
    }
    ageDays = ages.isEmpty ? null : ages.reduce(math.min);

    breaths = _floats(r'(?:saans|breath\w*|swas\w*|hanf\w*)\W+(?:\w+\W+){0,3}?(\d{2,3})\b(?!\s*/)', 1, 20, 130) +
        _floats(r'\bminute\s+(?:me|men|mein)\s+(\d{2,3})\b', 1, 20, 130) +
        _floats(r'\b(\d{2,3})\s*(?:per\s*minute|/\s*min|bar\b|baar\b|count\b|breaths?\b|\bmin\b)', 1, 20, 130) +
        _floats(r'\bgin\w*\s+(?:\w+\s+){0,2}(\d{2,3})\b', 1, 20, 130);

    final temps = <double>[];
    for (final mm in _tempNum.allMatches(t)) {
      final raw = mm.group(1)!;
      final v = double.parse(raw);
      final ctx = _slice(t, mm.start - 40, mm.end + 22);
      final marked = _tempMark.hasMatch(_slice(t, mm.end, mm.end + 14));
      if (_feverCtx.hasMatch(ctx) || marked) {
        if (v >= 94 && v <= 108) {
          temps.add((v - 32) * 5 / 9);
        } else if (v >= 35 && v <= 42.5 && (marked || RegExp(r'\.\d').hasMatch(raw))) {
          temps.add(v);
        }
      }
    }
    tempsC = temps;
    tempCMax = temps.isEmpty ? null : temps.reduce(math.max);
    tempFMin = temps.isEmpty ? null : temps.reduce(math.min) * 9 / 5 + 32;

    weightsKg = _floats(r'(\d(?:\.\d{1,2})?)\s*(?:kg|kilo|kgs)\b', 1, 0.5, 9);
    bps = [
      for (final m in _bpPair.allMatches(t))
        if (int.parse(m.group(1)!) >= 60 && int.parse(m.group(1)!) <= 260 && int.parse(m.group(2)!) >= 30 && int.parse(m.group(2)!) <= 160)
          (int.parse(m.group(1)!), int.parse(m.group(2)!)),
    ];
    bpSystolicOnly = _floats(r'\bbp\s*(?:ka\s*)?(?:aaya\s*)?(\d{3})\b(?!\s*/)', 1, 80, 260);
    hbs = _floats(r'\bhb\s*(?:ka\s*)?(?:level\s*)?(?:aaya\s*)?(\d{1,2}(?:\.\d)?)\b', 1, 2, 20);
    sugars = _floats(r'sugar\s*(?:level\s*)?(?:ka\s*)?(?:random\s*)?(?:aaya\s*)?(\d{2,3})\b', 1, 20, 700) +
        _floats(r'\brbs\s*(\d{2,3})\b', 1, 20, 700);
    muacs = _floats(r'\bmuac\s*(?:ka\s*)?(?:aaya\s*)?(\d{1,2}(?:\.\d)?)\b', 1, 5, 25);
    hours = _floats(r'(\d+(?:\.\d)?)\s*(?:ghant\w*|hours?|hrs?)\b', 1, 1, 100);
    pads = _floats(r'(\d{1,2})\s*(?:pads?|ped|paid|kapde)\b', 1, 1, 60);
    padMinutes = _floats(r'\b(?:pads?|ped|paid|kapda)\s+(\d{1,2})(?:\s*-\s*\d{1,2})?\s*(?:minute|min)\w*', 1, 1, 60) +
        _floats(r'\b(\d{1,2})\s*(?:minute|min)\w*\s+(?:me|men)\s+(?:\w+\s+){0,2}(?:pads?|ped|paid|bhar)', 1, 1, 60);
  }
}
