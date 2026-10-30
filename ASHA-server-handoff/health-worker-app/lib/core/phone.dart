/// Indian mobile number rules: exactly 10 digits, the first one 6, 7, 8 or 9. Spaces and dashes are ignored, and a leading +91, 91 or 0
/// is accepted and removed. Returns the 10 digits, or null when the text is not a valid mobile number.
String? normalizeIndianMobile(String input) {
  var d = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (d.startsWith('+91')) {
    d = d.substring(3);
  } else if (d.length == 12 && d.startsWith('91')) {
    d = d.substring(2);
  } else if (d.length == 11 && d.startsWith('0')) {
    d = d.substring(1);
  }
  return RegExp(r'^[6-9][0-9]{9}$').hasMatch(d) ? d : null;
}

enum PhoneProblem { required, invalid, same }

/// Checks Phone 1 (required) and Phone 2 (optional). Returns the problem for each field, or null for a field that is fine.
({PhoneProblem? first, PhoneProblem? second}) checkPhones(
  String phone1,
  String phone2,
) {
  PhoneProblem? first, second;
  final n1 = normalizeIndianMobile(phone1);
  if (phone1.trim().isEmpty) {
    first = PhoneProblem.required;
  } else if (n1 == null) {
    first = PhoneProblem.invalid;
  }
  if (phone2.trim().isNotEmpty) {
    final n2 = normalizeIndianMobile(phone2);
    if (n2 == null) {
      second = PhoneProblem.invalid;
    } else if (n2 == n1) {
      second = PhoneProblem.same;
    }
  }
  return (first: first, second: second);
}
