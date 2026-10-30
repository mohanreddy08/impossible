import '../l10n/app_localizations.dart';

/// Maps a domain validation code (see FieldWorkService) to a short, plain-language message.
String validationText(AppLocalizations l, String field, String code) =>
    switch ((field, code)) {
      ('actualDate', 'required') => l.errActualRequired,
      ('actualDate', 'future') => l.errFuture,
      ('village', 'invalid') => l.errVillageInvalid,
      ('members', 'invalid') => l.errMembersInvalid,
      ('categories', 'empty') => l.errCategoriesEmpty,
      ('worker', 'unknown') => l.errWorkerUnknown,
      ('visitTime', 'future') => l.errTimeFuture,
      ('visitTime', 'invalid') => l.errTimeInvalid,
      ('nextDate', 'required') => l.errNextRequired,
      ('nextDate', 'notAfterVisit') => l.errNextNotAfter,
      ('nextDate', 'inconsistent') => l.errInconsistent,
      ('status', 'alreadyFinal') => l.errAlreadyFinal,
      ('referral', 'needsCompletedVisit') => l.referralNeedsDone,
      ('plannedDate', 'beforeCreated') => l.errPlannedBefore,
      ('date', 'inPast') => l.errInPast,
      _ => l.errGeneric,
    };
