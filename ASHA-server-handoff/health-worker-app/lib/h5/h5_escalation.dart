import 'h5_facts.dart';
import 'h5_text.dart';

/// The hard-coded danger-sign layer (ESC protocol): the Dart twin of health-worker-backend/h5/escalation.py. It runs BEFORE retrieval and
/// before any model, on the phone, with no network. One rule per sign of the ESC document, each tied to its leaf section.
class H5Decision {
  final List<String> rules = [];
  final List<String> sections = [];
  String subject = '';
  bool get escalate => rules.isNotEmpty;

  void add(String rule, [String? s1, String? s2]) {
    if (!rules.contains(rule)) rules.add(rule);
    for (final s in [s1, s2]) {
      if (s != null && !sections.contains(s)) sections.add(s);
    }
  }
}

final RegExp _hypothetical = RegExp(foldPattern(
    r'aaye\s+to|ae\s+to|ho\s+to\b|kise\s+kehte|kitne\s+se\s+(?:upar|kam|zyada|jyada)|kitna\s+ho\s+to|maane|maana\s+jata|kab\s+maana|se\s+upar\s+aaye'));
final RegExp _howto = RegExp(foldPattern(r'kaise\s+(?:check|pata|dekh|jaanch|naap|kare|karte)|how\s+to'));
final RegExp _bleedAfter = RegExp(r'^\s*(?:ki\s+(?:kami|jach|kam)|ka\s+test|badh|jach)');
final RegExp _numberIn = RegExp(r'\b(\d{1,3})\b');

/// (pregnant, postpartum, newborn, child)
(bool, bool, bool, bool) subjectOf(H5Facts f) {
  final age = f.ageDays;
  final ago = f.timeagos.isEmpty ? null : f.timeagos.reduce((a, b) => a < b ? a : b);
  final preg = f.has('pregnant') || (f.has('pregnant_month_phrase') && !f.has('baby')) || f.pregUnits.isNotEmpty || f.has('anc_word');
  final pp = f.has('postpartum_phrase') && (ago == null || ago <= 45) && (f.has('mother') || f.has('delivery'));
  var newborn = f.has('newborn_word') || f.has('cord') || (age != null && age <= 59 && f.has('baby'));
  var child = f.has('baby') && !newborn && (age == null || (age >= 60 && age <= 1830));
  if (f.has('newborn_word') && age != null && age > 59) {
    newborn = false;
    child = true;
  }
  if (pp && newborn && ago != null && age == null) {
    newborn = f.has('newborn_word') && !f.has('mother');
  }
  return (preg, pp, newborn, child);
}

bool _bleedingPositive(H5Facts f) {
  for (final s in f.spans('bleeding')) {
    if (f.negated(s, 'bleeding')) continue;
    final end = s.$2 + 14 > f.t.length ? f.t.length : s.$2 + 14;
    if (_bleedAfter.hasMatch(f.t.substring(s.$2, end))) continue;
    return true;
  }
  return false;
}

double _min(List<double> v) => v.reduce((a, b) => a < b ? a : b);
double _max(List<double> v) => v.reduce((a, b) => a > b ? a : b);

