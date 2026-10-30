import 'h5_facts.dart';
import 'h5_text.dart';

/// The refusal layer (SCP-1.2): the Dart twin of health-worker-backend/h5/scope.py. Returns the reason, or '' when in scope.
final RegExp _albendazole = RegExp(foldPattern(r'albendazole|keede'));
final RegExp _hpv = RegExp(r'\bhpv\b');
final RegExp _whichMed = RegExp(foldPattern(r'kaun\s*s[aei]|koi\s+(?:dawai|goli|ilaaj)|dawai\s+(?:batao|chahiye)'));
final RegExp _doseUnit = RegExp(foldPattern(r'\bmg\b|\bunits?\b|\bml\b'));

String h5RefusalReason(H5Facts f) {
  if (f.has('sex_determination')) return 'sex determination (PC-PNDT)';
  if (f.has('admin')) return 'administrative question';
  if (f.has('family_planning')) return 'family planning / abortion services not in the protocols';
  if (f.has('report_reading')) return 'reading a scan, X-ray or lab report';
  if (f.has('unrelated')) return 'not about health';
  final hpv = f.has('protocol_topic') && _hpv.hasMatch(f.t);
  if (f.has('disease_not_covered') && !hpv) return 'condition not covered by the protocols';
  final protocolDrug = f.has('dose_in_protocol');
  if (_albendazole.hasMatch(f.t) && f.has('baby') && !(f.has('pregnant') || f.pregUnits.isNotEmpty)) {
    return 'medicine dose not in the protocols (albendazole for a child)';
  }
  if (f.has('dose_choice_q') && f.has('drug_not_in_protocol') && !protocolDrug) return 'dose or choice of a medicine not in the protocols';
  if (f.has('dose_choice_q') && f.has('tablet_word') && !protocolDrug && !f.has('protocol_topic') && !f.has('bp_word') && _whichMed.hasMatch(f.t)) {
    return 'which medicine to give';
  }
  if (f.has('drug_not_in_protocol') && _doseUnit.hasMatch(f.t) && !protocolDrug) return 'dose of a medicine not in the protocols';
  return '';
}
