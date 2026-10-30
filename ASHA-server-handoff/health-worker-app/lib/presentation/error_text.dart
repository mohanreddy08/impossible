import '../data/api/api_exceptions.dart';
import '../l10n/app_localizations.dart';

/// Plain-language text for every failure the API layer can produce (never raw exceptions, never server internals).
String apiErrorText(AppLocalizations l, Object e) => switch (e) {
  NetworkUnavailable() => l.errNetwork,
  RequestTimeout() => l.errTimeout,
  Unauthorized() => l.errUnauthorized,
  Forbidden() => l.errForbidden,
  NotConfigured() => l.errNotConfigured,
  InvalidResponse() => l.errInvalidResponse,
  ServerError() => l.errServer,
  _ => l.errUnknown,
};
