import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('te'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'ASHA'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get navVisits;

  /// No description provided for @navAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get navAsk;

  /// No description provided for @navHouseholds.
  ///
  /// In en, this message translates to:
  /// **'Households'**
  String get navHouseholds;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get optional;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'required'**
  String get required;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get loadMore;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get noResults;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @chooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get chooseDate;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Server not reachable'**
  String get statusServerUnreachable;

  /// No description provided for @syncPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{n} waiting to sync'**
  String syncPendingCount(int n);

  /// No description provided for @allSynced.
  ///
  /// In en, this message translates to:
  /// **'All changes synced'**
  String get allSynced;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {date}'**
  String lastSynced(String date);

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get neverSynced;

  /// No description provided for @demoBadge.
  ///
  /// In en, this message translates to:
  /// **'Demo data (synthetic)'**
  String get demoBadge;

  /// No description provided for @greetMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetMorning;

  /// No description provided for @greetAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetAfternoon;

  /// No description provided for @greetEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetEvening;

  /// No description provided for @homeQuestion.
  ///
  /// In en, this message translates to:
  /// **'What\'s on your list today?'**
  String get homeQuestion;

  /// No description provided for @nextVisit.
  ///
  /// In en, this message translates to:
  /// **'Next visit'**
  String get nextVisit;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @pendingReferrals.
  ///
  /// In en, this message translates to:
  /// **'Open referrals'**
  String get pendingReferrals;

  /// No description provided for @priorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Attend first'**
  String get priorityTitle;

  /// No description provided for @prioritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Households ranked by urgency'**
  String get prioritySubtitle;

  /// No description provided for @priorityUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get priorityUrgent;

  /// No description provided for @prioritySoon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get prioritySoon;

  /// No description provided for @priorityRoutine.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get priorityRoutine;

  /// No description provided for @priorityWhyOverdue.
  ///
  /// In en, this message translates to:
  /// **'Visit overdue by {days} days'**
  String priorityWhyOverdue(int days);

  /// No description provided for @priorityWhyToday.
  ///
  /// In en, this message translates to:
  /// **'Visit due today'**
  String get priorityWhyToday;

  /// No description provided for @priorityWhyReferral.
  ///
  /// In en, this message translates to:
  /// **'Open referral, waiting {days} days'**
  String priorityWhyReferral(int days);

  /// No description provided for @priorityWhyMissed.
  ///
  /// In en, this message translates to:
  /// **'{n} missed visits in the last 90 days'**
  String priorityWhyMissed(int n);

  /// No description provided for @priorityWhyType.
  ///
  /// In en, this message translates to:
  /// **'{category} follow-up'**
  String priorityWhyType(String category);

  /// No description provided for @priorityNote.
  ///
  /// In en, this message translates to:
  /// **'The order uses due dates, open referrals, missed visits and visit type. It is a prototype rule, not a clinical risk score, and needs clinical review.'**
  String get priorityNote;

  /// No description provided for @priorityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting: no overdue visits or open referrals.'**
  String get priorityEmpty;

  /// No description provided for @prioritySeeAll.
  ///
  /// In en, this message translates to:
  /// **'See full list'**
  String get prioritySeeAll;

  /// No description provided for @recordsTitle.
  ///
  /// In en, this message translates to:
  /// **'From your records on this phone'**
  String get recordsTitle;

  /// No description provided for @recordsFooter.
  ///
  /// In en, this message translates to:
  /// **'Taken from the household register on this phone, so it works offline. This is not medical advice.'**
  String get recordsFooter;

  /// No description provided for @recordsOverdue.
  ///
  /// In en, this message translates to:
  /// **'{n} households have an overdue visit.'**
  String recordsOverdue(int n);

  /// No description provided for @recordsDueToday.
  ///
  /// In en, this message translates to:
  /// **'{n} households have a visit due today.'**
  String recordsDueToday(int n);

  /// No description provided for @recordsReferrals.
  ///
  /// In en, this message translates to:
  /// **'{n} households have an open referral.'**
  String recordsReferrals(int n);

  /// No description provided for @recordsPriority.
  ///
  /// In en, this message translates to:
  /// **'{n} households are waiting. Most urgent first:'**
  String recordsPriority(int n);

  /// No description provided for @recordsNone.
  ///
  /// In en, this message translates to:
  /// **'None right now.'**
  String get recordsNone;

  /// No description provided for @recordsHouseholdMissing.
  ///
  /// In en, this message translates to:
  /// **'No household with ID {id} is on this phone.'**
  String recordsHouseholdMissing(String id);

  /// No description provided for @recordsHouseholdInfo.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}. Next visit: {next}. Last visit: {last}.'**
  String recordsHouseholdInfo(String status, String next, String last);

  /// No description provided for @clarifyAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap what applies, or type more:'**
  String get clarifyAddTitle;

  /// No description provided for @clarifyChipNow.
  ///
  /// In en, this message translates to:
  /// **'Happening right now'**
  String get clarifyChipNow;

  /// No description provided for @clarifyChipSevere.
  ///
  /// In en, this message translates to:
  /// **'It is severe'**
  String get clarifyChipSevere;

  /// No description provided for @clarifyChipPregnant.
  ///
  /// In en, this message translates to:
  /// **'Pregnant woman'**
  String get clarifyChipPregnant;

  /// No description provided for @clarifyChipChild.
  ///
  /// In en, this message translates to:
  /// **'Baby or child'**
  String get clarifyChipChild;

  /// No description provided for @alertOneTitle.
  ///
  /// In en, this message translates to:
  /// **'Urgent: household {id}'**
  String alertOneTitle(String id);

  /// No description provided for @alertOneBody.
  ///
  /// In en, this message translates to:
  /// **'Open the app and look at Attend first.'**
  String get alertOneBody;

  /// No description provided for @alertManyTitle.
  ///
  /// In en, this message translates to:
  /// **'Urgent: {n} households need attention'**
  String alertManyTitle(int n);

  /// No description provided for @alertManyBody.
  ///
  /// In en, this message translates to:
  /// **'Open the app and look at Attend first to see who to visit first.'**
  String get alertManyBody;

  /// No description provided for @aiAssistTitle.
  ///
  /// In en, this message translates to:
  /// **'Online AI help (optional)'**
  String get aiAssistTitle;

  /// No description provided for @aiAssistHelp.
  ///
  /// In en, this message translates to:
  /// **'Off by default. When off, the Ask page explains from the approved protocol on this phone only, so you get the same result with or without internet. When on and online, your question and the closest approved passages are sent to your server\'s AI, which writes the explanation; if it does not answer in 10 seconds the phone explains it itself.'**
  String get aiAssistHelp;

  /// No description provided for @alertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Urgent alerts'**
  String get alertsTitle;

  /// No description provided for @alertsHelp.
  ///
  /// In en, this message translates to:
  /// **'Get a notification when a household becomes urgent in the Attend first list. This is worked out on the phone, so it works without internet. The urgency rule is a prototype, not a clinical risk score.'**
  String get alertsHelp;

  /// No description provided for @alertsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked for this app. Allow them in the phone\'s settings to get urgent alerts.'**
  String get alertsPermissionDenied;

  /// No description provided for @safetyMsgEscalation.
  ///
  /// In en, this message translates to:
  /// **'Possible danger sign detected. Follow your approved escalation protocol and contact the supervising medical officer. [PLACEHOLDER TEXT - pending clinical approval]'**
  String get safetyMsgEscalation;

  /// No description provided for @safetyMsgClarification.
  ///
  /// In en, this message translates to:
  /// **'Please clarify: who is affected, which symptom, and whether it is happening now. [PLACEHOLDER TEXT - pending clinical approval]'**
  String get safetyMsgClarification;

  /// No description provided for @ruleBleeding.
  ///
  /// In en, this message translates to:
  /// **'Heavy bleeding'**
  String get ruleBleeding;

  /// No description provided for @ruleFits.
  ///
  /// In en, this message translates to:
  /// **'Fits / convulsions'**
  String get ruleFits;

  /// No description provided for @ruleBreathing.
  ///
  /// In en, this message translates to:
  /// **'Difficulty breathing'**
  String get ruleBreathing;

  /// No description provided for @ruleUnconscious.
  ///
  /// In en, this message translates to:
  /// **'Loss of consciousness / unresponsive'**
  String get ruleUnconscious;

  /// No description provided for @ruleFever.
  ///
  /// In en, this message translates to:
  /// **'High fever'**
  String get ruleFever;

  /// No description provided for @ruleNotFeeding.
  ///
  /// In en, this message translates to:
  /// **'Not feeding'**
  String get ruleNotFeeding;

  /// No description provided for @ruleAmbiguous.
  ///
  /// In en, this message translates to:
  /// **'Unclear description of being unwell'**
  String get ruleAmbiguous;

  /// No description provided for @ruleOutOfScope.
  ///
  /// In en, this message translates to:
  /// **'Medicine or dose request'**
  String get ruleOutOfScope;

  /// No description provided for @ruleOther.
  ///
  /// In en, this message translates to:
  /// **'Safety rule matched'**
  String get ruleOther;

  /// No description provided for @reasonMatched.
  ///
  /// In en, this message translates to:
  /// **'{label}: a matching phrase was found'**
  String reasonMatched(String label);

  /// No description provided for @reasonNeedsContext.
  ///
  /// In en, this message translates to:
  /// **'{label}: mentioned without enough detail (how severe, who, when)'**
  String reasonNeedsContext(String label);

  /// No description provided for @reasonShortMessage.
  ///
  /// In en, this message translates to:
  /// **'The message is too short to be sure, so more detail is requested'**
  String get reasonShortMessage;

  /// No description provided for @safetyRulesLabel.
  ///
  /// In en, this message translates to:
  /// **'Safety rules'**
  String get safetyRulesLabel;

  /// No description provided for @notValidatedShort.
  ///
  /// In en, this message translates to:
  /// **'not clinically validated'**
  String get notValidatedShort;

  /// No description provided for @tblHouseholds.
  ///
  /// In en, this message translates to:
  /// **'Households'**
  String get tblHouseholds;

  /// No description provided for @tblVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get tblVisits;

  /// No description provided for @tblReferrals.
  ///
  /// In en, this message translates to:
  /// **'Referrals'**
  String get tblReferrals;

  /// No description provided for @tblProtocolPassages.
  ///
  /// In en, this message translates to:
  /// **'Protocol passages'**
  String get tblProtocolPassages;

  /// No description provided for @tblSyncOutbox.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get tblSyncOutbox;

  /// No description provided for @shareSubject.
  ///
  /// In en, this message translates to:
  /// **'Referral summary'**
  String get shareSubject;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Your health worker companion'**
  String get splashTagline;

  /// No description provided for @obChooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get obChooseLanguage;

  /// No description provided for @obChooseLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'You can change this later in Settings.'**
  String get obChooseLanguageHint;

  /// No description provided for @obContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get obContinue;

  /// No description provided for @obSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get obSkip;

  /// No description provided for @obNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get obNext;

  /// No description provided for @obGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get obGetStarted;

  /// No description provided for @obStep.
  ///
  /// In en, this message translates to:
  /// **'Step {n} of {total}'**
  String obStep(int n, int total);

  /// No description provided for @ob1Title.
  ///
  /// In en, this message translates to:
  /// **'Your day in one place'**
  String get ob1Title;

  /// No description provided for @ob1Body.
  ///
  /// In en, this message translates to:
  /// **'See today\'s visits, record what happened, and use the Attend first list to know who needs you most.'**
  String get ob1Body;

  /// No description provided for @ob2Title.
  ///
  /// In en, this message translates to:
  /// **'Works without internet'**
  String get ob2Title;

  /// No description provided for @ob2Body.
  ///
  /// In en, this message translates to:
  /// **'Your list, visits and safety checks are kept on this phone. When the connection returns, your work is sent to the server automatically.'**
  String get ob2Body;

  /// No description provided for @ob3Title.
  ///
  /// In en, this message translates to:
  /// **'Safety comes first'**
  String get ob3Title;

  /// No description provided for @ob3Body.
  ///
  /// In en, this message translates to:
  /// **'ASHA warns you about possible danger signs. It does not replace a doctor or your approved protocols. The safety rules are still a draft and not clinically validated.'**
  String get ob3Body;

  /// No description provided for @ob4Title.
  ///
  /// In en, this message translates to:
  /// **'Two things ASHA may ask for'**
  String get ob4Title;

  /// No description provided for @ob4Mic.
  ///
  /// In en, this message translates to:
  /// **'Microphone: only while you tap Speak, to turn your voice into text. Audio is not saved.'**
  String get ob4Mic;

  /// No description provided for @ob4Notif.
  ///
  /// In en, this message translates to:
  /// **'Notifications: to tell you when a household becomes urgent. This works without internet.'**
  String get ob4Notif;

  /// No description provided for @ob4Server.
  ///
  /// In en, this message translates to:
  /// **'To sync your work, add your server address in Settings when you are ready.'**
  String get ob4Server;

  /// No description provided for @visitTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date and time of visit'**
  String get visitTimeLabel;

  /// No description provided for @visitTimeAuto.
  ///
  /// In en, this message translates to:
  /// **'Recorded automatically when you opened this visit. It cannot be changed.'**
  String get visitTimeAuto;

  /// No description provided for @visitTimeLocal.
  ///
  /// In en, this message translates to:
  /// **'Saved with the visit and sent to the server when you are online.'**
  String get visitTimeLocal;

  /// No description provided for @errTimeFuture.
  ///
  /// In en, this message translates to:
  /// **'That time has not happened yet today. Choose the time you actually went.'**
  String get errTimeFuture;

  /// No description provided for @errTimeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid time.'**
  String get errTimeInvalid;

  /// No description provided for @aiPrivacy.
  ///
  /// In en, this message translates to:
  /// **'When you are online, your question and the closest approved passages are also sent to your server\'s AI to write the explanation. Nothing is saved.'**
  String get aiPrivacy;

  /// No description provided for @escalationSampleHeading.
  ///
  /// In en, this message translates to:
  /// **'Sample text (not approved guidance)'**
  String get escalationSampleHeading;

  /// No description provided for @addFamily.
  ///
  /// In en, this message translates to:
  /// **'Add a new family'**
  String get addFamily;

  /// No description provided for @addFamilyTitle.
  ///
  /// In en, this message translates to:
  /// **'New family'**
  String get addFamilyTitle;

  /// No description provided for @villageLabel2.
  ///
  /// In en, this message translates to:
  /// **'Village ID'**
  String get villageLabel2;

  /// No description provided for @villageHint.
  ///
  /// In en, this message translates to:
  /// **'For example VIL-SYN-01'**
  String get villageHint;

  /// No description provided for @villagePick.
  ///
  /// In en, this message translates to:
  /// **'Villages on this phone'**
  String get villagePick;

  /// No description provided for @membersLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of family members'**
  String get membersLabel;

  /// No description provided for @membersDecrease.
  ///
  /// In en, this message translates to:
  /// **'Fewer members'**
  String get membersDecrease;

  /// No description provided for @membersIncrease.
  ///
  /// In en, this message translates to:
  /// **'More members'**
  String get membersIncrease;

  /// No description provided for @followupsLabel.
  ///
  /// In en, this message translates to:
  /// **'What follow-ups may this family need?'**
  String get followupsLabel;

  /// No description provided for @followupsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick all that apply. You can add more later.'**
  String get followupsHint;

  /// No description provided for @addFamilySave.
  ///
  /// In en, this message translates to:
  /// **'Add this family'**
  String get addFamilySave;

  /// No description provided for @addFamilyNote.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone now. It is sent to the server when you are online. The family gets an ID that you can use to schedule a first visit.'**
  String get addFamilyNote;

  /// No description provided for @addFamilyDone.
  ///
  /// In en, this message translates to:
  /// **'Family added: {id}. Schedule a first visit below.'**
  String addFamilyDone(String id);

  /// No description provided for @errVillageInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter the village ID: letters, numbers, dash or underscore, 2 to 32 characters.'**
  String get errVillageInvalid;

  /// No description provided for @errMembersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Members must be between 1 and 60.'**
  String get errMembersInvalid;

  /// No description provided for @errCategoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one follow-up type.'**
  String get errCategoriesEmpty;

  /// No description provided for @errWorkerUnknown.
  ///
  /// In en, this message translates to:
  /// **'This phone does not know which health worker you are yet. Sync once (or load the demo data), then add the family.'**
  String get errWorkerUnknown;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @askQuestion.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get askQuestion;

  /// No description provided for @openPlanner.
  ///
  /// In en, this message translates to:
  /// **'Today\'s visits'**
  String get openPlanner;

  /// No description provided for @reportsAction.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsAction;

  /// No description provided for @syncCentreAction.
  ///
  /// In en, this message translates to:
  /// **'Sync centre'**
  String get syncCentreAction;

  /// No description provided for @referralsAction.
  ///
  /// In en, this message translates to:
  /// **'Referrals'**
  String get referralsAction;

  /// No description provided for @noVisitsToday.
  ///
  /// In en, this message translates to:
  /// **'No visits due today'**
  String get noVisitsToday;

  /// No description provided for @emptyHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'No household data on this phone yet'**
  String get emptyHomeTitle;

  /// No description provided for @emptyHomeBody.
  ///
  /// In en, this message translates to:
  /// **'Connect to the server in Settings and sync, or load the synthetic demo data to try the app.'**
  String get emptyHomeBody;

  /// No description provided for @householdsCount.
  ///
  /// In en, this message translates to:
  /// **'{n} households on this phone'**
  String householdsCount(int n);

  /// No description provided for @plannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Visit planner'**
  String get plannerTitle;

  /// No description provided for @bucketOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get bucketOverdue;

  /// No description provided for @bucketToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get bucketToday;

  /// No description provided for @bucketUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get bucketUpcoming;

  /// No description provided for @priorityExplainer.
  ///
  /// In en, this message translates to:
  /// **'Ordered by due date: most overdue first. No risk score is used.'**
  String get priorityExplainer;

  /// No description provided for @reasonOverdue.
  ///
  /// In en, this message translates to:
  /// **'{category} follow-up was due {days} days ago'**
  String reasonOverdue(String category, int days);

  /// No description provided for @reasonToday.
  ///
  /// In en, this message translates to:
  /// **'{category} follow-up is due today'**
  String reasonToday(String category);

  /// No description provided for @reasonUpcoming.
  ///
  /// In en, this message translates to:
  /// **'{category} follow-up is due in {days} days'**
  String reasonUpcoming(String category, int days);

  /// No description provided for @lastVisitOn.
  ///
  /// In en, this message translates to:
  /// **'Last visit: {date}'**
  String lastVisitOn(String date);

  /// No description provided for @lastVisitNone.
  ///
  /// In en, this message translates to:
  /// **'No completed visit on record'**
  String get lastVisitNone;

  /// No description provided for @openReferralNote.
  ///
  /// In en, this message translates to:
  /// **'This household also has an open referral'**
  String get openReferralNote;

  /// No description provided for @recordOutcome.
  ///
  /// In en, this message translates to:
  /// **'Record visit'**
  String get recordOutcome;

  /// No description provided for @visitDetails.
  ///
  /// In en, this message translates to:
  /// **'Visit details'**
  String get visitDetails;

  /// No description provided for @outcomeLabel.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get outcomeLabel;

  /// No description provided for @outcomeCompleted.
  ///
  /// In en, this message translates to:
  /// **'Visit done'**
  String get outcomeCompleted;

  /// No description provided for @outcomeMissed.
  ///
  /// In en, this message translates to:
  /// **'Could not visit (not at home, etc.)'**
  String get outcomeMissed;

  /// No description provided for @outcomeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancel this visit'**
  String get outcomeCancelled;

  /// No description provided for @visitDate.
  ///
  /// In en, this message translates to:
  /// **'Date of visit'**
  String get visitDate;

  /// No description provided for @followupNeeded.
  ///
  /// In en, this message translates to:
  /// **'Another visit is needed'**
  String get followupNeeded;

  /// No description provided for @nextVisitDate.
  ///
  /// In en, this message translates to:
  /// **'Date of next visit'**
  String get nextVisitDate;

  /// No description provided for @recommendReferral.
  ///
  /// In en, this message translates to:
  /// **'Recommend a hospital referral'**
  String get recommendReferral;

  /// No description provided for @facilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Facility'**
  String get facilityLabel;

  /// No description provided for @serviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceLabel;

  /// No description provided for @noFacilitiesKnown.
  ///
  /// In en, this message translates to:
  /// **'No facility list is available on this phone yet, so a referral cannot be recorded here.'**
  String get noFacilitiesKnown;

  /// No description provided for @referralNeedsDone.
  ///
  /// In en, this message translates to:
  /// **'A referral can only be recorded for a visit that was done.'**
  String get referralNeedsDone;

  /// No description provided for @savedOffline.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. It will be sent when you are online.'**
  String get savedOffline;

  /// No description provided for @errActualRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the date the visit happened.'**
  String get errActualRequired;

  /// No description provided for @errFuture.
  ///
  /// In en, this message translates to:
  /// **'The visit date cannot be in the future.'**
  String get errFuture;

  /// No description provided for @errNextRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose the date of the next visit.'**
  String get errNextRequired;

  /// No description provided for @errNextNotAfter.
  ///
  /// In en, this message translates to:
  /// **'The next visit must be after this visit.'**
  String get errNextNotAfter;

  /// No description provided for @errInconsistent.
  ///
  /// In en, this message translates to:
  /// **'Remove the next visit date, or say another visit is needed.'**
  String get errInconsistent;

  /// No description provided for @errAlreadyFinal.
  ///
  /// In en, this message translates to:
  /// **'This visit has already been recorded.'**
  String get errAlreadyFinal;

  /// No description provided for @errPlannedBefore.
  ///
  /// In en, this message translates to:
  /// **'The planned date cannot be before the referral was made.'**
  String get errPlannedBefore;

  /// No description provided for @errInPast.
  ///
  /// In en, this message translates to:
  /// **'Choose today or a later date.'**
  String get errInPast;

  /// No description provided for @errNeedFacility.
  ///
  /// In en, this message translates to:
  /// **'Choose a facility.'**
  String get errNeedFacility;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Please check this entry.'**
  String get errGeneric;

  /// No description provided for @householdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Households'**
  String get householdsTitle;

  /// No description provided for @searchHouseholds.
  ///
  /// In en, this message translates to:
  /// **'Search by household ID'**
  String get searchHouseholds;

  /// No description provided for @filterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get filterStatus;

  /// No description provided for @filterCategory.
  ///
  /// In en, this message translates to:
  /// **'Follow-up type'**
  String get filterCategory;

  /// No description provided for @filterVillage.
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get filterVillage;

  /// No description provided for @statusUPCOMING.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get statusUPCOMING;

  /// No description provided for @statusDUE_TODAY.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get statusDUE_TODAY;

  /// No description provided for @statusOVERDUE.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get statusOVERDUE;

  /// No description provided for @statusCOMPLETED.
  ///
  /// In en, this message translates to:
  /// **'Recently visited'**
  String get statusCOMPLETED;

  /// No description provided for @statusNO_VISIT_DUE.
  ///
  /// In en, this message translates to:
  /// **'No visit due'**
  String get statusNO_VISIT_DUE;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'{n} members'**
  String members(int n);

  /// No description provided for @villageLabel.
  ///
  /// In en, this message translates to:
  /// **'Village'**
  String get villageLabel;

  /// No description provided for @nextVisitLabel.
  ///
  /// In en, this message translates to:
  /// **'Next visit'**
  String get nextVisitLabel;

  /// No description provided for @lastVisitLabel.
  ///
  /// In en, this message translates to:
  /// **'Last visit'**
  String get lastVisitLabel;

  /// No description provided for @eligibleFollowups.
  ///
  /// In en, this message translates to:
  /// **'Follow-up types'**
  String get eligibleFollowups;

  /// No description provided for @visitHistory.
  ///
  /// In en, this message translates to:
  /// **'Visit history'**
  String get visitHistory;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No visits recorded'**
  String get noHistory;

  /// No description provided for @scheduleVisit.
  ///
  /// In en, this message translates to:
  /// **'Schedule a visit'**
  String get scheduleVisit;

  /// No description provided for @householdReferrals.
  ///
  /// In en, this message translates to:
  /// **'Referrals'**
  String get householdReferrals;

  /// No description provided for @unsyncedBadge.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get unsyncedBadge;

  /// No description provided for @visitStatusPLANNED.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get visitStatusPLANNED;

  /// No description provided for @visitStatusCOMPLETED.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get visitStatusCOMPLETED;

  /// No description provided for @visitStatusMISSED.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get visitStatusMISSED;

  /// No description provided for @visitStatusRESCHEDULED.
  ///
  /// In en, this message translates to:
  /// **'Rescheduled'**
  String get visitStatusRESCHEDULED;

  /// No description provided for @visitStatusCANCELLED.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get visitStatusCANCELLED;

  /// No description provided for @catANC.
  ///
  /// In en, this message translates to:
  /// **'Antenatal care'**
  String get catANC;

  /// No description provided for @catIMMUNISATION.
  ///
  /// In en, this message translates to:
  /// **'Immunisation'**
  String get catIMMUNISATION;

  /// No description provided for @catNUTRITION.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get catNUTRITION;

  /// No description provided for @catHYPERTENSION.
  ///
  /// In en, this message translates to:
  /// **'Blood pressure'**
  String get catHYPERTENSION;

  /// No description provided for @catDIABETES.
  ///
  /// In en, this message translates to:
  /// **'Diabetes'**
  String get catDIABETES;

  /// No description provided for @catROUTINE.
  ///
  /// In en, this message translates to:
  /// **'Routine visit'**
  String get catROUTINE;

  /// No description provided for @catGENERAL.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get catGENERAL;

  /// No description provided for @referralsTitle.
  ///
  /// In en, this message translates to:
  /// **'Referrals'**
  String get referralsTitle;

  /// No description provided for @refFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get refFilterAll;

  /// No description provided for @refFilterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get refFilterOpen;

  /// No description provided for @refFilterRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get refFilterRecommended;

  /// No description provided for @refFilterPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get refFilterPlanned;

  /// No description provided for @refFilterConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Attendance confirmed'**
  String get refFilterConfirmed;

  /// No description provided for @refFilterClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get refFilterClosed;

  /// No description provided for @phaseRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended — not yet planned'**
  String get phaseRecommended;

  /// No description provided for @phasePlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned — attendance NOT confirmed'**
  String get phasePlanned;

  /// No description provided for @phaseConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Hospital attendance confirmed (hospital record)'**
  String get phaseConfirmed;

  /// No description provided for @phaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Referral cancelled'**
  String get phaseCancelled;

  /// No description provided for @phaseInvalid.
  ///
  /// In en, this message translates to:
  /// **'Record marked invalid'**
  String get phaseInvalid;

  /// No description provided for @phaseDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate record (not counted)'**
  String get phaseDuplicate;

  /// No description provided for @attendanceNote.
  ///
  /// In en, this message translates to:
  /// **'Attendance is only shown as confirmed when the hospital has a record of the visit. Recommending or planning a referral does not mean the person went.'**
  String get attendanceNote;

  /// No description provided for @stepRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get stepRecommended;

  /// No description provided for @stepPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get stepPlanned;

  /// No description provided for @stepAttended.
  ///
  /// In en, this message translates to:
  /// **'Attendance confirmed by hospital'**
  String get stepAttended;

  /// No description provided for @stepDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get stepDone;

  /// No description provided for @stepWaiting.
  ///
  /// In en, this message translates to:
  /// **'not yet'**
  String get stepWaiting;

  /// No description provided for @setPlannedDate.
  ///
  /// In en, this message translates to:
  /// **'Set planned date'**
  String get setPlannedDate;

  /// No description provided for @changePlannedDate.
  ///
  /// In en, this message translates to:
  /// **'Change planned date'**
  String get changePlannedDate;

  /// No description provided for @cancelReferral.
  ///
  /// In en, this message translates to:
  /// **'Cancel referral'**
  String get cancelReferral;

  /// No description provided for @cancelReferralConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel this referral? This is sent to the server when you are online.'**
  String get cancelReferralConfirm;

  /// No description provided for @plannedOn.
  ///
  /// In en, this message translates to:
  /// **'Planned for {date}'**
  String plannedOn(String date);

  /// No description provided for @createdOn.
  ///
  /// In en, this message translates to:
  /// **'Referral made {date}'**
  String createdOn(String date);

  /// No description provided for @attendanceRecordLabel.
  ///
  /// In en, this message translates to:
  /// **'Hospital record'**
  String get attendanceRecordLabel;

  /// No description provided for @confirmedOn.
  ///
  /// In en, this message translates to:
  /// **'Confirmed on {date}'**
  String confirmedOn(String date);

  /// No description provided for @askTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask a health question'**
  String get askTitle;

  /// No description provided for @askHint.
  ///
  /// In en, this message translates to:
  /// **'Type in Telugu, English or both'**
  String get askHint;

  /// No description provided for @askButton.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get askButton;

  /// No description provided for @askNeedsText.
  ///
  /// In en, this message translates to:
  /// **'Type a question first.'**
  String get askNeedsText;

  /// No description provided for @askTooLong.
  ///
  /// In en, this message translates to:
  /// **'The question is too long. Please shorten it.'**
  String get askTooLong;

  /// No description provided for @askChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get askChecking;

  /// No description provided for @askPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your question is not saved on this phone.'**
  String get askPrivacy;

  /// No description provided for @askSafetyOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Safety checks run on this phone, even without internet.'**
  String get askSafetyOnDevice;

  /// No description provided for @verifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verified protocol text'**
  String get verifiedTitle;

  /// No description provided for @unverifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unverified text — not medical guidance'**
  String get unverifiedTitle;

  /// No description provided for @sourceDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get sourceDocument;

  /// No description provided for @sourceSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get sourceSection;

  /// No description provided for @sourcePage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get sourcePage;

  /// No description provided for @sourceVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get sourceVersion;

  /// No description provided for @sourceStatus.
  ///
  /// In en, this message translates to:
  /// **'Source status'**
  String get sourceStatus;

  /// No description provided for @passageHeading.
  ///
  /// In en, this message translates to:
  /// **'Supporting passage (exact text)'**
  String get passageHeading;

  /// No description provided for @answeredOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Found in protocol text stored on this phone'**
  String get answeredOnDevice;

  /// No description provided for @answeredByServer.
  ///
  /// In en, this message translates to:
  /// **'Found by the server'**
  String get answeredByServer;

  /// No description provided for @insufficientTitle.
  ///
  /// In en, this message translates to:
  /// **'No verified answer available'**
  String get insufficientTitle;

  /// No description provided for @insufficientBody.
  ///
  /// In en, this message translates to:
  /// **'No approved protocol text matches this question. This is not an answer. Please ask your supervisor or medical officer.'**
  String get insufficientBody;

  /// No description provided for @cannotVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot be verified offline'**
  String get cannotVerifyTitle;

  /// No description provided for @cannotVerifyBody.
  ///
  /// In en, this message translates to:
  /// **'There is no approved protocol text on this phone and the server cannot be reached, so no answer can be given. Safety checks found no danger sign in your question, but that is not a medical answer.'**
  String get cannotVerifyBody;

  /// No description provided for @clarifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Please tell us more'**
  String get clarifyTitle;

  /// No description provided for @outOfScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'This app cannot help with this'**
  String get outOfScopeTitle;

  /// No description provided for @outOfScopeBody.
  ///
  /// In en, this message translates to:
  /// **'The app does not give medicine doses or prescriptions. Please refer the person to a medical officer.'**
  String get outOfScopeBody;

  /// No description provided for @escalationTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible danger sign'**
  String get escalationTitle;

  /// No description provided for @escalationLead.
  ///
  /// In en, this message translates to:
  /// **'Follow your approved escalation steps now.'**
  String get escalationLead;

  /// No description provided for @escalationPlaceholderNote.
  ///
  /// In en, this message translates to:
  /// **'The wording below is placeholder text that has not been approved by a clinician.'**
  String get escalationPlaceholderNote;

  /// No description provided for @notClinicallyValidated.
  ///
  /// In en, this message translates to:
  /// **'Safety rules are not clinically validated yet'**
  String get notClinicallyValidated;

  /// No description provided for @reviewNeeded.
  ///
  /// In en, this message translates to:
  /// **'Needs human review'**
  String get reviewNeeded;

  /// No description provided for @whyShown.
  ///
  /// In en, this message translates to:
  /// **'Why this was shown'**
  String get whyShown;

  /// No description provided for @rulesetLabel.
  ///
  /// In en, this message translates to:
  /// **'Rules version {v}'**
  String rulesetLabel(String v);

  /// No description provided for @callSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Call supervisor'**
  String get callSupervisor;

  /// No description provided for @escalationGuidanceHeading.
  ///
  /// In en, this message translates to:
  /// **'Approved guidance'**
  String get escalationGuidanceHeading;

  /// No description provided for @escalationNoGuidance.
  ///
  /// In en, this message translates to:
  /// **'No approved protocol is loaded on this phone yet, so no treatment advice can be shown. Use your approved escalation steps.'**
  String get escalationNoGuidance;

  /// No description provided for @noContactConfigured.
  ///
  /// In en, this message translates to:
  /// **'No supervisor number is set. Add one in Settings.'**
  String get noContactConfigured;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @facilityPick.
  ///
  /// In en, this message translates to:
  /// **'Facility'**
  String get facilityPick;

  /// No description provided for @periodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get periodLabel;

  /// No description provided for @period30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get period30;

  /// No description provided for @period90.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get period90;

  /// No description provided for @period180.
  ///
  /// In en, this message translates to:
  /// **'Last 6 months'**
  String get period180;

  /// No description provided for @reportLocal.
  ///
  /// In en, this message translates to:
  /// **'Summary from this phone'**
  String get reportLocal;

  /// No description provided for @reportServer.
  ///
  /// In en, this message translates to:
  /// **'Get report from server'**
  String get reportServer;

  /// No description provided for @reportComputedLocal.
  ///
  /// In en, this message translates to:
  /// **'Computed on this phone from saved records (works offline)'**
  String get reportComputedLocal;

  /// No description provided for @reportComputedServer.
  ///
  /// In en, this message translates to:
  /// **'Report from the server'**
  String get reportComputedServer;

  /// No description provided for @countRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get countRecommended;

  /// No description provided for @countPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get countPlanned;

  /// No description provided for @countConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Attendance confirmed (hospital record)'**
  String get countConfirmed;

  /// No description provided for @countTotal.
  ///
  /// In en, this message translates to:
  /// **'Total recorded referrals'**
  String get countTotal;

  /// No description provided for @byService.
  ///
  /// In en, this message translates to:
  /// **'By service'**
  String get byService;

  /// No description provided for @excludedRecords.
  ///
  /// In en, this message translates to:
  /// **'Records not counted'**
  String get excludedRecords;

  /// No description provided for @followUpsDue.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups due'**
  String get followUpsDue;

  /// No description provided for @followUpsDone.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups completed in period'**
  String get followUpsDone;

  /// No description provided for @freshFRESH.
  ///
  /// In en, this message translates to:
  /// **'Data is fresh (synced within 24 hours)'**
  String get freshFRESH;

  /// No description provided for @freshRECENT.
  ///
  /// In en, this message translates to:
  /// **'Data is recent (synced within 3 days)'**
  String get freshRECENT;

  /// No description provided for @freshSTALE_OFFLINE.
  ///
  /// In en, this message translates to:
  /// **'Data may be out of date (not synced for over 3 days)'**
  String get freshSTALE_OFFLINE;

  /// No description provided for @freshNOT_PROVIDED.
  ///
  /// In en, this message translates to:
  /// **'This phone has never synced'**
  String get freshNOT_PROVIDED;

  /// No description provided for @privacyNoticeReport.
  ///
  /// In en, this message translates to:
  /// **'Aggregate counts only. No household or patient details. These are recorded referrals, not predictions of who will attend. Household visits are not hospital attendance.'**
  String get privacyNoticeReport;

  /// No description provided for @shareCsv.
  ///
  /// In en, this message translates to:
  /// **'Share CSV'**
  String get shareCsv;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF'**
  String get sharePdf;

  /// No description provided for @noFacilities.
  ///
  /// In en, this message translates to:
  /// **'No referral records on this phone yet.'**
  String get noFacilities;

  /// No description provided for @reportOnlineOnly.
  ///
  /// In en, this message translates to:
  /// **'PDF and server reports need an internet connection.'**
  String get reportOnlineOnly;

  /// No description provided for @generatedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated {date}'**
  String generatedAt(String date);

  /// No description provided for @syncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync centre'**
  String get syncTitle;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @sectionPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get sectionPending;

  /// No description provided for @sectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Rejected by server'**
  String get sectionFailed;

  /// No description provided for @sectionConflict.
  ///
  /// In en, this message translates to:
  /// **'Needs your decision'**
  String get sectionConflict;

  /// No description provided for @sectionSynced.
  ///
  /// In en, this message translates to:
  /// **'Confirmed by server'**
  String get sectionSynced;

  /// No description provided for @retryOp.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get retryOp;

  /// No description provided for @discardOp.
  ///
  /// In en, this message translates to:
  /// **'Discard change'**
  String get discardOp;

  /// No description provided for @discardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard this change? Your saved edit will be undone on this phone. Other changes made at the same time stay queued.'**
  String get discardConfirm;

  /// No description provided for @resolveConflict.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get resolveConflict;

  /// No description provided for @keepServer.
  ///
  /// In en, this message translates to:
  /// **'Keep the server\'s version'**
  String get keepServer;

  /// No description provided for @keepMine.
  ///
  /// In en, this message translates to:
  /// **'Keep my change'**
  String get keepMine;

  /// No description provided for @conflictExplain.
  ///
  /// In en, this message translates to:
  /// **'Someone else changed this record before your change reached the server. Nothing was overwritten. Choose which version to keep.'**
  String get conflictExplain;

  /// No description provided for @serverHas.
  ///
  /// In en, this message translates to:
  /// **'Server has'**
  String get serverHas;

  /// No description provided for @youChanged.
  ///
  /// In en, this message translates to:
  /// **'You changed it to'**
  String get youChanged;

  /// No description provided for @opNewVisit.
  ///
  /// In en, this message translates to:
  /// **'New visit'**
  String get opNewVisit;

  /// No description provided for @opVisitOutcome.
  ///
  /// In en, this message translates to:
  /// **'Visit result'**
  String get opVisitOutcome;

  /// No description provided for @opNewReferral.
  ///
  /// In en, this message translates to:
  /// **'New referral'**
  String get opNewReferral;

  /// No description provided for @opReferralUpdate.
  ///
  /// In en, this message translates to:
  /// **'Referral change'**
  String get opReferralUpdate;

  /// No description provided for @opHouseholdUpdate.
  ///
  /// In en, this message translates to:
  /// **'Household change'**
  String get opHouseholdUpdate;

  /// No description provided for @opNewHousehold.
  ///
  /// In en, this message translates to:
  /// **'New household'**
  String get opNewHousehold;

  /// No description provided for @attemptsN.
  ///
  /// In en, this message translates to:
  /// **'Tried {n} times'**
  String attemptsN(int n);

  /// No description provided for @nothingPending.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting to be sent.'**
  String get nothingPending;

  /// No description provided for @syncResultOk.
  ///
  /// In en, this message translates to:
  /// **'Sync finished: {n} changes confirmed by the server.'**
  String syncResultOk(int n);

  /// No description provided for @syncAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept your access key. Check it in Settings. Your data is safe on this phone.'**
  String get syncAuthFailed;

  /// No description provided for @syncNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No server address is set. Add it in Settings. Your data is safe on this phone.'**
  String get syncNotConfigured;

  /// No description provided for @syncOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Your changes are saved on this phone and will be sent later.'**
  String get syncOffline;

  /// No description provided for @syncServerError.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem. Your changes are saved on this phone and will be sent again.'**
  String get syncServerError;

  /// No description provided for @syncNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Some changes were not accepted by the server. Nothing was lost: they are listed below.'**
  String get syncNeedsAttention;

  /// No description provided for @voiceLangTelugu.
  ///
  /// In en, this message translates to:
  /// **'Telugu'**
  String get voiceLangTelugu;

  /// No description provided for @voiceLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get voiceLangEnglish;

  /// No description provided for @voiceChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking voice support…'**
  String get voiceChecking;

  /// No description provided for @voicePackMissing.
  ///
  /// In en, this message translates to:
  /// **'This phone has no offline speech pack for {name}, so voice cannot work without internet. You can download the pack in the phone\'s speech settings (often Settings › Google › Speech › Offline speech recognition). Please type your question for now.'**
  String voicePackMissing(String name);

  /// No description provided for @voiceNoOfflineEngine.
  ///
  /// In en, this message translates to:
  /// **'This phone cannot recognise {name} speech without internet. Please type your question.'**
  String voiceNoOfflineEngine(String name);

  /// No description provided for @voiceOnlineOption.
  ///
  /// In en, this message translates to:
  /// **'If you want, you can allow the phone\'s online speech service in Settings (Online speech).'**
  String get voiceOnlineOption;

  /// No description provided for @voicePrivacyOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Your voice is turned into text on this phone only. Nothing is sent, and this app does not save your voice.'**
  String get voicePrivacyOnDevice;

  /// No description provided for @voicePrivacyOnline.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s online speech service turned your voice into text, so the audio was sent to that service. This app does not save your voice.'**
  String get voicePrivacyOnline;

  /// No description provided for @voiceTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Turning your voice into text…'**
  String get voiceTranscribing;

  /// No description provided for @voicePrivacyAppModel.
  ///
  /// In en, this message translates to:
  /// **'Your voice was turned into text on this phone by the app\'s own Telugu model. Nothing is sent, and this app does not save your voice. Speech recognition can make mistakes: check the words.'**
  String get voicePrivacyAppModel;

  /// No description provided for @voiceGetTeluguPack.
  ///
  /// In en, this message translates to:
  /// **'You can also download the Telugu voice pack once in Settings; after that Telugu voice works with no internet.'**
  String get voiceGetTeluguPack;

  /// No description provided for @teluguModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Telugu voice for this app (offline)'**
  String get teluguModelTitle;

  /// No description provided for @mapChipAvailable.
  ///
  /// In en, this message translates to:
  /// **'Offline map available'**
  String get mapChipAvailable;

  /// No description provided for @mapChipMissing.
  ///
  /// In en, this message translates to:
  /// **'Offline map not downloaded'**
  String get mapChipMissing;

  /// No description provided for @houseLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'House location'**
  String get houseLocationTitle;

  /// No description provided for @houseLocationOpen.
  ///
  /// In en, this message translates to:
  /// **'Tap to open the bigger map'**
  String get houseLocationOpen;

  /// No description provided for @houseLocationNone.
  ///
  /// In en, this message translates to:
  /// **'No map or position on this phone for this house yet.'**
  String get houseLocationNone;

  /// No description provided for @mapDemoNote.
  ///
  /// In en, this message translates to:
  /// **'Demo village map. It is made up, not a real place.'**
  String get mapDemoNote;

  /// No description provided for @phonesTitle.
  ///
  /// In en, this message translates to:
  /// **'Phone numbers'**
  String get phonesTitle;

  /// No description provided for @phone1Label.
  ///
  /// In en, this message translates to:
  /// **'Phone 1 (required)'**
  String get phone1Label;

  /// No description provided for @phone2Label.
  ///
  /// In en, this message translates to:
  /// **'Phone 2 (optional)'**
  String get phone2Label;

  /// No description provided for @phoneNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Not added'**
  String get phoneNotAdded;

  /// No description provided for @phoneEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get phoneEdit;

  /// No description provided for @phoneAdd.
  ///
  /// In en, this message translates to:
  /// **'Add phone numbers'**
  String get phoneAdd;

  /// No description provided for @phoneErrRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone 1 is needed.'**
  String get phoneErrRequired;

  /// No description provided for @phoneErrInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a 10-digit mobile number that starts with 6, 7, 8 or 9.'**
  String get phoneErrInvalid;

  /// No description provided for @phoneErrSame.
  ///
  /// In en, this message translates to:
  /// **'Phone 2 is the same as Phone 1.'**
  String get phoneErrSame;

  /// No description provided for @phoneCall.
  ///
  /// In en, this message translates to:
  /// **'Call {number}'**
  String phoneCall(String number);

  /// No description provided for @phoneCannotCall.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone app.'**
  String get phoneCannotCall;

  /// No description provided for @phoneLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone only. It is not sent to the server.'**
  String get phoneLocalOnly;

  /// No description provided for @teluguModelHelp.
  ///
  /// In en, this message translates to:
  /// **'Download once (about 44 MB, use Wi-Fi). After that, Telugu voice works with no internet and your voice never leaves the phone. It can make mistakes, so always check the words.'**
  String get teluguModelHelp;

  /// No description provided for @teluguModelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download Telugu voice'**
  String get teluguModelDownload;

  /// No description provided for @teluguModelProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {done} of {total} MB'**
  String teluguModelProgress(String done, int total);

  /// No description provided for @teluguModelReady.
  ///
  /// In en, this message translates to:
  /// **'Ready. Telugu voice works offline on this phone.'**
  String get teluguModelReady;

  /// No description provided for @teluguModelRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove (frees about 44 MB)'**
  String get teluguModelRemove;

  /// No description provided for @teluguModelNeedServer.
  ///
  /// In en, this message translates to:
  /// **'Set the server address and key above first: the pack is downloaded from your server.'**
  String get teluguModelNeedServer;

  /// No description provided for @teluguModelFailedNet.
  ///
  /// In en, this message translates to:
  /// **'Could not download. Check the internet and the server, then try again. What was downloaded is kept, so it continues.'**
  String get teluguModelFailedNet;

  /// No description provided for @teluguModelFailedSum.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was damaged, so it was discarded. Please try again.'**
  String get teluguModelFailedSum;

  /// No description provided for @teluguModelNotOnServer.
  ///
  /// In en, this message translates to:
  /// **'This server has no Telugu voice pack. Ask whoever runs the server to install it.'**
  String get teluguModelNotOnServer;

  /// No description provided for @altVoiceButton.
  ///
  /// In en, this message translates to:
  /// **'Alternative way to get Telugu voice'**
  String get altVoiceButton;

  /// No description provided for @altVoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Telugu voice with the Google keyboard'**
  String get altVoiceTitle;

  /// No description provided for @altVoiceIntro.
  ///
  /// In en, this message translates to:
  /// **'Use the voice typing of the Google keyboard (Gboard) to speak Telugu into the question box. Do these steps once.'**
  String get altVoiceIntro;

  /// No description provided for @altStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Open your phone\'s Settings'**
  String get altStep1Title;

  /// No description provided for @altStep1Body.
  ///
  /// In en, this message translates to:
  /// **'Open the Settings app of your phone (the gear icon).'**
  String get altStep1Body;

  /// No description provided for @altStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Find the keyboard settings'**
  String get altStep2Title;

  /// No description provided for @altStep2Body.
  ///
  /// In en, this message translates to:
  /// **'Go to System, then Languages and input. On some phones this is called General management, or Additional settings, then Language and input.'**
  String get altStep2Body;

  /// No description provided for @altStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Choose the Google keyboard'**
  String get altStep3Title;

  /// No description provided for @altStep3Body.
  ///
  /// In en, this message translates to:
  /// **'Tap On-screen keyboard (or Keyboards) and open Gboard, the Google keyboard. If you do not see it, install Gboard from the Play Store and set it as your keyboard.'**
  String get altStep3Body;

  /// No description provided for @altStep4Title.
  ///
  /// In en, this message translates to:
  /// **'Add Telugu'**
  String get altStep4Title;

  /// No description provided for @altStep4Body.
  ///
  /// In en, this message translates to:
  /// **'In Gboard tap Languages, then Add keyboard, search for Telugu, select it and tap Done.'**
  String get altStep4Body;

  /// No description provided for @altStep5Title.
  ///
  /// In en, this message translates to:
  /// **'Turn on voice typing'**
  String get altStep5Title;

  /// No description provided for @altStep5Body.
  ///
  /// In en, this message translates to:
  /// **'In the Gboard settings open Voice typing, switch on Use voice typing, and make sure Telugu is one of its languages.'**
  String get altStep5Body;

  /// No description provided for @altStep6Title.
  ///
  /// In en, this message translates to:
  /// **'Speak in this app'**
  String get altStep6Title;

  /// No description provided for @altStep6Body.
  ///
  /// In en, this message translates to:
  /// **'Come back to this app and open Ask. Tap the question box so the keyboard opens. If needed, switch to Telugu with the globe key, then tap the microphone key on the keyboard and speak your question.'**
  String get altStep6Body;

  /// No description provided for @altStep7Title.
  ///
  /// In en, this message translates to:
  /// **'Check the words'**
  String get altStep7Title;

  /// No description provided for @altStep7Body.
  ///
  /// In en, this message translates to:
  /// **'Look at the Telugu words, fix any mistakes, then press Check.'**
  String get altStep7Body;

  /// No description provided for @altVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'Please note: Gboard voice typing is Google\'s service, not this app\'s. It usually needs internet, and the audio goes to Google. It works without internet only if Telugu is listed in Gboard\'s offline languages; on the two phones we tried, Telugu was not offered offline. For Telugu voice with no internet, use Download Telugu voice in Settings.'**
  String get altVoiceNote;

  /// No description provided for @altOpenKeyboardSettings.
  ///
  /// In en, this message translates to:
  /// **'Open keyboard settings'**
  String get altOpenKeyboardSettings;

  /// No description provided for @altOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open it. Open your phone\'s Settings yourself and follow the steps.'**
  String get altOpenFailed;

  /// No description provided for @explAsking.
  ///
  /// In en, this message translates to:
  /// **'Asking the AI server… (up to 10 seconds)'**
  String get explAsking;

  /// No description provided for @explTitle.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get explTitle;

  /// No description provided for @explFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Explained on this phone, using sentences from the approved text below.'**
  String get explFromDevice;

  /// No description provided for @explFromServerText.
  ///
  /// In en, this message translates to:
  /// **'From your server: the approved text that answers your question, word for word.'**
  String get explFromServerText;

  /// No description provided for @explFromServer.
  ///
  /// In en, this message translates to:
  /// **'Explained by your server\'s AI from the approved text below.'**
  String get explFromServer;

  /// No description provided for @explNoteTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server did not answer in 10 seconds, so the phone explained it itself.'**
  String get explNoteTimeout;

  /// No description provided for @explNoteUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The server could not be reached, so the phone explained it itself.'**
  String get explNoteUnreachable;

  /// No description provided for @explNoteUnsafe.
  ///
  /// In en, this message translates to:
  /// **'The server\'s text was not shown because it named a medicine or a dose, so the phone explained it itself.'**
  String get explNoteUnsafe;

  /// No description provided for @explNoteRejected.
  ///
  /// In en, this message translates to:
  /// **'The server\'s text was not shown because it did not stay with the approved text (or its language), so the phone explained it itself.'**
  String get explNoteRejected;

  /// No description provided for @explDisclaimerDevice.
  ///
  /// In en, this message translates to:
  /// **'Taken word for word from the approved text. Not clinically validated: check with your supervisor.'**
  String get explDisclaimerDevice;

  /// No description provided for @explDisclaimerServer.
  ///
  /// In en, this message translates to:
  /// **'Written by an AI from the approved text. Not clinically verified. Not a diagnosis. Follow your approved protocols.'**
  String get explDisclaimerServer;

  /// No description provided for @sevHighTitle.
  ///
  /// In en, this message translates to:
  /// **'High: possible danger sign'**
  String get sevHighTitle;

  /// No description provided for @sevHighAction.
  ///
  /// In en, this message translates to:
  /// **'Act now: call your supervisor or take the person to the nearest health facility.'**
  String get sevHighAction;

  /// No description provided for @sevMediumTitle.
  ///
  /// In en, this message translates to:
  /// **'Medium: more details needed'**
  String get sevMediumTitle;

  /// No description provided for @sevMediumAction.
  ///
  /// In en, this message translates to:
  /// **'Tap what applies below, or type more, then check again.'**
  String get sevMediumAction;

  /// No description provided for @sevLowTitle.
  ///
  /// In en, this message translates to:
  /// **'Low: no danger sign found in what you wrote'**
  String get sevLowTitle;

  /// No description provided for @sevLowAction.
  ///
  /// In en, this message translates to:
  /// **'For information. Read the explanation and the approved text below.'**
  String get sevLowAction;

  /// No description provided for @voiceResultNote.
  ///
  /// In en, this message translates to:
  /// **'This text came from your voice and may contain mistakes. If it is not what you said, fix the words and press Check again.'**
  String get voiceResultNote;

  /// No description provided for @onlineSpeechTitle.
  ///
  /// In en, this message translates to:
  /// **'Online speech (optional)'**
  String get onlineSpeechTitle;

  /// No description provided for @onlineSpeechHelp.
  ///
  /// In en, this message translates to:
  /// **'Off by default. When off, voice works only for languages this phone can recognise offline, and your voice never leaves the phone. When on, and only if a language has no offline pack and you are online, your phone\'s speech service receives the audio to turn it into text.'**
  String get onlineSpeechHelp;

  /// No description provided for @speechCapsLabel.
  ///
  /// In en, this message translates to:
  /// **'Offline speech on this phone'**
  String get speechCapsLabel;

  /// No description provided for @speechCapsLine.
  ///
  /// In en, this message translates to:
  /// **'English: {en} · Telugu: {te}'**
  String speechCapsLine(String en, String te);

  /// No description provided for @speechYes.
  ///
  /// In en, this message translates to:
  /// **'installed'**
  String get speechYes;

  /// No description provided for @speechNo.
  ///
  /// In en, this message translates to:
  /// **'not installed'**
  String get speechNo;

  /// No description provided for @speechUnknown.
  ///
  /// In en, this message translates to:
  /// **'cannot check on this phone'**
  String get speechUnknown;

  /// No description provided for @voiceSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get voiceSpeak;

  /// No description provided for @voiceStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStop;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening… speak now'**
  String get voiceListening;

  /// No description provided for @voiceLangLabel.
  ///
  /// In en, this message translates to:
  /// **'Speak in'**
  String get voiceLangLabel;

  /// No description provided for @voiceCheckText.
  ///
  /// In en, this message translates to:
  /// **'Check the words below, fix any mistakes, then press Check.'**
  String get voiceCheckText;

  /// No description provided for @voicePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your phone\'s speech service turns your voice into text and may use the internet. This app does not save your voice.'**
  String get voicePrivacy;

  /// No description provided for @voicePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is off. Allow the microphone for this app in your phone settings, or type your question.'**
  String get voicePermissionDenied;

  /// No description provided for @voiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Voice input is not available on this phone. Please type your question.'**
  String get voiceUnavailable;

  /// No description provided for @voiceLanguageMissing.
  ///
  /// In en, this message translates to:
  /// **'This phone has no speech support for the chosen language. Install it in the phone\'s Google speech settings, or type your question.'**
  String get voiceLanguageMissing;

  /// No description provided for @voiceNoSpeech.
  ///
  /// In en, this message translates to:
  /// **'I did not hear anything. Tap Speak and try again.'**
  String get voiceNoSpeech;

  /// No description provided for @voiceOfflineLanguage.
  ///
  /// In en, this message translates to:
  /// **'You are offline and this phone has no offline speech pack for this language. Connect to the internet to speak, or type your question - typing and safety checks work offline.'**
  String get voiceOfflineLanguage;

  /// No description provided for @voiceNetwork.
  ///
  /// In en, this message translates to:
  /// **'Voice needs a connection on this phone right now. Please type your question.'**
  String get voiceNetwork;

  /// No description provided for @voiceOther.
  ///
  /// In en, this message translates to:
  /// **'Voice input stopped. Please try again or type.'**
  String get voiceOther;

  /// No description provided for @noServerForAnswer.
  ///
  /// In en, this message translates to:
  /// **'There is no approved protocol text on this phone and no server address is set in Settings, so no answer can be given. Safety checks found no danger sign in your question, but that is not a medical answer.'**
  String get noServerForAnswer;

  /// No description provided for @homeMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get homeMore;

  /// No description provided for @syncNeverSentWarning.
  ///
  /// In en, this message translates to:
  /// **'A change is only \'synced\' after the server confirms it.'**
  String get syncNeverSentWarning;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langTelugu.
  ///
  /// In en, this message translates to:
  /// **'తెలుగు'**
  String get langTelugu;

  /// No description provided for @serverSection.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverSection;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://your-server.example'**
  String get serverUrlHint;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'Access key'**
  String get apiKey;

  /// No description provided for @apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Stored securely on this phone'**
  String get apiKeyHint;

  /// No description provided for @apiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'Access key saved'**
  String get apiKeySaved;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @connectionOk.
  ///
  /// In en, this message translates to:
  /// **'Server reachable'**
  String get connectionOk;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server'**
  String get connectionFailed;

  /// No description provided for @insecureWarning.
  ///
  /// In en, this message translates to:
  /// **'This address uses plain http. Data and your key can be read on the network. Use https for a real server.'**
  String get insecureWarning;

  /// No description provided for @invalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a full address starting with http:// or https://'**
  String get invalidUrl;

  /// No description provided for @demoSection.
  ///
  /// In en, this message translates to:
  /// **'Demo data'**
  String get demoSection;

  /// No description provided for @loadDemo.
  ///
  /// In en, this message translates to:
  /// **'Load synthetic demo data'**
  String get loadDemo;

  /// No description provided for @demoLoadedN.
  ///
  /// In en, this message translates to:
  /// **'Loaded {n} households of demo data'**
  String demoLoadedN(int n);

  /// No description provided for @useDemoDate.
  ///
  /// In en, this message translates to:
  /// **'Use the demo date (13 Oct 2026)'**
  String get useDemoDate;

  /// No description provided for @demoExplain.
  ///
  /// In en, this message translates to:
  /// **'Synthetic records for trying the app. They are not real people.'**
  String get demoExplain;

  /// No description provided for @escalationContact.
  ///
  /// In en, this message translates to:
  /// **'Supervisor phone number'**
  String get escalationContact;

  /// No description provided for @escalationContactHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown on danger-sign alerts so you can call quickly.'**
  String get escalationContactHelp;

  /// No description provided for @protocolSection.
  ///
  /// In en, this message translates to:
  /// **'Protocol library'**
  String get protocolSection;

  /// No description provided for @protocolCountN.
  ///
  /// In en, this message translates to:
  /// **'{n} approved passages on this phone'**
  String protocolCountN(int n);

  /// No description provided for @protocolNone.
  ///
  /// In en, this message translates to:
  /// **'No approved protocol text is installed yet. Questions cannot be answered from protocols until official documents are approved on the server.'**
  String get protocolNone;

  /// No description provided for @refreshProtocols.
  ///
  /// In en, this message translates to:
  /// **'Download approved protocols'**
  String get refreshProtocols;

  /// No description provided for @protocolRefreshed.
  ///
  /// In en, this message translates to:
  /// **'{n} passages stored'**
  String protocolRefreshed(int n);

  /// No description provided for @privacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy and local data'**
  String get privacyTitle;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'Household, visit and referral records are stored in a database on this phone. Questions you type are not saved. Notifications never show household details. Data is sent to the server only when you sync. The access key is kept in the phone\'s secure storage.'**
  String get privacyBody;

  /// No description provided for @clearData.
  ///
  /// In en, this message translates to:
  /// **'Clear all data on this phone'**
  String get clearData;

  /// No description provided for @clearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all households, visits, referrals and unsent changes from this phone? Unsent changes will be lost.'**
  String get clearConfirm;

  /// No description provided for @clearDone.
  ///
  /// In en, this message translates to:
  /// **'All local data deleted'**
  String get clearDone;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About and diagnostics'**
  String get aboutTitle;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get appVersion;

  /// No description provided for @dbSchema.
  ///
  /// In en, this message translates to:
  /// **'Local database version'**
  String get dbSchema;

  /// No description provided for @diagnosticsNote.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics contain counts and versions only, never health information.'**
  String get diagnosticsNote;

  /// No description provided for @validationNote.
  ///
  /// In en, this message translates to:
  /// **'Not clinically validated. Draft safety rules, synthetic data.'**
  String get validationNote;

  /// No description provided for @moreTitle.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTitle;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection. Try again when you are online.'**
  String get errNetwork;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to answer.'**
  String get errTimeout;

  /// No description provided for @errUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept your access key. Check Settings.'**
  String get errUnauthorized;

  /// No description provided for @errServer.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem. Try again later.'**
  String get errServer;

  /// No description provided for @errInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The server sent an unexpected answer.'**
  String get errInvalidResponse;

  /// No description provided for @errNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Set the server address in Settings first.'**
  String get errNotConfigured;

  /// No description provided for @errForbidden.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to do this.'**
  String get errForbidden;

  /// No description provided for @errUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errUnknown;

  /// No description provided for @semBottomNav.
  ///
  /// In en, this message translates to:
  /// **'Main navigation'**
  String get semBottomNav;

  /// No description provided for @semStatusChip.
  ///
  /// In en, this message translates to:
  /// **'Connection and sync status. Tap to open the sync centre.'**
  String get semStatusChip;

  /// No description provided for @h5MapTitle.
  ///
  /// In en, this message translates to:
  /// **'Houses map'**
  String get h5MapTitle;

  /// No description provided for @h5MapChip.
  ///
  /// In en, this message translates to:
  /// **'Offline map: {n} houses. Tap to open.'**
  String h5MapChip(int n);

  /// No description provided for @h5AllVillages.
  ///
  /// In en, this message translates to:
  /// **'All villages'**
  String get h5AllVillages;

  /// No description provided for @h5HousesIn.
  ///
  /// In en, this message translates to:
  /// **'{n} houses'**
  String h5HousesIn(int n);

  /// No description provided for @h5LegendUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get h5LegendUrgent;

  /// No description provided for @h5LegendDue.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get h5LegendDue;

  /// No description provided for @h5LegendSoon.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get h5LegendSoon;

  /// No description provided for @h5LegendNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing due'**
  String get h5LegendNone;

  /// No description provided for @h5MapMadeUp.
  ///
  /// In en, this message translates to:
  /// **'Made-up map. The house positions are not real.'**
  String get h5MapMadeUp;

  /// No description provided for @h5MapAsOf.
  ///
  /// In en, this message translates to:
  /// **'Visit list as of {date}'**
  String h5MapAsOf(String date);

  /// No description provided for @h5HouseNo.
  ///
  /// In en, this message translates to:
  /// **'House {no}'**
  String h5HouseNo(String no);

  /// No description provided for @h5PeopleCount.
  ///
  /// In en, this message translates to:
  /// **'{n} people'**
  String h5PeopleCount(int n);

  /// No description provided for @h5OpenHouse.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get h5OpenHouse;

  /// No description provided for @h5DueNow.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get h5DueNow;

  /// No description provided for @h5NothingDue.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due for this house.'**
  String get h5NothingDue;

  /// No description provided for @h5PickTitle.
  ///
  /// In en, this message translates to:
  /// **'House location'**
  String get h5PickTitle;

  /// No description provided for @h5PickHelp.
  ///
  /// In en, this message translates to:
  /// **'Tap the map where the house is.'**
  String get h5PickHelp;

  /// No description provided for @h5PickUse.
  ///
  /// In en, this message translates to:
  /// **'Use this location'**
  String get h5PickUse;

  /// No description provided for @h5PickCardTitle.
  ///
  /// In en, this message translates to:
  /// **'House location (optional)'**
  String get h5PickCardTitle;

  /// No description provided for @h5PickOpen.
  ///
  /// In en, this message translates to:
  /// **'Choose on the map'**
  String get h5PickOpen;

  /// No description provided for @h5PickChange.
  ///
  /// In en, this message translates to:
  /// **'Change on the map'**
  String get h5PickChange;

  /// No description provided for @h5PickNone.
  ///
  /// In en, this message translates to:
  /// **'No location chosen yet.'**
  String get h5PickNone;

  /// No description provided for @h5PickedAt.
  ///
  /// In en, this message translates to:
  /// **'Chosen: {lat}, {lng}'**
  String h5PickedAt(String lat, String lng);

  /// No description provided for @h5PickClear.
  ///
  /// In en, this message translates to:
  /// **'Remove location'**
  String get h5PickClear;

  /// No description provided for @h5PickNoMap.
  ///
  /// In en, this message translates to:
  /// **'No map is on this phone.'**
  String get h5PickNoMap;

  /// No description provided for @h5MemberPregnant.
  ///
  /// In en, this message translates to:
  /// **'Pregnant'**
  String get h5MemberPregnant;

  /// No description provided for @h5PriorityN.
  ///
  /// In en, this message translates to:
  /// **'Priority {n}'**
  String h5PriorityN(int n);

  /// No description provided for @h5StatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get h5StatusOverdue;

  /// No description provided for @h5StatusToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get h5StatusToday;

  /// No description provided for @h5StatusWeek.
  ///
  /// In en, this message translates to:
  /// **'Due this week'**
  String get h5StatusWeek;

  /// No description provided for @h5MembersTitle.
  ///
  /// In en, this message translates to:
  /// **'People in this house'**
  String get h5MembersTitle;

  /// No description provided for @h5HouseTitle.
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get h5HouseTitle;

  /// No description provided for @h5VillageLine.
  ///
  /// In en, this message translates to:
  /// **'{village}, ASHA {asha}'**
  String h5VillageLine(String village, String asha);

  /// No description provided for @h5VisitTitle.
  ///
  /// In en, this message translates to:
  /// **'Visit list'**
  String get h5VisitTitle;

  /// No description provided for @h5VisitAsOf.
  ///
  /// In en, this message translates to:
  /// **'As of {date}. {n} items.'**
  String h5VisitAsOf(String date, int n);

  /// No description provided for @h5AllAshas.
  ///
  /// In en, this message translates to:
  /// **'All ASHAs'**
  String get h5AllAshas;

  /// No description provided for @h5Priority1.
  ///
  /// In en, this message translates to:
  /// **'Priority 1: high risk, due now'**
  String get h5Priority1;

  /// No description provided for @h5Priority2.
  ///
  /// In en, this message translates to:
  /// **'Priority 2: due now'**
  String get h5Priority2;

  /// No description provided for @h5Priority3.
  ///
  /// In en, this message translates to:
  /// **'Priority 3: later this week'**
  String get h5Priority3;

  /// No description provided for @h5VisitEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due.'**
  String get h5VisitEmpty;

  /// No description provided for @h5MoreVisit.
  ///
  /// In en, this message translates to:
  /// **'Visit list (block data)'**
  String get h5MoreVisit;

  /// No description provided for @h5MoreMap.
  ///
  /// In en, this message translates to:
  /// **'Houses map'**
  String get h5MoreMap;

  /// No description provided for @h5DueOn.
  ///
  /// In en, this message translates to:
  /// **'due {date}'**
  String h5DueOn(String date);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
