import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/core/phone.dart';

void main() {
  group('Indian mobile numbers', () {
    test('10 digits starting with 6, 7, 8 or 9 are valid', () {
      for (final n in ['6000000000', '9123456780', '8123456789', '9876543210']) {
        expect(normalizeIndianMobile(n), n, reason: n);
      }
    });

    test('spaces, dashes, +91, 91 and a leading 0 are accepted and removed', () {
      expect(normalizeIndianMobile('98765 43210'), '9876543210');
      expect(normalizeIndianMobile('98765-43210'), '9876543210');
      expect(normalizeIndianMobile('+91 98765 43210'), '9876543210');
      expect(normalizeIndianMobile('919876543210'), '9876543210');
      expect(normalizeIndianMobile('09876543210'), '9876543210');
    });

    test('anything else is refused', () {
      for (final n in [
        '',
        '5876543210', // starts with 5
        '0123456789',
        '987654321', // 9 digits
        '98765432101', // 11 digits, not a leading 0
        '98765x3210',
        '+1 9876543210',
        '9876543210 9876543210',
      ]) {
        expect(normalizeIndianMobile(n), isNull, reason: n);
      }
    });
  });

  group('Phone 1 required, Phone 2 optional', () {
    test('both fine, and Phone 2 may be empty', () {
      expect(checkPhones('9876543210', ''), (first: null, second: null));
      expect(checkPhones('9876543210', '8123456789'), (first: null, second: null));
    });

    test('Phone 1 empty is "required", a bad one is "invalid"', () {
      expect(checkPhones('', '').first, PhoneProblem.required);
      expect(checkPhones('   ', '').first, PhoneProblem.required);
      expect(checkPhones('12345', '').first, PhoneProblem.invalid);
    });

    test('a bad Phone 2 is invalid, the same number twice is flagged', () {
      expect(checkPhones('9876543210', '1234').second, PhoneProblem.invalid);
      expect(checkPhones('9876543210', '98765 43210').second, PhoneProblem.same);
      expect(checkPhones('9876543210', '+919876543210').second, PhoneProblem.same);
    });
  });
}
