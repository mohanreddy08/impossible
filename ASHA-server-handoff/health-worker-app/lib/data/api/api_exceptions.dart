/// Every failure the API layer can produce. UI code maps these to plain-language messages; none carries request bodies.
sealed class ApiException implements Exception {
  const ApiException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() =>
      '$runtimeType(${code ?? ''}${code == null ? '' : ': '}$message)';
}

/// No connection / DNS / socket failure. The request may or may not have reached the server: treat writes as UNKNOWN.
class NetworkUnavailable extends ApiException {
  const NetworkUnavailable([super.message = 'network unavailable']);
}

class RequestTimeout extends ApiException {
  const RequestTimeout([super.message = 'request timed out']);
}

/// 401: key missing, wrong, or revoked. The user must re-enter credentials in Settings.
class Unauthorized extends ApiException {
  const Unauthorized([super.message = 'credentials rejected'])
    : super(code: 'UNAUTHORIZED');
}

class Forbidden extends ApiException {
  const Forbidden(super.message) : super(code: 'FORBIDDEN');
}

class NotFoundError extends ApiException {
  const NotFoundError(super.message) : super(code: 'NOT_FOUND');
}

class ConflictError extends ApiException {
  const ConflictError(super.message, {super.code});
}

class ValidationFailed extends ApiException {
  const ValidationFailed(super.message, {super.code, this.details});
  final Object? details;
}

class ServerError extends ApiException {
  const ServerError(this.status, super.message, {super.code});
  final int status;
}

/// The server answered, but not with the documented shape.
class InvalidResponse extends ApiException {
  const InvalidResponse([super.message = 'unexpected response from server']);
}

class NotConfigured extends ApiException {
  const NotConfigured()
    : super('server address not set', code: 'NOT_CONFIGURED');
}
