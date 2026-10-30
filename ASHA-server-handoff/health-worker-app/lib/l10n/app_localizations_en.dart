// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'ASHA';

  @override
  String get navHome => 'Home';

  @override
  String get navVisits => 'Visits';

  @override
  String get navAsk => 'Ask';

  @override
  String get navHouseholds => 'Households';

  @override
  String get navMore => 'More';

  @override
  String get loading => 'Loading…';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get discard => 'Discard';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get today => 'Today';

  @override
  String get optional => 'optional';

  @override
  String get required => 'required';

  @override
  String get search => 'Search';

  @override
  String get all => 'All';

  @override
  String get clear => 'Clear';

  @override
  String get loadMore => 'Show more';

  @override
  String get noResults => 'Nothing found';

  @override
  String get back => 'Back';

  @override
  String get chooseDate => 'Choose date';

  @override
  String get notSet => 'Not set';

  @override
  String get none => 'None';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusServerUnreachable => 'Server not reachable';

  @override
  String syncPendingCount(int n) {
    return '$n waiting to sync';
  }

  @override
  String get allSynced => 'All changes synced';

  @override
  String lastSynced(String date) {
    return 'Last synced $date';
  }

  @override
  String get neverSynced => 'Never synced';

  @override
  String get demoBadge => 'Demo data (synthetic)';

  @override
  String get greetMorning => 'Good morning';

  @override
  String get greetAfternoon => 'Good afternoon';

  @override
  String get greetEvening => 'Good evening';

  @override
  String get homeQuestion => 'What\'s on your list today?';

  @override
  String get nextVisit => 'Next visit';

  @override
  String get dueToday => 'Due today';

  @override
  String get overdue => 'Overdue';

  @override
  String get upcoming => 'Upcoming';

  @override
  String get pendingReferrals => 'Open referrals';

  @override
  String get priorityTitle => 'Attend first';

  @override
  String get prioritySubtitle => 'Households ranked by urgency';

  @override
  String get priorityUrgent => 'Urgent';

  @override
  String get prioritySoon => 'Soon';

  @override
  String get priorityRoutine => 'Routine';

  @override
  String priorityWhyOverdue(int days) {
    return 'Visit overdue by $days days';
  }

  @override
  String get priorityWhyToday => 'Visit due today';

  @override
  String priorityWhyReferral(int days) {
    return 'Open referral, waiting $days days';
  }

  @override
  String priorityWhyMissed(int n) {
    return '$n missed visits in the last 90 days';
  }

  @override
  String priorityWhyType(String category) {
    return '$category follow-up';
  }

  @override
  String get priorityNote =>
      'The order uses due dates, open referrals, missed visits and visit type. It is a prototype rule, not a clinical risk score, and needs clinical review.';

  @override
  String get priorityEmpty =>
      'Nothing is waiting: no overdue visits or open referrals.';

  @override
  String get prioritySeeAll => 'See full list';

  @override
  String get recordsTitle => 'From your records on this phone';

  @override
  String get recordsFooter =>
      'Taken from the household register on this phone, so it works offline. This is not medical advice.';

  @override
  String recordsOverdue(int n) {
    return '$n households have an overdue visit.';
  }

  @override
  String recordsDueToday(int n) {
    return '$n households have a visit due today.';
  }

  @override
  String recordsReferrals(int n) {
    return '$n households have an open referral.';
  }

  @override
  String recordsPriority(int n) {
    return '$n households are waiting. Most urgent first:';
  }

  @override
  String get recordsNone => 'None right now.';

  @override
  String recordsHouseholdMissing(String id) {
    return 'No household with ID $id is on this phone.';
  }

  @override
  String recordsHouseholdInfo(String status, String next, String last) {
    return 'Status: $status. Next visit: $next. Last visit: $last.';
  }

  @override
  String get clarifyAddTitle => 'Tap what applies, or type more:';

  @override
  String get clarifyChipNow => 'Happening right now';

  @override
  String get clarifyChipSevere => 'It is severe';

  @override
  String get clarifyChipPregnant => 'Pregnant woman';

  @override
  String get clarifyChipChild => 'Baby or child';

  @override
  String alertOneTitle(String id) {
    return 'Urgent: household $id';
  }

  @override
  String get alertOneBody => 'Open the app and look at Attend first.';

  @override
  String alertManyTitle(int n) {
    return 'Urgent: $n households need attention';
  }

  @override
  String get alertManyBody =>
      'Open the app and look at Attend first to see who to visit first.';

  @override
  String get aiAssistTitle => 'Online AI help (optional)';

  @override
  String get aiAssistHelp =>
      'Off by default. When off, the Ask page explains from the approved protocol on this phone only, so you get the same result with or without internet. When on and online, your question and the closest approved passages are sent to your server\'s AI, which writes the explanation; if it does not answer in 10 seconds the phone explains it itself.';

  @override
  String get alertsTitle => 'Urgent alerts';

  @override
  String get alertsHelp =>
      'Get a notification when a household becomes urgent in the Attend first list. This is worked out on the phone, so it works without internet. The urgency rule is a prototype, not a clinical risk score.';

  @override
  String get alertsPermissionDenied =>
      'Notifications are blocked for this app. Allow them in the phone\'s settings to get urgent alerts.';

  @override
  String get safetyMsgEscalation =>
      'Possible danger sign detected. Follow your approved escalation protocol and contact the supervising medical officer. [PLACEHOLDER TEXT - pending clinical approval]';

  @override
  String get safetyMsgClarification =>
      'Please clarify: who is affected, which symptom, and whether it is happening now. [PLACEHOLDER TEXT - pending clinical approval]';

  @override
  String get ruleBleeding => 'Heavy bleeding';

  @override
  String get ruleFits => 'Fits / convulsions';

  @override
  String get ruleBreathing => 'Difficulty breathing';

  @override
  String get ruleUnconscious => 'Loss of consciousness / unresponsive';

  @override
  String get ruleFever => 'High fever';

  @override
  String get ruleNotFeeding => 'Not feeding';

  @override
  String get ruleAmbiguous => 'Unclear description of being unwell';

  @override
  String get ruleOutOfScope => 'Medicine or dose request';

  @override
  String get ruleOther => 'Safety rule matched';

  @override
  String reasonMatched(String label) {
    return '$label: a matching phrase was found';
  }

  @override
  String reasonNeedsContext(String label) {
    return '$label: mentioned without enough detail (how severe, who, when)';
  }

  @override
  String get reasonShortMessage =>
      'The message is too short to be sure, so more detail is requested';

  @override
  String get safetyRulesLabel => 'Safety rules';

  @override
  String get notValidatedShort => 'not clinically validated';

  @override
  String get tblHouseholds => 'Households';

  @override
  String get tblVisits => 'Visits';

  @override
  String get tblReferrals => 'Referrals';

  @override
  String get tblProtocolPassages => 'Protocol passages';

  @override
  String get tblSyncOutbox => 'Waiting to send';

  @override
  String get shareSubject => 'Referral summary';

  @override
  String get splashTagline => 'Your health worker companion';

  @override
  String get obChooseLanguage => 'Choose your language';

  @override
  String get obChooseLanguageHint => 'You can change this later in Settings.';

  @override
  String get obContinue => 'Continue';

  @override
  String get obSkip => 'Skip';

  @override
  String get obNext => 'Next';

  @override
  String get obGetStarted => 'Get started';

  @override
  String obStep(int n, int total) {
    return 'Step $n of $total';
  }

  @override
  String get ob1Title => 'Your day in one place';

  @override
  String get ob1Body =>
      'See today\'s visits, record what happened, and use the Attend first list to know who needs you most.';

  @override
  String get ob2Title => 'Works without internet';

  @override
  String get ob2Body =>
      'Your list, visits and safety checks are kept on this phone. When the connection returns, your work is sent to the server automatically.';

  @override
  String get ob3Title => 'Safety comes first';

  @override
  String get ob3Body =>
      'ASHA warns you about possible danger signs. It does not replace a doctor or your approved protocols. The safety rules are still a draft and not clinically validated.';

  @override
  String get ob4Title => 'Two things ASHA may ask for';

  @override
  String get ob4Mic =>
      'Microphone: only while you tap Speak, to turn your voice into text. Audio is not saved.';

  @override
  String get ob4Notif =>
      'Notifications: to tell you when a household becomes urgent. This works without internet.';

  @override
  String get ob4Server =>
      'To sync your work, add your server address in Settings when you are ready.';

  @override
  String get visitTimeLabel => 'Date and time of visit';

  @override
  String get visitTimeAuto =>
      'Recorded automatically when you opened this visit. It cannot be changed.';

  @override
  String get visitTimeLocal =>
      'Saved with the visit and sent to the server when you are online.';

  @override
  String get errTimeFuture =>
      'That time has not happened yet today. Choose the time you actually went.';

  @override
  String get errTimeInvalid => 'Choose a valid time.';

  @override
  String get aiPrivacy =>
      'When you are online, your question and the closest approved passages are also sent to your server\'s AI to write the explanation. Nothing is saved.';

  @override
  String get escalationSampleHeading => 'Sample text (not approved guidance)';

  @override
  String get addFamily => 'Add a new family';

  @override
  String get addFamilyTitle => 'New family';

  @override
  String get villageLabel2 => 'Village ID';

  @override
  String get villageHint => 'For example VIL-SYN-01';

  @override
  String get villagePick => 'Villages on this phone';

  @override
  String get membersLabel => 'Number of family members';

  @override
  String get membersDecrease => 'Fewer members';

  @override
  String get membersIncrease => 'More members';

  @override
  String get followupsLabel => 'What follow-ups may this family need?';

  @override
  String get followupsHint => 'Pick all that apply. You can add more later.';

  @override
  String get addFamilySave => 'Add this family';

  @override
  String get addFamilyNote =>
      'Saved on this phone now. It is sent to the server when you are online. The family gets an ID that you can use to schedule a first visit.';

  @override
  String addFamilyDone(String id) {
    return 'Family added: $id. Schedule a first visit below.';
  }

  @override
  String get errVillageInvalid =>
      'Enter the village ID: letters, numbers, dash or underscore, 2 to 32 characters.';

  @override
  String get errMembersInvalid => 'Members must be between 1 and 60.';

  @override
  String get errCategoriesEmpty => 'Pick at least one follow-up type.';

  @override
  String get errWorkerUnknown =>
      'This phone does not know which health worker you are yet. Sync once (or load the demo data), then add the family.';

  @override
  String get quickActions => 'Quick actions';

  @override
  String get askQuestion => 'Ask a question';

  @override
  String get openPlanner => 'Today\'s visits';

  @override
  String get reportsAction => 'Reports';

  @override
  String get syncCentreAction => 'Sync centre';

  @override
  String get referralsAction => 'Referrals';

  @override
  String get noVisitsToday => 'No visits due today';

  @override
  String get emptyHomeTitle => 'No household data on this phone yet';

  @override
  String get emptyHomeBody =>
      'Connect to the server in Settings and sync, or load the synthetic demo data to try the app.';

  @override
  String householdsCount(int n) {
    return '$n households on this phone';
  }

  @override
  String get plannerTitle => 'Visit planner';

  @override
  String get bucketOverdue => 'Overdue';

  @override
  String get bucketToday => 'Today';

  @override
  String get bucketUpcoming => 'Upcoming';

  @override
  String get priorityExplainer =>
      'Ordered by due date: most overdue first. No risk score is used.';

  @override
  String reasonOverdue(String category, int days) {
    return '$category follow-up was due $days days ago';
  }

  @override
  String reasonToday(String category) {
    return '$category follow-up is due today';
  }

  @override
  String reasonUpcoming(String category, int days) {
    return '$category follow-up is due in $days days';
  }

  @override
  String lastVisitOn(String date) {
    return 'Last visit: $date';
  }

  @override
  String get lastVisitNone => 'No completed visit on record';

  @override
  String get openReferralNote => 'This household also has an open referral';

  @override
  String get recordOutcome => 'Record visit';

  @override
  String get visitDetails => 'Visit details';

  @override
  String get outcomeLabel => 'What happened?';

  @override
  String get outcomeCompleted => 'Visit done';

  @override
  String get outcomeMissed => 'Could not visit (not at home, etc.)';

  @override
  String get outcomeCancelled => 'Cancel this visit';

  @override
  String get visitDate => 'Date of visit';

  @override
  String get followupNeeded => 'Another visit is needed';

  @override
  String get nextVisitDate => 'Date of next visit';

  @override
  String get recommendReferral => 'Recommend a hospital referral';

  @override
  String get facilityLabel => 'Facility';

  @override
  String get serviceLabel => 'Service';

  @override
  String get noFacilitiesKnown =>
      'No facility list is available on this phone yet, so a referral cannot be recorded here.';

  @override
  String get referralNeedsDone =>
      'A referral can only be recorded for a visit that was done.';

  @override
  String get savedOffline =>
      'Saved on this phone. It will be sent when you are online.';

  @override
  String get errActualRequired => 'Choose the date the visit happened.';

  @override
  String get errFuture => 'The visit date cannot be in the future.';

  @override
  String get errNextRequired => 'Choose the date of the next visit.';

  @override
  String get errNextNotAfter => 'The next visit must be after this visit.';

  @override
  String get errInconsistent =>
      'Remove the next visit date, or say another visit is needed.';

  @override
  String get errAlreadyFinal => 'This visit has already been recorded.';

  @override
  String get errPlannedBefore =>
      'The planned date cannot be before the referral was made.';

  @override
  String get errInPast => 'Choose today or a later date.';

  @override
  String get errNeedFacility => 'Choose a facility.';

  @override
  String get errGeneric => 'Please check this entry.';

  @override
  String get householdsTitle => 'Households';

  @override
  String get searchHouseholds => 'Search by household ID';

  @override
  String get filterStatus => 'Status';

  @override
  String get filterCategory => 'Follow-up type';

  @override
  String get filterVillage => 'Village';

  @override
  String get statusUPCOMING => 'Upcoming';

  @override
  String get statusDUE_TODAY => 'Due today';

  @override
  String get statusOVERDUE => 'Overdue';

  @override
  String get statusCOMPLETED => 'Recently visited';

  @override
  String get statusNO_VISIT_DUE => 'No visit due';

  @override
  String members(int n) {
    return '$n members';
  }

  @override
  String get villageLabel => 'Village';

  @override
  String get nextVisitLabel => 'Next visit';

  @override
  String get lastVisitLabel => 'Last visit';

  @override
  String get eligibleFollowups => 'Follow-up types';

  @override
  String get visitHistory => 'Visit history';

  @override
  String get noHistory => 'No visits recorded';

  @override
  String get scheduleVisit => 'Schedule a visit';

  @override
  String get householdReferrals => 'Referrals';

  @override
  String get unsyncedBadge => 'Not synced yet';

  @override
  String get visitStatusPLANNED => 'Planned';

  @override
  String get visitStatusCOMPLETED => 'Done';

  @override
  String get visitStatusMISSED => 'Missed';

  @override
  String get visitStatusRESCHEDULED => 'Rescheduled';

  @override
  String get visitStatusCANCELLED => 'Cancelled';

  @override
  String get catANC => 'Antenatal care';

  @override
  String get catIMMUNISATION => 'Immunisation';

  @override
  String get catNUTRITION => 'Nutrition';

  @override
  String get catHYPERTENSION => 'Blood pressure';

  @override
  String get catDIABETES => 'Diabetes';

  @override
  String get catROUTINE => 'Routine visit';

  @override
  String get catGENERAL => 'General';

  @override
  String get referralsTitle => 'Referrals';

  @override
  String get refFilterAll => 'All';

  @override
  String get refFilterOpen => 'Open';

  @override
  String get refFilterRecommended => 'Recommended';

  @override
  String get refFilterPlanned => 'Planned';

  @override
  String get refFilterConfirmed => 'Attendance confirmed';

  @override
  String get refFilterClosed => 'Closed';

  @override
  String get phaseRecommended => 'Recommended — not yet planned';

  @override
  String get phasePlanned => 'Planned — attendance NOT confirmed';

  @override
  String get phaseConfirmed =>
      'Hospital attendance confirmed (hospital record)';

  @override
  String get phaseCancelled => 'Referral cancelled';

  @override
  String get phaseInvalid => 'Record marked invalid';

  @override
  String get phaseDuplicate => 'Duplicate record (not counted)';

  @override
  String get attendanceNote =>
      'Attendance is only shown as confirmed when the hospital has a record of the visit. Recommending or planning a referral does not mean the person went.';

  @override
  String get stepRecommended => 'Recommended';

  @override
  String get stepPlanned => 'Planned';

  @override
  String get stepAttended => 'Attendance confirmed by hospital';

  @override
  String get stepDone => 'done';

  @override
  String get stepWaiting => 'not yet';

  @override
  String get setPlannedDate => 'Set planned date';

  @override
  String get changePlannedDate => 'Change planned date';

  @override
  String get cancelReferral => 'Cancel referral';

  @override
  String get cancelReferralConfirm =>
      'Cancel this referral? This is sent to the server when you are online.';

  @override
  String plannedOn(String date) {
    return 'Planned for $date';
  }

  @override
  String createdOn(String date) {
    return 'Referral made $date';
  }

  @override
  String get attendanceRecordLabel => 'Hospital record';

  @override
  String confirmedOn(String date) {
    return 'Confirmed on $date';
  }

  @override
  String get askTitle => 'Ask a health question';

  @override
  String get askHint => 'Type in Telugu, English or both';

  @override
  String get askButton => 'Check';

  @override
  String get askNeedsText => 'Type a question first.';

  @override
  String get askTooLong => 'The question is too long. Please shorten it.';

  @override
  String get askChecking => 'Checking…';

  @override
  String get askPrivacy => 'Your question is not saved on this phone.';

  @override
  String get askSafetyOnDevice =>
      'Safety checks run on this phone, even without internet.';

  @override
  String get verifiedTitle => 'Verified protocol text';

  @override
  String get unverifiedTitle => 'Unverified text — not medical guidance';

  @override
  String get sourceDocument => 'Document';

  @override
  String get sourceSection => 'Section';

  @override
  String get sourcePage => 'Page';

  @override
  String get sourceVersion => 'Version';

  @override
  String get sourceStatus => 'Source status';

  @override
  String get passageHeading => 'Supporting passage (exact text)';

  @override
  String get answeredOnDevice => 'Found in protocol text stored on this phone';

  @override
  String get answeredByServer => 'Found by the server';

  @override
  String get insufficientTitle => 'No verified answer available';

  @override
  String get insufficientBody =>
      'No approved protocol text matches this question. This is not an answer. Please ask your supervisor or medical officer.';

  @override
  String get cannotVerifyTitle => 'Cannot be verified offline';

  @override
  String get cannotVerifyBody =>
      'There is no approved protocol text on this phone and the server cannot be reached, so no answer can be given. Safety checks found no danger sign in your question, but that is not a medical answer.';

  @override
  String get clarifyTitle => 'Please tell us more';

  @override
  String get outOfScopeTitle => 'This app cannot help with this';

  @override
  String get outOfScopeBody =>
      'The app does not give medicine doses or prescriptions. Please refer the person to a medical officer.';

  @override
  String get escalationTitle => 'Possible danger sign';

  @override
  String get escalationLead => 'Follow your approved escalation steps now.';

  @override
  String get escalationPlaceholderNote =>
      'The wording below is placeholder text that has not been approved by a clinician.';

  @override
  String get notClinicallyValidated =>
      'Safety rules are not clinically validated yet';

  @override
  String get reviewNeeded => 'Needs human review';

  @override
  String get whyShown => 'Why this was shown';

  @override
  String rulesetLabel(String v) {
    return 'Rules version $v';
  }

  @override
  String get callSupervisor => 'Call supervisor';

  @override
  String get escalationGuidanceHeading => 'Approved guidance';

  @override
  String get escalationNoGuidance =>
      'No approved protocol is loaded on this phone yet, so no treatment advice can be shown. Use your approved escalation steps.';

  @override
  String get noContactConfigured =>
      'No supervisor number is set. Add one in Settings.';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get facilityPick => 'Facility';

  @override
  String get periodLabel => 'Period';

  @override
  String get period30 => 'Last 30 days';

  @override
  String get period90 => 'Last 90 days';

  @override
  String get period180 => 'Last 6 months';

  @override
  String get reportLocal => 'Summary from this phone';

  @override
  String get reportServer => 'Get report from server';

  @override
  String get reportComputedLocal =>
      'Computed on this phone from saved records (works offline)';

  @override
  String get reportComputedServer => 'Report from the server';

  @override
  String get countRecommended => 'Recommended';

  @override
  String get countPlanned => 'Planned';

  @override
  String get countConfirmed => 'Attendance confirmed (hospital record)';

  @override
  String get countTotal => 'Total recorded referrals';

  @override
  String get byService => 'By service';

  @override
  String get excludedRecords => 'Records not counted';

  @override
  String get followUpsDue => 'Follow-ups due';

  @override
  String get followUpsDone => 'Follow-ups completed in period';

  @override
  String get freshFRESH => 'Data is fresh (synced within 24 hours)';

  @override
  String get freshRECENT => 'Data is recent (synced within 3 days)';

  @override
  String get freshSTALE_OFFLINE =>
      'Data may be out of date (not synced for over 3 days)';

  @override
  String get freshNOT_PROVIDED => 'This phone has never synced';

  @override
  String get privacyNoticeReport =>
      'Aggregate counts only. No household or patient details. These are recorded referrals, not predictions of who will attend. Household visits are not hospital attendance.';

  @override
  String get shareCsv => 'Share CSV';

  @override
  String get sharePdf => 'Share PDF';

  @override
  String get noFacilities => 'No referral records on this phone yet.';

  @override
  String get reportOnlineOnly =>
      'PDF and server reports need an internet connection.';

  @override
  String generatedAt(String date) {
    return 'Generated $date';
  }

  @override
  String get syncTitle => 'Sync centre';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncing => 'Syncing…';

  @override
  String get sectionPending => 'Waiting to send';

  @override
  String get sectionFailed => 'Rejected by server';

  @override
  String get sectionConflict => 'Needs your decision';

  @override
  String get sectionSynced => 'Confirmed by server';

  @override
  String get retryOp => 'Send again';

  @override
  String get discardOp => 'Discard change';

  @override
  String get discardConfirm =>
      'Discard this change? Your saved edit will be undone on this phone. Other changes made at the same time stay queued.';

  @override
  String get resolveConflict => 'Resolve';

  @override
  String get keepServer => 'Keep the server\'s version';

  @override
  String get keepMine => 'Keep my change';

  @override
  String get conflictExplain =>
      'Someone else changed this record before your change reached the server. Nothing was overwritten. Choose which version to keep.';

  @override
  String get serverHas => 'Server has';

  @override
  String get youChanged => 'You changed it to';

  @override
  String get opNewVisit => 'New visit';

  @override
  String get opVisitOutcome => 'Visit result';

  @override
  String get opNewReferral => 'New referral';

  @override
  String get opReferralUpdate => 'Referral change';

  @override
  String get opHouseholdUpdate => 'Household change';

  @override
  String get opNewHousehold => 'New household';

  @override
  String attemptsN(int n) {
    return 'Tried $n times';
  }

  @override
  String get nothingPending => 'Nothing is waiting to be sent.';

  @override
  String syncResultOk(int n) {
    return 'Sync finished: $n changes confirmed by the server.';
  }

  @override
  String get syncAuthFailed =>
      'The server did not accept your access key. Check it in Settings. Your data is safe on this phone.';

  @override
  String get syncNotConfigured =>
      'No server address is set. Add it in Settings. Your data is safe on this phone.';

  @override
  String get syncOffline =>
      'No connection. Your changes are saved on this phone and will be sent later.';

  @override
  String get syncServerError =>
      'The server had a problem. Your changes are saved on this phone and will be sent again.';

  @override
  String get syncNeedsAttention =>
      'Some changes were not accepted by the server. Nothing was lost: they are listed below.';

  @override
  String get voiceLangTelugu => 'Telugu';

  @override
  String get voiceLangEnglish => 'English';

  @override
  String get voiceChecking => 'Checking voice support…';

  @override
  String voicePackMissing(String name) {
    return 'This phone has no offline speech pack for $name, so voice cannot work without internet. You can download the pack in the phone\'s speech settings (often Settings › Google › Speech › Offline speech recognition). Please type your question for now.';
  }

  @override
  String voiceNoOfflineEngine(String name) {
    return 'This phone cannot recognise $name speech without internet. Please type your question.';
  }

  @override
  String get voiceOnlineOption =>
      'If you want, you can allow the phone\'s online speech service in Settings (Online speech).';

  @override
  String get voicePrivacyOnDevice =>
      'Your voice is turned into text on this phone only. Nothing is sent, and this app does not save your voice.';

  @override
  String get voicePrivacyOnline =>
      'Your phone\'s online speech service turned your voice into text, so the audio was sent to that service. This app does not save your voice.';

  @override
  String get voiceTranscribing => 'Turning your voice into text…';

  @override
  String get voicePrivacyAppModel =>
      'Your voice was turned into text on this phone by the app\'s own Telugu model. Nothing is sent, and this app does not save your voice. Speech recognition can make mistakes: check the words.';

  @override
  String get voiceGetTeluguPack =>
      'You can also download the Telugu voice pack once in Settings; after that Telugu voice works with no internet.';

  @override
  String get teluguModelTitle => 'Telugu voice for this app (offline)';

  @override
  String get mapChipAvailable => 'Offline map available';

  @override
  String get mapChipMissing => 'Offline map not downloaded';

  @override
  String get houseLocationTitle => 'House location';

  @override
  String get houseLocationOpen => 'Tap to open the bigger map';

  @override
  String get houseLocationNone =>
      'No map or position on this phone for this house yet.';

  @override
  String get mapDemoNote =>
      'Demo village map. It is made up, not a real place.';

  @override
  String get phonesTitle => 'Phone numbers';

  @override
  String get phone1Label => 'Phone 1 (required)';

  @override
  String get phone2Label => 'Phone 2 (optional)';

  @override
  String get phoneNotAdded => 'Not added';

  @override
  String get phoneEdit => 'Edit';

  @override
  String get phoneAdd => 'Add phone numbers';

  @override
  String get phoneErrRequired => 'Phone 1 is needed.';

  @override
  String get phoneErrInvalid =>
      'Enter a 10-digit mobile number that starts with 6, 7, 8 or 9.';

  @override
  String get phoneErrSame => 'Phone 2 is the same as Phone 1.';

  @override
  String phoneCall(String number) {
    return 'Call $number';
  }

  @override
  String get phoneCannotCall => 'Could not open the phone app.';

  @override
  String get phoneLocalOnly =>
      'Saved on this phone only. It is not sent to the server.';

  @override
  String get teluguModelHelp =>
      'Download once (about 44 MB, use Wi-Fi). After that, Telugu voice works with no internet and your voice never leaves the phone. It can make mistakes, so always check the words.';

  @override
  String get teluguModelDownload => 'Download Telugu voice';

  @override
  String teluguModelProgress(String done, int total) {
    return 'Downloading… $done of $total MB';
  }

  @override
  String get teluguModelReady =>
      'Ready. Telugu voice works offline on this phone.';

  @override
  String get teluguModelRemove => 'Remove (frees about 44 MB)';

  @override
  String get teluguModelNeedServer =>
      'Set the server address and key above first: the pack is downloaded from your server.';

  @override
  String get teluguModelFailedNet =>
      'Could not download. Check the internet and the server, then try again. What was downloaded is kept, so it continues.';

  @override
  String get teluguModelFailedSum =>
      'The downloaded file was damaged, so it was discarded. Please try again.';

  @override
  String get teluguModelNotOnServer =>
      'This server has no Telugu voice pack. Ask whoever runs the server to install it.';

  @override
  String get altVoiceButton => 'Alternative way to get Telugu voice';

  @override
  String get altVoiceTitle => 'Telugu voice with the Google keyboard';

  @override
  String get altVoiceIntro =>
      'Use the voice typing of the Google keyboard (Gboard) to speak Telugu into the question box. Do these steps once.';

  @override
  String get altStep1Title => 'Open your phone\'s Settings';

  @override
  String get altStep1Body =>
      'Open the Settings app of your phone (the gear icon).';

  @override
  String get altStep2Title => 'Find the keyboard settings';

  @override
  String get altStep2Body =>
      'Go to System, then Languages and input. On some phones this is called General management, or Additional settings, then Language and input.';

  @override
  String get altStep3Title => 'Choose the Google keyboard';

  @override
  String get altStep3Body =>
      'Tap On-screen keyboard (or Keyboards) and open Gboard, the Google keyboard. If you do not see it, install Gboard from the Play Store and set it as your keyboard.';

  @override
  String get altStep4Title => 'Add Telugu';

  @override
  String get altStep4Body =>
      'In Gboard tap Languages, then Add keyboard, search for Telugu, select it and tap Done.';

  @override
  String get altStep5Title => 'Turn on voice typing';

  @override
  String get altStep5Body =>
      'In the Gboard settings open Voice typing, switch on Use voice typing, and make sure Telugu is one of its languages.';

  @override
  String get altStep6Title => 'Speak in this app';

  @override
  String get altStep6Body =>
      'Come back to this app and open Ask. Tap the question box so the keyboard opens. If needed, switch to Telugu with the globe key, then tap the microphone key on the keyboard and speak your question.';

  @override
  String get altStep7Title => 'Check the words';

  @override
  String get altStep7Body =>
      'Look at the Telugu words, fix any mistakes, then press Check.';

  @override
  String get altVoiceNote =>
      'Please note: Gboard voice typing is Google\'s service, not this app\'s. It usually needs internet, and the audio goes to Google. It works without internet only if Telugu is listed in Gboard\'s offline languages; on the two phones we tried, Telugu was not offered offline. For Telugu voice with no internet, use Download Telugu voice in Settings.';

  @override
  String get altOpenKeyboardSettings => 'Open keyboard settings';

  @override
  String get altOpenFailed =>
      'Could not open it. Open your phone\'s Settings yourself and follow the steps.';

  @override
  String get explAsking => 'Asking the AI server… (up to 10 seconds)';

  @override
  String get explTitle => 'Explanation';

  @override
  String get explFromDevice =>
      'Explained on this phone, using sentences from the approved text below.';

  @override
  String get explFromServerText =>
      'From your server: the approved text that answers your question, word for word.';

  @override
  String get explFromServer =>
      'Explained by your server\'s AI from the approved text below.';

  @override
  String get explNoteTimeout =>
      'The server did not answer in 10 seconds, so the phone explained it itself.';

  @override
  String get explNoteUnreachable =>
      'The server could not be reached, so the phone explained it itself.';

  @override
  String get explNoteUnsafe =>
      'The server\'s text was not shown because it named a medicine or a dose, so the phone explained it itself.';

  @override
  String get explNoteRejected =>
      'The server\'s text was not shown because it did not stay with the approved text (or its language), so the phone explained it itself.';

  @override
  String get explDisclaimerDevice =>
      'Taken word for word from the approved text. Not clinically validated: check with your supervisor.';

  @override
  String get explDisclaimerServer =>
      'Written by an AI from the approved text. Not clinically verified. Not a diagnosis. Follow your approved protocols.';

  @override
  String get sevHighTitle => 'High: possible danger sign';

  @override
  String get sevHighAction =>
      'Act now: call your supervisor or take the person to the nearest health facility.';

  @override
  String get sevMediumTitle => 'Medium: more details needed';

  @override
  String get sevMediumAction =>
      'Tap what applies below, or type more, then check again.';

  @override
  String get sevLowTitle => 'Low: no danger sign found in what you wrote';

  @override
  String get sevLowAction =>
      'For information. Read the explanation and the approved text below.';

  @override
  String get voiceResultNote =>
      'This text came from your voice and may contain mistakes. If it is not what you said, fix the words and press Check again.';

  @override
  String get onlineSpeechTitle => 'Online speech (optional)';

  @override
  String get onlineSpeechHelp =>
      'Off by default. When off, voice works only for languages this phone can recognise offline, and your voice never leaves the phone. When on, and only if a language has no offline pack and you are online, your phone\'s speech service receives the audio to turn it into text.';

  @override
  String get speechCapsLabel => 'Offline speech on this phone';

  @override
  String speechCapsLine(String en, String te) {
    return 'English: $en · Telugu: $te';
  }

  @override
  String get speechYes => 'installed';

  @override
  String get speechNo => 'not installed';

  @override
  String get speechUnknown => 'cannot check on this phone';

  @override
  String get voiceSpeak => 'Speak';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceListening => 'Listening… speak now';

  @override
  String get voiceLangLabel => 'Speak in';

  @override
  String get voiceCheckText =>
      'Check the words below, fix any mistakes, then press Check.';

  @override
  String get voicePrivacy =>
      'Your phone\'s speech service turns your voice into text and may use the internet. This app does not save your voice.';

  @override
  String get voicePermissionDenied =>
      'Microphone permission is off. Allow the microphone for this app in your phone settings, or type your question.';

  @override
  String get voiceUnavailable =>
      'Voice input is not available on this phone. Please type your question.';

  @override
  String get voiceLanguageMissing =>
      'This phone has no speech support for the chosen language. Install it in the phone\'s Google speech settings, or type your question.';

  @override
  String get voiceNoSpeech =>
      'I did not hear anything. Tap Speak and try again.';

  @override
  String get voiceOfflineLanguage =>
      'You are offline and this phone has no offline speech pack for this language. Connect to the internet to speak, or type your question - typing and safety checks work offline.';

  @override
  String get voiceNetwork =>
      'Voice needs a connection on this phone right now. Please type your question.';

  @override
  String get voiceOther => 'Voice input stopped. Please try again or type.';

  @override
  String get noServerForAnswer =>
      'There is no approved protocol text on this phone and no server address is set in Settings, so no answer can be given. Safety checks found no danger sign in your question, but that is not a medical answer.';

  @override
  String get homeMore => 'More';

  @override
  String get syncNeverSentWarning =>
      'A change is only \'synced\' after the server confirms it.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get languageLabel => 'Language';

  @override
  String get langEnglish => 'English';

  @override
  String get langTelugu => 'తెలుగు';

  @override
  String get serverSection => 'Server';

  @override
  String get serverUrl => 'Server address';

  @override
  String get serverUrlHint => 'https://your-server.example';

  @override
  String get apiKey => 'Access key';

  @override
  String get apiKeyHint => 'Stored securely on this phone';

  @override
  String get apiKeySaved => 'Access key saved';

  @override
  String get testConnection => 'Test connection';

  @override
  String get connectionOk => 'Server reachable';

  @override
  String get connectionFailed => 'Could not reach the server';

  @override
  String get insecureWarning =>
      'This address uses plain http. Data and your key can be read on the network. Use https for a real server.';

  @override
  String get invalidUrl =>
      'Enter a full address starting with http:// or https://';

  @override
  String get demoSection => 'Demo data';

  @override
  String get loadDemo => 'Load synthetic demo data';

  @override
  String demoLoadedN(int n) {
    return 'Loaded $n households of demo data';
  }

  @override
  String get useDemoDate => 'Use the demo date (13 Oct 2026)';

  @override
  String get demoExplain =>
      'Synthetic records for trying the app. They are not real people.';

  @override
  String get escalationContact => 'Supervisor phone number';

  @override
  String get escalationContactHelp =>
      'Shown on danger-sign alerts so you can call quickly.';

  @override
  String get protocolSection => 'Protocol library';

  @override
  String protocolCountN(int n) {
    return '$n approved passages on this phone';
  }

  @override
  String get protocolNone =>
      'No approved protocol text is installed yet. Questions cannot be answered from protocols until official documents are approved on the server.';

  @override
  String get refreshProtocols => 'Download approved protocols';

  @override
  String protocolRefreshed(int n) {
    return '$n passages stored';
  }

  @override
  String get privacyTitle => 'Privacy and local data';

  @override
  String get privacyBody =>
      'Household, visit and referral records are stored in a database on this phone. Questions you type are not saved. Notifications never show household details. Data is sent to the server only when you sync. The access key is kept in the phone\'s secure storage.';

  @override
  String get clearData => 'Clear all data on this phone';

  @override
  String get clearConfirm =>
      'Delete all households, visits, referrals and unsent changes from this phone? Unsent changes will be lost.';

  @override
  String get clearDone => 'All local data deleted';

  @override
  String get aboutTitle => 'About and diagnostics';

  @override
  String get appVersion => 'App version';

  @override
  String get dbSchema => 'Local database version';

  @override
  String get diagnosticsNote =>
      'Diagnostics contain counts and versions only, never health information.';

  @override
  String get validationNote =>
      'Not clinically validated. Draft safety rules, synthetic data.';

  @override
  String get moreTitle => 'More';

  @override
  String get errNetwork => 'No connection. Try again when you are online.';

  @override
  String get errTimeout => 'The server took too long to answer.';

  @override
  String get errUnauthorized =>
      'The server did not accept your access key. Check Settings.';

  @override
  String get errServer => 'The server had a problem. Try again later.';

  @override
  String get errInvalidResponse => 'The server sent an unexpected answer.';

  @override
  String get errNotConfigured => 'Set the server address in Settings first.';

  @override
  String get errForbidden => 'You are not allowed to do this.';

  @override
  String get errUnknown => 'Something went wrong. Try again.';

  @override
  String get semBottomNav => 'Main navigation';

  @override
  String get semStatusChip =>
      'Connection and sync status. Tap to open the sync centre.';

  @override
  String get h5MapTitle => 'Houses map';

  @override
  String h5MapChip(int n) {
    return 'Offline map: $n houses. Tap to open.';
  }

  @override
  String get h5AllVillages => 'All villages';

  @override
  String h5HousesIn(int n) {
    return '$n houses';
  }

  @override
  String get h5LegendUrgent => 'Urgent';

  @override
  String get h5LegendDue => 'Due';

  @override
  String get h5LegendSoon => 'This week';

  @override
  String get h5LegendNone => 'Nothing due';

  @override
  String get h5MapMadeUp => 'Made-up map. The house positions are not real.';

  @override
  String h5MapAsOf(String date) {
    return 'Visit list as of $date';
  }

  @override
  String h5HouseNo(String no) {
    return 'House $no';
  }

  @override
  String h5PeopleCount(int n) {
    return '$n people';
  }

  @override
  String get h5OpenHouse => 'Open';

  @override
  String get h5DueNow => 'To do';

  @override
  String get h5NothingDue => 'Nothing is due for this house.';

  @override
  String get h5PickTitle => 'House location';

  @override
  String get h5PickHelp => 'Tap the map where the house is.';

  @override
  String get h5PickUse => 'Use this location';

  @override
  String get h5PickCardTitle => 'House location (optional)';

  @override
  String get h5PickOpen => 'Choose on the map';

  @override
  String get h5PickChange => 'Change on the map';

  @override
  String get h5PickNone => 'No location chosen yet.';

  @override
  String h5PickedAt(String lat, String lng) {
    return 'Chosen: $lat, $lng';
  }

  @override
  String get h5PickClear => 'Remove location';

  @override
  String get h5PickNoMap => 'No map is on this phone.';

  @override
  String get h5MemberPregnant => 'Pregnant';

  @override
  String h5PriorityN(int n) {
    return 'Priority $n';
  }

  @override
  String get h5StatusOverdue => 'Overdue';

  @override
  String get h5StatusToday => 'Due today';

  @override
  String get h5StatusWeek => 'Due this week';

  @override
  String get h5MembersTitle => 'People in this house';

  @override
  String get h5HouseTitle => 'House';

  @override
  String h5VillageLine(String village, String asha) {
    return '$village, ASHA $asha';
  }

  @override
  String get h5VisitTitle => 'Visit list';

  @override
  String h5VisitAsOf(String date, int n) {
    return 'As of $date. $n items.';
  }

  @override
  String get h5AllAshas => 'All ASHAs';

  @override
  String get h5Priority1 => 'Priority 1: high risk, due now';

  @override
  String get h5Priority2 => 'Priority 2: due now';

  @override
  String get h5Priority3 => 'Priority 3: later this week';

  @override
  String get h5VisitEmpty => 'Nothing is due.';

  @override
  String get h5MoreVisit => 'Visit list (block data)';

  @override
  String get h5MoreMap => 'Houses map';

  @override
  String h5DueOn(String date) {
    return 'due $date';
  }
}
