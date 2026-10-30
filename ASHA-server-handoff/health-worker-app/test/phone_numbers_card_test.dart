import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_companion/presentation/widgets/phone_numbers_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.enterText(find.byKey(Key(key)), text);
  await t.pump();
}

void main() {
  sqfliteFfiInit();

  uiTest('Phone 1 is required, bad numbers show a clear message, good ones are saved and can be called', (t) async {
    final rig = (await t.runAsync(() => buildRig(configured: false)))!;
    final called = <Uri>[];
    await pumpApp(
      t,
      rig,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PhoneNumbersCard(
            householdId: 'HH-SYN-00001',
            launcher: (u) async {
              called.add(u);
              return true;
            },
          ),
        ),
      ),
      size: const Size(412, 1400),
    );
    await settle(t, maxRounds: 6);
    expect(find.text('Not added'), findsOneWidget);
    expect(find.text('Saved on this phone only. It is not sent to the server.'), findsWidgets);

    await t.tap(find.byKey(const Key('phones-add')));
    await settle(t, maxRounds: 6);
    // empty Phone 1
    await t.tap(find.byKey(const Key('phones-save')));
    await t.pump();
    expect(find.text('Phone 1 is needed.'), findsOneWidget);
    // too short
    await _type(t, 'phone1-field', '12345');
    expect(find.text('Enter a 10-digit mobile number that starts with 6, 7, 8 or 9.'), findsOneWidget);
    // starts with 5
    await _type(t, 'phone1-field', '5876543210');
    expect(find.text('Enter a 10-digit mobile number that starts with 6, 7, 8 or 9.'), findsOneWidget);
    // good Phone 1, bad optional Phone 2
    await _type(t, 'phone1-field', '98765 43210');
    await _type(t, 'phone2-field', '123');
    expect(find.text('Phone 1 is needed.'), findsNothing);
    expect(find.text('Enter a 10-digit mobile number that starts with 6, 7, 8 or 9.'), findsOneWidget);
    // Phone 2 empty is fine
    await _type(t, 'phone2-field', '');
    await t.tap(find.byKey(const Key('phones-save')));
    await settle(t, maxRounds: 10);
    expect(find.byKey(const Key('call-9876543210')), findsOneWidget);
    expect(find.text('98765 43210'), findsWidgets);
    expect(find.text('Phone 2 (optional)'), findsNothing);

    // stored as plain digits, on this phone only
    expect((await t.runAsync(() => rig.services.store.contactsFor('HH-SYN-00001')))!.$1, '9876543210');

    await t.tap(find.byKey(const Key('call-9876543210')));
    await t.pump();
    expect(called.single.toString(), 'tel:9876543210');

    // add a second number
    await t.tap(find.byKey(const Key('phones-edit')));
    await settle(t, maxRounds: 6);
    await _type(t, 'phone2-field', '+91 81234 56789');
    await t.tap(find.byKey(const Key('phones-save')));
    await settle(t, maxRounds: 10);
    expect(find.byKey(const Key('call-8123456789')), findsOneWidget);
  });

  uiTest('the messages are in Telugu when the app is in Telugu', (t) async {
    final rig = (await t.runAsync(() => buildRig(configured: false, lang: 'te')))!;
    await pumpApp(
      t,
      rig,
      home: const Scaffold(body: SingleChildScrollView(child: PhoneNumbersCard(householdId: 'HH-SYN-00002'))),
      size: const Size(412, 1400),
    );
    await settle(t, maxRounds: 6);
    expect(find.text('ఫోన్ నంబర్లు'), findsOneWidget);
    await t.tap(find.byKey(const Key('phones-add')));
    await settle(t, maxRounds: 6);
    await t.tap(find.byKey(const Key('phones-save')));
    await t.pump();
    expect(find.text('ఫోన్ 1 అవసరం.'), findsOneWidget);
    await _type(t, 'phone1-field', '12345');
    expect(find.text('6, 7, 8 లేదా 9తో మొదలయ్యే 10 అంకెల మొబైల్ నంబర్ ఇవ్వండి.'), findsOneWidget);
  });
}