H5Decision decideDanger(H5Facts f) {
  final d = H5Decision();
  final (preg, pp, nb, child) = subjectOf(f);
  final baby = f.has('baby');
  final hyp = _hypothetical.hasMatch(f.t);
  d.subject = nb ? 'newborn' : pp ? 'postpartum' : preg ? 'pregnant' : child ? 'child' : 'adult';

  final fits = f.hasPos('fits');
  final unconscious = f.hasPos('unconscious');
  final lethargic = f.hasPos('lethargic');
  final notFeeding = f.hasPos('not_feeding');
  final notDrinking = f.hasPos('not_drinking');
  final vomitAll = f.hasPos('vomit_all');
  final fever = f.has('fever');
  final afterVaccine = f.has('vaccine_ctx') && f.hasPos('fits');
  final ncd = f.has('ncd_context');
  final adultCtx = f.has('adult_patient') && !baby;

  // ---- ESC-2 pregnancy
  if (preg && !nb) {
    final bleed = _bleedingPositive(f);
    if (bleed && !f.near('bleeding', 'stool_ctx', 18) && !(pp && (f.pads.isNotEmpty || f.padMinutes.isNotEmpty))) {
      d.add('preg-bleeding', 'ESC-2.1');
    }
    if (fits || unconscious) d.add('preg-fits-or-faint', 'ESC-2.2');
    if (f.bps.any((p) => p.$1 >= 140 || p.$2 >= 90) && !hyp) d.add('preg-bp-140-90', 'ESC-2.3');
    if (f.hasPos('blur_vision') || f.hasPos('swelling_face') || (f.hasPos('headache') && f.has('severe'))) {
      d.add('preg-preeclampsia-signs', 'ESC-2.3');
    }
    if ((f.tempCMax != null && f.tempCMax! > 38.0) || (fever && f.hasPos('high_fever'))) d.add('preg-high-fever', 'ESC-2.4');
    if (f.hbs.any((h) => h < 7.0) && !hyp) d.add('preg-hb-below-7', 'ESC-2.5');
    if (f.hasPos('pallor') && (f.hasPos('breath_fast') || f.has('severe')) && !hyp) d.add('preg-severe-pallor', 'ESC-2.5');
    if (f.hasPos('breath_fast') && !hyp) d.add('preg-breathless', 'ESC-2.5');
    if (f.has('belly_pain') && f.has('severe') && !f.has('improving')) d.add('preg-severe-belly-pain', 'ESC-2.6');
    if (f.hasPos('vomit') && (vomitAll || f.has('severe'))) d.add('preg-excessive-vomiting', 'ESC-2.6');
    if (f.hasPos('foul') && (f.has('vaginal_ctx') || f.has('pregnant')) && !f.has('cord')) d.add('preg-foul-discharge', 'ESC-2.8');
    if (f.has('limb_first') || f.has('placenta_stuck') || f.has('twins')) d.add('labour-complication', 'ESC-2.8');
  }

  // these name the pregnancy themselves, so "pregnant" need not be written
  if (f.hasPos('movement') && !nb) d.add('reduced-foetal-movement', 'ESC-2.7');
  if (f.hasPos('water_bag') && !hyp && !nb) d.add('water-bag-leaking', 'ESC-2.8');
  if (f.hours.isNotEmpty && f.has('labour_pain') && _max(f.hours) > 12) d.add('labour-over-12h', 'ESC-2.8');

  // ---- ESC-3 mother after delivery
  if (pp && !(nb && !f.has('mother'))) {
    if ((f.pads.isNotEmpty && _max(f.pads) > 5) || (f.padMinutes.isNotEmpty && _min(f.padMinutes) < 5)) {
      d.add('pp-heavy-bleeding', 'ESC-3.1');
    } else if (_bleedingPositive(f) && f.has('severe') && !hyp) {
      d.add('pp-heavy-bleeding', 'ESC-3.1');
    }
    if ((f.tempCMax != null && f.tempCMax! > 38.0) || (fever && f.hasPos('high_fever')) || (f.hasPos('foul') && fever)) {
      d.add('pp-fever-or-foul-discharge', 'ESC-3.2');
    }
    if (fits || unconscious || f.hasPos('abnormal_behavior') || (f.hasPos('headache') && f.hasPos('blur_vision'))) {
      d.add('pp-fits-or-abnormal', 'ESC-3.3');
    }
    if (f.hasPos('breath_fast') || (f.hasPos('pallor') && f.has('severe')) || (f.has('belly_pain') && f.has('severe'))) {
      d.add('pp-breathless-pallor-pain', 'ESC-3.4');
    }
  }

  // ---- ESC-4 newborn / young infant (up to 2 months)
  if (nb) {
    if (notFeeding || f.hasPos('weak_cry') || f.hasPos('limp_limbs') || lethargic || unconscious || fits) {
      d.add('nb-feeding-cry-activity-fits', 'ESC-4.1');
    }
    if ((f.breaths.isNotEmpty && _max(f.breaths) >= 60) || f.hasPos('chest_indraw') || f.hasPos('blue') || (f.hasPos('breath_fast') && !hyp)) {
      d.add('nb-breathing', 'ESC-4.2');
    }
    if (!hyp) {
      if ((f.tempCMax != null && f.tempCMax! > 37.2) || (fever && f.tempCMax == null && f.hasPos('fever'))) d.add('nb-fever', 'ESC-4.3');
      if ((f.tempFMin != null && f.tempFMin! < 95.9) || (f.hasPos('cold_touch') && !f.has('hands_feet_only'))) d.add('nb-cold', 'ESC-4.3');
    }
    final cordBad = f.near('cord', 'pus', 45) || f.near('cord', 'red_area', 45) || f.near('cord', 'bleeding', 45) || f.near('cord', 'foul', 45);
    if (cordBad && !f.has('generic_question')) d.add('nb-cord-infection', 'ESC-4.4');
    if (f.has('pustules') && f.has('pus')) {
      for (final s in f.spans('pustules')) {
        final a = s.$1 - 40 < 0 ? 0 : s.$1 - 40;
        final b = s.$2 + 40 > f.t.length ? f.t.length : s.$2 + 40;
        final nums = [for (final m in _numberIn.allMatches(f.t.substring(a, b))) int.parse(m.group(1)!)];
        if (nums.isNotEmpty && nums.reduce((x, y) => x > y ? x : y) >= 10) {
          d.add('nb-pustules-10-plus', 'ESC-4.4');
          break;
        }
      }
    }
    if (f.hasPos('jaundice') && (f.has('day_one') || f.has('palms_soles') || (f.ageDays != null && f.ageDays! >= 14))) {
      d.add('nb-jaundice', 'ESC-4.4');
    }
    if (f.hasPos('distended') || (f.hasPos('vomit') && f.has('severe'))) d.add('nb-distended-or-vomiting', 'ESC-4.4');
    if (f.hasPos('stool_blood')) d.add('nb-blood-in-stool', 'ESC-4.4');
    if (f.weightsKg.any((w) => w < 1.8) && !hyp) d.add('nb-weight-below-1.8', 'ESC-4.4');
  }

  // ---- ESC-5 child 2 months - 5 years
  if (child || (baby && !nb)) {
    final gds = fits || unconscious || lethargic || notFeeding || notDrinking || vomitAll;
    if (notFeeding || notDrinking || vomitAll || fits || unconscious || lethargic) d.add('child-general-danger-sign', 'ESC-5.1');
    final age = f.ageDays;
    final thr = (age != null && age < 365) ? 50 : 40;
    if (f.breaths.isNotEmpty && _max(f.breaths) >= thr && !hyp) d.add('child-fast-breathing', 'ESC-5.2');
    if (f.hasPos('chest_indraw') || f.hasPos('stridor') || f.hasPos('blue')) d.add('child-chest-indrawing-or-stridor', 'ESC-5.2');
    if (f.hasPos('stool_blood') && !hyp) d.add('child-blood-in-stool', 'ESC-5.3');
    final diar = f.has('diarrhoea');
    if (diar && f.durations.isNotEmpty && _max(f.durations) >= 14) d.add('child-diarrhoea-14-days', 'ESC-5.3');
    final sev = ((lethargic || unconscious) ? 1 : 0) + (f.hasPos('dehydr_sunken') ? 1 : 0) + (notDrinking ? 1 : 0) + (f.hasPos('skin_very_slow') ? 1 : 0);
    if (sev >= 2) d.add('child-severe-dehydration', 'ESC-5.3');
    final sam = f.muacs.isNotEmpty && _min(f.muacs) < 11.5;
    if (diar && sam) d.add('child-diarrhoea-with-sam', 'ESC-5.3');
    if (fever && (gds || f.hasPos('stiff_neck'))) d.add('child-fever-with-danger-sign', 'ESC-5.4');
    if (fever && f.durations.isNotEmpty && _max(f.durations) > 7 && !diar) d.add('child-fever-over-7-days', 'ESC-5.4');
    final oedema = f.hasPos('swelling_feet') && (f.has('pitting') || f.tokens.contains('dono')) && !_howto.hasMatch(f.t);
    if (oedema) d.add('child-oedema-both-feet', 'ESC-5.5', 'NUT-2.1');
    if (sam && (f.hasPos('poor_appetite') || f.hasPos('wasted') || lethargic || f.hasPos('breath_fast') || f.hasPos('pallor') || f.hasPos('irritable') || oedema)) {
      d.add('child-sam-with-complication', 'ESC-5.5', 'NUT-2.1');
    }
    if (age != null && age < 184 && (f.hasPos('wasted') || (notFeeding && f.has('weak_cry')))) d.add('infant-wasted-or-too-weak-to-suckle', 'ESC-5.5');
    if (f.hasPos('wasted') && f.hasPos('not_feeding') && d.rules.isEmpty) d.add('infant-wasted-or-too-weak-to-suckle', 'ESC-5.5');
    if (afterVaccine || ((f.has('vaccine_ctx') && (f.hasPos('breath_fast') || f.hasPos('swelling_face'))) && !f.has('improving'))) {
      if (fits || f.hasPos('breath_fast') || f.hasPos('swelling_face') || lethargic) d.add('child-reaction-after-vaccine', 'ESC-5.6');
    }
    if (f.hasPos('pallor') && f.has('palms_soles') && f.has('severe')) d.add('child-severe-palmar-pallor', 'ESC-5.7');
  }

  // ---- ESC-6 adults with hypertension / diabetes (and other adults)
  if (!baby && !preg && !pp) {
    if (f.bps.any((p) => p.$1 >= 180 || p.$2 >= 110) && !hyp) d.add('adult-bp-180-110', 'ESC-6.4');
    if (f.bpSystolicOnly.any((x) => x >= 180) && !hyp) d.add('adult-bp-180-110', 'ESC-6.4');
    if (f.hasPos('chest_pain')) d.add('adult-chest-pain', 'ESC-6.1');
    if (f.hasPos('stroke')) d.add('adult-stroke-signs', 'ESC-6.2');
    if ((f.sugars.isNotEmpty && _min(f.sugars) < 70 && !hyp) ||
        (ncd && f.hasPos('low_sugar_signs') && (f.hasPos('sweat') || f.hasPos('confus') || f.has('low_sugar_word')) && !hyp && adultCtx)) {
      d.add('adult-low-sugar', 'ESC-6.3');
    }
    if (unconscious && (ncd || adultCtx || f.has('adult_patient'))) d.add('adult-unconscious', 'ESC-6.3', 'ESC-1.3');
  }
  // ---- ESC-1.4 other life-threatening emergencies (anyone)
  if (f.hasPos('emergency_other') && !hyp) d.add('other-emergency', 'ESC-1.4');
  if (unconscious && d.rules.isEmpty) d.add('unconscious', 'ESC-1.4');
  return d;
}
