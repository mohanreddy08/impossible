// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appName => 'ASHA';

  @override
  String get navHome => 'హోమ్';

  @override
  String get navVisits => 'సందర్శనలు';

  @override
  String get navAsk => 'అడగండి';

  @override
  String get navHouseholds => 'ఇళ్లు';

  @override
  String get navMore => 'మరిన్ని';

  @override
  String get loading => 'లోడ్ అవుతోంది…';

  @override
  String get retry => 'మళ్ళీ ప్రయత్నించండి';

  @override
  String get cancel => 'రద్దు';

  @override
  String get save => 'సేవ్ చేయండి';

  @override
  String get close => 'మూసివేయి';

  @override
  String get confirm => 'నిర్ధారించండి';

  @override
  String get discard => 'వదిలేయండి';

  @override
  String get yes => 'అవును';

  @override
  String get no => 'కాదు';

  @override
  String get today => 'ఈ రోజు';

  @override
  String get optional => 'ఐచ్ఛికం';

  @override
  String get required => 'తప్పనిసరి';

  @override
  String get search => 'వెతకండి';

  @override
  String get all => 'అన్నీ';

  @override
  String get clear => 'తొలగించు';

  @override
  String get loadMore => 'ఇంకా చూపించు';

  @override
  String get noResults => 'ఏమీ దొరకలేదు';

  @override
  String get back => 'వెనుకకు';

  @override
  String get chooseDate => 'తేదీని ఎంచుకోండి';

  @override
  String get notSet => 'నమోదు కాలేదు';

  @override
  String get none => 'ఏమీ లేదు';

  @override
  String get statusOnline => 'ఆన్‌లైన్';

  @override
  String get statusOffline => 'ఆఫ్‌లైన్';

  @override
  String get statusServerUnreachable => 'సర్వర్ అందుబాటులో లేదు';

  @override
  String syncPendingCount(int n) {
    return '$n సింక్ కోసం వేచి ఉన్నాయి';
  }

  @override
  String get allSynced => 'అన్ని మార్పులు సింక్ అయ్యాయి';

  @override
  String lastSynced(String date) {
    return 'చివరి సింక్ $date';
  }

  @override
  String get neverSynced => 'ఇంకా సింక్ కాలేదు';

  @override
  String get demoBadge => 'డెమో డేటా (కృత్రిమం)';

  @override
  String get greetMorning => 'శుభోదయం';

  @override
  String get greetAfternoon => 'శుభ మధ్యాహ్నం';

  @override
  String get greetEvening => 'శుభ సాయంత్రం';

  @override
  String get homeQuestion => 'ఈ రోజు మీ జాబితాలో ఏముంది?';

  @override
  String get nextVisit => 'తదుపరి సందర్శన';

  @override
  String get dueToday => 'ఈ రోజు';

  @override
  String get overdue => 'ఆలస్యమైనవి';

  @override
  String get upcoming => 'రాబోయేవి';

  @override
  String get pendingReferrals => 'పెండింగ్ రెఫరల్స్';

  @override
  String get priorityTitle => 'ముందు చూడాల్సినవి';

  @override
  String get prioritySubtitle => 'అత్యవసరత ప్రకారం ఇళ్ల వరుస';

  @override
  String get priorityUrgent => 'అత్యవసరం';

  @override
  String get prioritySoon => 'త్వరలో';

  @override
  String get priorityRoutine => 'సాధారణం';

  @override
  String priorityWhyOverdue(int days) {
    return 'సందర్శన $days రోజులు ఆలస్యం';
  }

  @override
  String get priorityWhyToday => 'ఈ రోజు సందర్శన';

  @override
  String priorityWhyReferral(int days) {
    return 'ఓపెన్ రెఫరల్, $days రోజులుగా వేచి ఉంది';
  }

  @override
  String priorityWhyMissed(int n) {
    return 'గత 90 రోజుల్లో $n సందర్శనలు తప్పాయి';
  }

  @override
  String priorityWhyType(String category) {
    return '$category ఫాలో-అప్';
  }

  @override
  String get priorityNote =>
      'వరుసకు గడువు తేదీలు, ఓపెన్ రెఫరల్స్, తప్పిన సందర్శనలు, సందర్శన రకం వాడతారు. ఇది నమూనా నియమం, వైద్య రిస్క్ స్కోర్ కాదు; వైద్య సమీక్ష అవసరం.';

  @override
  String get priorityEmpty =>
      'ఏమీ వేచి లేదు: ఆలస్యమైన సందర్శనలు, ఓపెన్ రెఫరల్స్ లేవు.';

  @override
  String get prioritySeeAll => 'పూర్తి జాబితా చూడండి';

  @override
  String get recordsTitle => 'ఈ ఫోన్‌లోని మీ రికార్డుల నుండి';

  @override
  String get recordsFooter =>
      'ఈ ఫోన్‌లోని ఇళ్ల రిజిస్టర్ నుండి తీసుకున్నది, కాబట్టి ఆఫ్‌లైన్‌లో పనిచేస్తుంది. ఇది వైద్య సలహా కాదు.';

  @override
  String recordsOverdue(int n) {
    return '$n ఇళ్లకు ఆలస్యమైన సందర్శన ఉంది.';
  }

  @override
  String recordsDueToday(int n) {
    return '$n ఇళ్లకు ఈ రోజు సందర్శన ఉంది.';
  }

  @override
  String recordsReferrals(int n) {
    return '$n ఇళ్లకు ఓపెన్ రెఫరల్ ఉంది.';
  }

  @override
  String recordsPriority(int n) {
    return '$n ఇళ్లు వేచి ఉన్నాయి. అత్యవసరమైనవి ముందు:';
  }

  @override
  String get recordsNone => 'ప్రస్తుతం ఏమీ లేవు.';

  @override
  String recordsHouseholdMissing(String id) {
    return 'ID $id ఉన్న ఇల్లు ఈ ఫోన్‌లో లేదు.';
  }

  @override
  String recordsHouseholdInfo(String status, String next, String last) {
    return 'స్థితి: $status. తదుపరి సందర్శన: $next. చివరి సందర్శన: $last.';
  }

  @override
  String get clarifyAddTitle => 'వర్తించేది నొక్కండి, లేదా మరింత టైప్ చేయండి:';

  @override
  String get clarifyChipNow => 'ఇప్పుడే జరుగుతోంది';

  @override
  String get clarifyChipSevere => 'తీవ్రంగా ఉంది';

  @override
  String get clarifyChipPregnant => 'గర్భిణీ స్త్రీ';

  @override
  String get clarifyChipChild => 'పసిబిడ్డ / పిల్లవాడు';

  @override
  String alertOneTitle(String id) {
    return 'అత్యవసరం: ఇల్లు $id';
  }

  @override
  String get alertOneBody => 'యాప్ తెరిచి \'ముందు చూడాల్సినవి\' చూడండి.';

  @override
  String alertManyTitle(int n) {
    return 'అత్యవసరం: $n ఇళ్లకు శ్రద్ధ అవసరం';
  }

  @override
  String get alertManyBody =>
      'ఎవరిని ముందు చూడాలో తెలుసుకోవడానికి యాప్ తెరిచి \'ముందు చూడాల్సినవి\' చూడండి.';

  @override
  String get aiAssistTitle => 'ఆన్‌లైన్ కృత్రిమ మేధ సహాయం (ఐచ్ఛికం)';

  @override
  String get aiAssistHelp =>
      'డిఫాల్ట్‌గా ఆఫ్. ఆఫ్‌లో ఉంటే, అడగండి పేజీ ఈ ఫోన్‌లోని ఆమోదిత ప్రోటోకాల్ నుండి మాత్రమే వివరిస్తుంది, కాబట్టి ఇంటర్నెట్ ఉన్నా లేకున్నా ఒకే ఫలితం వస్తుంది. ఆన్‌లో ఉండి ఆన్‌లైన్‌లో ఉన్నప్పుడు, మీ ప్రశ్న మరియు దగ్గరి ఆమోదిత భాగాలు మీ సర్వర్‌లోని కృత్రిమ మేధకు పంపబడతాయి, అది వివరణ రాస్తుంది; 10 సెకన్లలో స్పందించకపోతే ఫోనే వివరిస్తుంది.';

  @override
  String get alertsTitle => 'అత్యవసర హెచ్చరికలు';

  @override
  String get alertsHelp =>
      'ముందు చూడాల్సినవి జాబితాలో ఏదైనా ఇల్లు అత్యవసరమైతే నోటిఫికేషన్ వస్తుంది. ఇది ఫోన్‌లోనే లెక్కిస్తారు, కాబట్టి ఇంటర్నెట్ లేకున్నా పనిచేస్తుంది. అత్యవసర నియమం నమూనా మాత్రమే, వైద్య రిస్క్ స్కోర్ కాదు.';

  @override
  String get alertsPermissionDenied =>
      'ఈ యాప్‌కు నోటిఫికేషన్లు నిలిపివేయబడ్డాయి. అత్యవసర హెచ్చరికల కోసం ఫోన్ సెట్టింగ్స్‌లో అనుమతించండి.';

  @override
  String get safetyMsgEscalation =>
      'ప్రమాద సంకేతం కావచ్చు. మీ ఆమోదిత అత్యవసర ప్రోటోకాల్‌ను అనుసరించి సూపర్‌వైజింగ్ వైద్యాధికారిని సంప్రదించండి. [తాత్కాలిక వచనం - వైద్య ఆమోదం పెండింగ్]';

  @override
  String get safetyMsgClarification =>
      'దయచేసి వివరించండి: ఎవరికి, ఏ లక్షణం, ఇప్పుడే జరుగుతోందా. [తాత్కాలిక వచనం - వైద్య ఆమోదం పెండింగ్]';

  @override
  String get ruleBleeding => 'భారీ రక్తస్రావం';

  @override
  String get ruleFits => 'ఫిట్స్ / మూర్ఛ';

  @override
  String get ruleBreathing => 'శ్వాస తీసుకోవడంలో ఇబ్బంది';

  @override
  String get ruleUnconscious => 'స్పృహ కోల్పోవడం / స్పందించకపోవడం';

  @override
  String get ruleFever => 'తీవ్రమైన జ్వరం';

  @override
  String get ruleNotFeeding => 'పాలు తాగకపోవడం';

  @override
  String get ruleAmbiguous => 'అనారోగ్యం గురించి స్పష్టత లేని వివరణ';

  @override
  String get ruleOutOfScope => 'మందు లేదా మోతాదు కోసం అడిగారు';

  @override
  String get ruleOther => 'భద్రతా నియమం సరిపోలింది';

  @override
  String reasonMatched(String label) {
    return '$label: సరిపోలే పదబంధం కనిపించింది';
  }

  @override
  String reasonNeedsContext(String label) {
    return '$label: తగినంత వివరాలు లేవు (ఎంత తీవ్రం, ఎవరికి, ఎప్పుడు)';
  }

  @override
  String get reasonShortMessage =>
      'సందేశం చాలా చిన్నది, అందుకే మరిన్ని వివరాలు అడుగుతున్నాం';

  @override
  String get safetyRulesLabel => 'భద్రతా నియమాలు';

  @override
  String get notValidatedShort => 'వైద్యపరంగా ధృవీకరించలేదు';

  @override
  String get tblHouseholds => 'ఇళ్లు';

  @override
  String get tblVisits => 'సందర్శనలు';

  @override
  String get tblReferrals => 'రెఫరల్స్';

  @override
  String get tblProtocolPassages => 'ప్రోటోకాల్ భాగాలు';

  @override
  String get tblSyncOutbox => 'పంపడానికి వేచి ఉన్నవి';

  @override
  String get shareSubject => 'రెఫరల్ సారాంశం';

  @override
  String get splashTagline => 'మీ ఆరోగ్య కార్యకర్త సహాయకుడు';

  @override
  String get obChooseLanguage => 'మీ భాషను ఎంచుకోండి';

  @override
  String get obChooseLanguageHint => 'దీన్ని తర్వాత సెట్టింగ్స్‌లో మార్చవచ్చు.';

  @override
  String get obContinue => 'కొనసాగించండి';

  @override
  String get obSkip => 'దాటవేయి';

  @override
  String get obNext => 'తదుపరి';

  @override
  String get obGetStarted => 'ప్రారంభించండి';

  @override
  String obStep(int n, int total) {
    return '$total లో $nవ దశ';
  }

  @override
  String get ob1Title => 'మీ రోజు ఒకే చోట';

  @override
  String get ob1Body =>
      'ఈ రోజు సందర్శనలు చూడండి, ఏమైందో నమోదు చేయండి, ఎవరికి ముందు వెళ్లాలో \'ముందు చూడాల్సినవి\' జాబితాలో తెలుసుకోండి.';

  @override
  String get ob2Title => 'ఇంటర్నెట్ లేకున్నా పనిచేస్తుంది';

  @override
  String get ob2Body =>
      'మీ జాబితా, సందర్శనలు, భద్రతా తనిఖీలు ఈ ఫోన్‌లోనే ఉంటాయి. కనెక్షన్ వచ్చినప్పుడు మీ పని ఆటోమేటిక్‌గా సర్వర్‌కు వెళ్తుంది.';

  @override
  String get ob3Title => 'భద్రతే ముందు';

  @override
  String get ob3Body =>
      'ప్రమాద సంకేతాల గురించి ASHA హెచ్చరిస్తుంది. ఇది డాక్టర్‌కు లేదా మీ ఆమోదిత ప్రోటోకాల్స్‌కు ప్రత్యామ్నాయం కాదు. భద్రతా నియమాలు ఇంకా ముసాయిదా మాత్రమే, వైద్యపరంగా ధృవీకరించలేదు.';

  @override
  String get ob4Title => 'ASHA అడిగే రెండు అనుమతులు';

  @override
  String get ob4Mic =>
      'మైక్రోఫోన్: మీరు \'మాట్లాడండి\' నొక్కినప్పుడు మాత్రమే, మీ గొంతును అక్షరాలుగా మార్చడానికి. ఆడియో సేవ్ చేయబడదు.';

  @override
  String get ob4Notif =>
      'నోటిఫికేషన్లు: ఏదైనా ఇల్లు అత్యవసరమైనప్పుడు తెలియజేయడానికి. ఇంటర్నెట్ లేకున్నా పనిచేస్తుంది.';

  @override
  String get ob4Server =>
      'మీ పనిని సింక్ చేయడానికి, సిద్ధంగా ఉన్నప్పుడు సెట్టింగ్స్‌లో మీ సర్వర్ చిరునామా జోడించండి.';

  @override
  String get visitTimeLabel => 'సందర్శన తేదీ మరియు సమయం';

  @override
  String get visitTimeAuto =>
      'ఈ సందర్శనను తెరిచినప్పుడు ఆటోమేటిక్‌గా నమోదైంది. దీన్ని మార్చలేరు.';

  @override
  String get visitTimeLocal =>
      'సందర్శనతో పాటు సేవ్ అవుతుంది, ఆన్‌లైన్‌లో ఉన్నప్పుడు సర్వర్‌కు పంపబడుతుంది.';

  @override
  String get errTimeFuture =>
      'ఆ సమయం ఈ రోజు ఇంకా రాలేదు. మీరు నిజంగా వెళ్లిన సమయాన్ని ఎంచుకోండి.';

  @override
  String get errTimeInvalid => 'సరైన సమయాన్ని ఎంచుకోండి.';

  @override
  String get aiPrivacy =>
      'ఆన్‌లైన్‌లో ఉన్నప్పుడు, మీ ప్రశ్న మరియు దగ్గరి ఆమోదిత భాగాలు వివరణ రాయడానికి మీ సర్వర్‌లోని కృత్రిమ మేధకు కూడా పంపబడతాయి. ఏదీ సేవ్ చేయబడదు.';

  @override
  String get escalationSampleHeading => 'నమూనా పాఠం (ఆమోదిత మార్గదర్శకం కాదు)';

  @override
  String get addFamily => 'కొత్త కుటుంబాన్ని చేర్చండి';

  @override
  String get addFamilyTitle => 'కొత్త కుటుంబం';

  @override
  String get villageLabel2 => 'గ్రామ ID';

  @override
  String get villageHint => 'ఉదాహరణ: VIL-SYN-01';

  @override
  String get villagePick => 'ఈ ఫోన్‌లోని గ్రామాలు';

  @override
  String get membersLabel => 'కుటుంబ సభ్యుల సంఖ్య';

  @override
  String get membersDecrease => 'తక్కువ సభ్యులు';

  @override
  String get membersIncrease => 'ఎక్కువ సభ్యులు';

  @override
  String get followupsLabel => 'ఈ కుటుంబానికి ఏ ఫాలో-అప్‌లు అవసరం కావచ్చు?';

  @override
  String get followupsHint =>
      'వర్తించేవన్నీ ఎంచుకోండి. తర్వాత ఇంకా చేర్చవచ్చు.';

  @override
  String get addFamilySave => 'ఈ కుటుంబాన్ని చేర్చండి';

  @override
  String get addFamilyNote =>
      'ఇప్పుడే ఈ ఫోన్‌లో సేవ్ అవుతుంది. ఆన్‌లైన్‌లో ఉన్నప్పుడు సర్వర్‌కు పంపబడుతుంది. మొదటి సందర్శనను ప్లాన్ చేయడానికి కుటుంబానికి ఒక ID వస్తుంది.';

  @override
  String addFamilyDone(String id) {
    return 'కుటుంబం చేర్చబడింది: $id. క్రింద మొదటి సందర్శనను ప్లాన్ చేయండి.';
  }

  @override
  String get errVillageInvalid =>
      'గ్రామ ID నమోదు చేయండి: అక్షరాలు, అంకెలు, డాష్ లేదా అండర్‌స్కోర్, 2 నుండి 32 వరకు.';

  @override
  String get errMembersInvalid => 'సభ్యుల సంఖ్య 1 నుండి 60 మధ్య ఉండాలి.';

  @override
  String get errCategoriesEmpty => 'కనీసం ఒక ఫాలో-అప్ రకాన్ని ఎంచుకోండి.';

  @override
  String get errWorkerUnknown =>
      'మీరు ఏ ఆరోగ్య కార్యకర్తనో ఈ ఫోన్‌కు ఇంకా తెలియదు. ఒకసారి సింక్ చేయండి (లేదా డెమో డేటా లోడ్ చేయండి), తర్వాత కుటుంబాన్ని చేర్చండి.';

  @override
  String get quickActions => 'త్వరిత చర్యలు';

  @override
  String get askQuestion => 'ప్రశ్న అడగండి';

  @override
  String get openPlanner => 'ఈ రోజు సందర్శనలు';

  @override
  String get reportsAction => 'నివేదికలు';

  @override
  String get syncCentreAction => 'సింక్ కేంద్రం';

  @override
  String get referralsAction => 'రెఫరల్స్';

  @override
  String get noVisitsToday => 'ఈ రోజు సందర్శనలు లేవు';

  @override
  String get emptyHomeTitle => 'ఈ ఫోన్‌లో ఇంకా ఇళ్ల వివరాలు లేవు';

  @override
  String get emptyHomeBody =>
      'సెట్టింగ్స్‌లో సర్వర్‌కు కనెక్ట్ అయి సింక్ చేయండి, లేదా యాప్‌ను ప్రయత్నించడానికి డెమో డేటాను లోడ్ చేయండి.';

  @override
  String householdsCount(int n) {
    return 'ఈ ఫోన్‌లో $n ఇళ్లు';
  }

  @override
  String get plannerTitle => 'సందర్శనల ప్రణాళిక';

  @override
  String get bucketOverdue => 'ఆలస్యం';

  @override
  String get bucketToday => 'ఈ రోజు';

  @override
  String get bucketUpcoming => 'రాబోయేవి';

  @override
  String get priorityExplainer =>
      'గడువు తేదీ ప్రకారం వరుస: ఎక్కువ ఆలస్యమైనవి ముందు. ఎలాంటి రిస్క్ స్కోరు వాడలేదు.';

  @override
  String reasonOverdue(String category, int days) {
    return '$category ఫాలో-అప్ $days రోజుల క్రితమే చేయాల్సింది';
  }

  @override
  String reasonToday(String category) {
    return '$category ఫాలో-అప్ ఈ రోజు చేయాలి';
  }

  @override
  String reasonUpcoming(String category, int days) {
    return '$category ఫాలో-అప్ $days రోజుల్లో చేయాలి';
  }

  @override
  String lastVisitOn(String date) {
    return 'చివరి సందర్శన: $date';
  }

  @override
  String get lastVisitNone => 'పూర్తయిన సందర్శన నమోదు లేదు';

  @override
  String get openReferralNote => 'ఈ ఇంటికి ఓపెన్ రెఫరల్ కూడా ఉంది';

  @override
  String get recordOutcome => 'సందర్శనను నమోదు చేయండి';

  @override
  String get visitDetails => 'సందర్శన వివరాలు';

  @override
  String get outcomeLabel => 'ఏమైంది?';

  @override
  String get outcomeCompleted => 'సందర్శన పూర్తయింది';

  @override
  String get outcomeMissed => 'సందర్శించలేకపోయాను (ఇంట్లో లేరు మొ.)';

  @override
  String get outcomeCancelled => 'ఈ సందర్శనను రద్దు చేయండి';

  @override
  String get visitDate => 'సందర్శన తేదీ';

  @override
  String get followupNeeded => 'మరో సందర్శన అవసరం';

  @override
  String get nextVisitDate => 'తదుపరి సందర్శన తేదీ';

  @override
  String get recommendReferral => 'ఆసుపత్రికి రెఫరల్ సిఫార్సు చేయండి';

  @override
  String get facilityLabel => 'ఆరోగ్య కేంద్రం';

  @override
  String get serviceLabel => 'సేవ';

  @override
  String get noFacilitiesKnown =>
      'ఈ ఫోన్‌లో ఇంకా ఆరోగ్య కేంద్రాల జాబితా లేదు, అందువల్ల ఇక్కడ రెఫరల్ నమోదు చేయలేరు.';

  @override
  String get referralNeedsDone =>
      'చేసిన సందర్శనకు మాత్రమే రెఫరల్ నమోదు చేయవచ్చు.';

  @override
  String get savedOffline =>
      'ఈ ఫోన్‌లో సేవ్ అయింది. ఆన్‌లైన్‌లో ఉన్నప్పుడు పంపబడుతుంది.';

  @override
  String get errActualRequired => 'సందర్శన జరిగిన తేదీని ఎంచుకోండి.';

  @override
  String get errFuture => 'సందర్శన తేదీ భవిష్యత్తులో ఉండకూడదు.';

  @override
  String get errNextRequired => 'తదుపరి సందర్శన తేదీని ఎంచుకోండి.';

  @override
  String get errNextNotAfter => 'తదుపరి సందర్శన ఈ సందర్శన తర్వాత ఉండాలి.';

  @override
  String get errInconsistent =>
      'తదుపరి సందర్శన తేదీని తొలగించండి, లేదా మరో సందర్శన అవసరమని చెప్పండి.';

  @override
  String get errAlreadyFinal => 'ఈ సందర్శన ఇప్పటికే నమోదైంది.';

  @override
  String get errPlannedBefore =>
      'ప్లాన్ చేసిన తేదీ రెఫరల్ చేసిన తేదీకి ముందు ఉండకూడదు.';

  @override
  String get errInPast => 'ఈ రోజు లేదా తర్వాతి తేదీని ఎంచుకోండి.';

  @override
  String get errNeedFacility => 'ఆరోగ్య కేంద్రాన్ని ఎంచుకోండి.';

  @override
  String get errGeneric => 'దయచేసి ఈ నమోదును సరిచూడండి.';

  @override
  String get householdsTitle => 'ఇళ్లు';

  @override
  String get searchHouseholds => 'ఇంటి ఐడీతో వెతకండి';

  @override
  String get filterStatus => 'స్థితి';

  @override
  String get filterCategory => 'ఫాలో-అప్ రకం';

  @override
  String get filterVillage => 'గ్రామం';

  @override
  String get statusUPCOMING => 'రాబోయేది';

  @override
  String get statusDUE_TODAY => 'ఈ రోజు';

  @override
  String get statusOVERDUE => 'ఆలస్యం';

  @override
  String get statusCOMPLETED => 'ఇటీవల సందర్శించారు';

  @override
  String get statusNO_VISIT_DUE => 'సందర్శన అవసరం లేదు';

  @override
  String members(int n) {
    return '$n సభ్యులు';
  }

  @override
  String get villageLabel => 'గ్రామం';

  @override
  String get nextVisitLabel => 'తదుపరి సందర్శన';

  @override
  String get lastVisitLabel => 'చివరి సందర్శన';

  @override
  String get eligibleFollowups => 'ఫాలో-అప్ రకాలు';

  @override
  String get visitHistory => 'సందర్శనల చరిత్ర';

  @override
  String get noHistory => 'సందర్శనలు నమోదు కాలేదు';

  @override
  String get scheduleVisit => 'సందర్శనను షెడ్యూల్ చేయండి';

  @override
  String get householdReferrals => 'రెఫరల్స్';

  @override
  String get unsyncedBadge => 'ఇంకా సింక్ కాలేదు';

  @override
  String get visitStatusPLANNED => 'ప్రణాళిక';

  @override
  String get visitStatusCOMPLETED => 'పూర్తి';

  @override
  String get visitStatusMISSED => 'వీలుకాలేదు';

  @override
  String get visitStatusRESCHEDULED => 'తేదీ మార్చారు';

  @override
  String get visitStatusCANCELLED => 'రద్దు';

  @override
  String get catANC => 'గర్భిణీ సంరక్షణ';

  @override
  String get catIMMUNISATION => 'టీకాలు';

  @override
  String get catNUTRITION => 'పోషణ';

  @override
  String get catHYPERTENSION => 'రక్తపోటు';

  @override
  String get catDIABETES => 'మధుమేహం';

  @override
  String get catROUTINE => 'సాధారణ సందర్శన';

  @override
  String get catGENERAL => 'సాధారణం';

  @override
  String get referralsTitle => 'రెఫరల్స్';

  @override
  String get refFilterAll => 'అన్నీ';

  @override
  String get refFilterOpen => 'పెండింగ్';

  @override
  String get refFilterRecommended => 'సిఫార్సు చేసినవి';

  @override
  String get refFilterPlanned => 'ప్లాన్ చేసినవి';

  @override
  String get refFilterConfirmed => 'హాజరు నిర్ధారించినవి';

  @override
  String get refFilterClosed => 'ముగిసినవి';

  @override
  String get phaseRecommended => 'సిఫార్సు చేశారు — ఇంకా ప్లాన్ కాలేదు';

  @override
  String get phasePlanned => 'ప్లాన్ చేశారు — హాజరు నిర్ధారణ కాలేదు';

  @override
  String get phaseConfirmed =>
      'ఆసుపత్రి హాజరు నిర్ధారించబడింది (ఆసుపత్రి రికార్డు)';

  @override
  String get phaseCancelled => 'రెఫరల్ రద్దయింది';

  @override
  String get phaseInvalid => 'రికార్డు చెల్లనిదిగా గుర్తించారు';

  @override
  String get phaseDuplicate => 'నకిలీ రికార్డు (లెక్కించరు)';

  @override
  String get attendanceNote =>
      'ఆసుపత్రిలో సందర్శన రికార్డు ఉన్నప్పుడు మాత్రమే హాజరు నిర్ధారితంగా చూపబడుతుంది. రెఫరల్ సిఫార్సు లేదా ప్లాన్ చేయడం అంటే వ్యక్తి వెళ్లారని కాదు.';

  @override
  String get stepRecommended => 'సిఫార్సు';

  @override
  String get stepPlanned => 'ప్లాన్';

  @override
  String get stepAttended => 'ఆసుపత్రి హాజరు నిర్ధారణ';

  @override
  String get stepDone => 'పూర్తి';

  @override
  String get stepWaiting => 'ఇంకా కాలేదు';

  @override
  String get setPlannedDate => 'ప్లాన్ చేసిన తేదీని ఇవ్వండి';

  @override
  String get changePlannedDate => 'ప్లాన్ తేదీని మార్చండి';

  @override
  String get cancelReferral => 'రెఫరల్ రద్దు చేయండి';

  @override
  String get cancelReferralConfirm =>
      'ఈ రెఫరల్‌ను రద్దు చేయాలా? ఆన్‌లైన్‌లో ఉన్నప్పుడు ఇది సర్వర్‌కు పంపబడుతుంది.';

  @override
  String plannedOn(String date) {
    return '$date కు ప్లాన్ చేశారు';
  }

  @override
  String createdOn(String date) {
    return 'రెఫరల్ చేసిన తేదీ $date';
  }

  @override
  String get attendanceRecordLabel => 'ఆసుపత్రి రికార్డు';

  @override
  String confirmedOn(String date) {
    return '$date న నిర్ధారణ';
  }

  @override
  String get askTitle => 'ఆరోగ్య ప్రశ్న అడగండి';

  @override
  String get askHint => 'తెలుగు, ఆంగ్లం లేదా రెండింటిలో టైప్ చేయండి';

  @override
  String get askButton => 'చూడండి';

  @override
  String get askNeedsText => 'ముందు ఒక ప్రశ్న టైప్ చేయండి.';

  @override
  String get askTooLong => 'ప్రశ్న చాలా పెద్దది. దయచేసి కుదించండి.';

  @override
  String get askChecking => 'చూస్తోంది…';

  @override
  String get askPrivacy => 'మీ ప్రశ్న ఈ ఫోన్‌లో సేవ్ చేయబడదు.';

  @override
  String get askSafetyOnDevice =>
      'భద్రతా తనిఖీలు ఇంటర్నెట్ లేకపోయినా ఈ ఫోన్‌లోనే జరుగుతాయి.';

  @override
  String get verifiedTitle => 'ధృవీకరించిన ప్రోటోకాల్ పాఠం';

  @override
  String get unverifiedTitle => 'ధృవీకరించని పాఠం — వైద్య మార్గదర్శకం కాదు';

  @override
  String get sourceDocument => 'పత్రం';

  @override
  String get sourceSection => 'విభాగం';

  @override
  String get sourcePage => 'పేజీ';

  @override
  String get sourceVersion => 'వెర్షన్';

  @override
  String get sourceStatus => 'మూల స్థితి';

  @override
  String get passageHeading => 'ఆధార భాగం (అసలు పాఠం)';

  @override
  String get answeredOnDevice => 'ఈ ఫోన్‌లో ఉన్న ప్రోటోకాల్ పాఠంలో దొరికింది';

  @override
  String get answeredByServer => 'సర్వర్ కనుగొంది';

  @override
  String get insufficientTitle => 'ధృవీకరించిన సమాధానం అందుబాటులో లేదు';

  @override
  String get insufficientBody =>
      'ఈ ప్రశ్నకు సరిపోయే ఆమోదిత ప్రోటోకాల్ పాఠం లేదు. ఇది సమాధానం కాదు. దయచేసి మీ సూపర్‌వైజర్ లేదా వైద్యాధికారిని అడగండి.';

  @override
  String get cannotVerifyTitle => 'ఆఫ్‌లైన్‌లో ధృవీకరించలేము';

  @override
  String get cannotVerifyBody =>
      'ఈ ఫోన్‌లో ఆమోదిత ప్రోటోకాల్ పాఠం లేదు, సర్వర్ కూడా అందుబాటులో లేదు, అందువల్ల సమాధానం ఇవ్వలేము. మీ ప్రశ్నలో ప్రమాద సంకేతం కనబడలేదు, కానీ అది వైద్య సమాధానం కాదు.';

  @override
  String get clarifyTitle => 'దయచేసి మరిన్ని వివరాలు చెప్పండి';

  @override
  String get outOfScopeTitle => 'ఈ యాప్ దీనికి సహాయం చేయలేదు';

  @override
  String get outOfScopeBody =>
      'ఈ యాప్ మందుల మోతాదులు లేదా ప్రిస్క్రిప్షన్లు ఇవ్వదు. దయచేసి వ్యక్తిని వైద్యాధికారి వద్దకు పంపండి.';

  @override
  String get escalationTitle => 'ప్రమాద సంకేతం కావచ్చు';

  @override
  String get escalationLead => 'ఇప్పుడే మీ ఆమోదిత అత్యవసర చర్యలను అనుసరించండి.';

  @override
  String get escalationPlaceholderNote =>
      'కింది పదాలు వైద్యులు ఆమోదించని తాత్కాలిక పాఠం.';

  @override
  String get notClinicallyValidated =>
      'భద్రతా నియమాలు ఇంకా వైద్యపరంగా ధృవీకరించబడలేదు';

  @override
  String get reviewNeeded => 'మానవ సమీక్ష అవసరం';

  @override
  String get whyShown => 'ఇది ఎందుకు చూపించారు';

  @override
  String rulesetLabel(String v) {
    return 'నియమాల వెర్షన్ $v';
  }

  @override
  String get callSupervisor => 'సూపర్‌వైజర్‌కు కాల్ చేయండి';

  @override
  String get escalationGuidanceHeading => 'ఆమోదిత మార్గదర్శకం';

  @override
  String get escalationNoGuidance =>
      'ఈ ఫోన్‌లో ఇంకా ఆమోదిత ప్రోటోకాల్ లేదు, కాబట్టి చికిత్స సలహా చూపలేము. మీ ఆమోదిత అత్యవసర చర్యలను అనుసరించండి.';

  @override
  String get noContactConfigured =>
      'సూపర్‌వైజర్ నంబర్ ఇవ్వలేదు. సెట్టింగ్స్‌లో జోడించండి.';

  @override
  String get reportsTitle => 'నివేదికలు';

  @override
  String get facilityPick => 'ఆరోగ్య కేంద్రం';

  @override
  String get periodLabel => 'కాలం';

  @override
  String get period30 => 'గత 30 రోజులు';

  @override
  String get period90 => 'గత 90 రోజులు';

  @override
  String get period180 => 'గత 6 నెలలు';

  @override
  String get reportLocal => 'ఈ ఫోన్ నుండి సారాంశం';

  @override
  String get reportServer => 'సర్వర్ నుండి నివేదిక పొందండి';

  @override
  String get reportComputedLocal =>
      'ఈ ఫోన్‌లోని రికార్డుల నుండి లెక్కించబడింది (ఆఫ్‌లైన్‌లో పనిచేస్తుంది)';

  @override
  String get reportComputedServer => 'సర్వర్ నుండి నివేదిక';

  @override
  String get countRecommended => 'సిఫార్సు చేసినవి';

  @override
  String get countPlanned => 'ప్లాన్ చేసినవి';

  @override
  String get countConfirmed => 'హాజరు నిర్ధారణ (ఆసుపత్రి రికార్డు)';

  @override
  String get countTotal => 'మొత్తం నమోదైన రెఫరల్స్';

  @override
  String get byService => 'సేవ వారీగా';

  @override
  String get excludedRecords => 'లెక్కించని రికార్డులు';

  @override
  String get followUpsDue => 'గడువు ఉన్న ఫాలో-అప్‌లు';

  @override
  String get followUpsDone => 'కాలంలో పూర్తైన ఫాలో-అప్‌లు';

  @override
  String get freshFRESH => 'డేటా తాజాది (24 గంటల్లో సింక్ అయింది)';

  @override
  String get freshRECENT => 'డేటా ఇటీవలిది (3 రోజుల్లో సింక్ అయింది)';

  @override
  String get freshSTALE_OFFLINE =>
      'డేటా పాతది కావచ్చు (3 రోజులకు పైగా సింక్ కాలేదు)';

  @override
  String get freshNOT_PROVIDED => 'ఈ ఫోన్ ఇంకా సింక్ కాలేదు';

  @override
  String get privacyNoticeReport =>
      'మొత్తం సంఖ్యలు మాత్రమే. ఇంటి లేదా రోగి వివరాలు లేవు. ఇవి నమోదైన రెఫరల్స్, ఎవరు వెళ్తారనే అంచనాలు కాదు. ఇంటి సందర్శనలు ఆసుపత్రి హాజరు కావు.';

  @override
  String get shareCsv => 'CSV షేర్ చేయండి';

  @override
  String get sharePdf => 'PDF షేర్ చేయండి';

  @override
  String get noFacilities => 'ఈ ఫోన్‌లో ఇంకా రెఫరల్ రికార్డులు లేవు.';

  @override
  String get reportOnlineOnly => 'PDF మరియు సర్వర్ నివేదికలకు ఇంటర్నెట్ అవసరం.';

  @override
  String generatedAt(String date) {
    return 'రూపొందించిన తేదీ $date';
  }

  @override
  String get syncTitle => 'సింక్ కేంద్రం';

  @override
  String get syncNow => 'ఇప్పుడు సింక్ చేయండి';

  @override
  String get syncing => 'సింక్ అవుతోంది…';

  @override
  String get sectionPending => 'పంపడానికి వేచి ఉన్నవి';

  @override
  String get sectionFailed => 'సర్వర్ తిరస్కరించినవి';

  @override
  String get sectionConflict => 'మీ నిర్ణయం అవసరం';

  @override
  String get sectionSynced => 'సర్వర్ నిర్ధారించినవి';

  @override
  String get retryOp => 'మళ్ళీ పంపండి';

  @override
  String get discardOp => 'మార్పును వదిలేయండి';

  @override
  String get discardConfirm =>
      'ఈ మార్పును వదిలేయాలా? ఈ ఫోన్‌లో మీరు సేవ్ చేసిన మార్పు రద్దవుతుంది. అదే సమయంలో చేసిన ఇతర మార్పులు క్యూలో ఉంటాయి.';

  @override
  String get resolveConflict => 'పరిష్కరించండి';

  @override
  String get keepServer => 'సర్వర్ వెర్షన్ ఉంచండి';

  @override
  String get keepMine => 'నా మార్పును ఉంచండి';

  @override
  String get conflictExplain =>
      'మీ మార్పు సర్వర్‌కు చేరకముందే మరొకరు ఈ రికార్డును మార్చారు. ఏదీ మార్చబడలేదు. ఏ వెర్షన్ ఉంచాలో ఎంచుకోండి.';

  @override
  String get serverHas => 'సర్వర్‌లో ఉంది';

  @override
  String get youChanged => 'మీరు మార్చింది';

  @override
  String get opNewVisit => 'కొత్త సందర్శన';

  @override
  String get opVisitOutcome => 'సందర్శన ఫలితం';

  @override
  String get opNewReferral => 'కొత్త రెఫరల్';

  @override
  String get opReferralUpdate => 'రెఫరల్ మార్పు';

  @override
  String get opHouseholdUpdate => 'ఇంటి వివరాల మార్పు';

  @override
  String get opNewHousehold => 'కొత్త ఇల్లు';

  @override
  String attemptsN(int n) {
    return '$n సార్లు ప్రయత్నించారు';
  }

  @override
  String get nothingPending => 'పంపడానికి ఏమీ వేచి లేదు.';

  @override
  String syncResultOk(int n) {
    return 'సింక్ పూర్తయింది: సర్వర్ $n మార్పులను నిర్ధారించింది.';
  }

  @override
  String get syncAuthFailed =>
      'సర్వర్ మీ యాక్సెస్ కీని అంగీకరించలేదు. సెట్టింగ్స్‌లో చూడండి. మీ డేటా ఈ ఫోన్‌లో భద్రంగా ఉంది.';

  @override
  String get syncNotConfigured =>
      'సర్వర్ చిరునామా ఇవ్వలేదు. సెట్టింగ్స్‌లో జోడించండి. మీ డేటా ఈ ఫోన్‌లో భద్రంగా ఉంది.';

  @override
  String get syncOffline =>
      'కనెక్షన్ లేదు. మీ మార్పులు ఈ ఫోన్‌లో సేవ్ అయ్యాయి, తర్వాత పంపబడతాయి.';

  @override
  String get syncServerError =>
      'సర్వర్‌లో సమస్య వచ్చింది. మీ మార్పులు ఈ ఫోన్‌లో సేవ్ అయ్యాయి, మళ్ళీ పంపబడతాయి.';

  @override
  String get syncNeedsAttention =>
      'కొన్ని మార్పులను సర్వర్ అంగీకరించలేదు. ఏదీ పోలేదు: అవి కింద ఉన్నాయి.';

  @override
  String get voiceLangTelugu => 'తెలుగు';

  @override
  String get voiceLangEnglish => 'ఇంగ్లీష్';

  @override
  String get voiceChecking => 'వాయిస్ సపోర్ట్ చూస్తోంది…';

  @override
  String voicePackMissing(String name) {
    return 'ఈ ఫోన్‌లో $name కోసం ఆఫ్‌లైన్ వాయిస్ ప్యాక్ లేదు, కాబట్టి ఇంటర్నెట్ లేకుండా వాయిస్ పనిచేయదు. ఫోన్ వాయిస్ సెట్టింగ్స్‌లో ఆ ప్యాక్‌ను డౌన్‌లోడ్ చేసుకోవచ్చు. ప్రస్తుతానికి మీ ప్రశ్నను టైప్ చేయండి.';
  }

  @override
  String voiceNoOfflineEngine(String name) {
    return 'ఈ ఫోన్ ఇంటర్నెట్ లేకుండా $name మాటలను గుర్తించలేదు. దయచేసి మీ ప్రశ్నను టైప్ చేయండి.';
  }

  @override
  String get voiceOnlineOption =>
      'కావాలంటే, సెట్టింగ్స్‌లో (ఆన్‌లైన్ వాయిస్) ఫోన్ ఆన్‌లైన్ వాయిస్ సేవను అనుమతించవచ్చు.';

  @override
  String get voicePrivacyOnDevice =>
      'మీ గొంతు ఈ ఫోన్‌లోనే అక్షరాలుగా మారుతుంది. ఏదీ పంపబడదు, ఈ యాప్ మీ గొంతును సేవ్ చేయదు.';

  @override
  String get voicePrivacyOnline =>
      'మీ ఫోన్ ఆన్‌లైన్ వాయిస్ సేవ మీ గొంతును అక్షరాలుగా మార్చింది, కాబట్టి ఆ ఆడియో ఆ సేవకు పంపబడింది. ఈ యాప్ మీ గొంతును సేవ్ చేయదు.';

  @override
  String get voiceTranscribing => 'మీ గొంతును అక్షరాలుగా మారుస్తోంది…';

  @override
  String get voicePrivacyAppModel =>
      'మీ గొంతును ఈ ఫోన్‌లోనే యాప్ సొంత తెలుగు మోడల్ అక్షరాలుగా మార్చింది. ఏదీ పంపబడదు, ఈ యాప్ మీ గొంతును సేవ్ చేయదు. గుర్తింపులో తప్పులు రావచ్చు: పదాలను చూడండి.';

  @override
  String get voiceGetTeluguPack =>
      'సెట్టింగ్స్‌లో తెలుగు వాయిస్ ప్యాక్‌ను ఒక్కసారి డౌన్‌లోడ్ చేసుకోవచ్చు; ఆ తర్వాత ఇంటర్నెట్ లేకుండానే తెలుగు వాయిస్ పనిచేస్తుంది.';

  @override
  String get teluguModelTitle => 'ఈ యాప్‌కు తెలుగు వాయిస్ (ఆఫ్‌లైన్)';

  @override
  String get mapChipAvailable => 'ఆఫ్‌లైన్ మ్యాప్ అందుబాటులో ఉంది';

  @override
  String get mapChipMissing => 'ఆఫ్‌లైన్ మ్యాప్ డౌన్‌లోడ్ కాలేదు';

  @override
  String get houseLocationTitle => 'ఇంటి స్థానం';

  @override
  String get houseLocationOpen => 'పెద్ద మ్యాప్ చూడటానికి తాకండి';

  @override
  String get houseLocationNone =>
      'ఈ ఇంటికి ఈ ఫోన్‌లో ఇంకా మ్యాప్ లేదా స్థానం లేదు.';

  @override
  String get mapDemoNote =>
      'డెమో గ్రామ మ్యాప్. ఇది కల్పితం, నిజమైన ప్రదేశం కాదు.';

  @override
  String get phonesTitle => 'ఫోన్ నంబర్లు';

  @override
  String get phone1Label => 'ఫోన్ 1 (తప్పనిసరి)';

  @override
  String get phone2Label => 'ఫోన్ 2 (ఐచ్ఛికం)';

  @override
  String get phoneNotAdded => 'చేర్చలేదు';

  @override
  String get phoneEdit => 'మార్చండి';

  @override
  String get phoneAdd => 'ఫోన్ నంబర్లు చేర్చండి';

  @override
  String get phoneErrRequired => 'ఫోన్ 1 అవసరం.';

  @override
  String get phoneErrInvalid =>
      '6, 7, 8 లేదా 9తో మొదలయ్యే 10 అంకెల మొబైల్ నంబర్ ఇవ్వండి.';

  @override
  String get phoneErrSame => 'ఫోన్ 2, ఫోన్ 1 ఒకటే.';

  @override
  String phoneCall(String number) {
    return '$numberకు కాల్ చేయండి';
  }

  @override
  String get phoneCannotCall => 'ఫోన్ యాప్ తెరవలేకపోయాం.';

  @override
  String get phoneLocalOnly =>
      'ఈ ఫోన్‌లో మాత్రమే సేవ్ అవుతుంది. సర్వర్‌కు పంపరు.';

  @override
  String get teluguModelHelp =>
      'ఒక్కసారి డౌన్‌లోడ్ చేయండి (సుమారు 44 మెగాబైట్లు, వైఫై వాడండి). ఆ తర్వాత ఇంటర్నెట్ లేకుండానే తెలుగు వాయిస్ పనిచేస్తుంది, మీ గొంతు ఫోన్ దాటి వెళ్ళదు. తప్పులు రావచ్చు, కాబట్టి పదాలను తప్పక చూడండి.';

  @override
  String get teluguModelDownload => 'తెలుగు వాయిస్ డౌన్‌లోడ్ చేయండి';

  @override
  String teluguModelProgress(String done, int total) {
    return 'డౌన్‌లోడ్ అవుతోంది… $total మెగాబైట్లలో $done';
  }

  @override
  String get teluguModelReady =>
      'సిద్ధంగా ఉంది. ఈ ఫోన్‌లో తెలుగు వాయిస్ ఆఫ్‌లైన్‌లో పనిచేస్తుంది.';

  @override
  String get teluguModelRemove =>
      'తొలగించండి (సుమారు 44 మెగాబైట్లు ఖాళీ అవుతుంది)';

  @override
  String get teluguModelNeedServer =>
      'ముందు పైన సర్వర్ చిరునామా, కీ పెట్టండి: ప్యాక్ మీ సర్వర్ నుండి డౌన్‌లోడ్ అవుతుంది.';

  @override
  String get teluguModelFailedNet =>
      'డౌన్‌లోడ్ కాలేదు. ఇంటర్నెట్, సర్వర్ చూసి మళ్ళీ ప్రయత్నించండి. డౌన్‌లోడ్ అయినది ఉంచబడుతుంది, కాబట్టి అక్కడినుండే కొనసాగుతుంది.';

  @override
  String get teluguModelFailedSum =>
      'డౌన్‌లోడ్ అయిన ఫైల్ పాడైంది, కాబట్టి తీసివేయబడింది. దయచేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get teluguModelNotOnServer =>
      'ఈ సర్వర్‌లో తెలుగు వాయిస్ ప్యాక్ లేదు. సర్వర్ నడిపేవారిని ఇన్‌స్టాల్ చేయమని అడగండి.';

  @override
  String get altVoiceButton => 'తెలుగు వాయిస్ పొందడానికి మరో మార్గం';

  @override
  String get altVoiceTitle => 'గూగుల్ కీబోర్డ్‌తో తెలుగు వాయిస్';

  @override
  String get altVoiceIntro =>
      'గూగుల్ కీబోర్డ్ (జీబోర్డ్) వాయిస్ టైపింగ్‌తో ప్రశ్న పెట్టెలో తెలుగులో మాట్లాడండి. ఈ దశలను ఒక్కసారి చేయండి.';

  @override
  String get altStep1Title => 'ఫోన్ సెట్టింగ్స్ తెరవండి';

  @override
  String get altStep1Body =>
      'మీ ఫోన్‌లోని సెట్టింగ్స్ యాప్‌ను (గేర్ గుర్తు) తెరవండి.';

  @override
  String get altStep2Title => 'కీబోర్డ్ సెట్టింగ్స్ కనుక్కోండి';

  @override
  String get altStep2Body =>
      'సిస్టమ్, తర్వాత భాషలు మరియు ఇన్‌పుట్‌కు వెళ్ళండి. కొన్ని ఫోన్‌లలో దీనిని జనరల్ మేనేజ్‌మెంట్ లేదా అదనపు సెట్టింగ్స్, తర్వాత భాష మరియు ఇన్‌పుట్ అంటారు.';

  @override
  String get altStep3Title => 'గూగుల్ కీబోర్డ్‌ను ఎంచుకోండి';

  @override
  String get altStep3Body =>
      'ఆన్-స్క్రీన్ కీబోర్డ్‌ను (లేదా కీబోర్డ్‌లు) నొక్కి గూగుల్ కీబోర్డ్ అయిన జీబోర్డ్‌ను తెరవండి. అది కనిపించకపోతే ప్లే స్టోర్ నుండి జీబోర్డ్‌ను ఇన్‌స్టాల్ చేసి మీ కీబోర్డ్‌గా పెట్టుకోండి.';

  @override
  String get altStep4Title => 'తెలుగును జోడించండి';

  @override
  String get altStep4Body =>
      'జీబోర్డ్‌లో భాషలు, తర్వాత కీబోర్డ్ జోడించండి నొక్కి, తెలుగును వెతికి ఎంచుకుని పూర్తయింది నొక్కండి.';

  @override
  String get altStep5Title => 'వాయిస్ టైపింగ్ ఆన్ చేయండి';

  @override
  String get altStep5Body =>
      'జీబోర్డ్ సెట్టింగ్స్‌లో వాయిస్ టైపింగ్ తెరిచి, వాయిస్ టైపింగ్ వాడండి ఆన్ చేసి, దానిలోని భాషలలో తెలుగు ఉందో చూడండి.';

  @override
  String get altStep6Title => 'ఈ యాప్‌లో మాట్లాడండి';

  @override
  String get altStep6Body =>
      'ఈ యాప్‌కు తిరిగి వచ్చి అడగండి తెరవండి. కీబోర్డ్ తెరుచుకునేలా ప్రశ్న పెట్టెను నొక్కండి. అవసరమైతే గ్లోబ్ కీతో తెలుగుకు మారి, కీబోర్డ్‌లోని మైక్ కీని నొక్కి మీ ప్రశ్న చెప్పండి.';

  @override
  String get altStep7Title => 'పదాలను చూడండి';

  @override
  String get altStep7Body =>
      'తెలుగు పదాలను చూసి, తప్పులు సరిచేసి, తర్వాత చూడండి నొక్కండి.';

  @override
  String get altVoiceNote =>
      'గమనిక: జీబోర్డ్ వాయిస్ టైపింగ్ గూగుల్ సేవ, ఈ యాప్‌ది కాదు. దీనికి సాధారణంగా ఇంటర్నెట్ కావాలి, ఆడియో గూగుల్‌కు వెళుతుంది. జీబోర్డ్ ఆఫ్‌లైన్ భాషల జాబితాలో తెలుగు ఉంటేనే ఇంటర్నెట్ లేకుండా పనిచేస్తుంది; మేము చూసిన రెండు ఫోన్‌లలో తెలుగు ఆఫ్‌లైన్‌లో లేదు. ఇంటర్నెట్ లేకుండా తెలుగు వాయిస్ కోసం సెట్టింగ్స్‌లోని తెలుగు వాయిస్ డౌన్‌లోడ్ వాడండి.';

  @override
  String get altOpenKeyboardSettings => 'కీబోర్డ్ సెట్టింగ్స్ తెరవండి';

  @override
  String get altOpenFailed =>
      'తెరవడం కాలేదు. మీ ఫోన్ సెట్టింగ్స్‌ను మీరే తెరిచి ఈ దశలను అనుసరించండి.';

  @override
  String get explAsking =>
      'కృత్రిమ మేధ సర్వర్‌ను అడుగుతున్నాం… (గరిష్ఠంగా 10 సెకన్లు)';

  @override
  String get explTitle => 'వివరణ';

  @override
  String get explFromDevice =>
      'ఈ ఫోన్‌లోనే, కింద ఉన్న ఆమోదిత పాఠ్యంలోని వాక్యాలతో వివరించింది.';

  @override
  String get explFromServerText =>
      'మీ సర్వర్ నుండి: మీ ప్రశ్నకు సమాధానమిచ్చే ఆమోదిత పాఠ్యం, యథాతథంగా.';

  @override
  String get explFromServer =>
      'మీ సర్వర్‌లోని కృత్రిమ మేధ, కింద ఉన్న ఆమోదిత పాఠ్యం ఆధారంగా వివరించింది.';

  @override
  String get explNoteTimeout =>
      'సర్వర్ 10 సెకన్లలో స్పందించలేదు, కాబట్టి ఫోనే వివరించింది.';

  @override
  String get explNoteUnreachable =>
      'సర్వర్‌ను చేరుకోలేకపోయాం, కాబట్టి ఫోనే వివరించింది.';

  @override
  String get explNoteUnsafe =>
      'సర్వర్ రాసిన పాఠ్యంలో మందు లేదా మోతాదు ఉన్నందున దాన్ని చూపలేదు; ఫోనే వివరించింది.';

  @override
  String get explNoteRejected =>
      'సర్వర్ రాసిన పాఠ్యం ఆమోదిత పాఠ్యానికి (లేదా భాషకు) తగినట్లుగా లేనందున దాన్ని చూపలేదు; ఫోనే వివరించింది.';

  @override
  String get explDisclaimerDevice =>
      'ఆమోదిత పాఠ్యం నుండి పదానికి పదం తీసుకున్నది. వైద్యపరంగా ధృవీకరించలేదు: మీ పర్యవేక్షకునితో సరిచూడండి.';

  @override
  String get explDisclaimerServer =>
      'కృత్రిమ మేధ ఆమోదిత పాఠ్యం నుండి రాసింది. వైద్యపరంగా ధృవీకరించలేదు. రోగనిర్ధారణ కాదు. మీ ఆమోదిత ప్రోటోకాల్స్‌ను అనుసరించండి.';

  @override
  String get sevHighTitle => 'అధికం: ప్రమాద సంకేతం కావచ్చు';

  @override
  String get sevHighAction =>
      'వెంటనే చర్య తీసుకోండి: మీ పర్యవేక్షకునికి ఫోన్ చేయండి లేదా వారిని దగ్గరి ఆరోగ్య కేంద్రానికి తీసుకెళ్ళండి.';

  @override
  String get sevMediumTitle => 'మధ్యస్థం: మరిన్ని వివరాలు కావాలి';

  @override
  String get sevMediumAction =>
      'కింద వర్తించేదాన్ని నొక్కండి, లేదా మరింత టైప్ చేసి, మళ్ళీ చూడండి.';

  @override
  String get sevLowTitle =>
      'తక్కువ: మీరు రాసినదాంట్లో ప్రమాద సంకేతం కనిపించలేదు';

  @override
  String get sevLowAction =>
      'సమాచారం కోసం. కింద ఉన్న వివరణ మరియు ఆమోదిత పాఠ్యాన్ని చదవండి.';

  @override
  String get voiceResultNote =>
      'ఈ పాఠం మీ గొంతు నుండి వచ్చింది, తప్పులు ఉండవచ్చు. మీరు చెప్పినది కాకపోతే పదాలను సరిచేసి మళ్ళీ \'చూడండి\' నొక్కండి.';

  @override
  String get onlineSpeechTitle => 'ఆన్‌లైన్ వాయిస్ (ఐచ్ఛికం)';

  @override
  String get onlineSpeechHelp =>
      'డిఫాల్ట్‌గా ఆఫ్. ఆఫ్‌లో ఉంటే, ఈ ఫోన్ ఆఫ్‌లైన్‌లో గుర్తించగల భాషలకు మాత్రమే వాయిస్ పనిచేస్తుంది, మీ గొంతు ఫోన్ దాటి వెళ్ళదు. ఆన్‌లో ఉంటే, ఒక భాషకు ఆఫ్‌లైన్ ప్యాక్ లేనప్పుడు మరియు మీరు ఆన్‌లైన్‌లో ఉన్నప్పుడు మాత్రమే, మీ ఫోన్ వాయిస్ సేవ ఆ ఆడియోను అందుకుంటుంది.';

  @override
  String get speechCapsLabel => 'ఈ ఫోన్‌లో ఆఫ్‌లైన్ వాయిస్';

  @override
  String speechCapsLine(String en, String te) {
    return 'ఇంగ్లీష్: $en · తెలుగు: $te';
  }

  @override
  String get speechYes => 'ఇన్‌స్టాల్ అయింది';

  @override
  String get speechNo => 'ఇన్‌స్టాల్ కాలేదు';

  @override
  String get speechUnknown => 'ఈ ఫోన్‌లో చూడలేము';

  @override
  String get voiceSpeak => 'మాట్లాడండి';

  @override
  String get voiceStop => 'ఆపండి';

  @override
  String get voiceListening => 'వింటోంది… ఇప్పుడు మాట్లాడండి';

  @override
  String get voiceLangLabel => 'ఏ భాషలో';

  @override
  String get voiceCheckText =>
      'కింద ఉన్న పదాలను చూడండి, తప్పులు సరిచేసి, తర్వాత \'చూడండి\' నొక్కండి.';

  @override
  String get voicePrivacy =>
      'మీ ఫోన్‌లోని స్పీచ్ సేవ మీ గొంతును అక్షరాలుగా మారుస్తుంది, ఇంటర్నెట్ వాడవచ్చు. ఈ యాప్ మీ గొంతును సేవ్ చేయదు.';

  @override
  String get voicePermissionDenied =>
      'మైక్రోఫోన్ అనుమతి లేదు. ఫోన్ సెట్టింగ్స్‌లో ఈ యాప్‌కు మైక్ అనుమతి ఇవ్వండి, లేదా ప్రశ్నను టైప్ చేయండి.';

  @override
  String get voiceUnavailable =>
      'ఈ ఫోన్‌లో వాయిస్ ఇన్‌పుట్ అందుబాటులో లేదు. దయచేసి ప్రశ్నను టైప్ చేయండి.';

  @override
  String get voiceLanguageMissing =>
      'ఎంచుకున్న భాషకు ఈ ఫోన్‌లో స్పీచ్ సపోర్ట్ లేదు. ఫోన్ గూగుల్ స్పీచ్ సెట్టింగ్స్‌లో ఇన్‌స్టాల్ చేయండి, లేదా ప్రశ్నను టైప్ చేయండి.';

  @override
  String get voiceNoSpeech =>
      'ఏమీ వినిపించలేదు. \'మాట్లాడండి\' నొక్కి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get voiceOfflineLanguage =>
      'మీరు ఆఫ్‌లైన్‌లో ఉన్నారు, ఈ భాషకు ఫోన్‌లో ఆఫ్‌లైన్ స్పీచ్ ప్యాక్ లేదు. మాట్లాడటానికి ఇంటర్నెట్‌కు కనెక్ట్ అవ్వండి, లేదా ప్రశ్నను టైప్ చేయండి - టైపింగ్ మరియు సేఫ్టీ చెక్‌లు ఆఫ్‌లైన్‌లో పనిచేస్తాయి.';

  @override
  String get voiceNetwork =>
      'ఈ ఫోన్‌లో వాయిస్‌కు ఇప్పుడు ఇంటర్నెట్ అవసరం. దయచేసి ప్రశ్నను టైప్ చేయండి.';

  @override
  String get voiceOther =>
      'వాయిస్ ఇన్‌పుట్ ఆగిపోయింది. మళ్ళీ ప్రయత్నించండి లేదా టైప్ చేయండి.';

  @override
  String get noServerForAnswer =>
      'ఈ ఫోన్‌లో ఆమోదిత ప్రోటోకాల్ పాఠం లేదు, సెట్టింగ్స్‌లో సర్వర్ చిరునామా కూడా ఇవ్వలేదు, అందువల్ల సమాధానం ఇవ్వలేము. మీ ప్రశ్నలో ప్రమాద సంకేతం కనబడలేదు, కానీ అది వైద్య సమాధానం కాదు.';

  @override
  String get homeMore => 'మరిన్ని';

  @override
  String get syncNeverSentWarning =>
      'సర్వర్ నిర్ధారించిన తర్వాత మాత్రమే మార్పు \'సింక్ అయినట్లు\'.';

  @override
  String get settingsTitle => 'సెట్టింగ్స్';

  @override
  String get languageLabel => 'భాష';

  @override
  String get langEnglish => 'English';

  @override
  String get langTelugu => 'తెలుగు';

  @override
  String get serverSection => 'సర్వర్';

  @override
  String get serverUrl => 'సర్వర్ చిరునామా';

  @override
  String get serverUrlHint => 'https://your-server.example';

  @override
  String get apiKey => 'యాక్సెస్ కీ';

  @override
  String get apiKeyHint => 'ఈ ఫోన్‌లో భద్రంగా నిల్వ అవుతుంది';

  @override
  String get apiKeySaved => 'యాక్సెస్ కీ సేవ్ అయింది';

  @override
  String get testConnection => 'కనెక్షన్ పరీక్షించండి';

  @override
  String get connectionOk => 'సర్వర్ అందుబాటులో ఉంది';

  @override
  String get connectionFailed => 'సర్వర్‌ను చేరలేకపోయాము';

  @override
  String get insecureWarning =>
      'ఈ చిరునామా సాధారణ http వాడుతోంది. డేటా మరియు కీ నెట్‌వర్క్‌లో చదవబడవచ్చు. నిజమైన సర్వర్‌కు https వాడండి.';

  @override
  String get invalidUrl =>
      'http:// లేదా https:// తో మొదలయ్యే పూర్తి చిరునామా ఇవ్వండి';

  @override
  String get demoSection => 'డెమో డేటా';

  @override
  String get loadDemo => 'కృత్రిమ డెమో డేటాను లోడ్ చేయండి';

  @override
  String demoLoadedN(int n) {
    return '$n ఇళ్ల డెమో డేటా లోడ్ అయింది';
  }

  @override
  String get useDemoDate => 'డెమో తేదీ వాడండి (13 అక్టోబర్ 2026)';

  @override
  String get demoExplain =>
      'యాప్‌ను ప్రయత్నించడానికి కృత్రిమ రికార్డులు. ఇవి నిజమైన వ్యక్తులు కాదు.';

  @override
  String get escalationContact => 'సూపర్‌వైజర్ ఫోన్ నంబర్';

  @override
  String get escalationContactHelp =>
      'ప్రమాద సంకేత హెచ్చరికలో చూపబడుతుంది, త్వరగా కాల్ చేయడానికి.';

  @override
  String get protocolSection => 'ప్రోటోకాల్ లైబ్రరీ';

  @override
  String protocolCountN(int n) {
    return 'ఈ ఫోన్‌లో $n ఆమోదిత భాగాలు ఉన్నాయి';
  }

  @override
  String get protocolNone =>
      'ఇంకా ఆమోదిత ప్రోటోకాల్ పాఠం ఇన్‌స్టాల్ కాలేదు. అధికారిక పత్రాలు సర్వర్‌లో ఆమోదం పొందే వరకు ప్రశ్నలకు ప్రోటోకాల్ ఆధారంగా సమాధానం ఇవ్వలేము.';

  @override
  String get refreshProtocols => 'ఆమోదిత ప్రోటోకాల్స్ డౌన్‌లోడ్ చేయండి';

  @override
  String protocolRefreshed(int n) {
    return '$n భాగాలు నిల్వ అయ్యాయి';
  }

  @override
  String get privacyTitle => 'గోప్యత మరియు స్థానిక డేటా';

  @override
  String get privacyBody =>
      'ఇంటి, సందర్శన మరియు రెఫరల్ రికార్డులు ఈ ఫోన్‌లోని డేటాబేస్‌లో నిల్వ అవుతాయి. మీరు టైప్ చేసిన ప్రశ్నలు సేవ్ కావు. నోటిఫికేషన్లలో ఇంటి వివరాలు చూపబడవు. మీరు సింక్ చేసినప్పుడు మాత్రమే డేటా సర్వర్‌కు వెళ్తుంది. యాక్సెస్ కీ ఫోన్ సురక్షిత నిల్వలో ఉంటుంది.';

  @override
  String get clearData => 'ఈ ఫోన్‌లోని మొత్తం డేటాను తొలగించండి';

  @override
  String get clearConfirm =>
      'ఈ ఫోన్ నుండి అన్ని ఇళ్లు, సందర్శనలు, రెఫరల్స్ మరియు పంపని మార్పులను తొలగించాలా? పంపని మార్పులు పోతాయి.';

  @override
  String get clearDone => 'స్థానిక డేటా అంతా తొలగించబడింది';

  @override
  String get aboutTitle => 'గురించి మరియు డయాగ్నోస్టిక్స్';

  @override
  String get appVersion => 'యాప్ వెర్షన్';

  @override
  String get dbSchema => 'స్థానిక డేటాబేస్ వెర్షన్';

  @override
  String get diagnosticsNote =>
      'డయాగ్నోస్టిక్స్‌లో సంఖ్యలు మరియు వెర్షన్లు మాత్రమే ఉంటాయి, ఆరోగ్య సమాచారం ఎప్పుడూ ఉండదు.';

  @override
  String get validationNote =>
      'వైద్యపరంగా ధృవీకరించబడలేదు. ముసాయిదా భద్రతా నియమాలు, కృత్రిమ డేటా.';

  @override
  String get moreTitle => 'మరిన్ని';

  @override
  String get errNetwork =>
      'కనెక్షన్ లేదు. ఆన్‌లైన్‌లో ఉన్నప్పుడు మళ్ళీ ప్రయత్నించండి.';

  @override
  String get errTimeout => 'సర్వర్ సమాధానం ఇవ్వడానికి చాలా సమయం తీసుకుంది.';

  @override
  String get errUnauthorized =>
      'సర్వర్ మీ యాక్సెస్ కీని అంగీకరించలేదు. సెట్టింగ్స్ చూడండి.';

  @override
  String get errServer =>
      'సర్వర్‌లో సమస్య వచ్చింది. తర్వాత మళ్ళీ ప్రయత్నించండి.';

  @override
  String get errInvalidResponse => 'సర్వర్ ఊహించని సమాధానం పంపింది.';

  @override
  String get errNotConfigured =>
      'ముందు సెట్టింగ్స్‌లో సర్వర్ చిరునామా ఇవ్వండి.';

  @override
  String get errForbidden => 'ఇది చేయడానికి మీకు అనుమతి లేదు.';

  @override
  String get errUnknown => 'ఏదో తప్పు జరిగింది. మళ్ళీ ప్రయత్నించండి.';

  @override
  String get semBottomNav => 'ప్రధాన నావిగేషన్';

  @override
  String get semStatusChip =>
      'కనెక్షన్ మరియు సింక్ స్థితి. సింక్ కేంద్రం తెరవడానికి నొక్కండి.';

  @override
  String get h5MapTitle => 'ఇళ్ల మ్యాప్';

  @override
  String h5MapChip(int n) {
    return 'ఆఫ్‌లైన్ మ్యాప్: $n ఇళ్లు. తెరవడానికి నొక్కండి.';
  }

  @override
  String get h5AllVillages => 'అన్ని గ్రామాలు';

  @override
  String h5HousesIn(int n) {
    return '$n ఇళ్లు';
  }

  @override
  String get h5LegendUrgent => 'అత్యవసరం';

  @override
  String get h5LegendDue => 'చేయాల్సినవి';

  @override
  String get h5LegendSoon => 'ఈ వారం';

  @override
  String get h5LegendNone => 'ఏమీ లేదు';

  @override
  String get h5MapMadeUp => 'ఇది కల్పిత మ్యాప్. ఇళ్ల స్థానాలు నిజమైనవి కావు.';

  @override
  String h5MapAsOf(String date) {
    return '$date నాటి సందర్శన జాబితా';
  }

  @override
  String h5HouseNo(String no) {
    return 'ఇంటి నెం. $no';
  }

  @override
  String h5PeopleCount(int n) {
    return '$n మంది';
  }

  @override
  String get h5OpenHouse => 'తెరవండి';

  @override
  String get h5DueNow => 'చేయాల్సినవి';

  @override
  String get h5NothingDue => 'ఈ ఇంటికి ఏమీ గడువు లేదు.';

  @override
  String get h5PickTitle => 'ఇంటి స్థానం';

  @override
  String get h5PickHelp => 'ఇల్లు ఉన్న చోట మ్యాప్‌ను నొక్కండి.';

  @override
  String get h5PickUse => 'ఈ స్థానాన్ని వాడండి';

  @override
  String get h5PickCardTitle => 'ఇంటి స్థానం (ఐచ్ఛికం)';

  @override
  String get h5PickOpen => 'మ్యాప్‌లో ఎంచుకోండి';

  @override
  String get h5PickChange => 'మ్యాప్‌లో మార్చండి';

  @override
  String get h5PickNone => 'ఇంకా స్థానం ఎంచుకోలేదు.';

  @override
  String h5PickedAt(String lat, String lng) {
    return 'ఎంచుకున్నది: $lat, $lng';
  }

  @override
  String get h5PickClear => 'స్థానాన్ని తొలగించండి';

  @override
  String get h5PickNoMap => 'ఈ ఫోన్‌లో మ్యాప్ లేదు.';

  @override
  String get h5MemberPregnant => 'గర్భిణి';

  @override
  String h5PriorityN(int n) {
    return 'ప్రాధాన్యత $n';
  }

  @override
  String get h5StatusOverdue => 'గడువు దాటింది';

  @override
  String get h5StatusToday => 'ఈ రోజు';

  @override
  String get h5StatusWeek => 'ఈ వారం';

  @override
  String get h5MembersTitle => 'ఈ ఇంట్లోని వారు';

  @override
  String get h5HouseTitle => 'ఇల్లు';

  @override
  String h5VillageLine(String village, String asha) {
    return '$village, ఆశా $asha';
  }

  @override
  String get h5VisitTitle => 'సందర్శన జాబితా';

  @override
  String h5VisitAsOf(String date, int n) {
    return '$date నాటికి. $n అంశాలు.';
  }

  @override
  String get h5AllAshas => 'అందరు ఆశాలు';

  @override
  String get h5Priority1 => 'ప్రాధాన్యత 1: అధిక ప్రమాదం, ఇప్పుడే';

  @override
  String get h5Priority2 => 'ప్రాధాన్యత 2: ఇప్పుడే చేయాలి';

  @override
  String get h5Priority3 => 'ప్రాధాన్యత 3: ఈ వారం లోపు';

  @override
  String get h5VisitEmpty => 'ఏమీ గడువు లేదు.';

  @override
  String get h5MoreVisit => 'సందర్శన జాబితా (బ్లాక్ డేటా)';

  @override
  String get h5MoreMap => 'ఇళ్ల మ్యాప్';

  @override
  String h5DueOn(String date) {
    return 'గడువు $date';
  }
}
