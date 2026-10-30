from typing import Any, Optional


class DomainError(Exception):
    status_code = 400
    code = "BAD_REQUEST"

    def __init__(self, message: str, code: Optional[str] = None, details: Any = None, status_code: Optional[int] = None):
        super().__init__(message)
        self.message = message
        self.code = code or self.code
        self.details = details
        if status_code:
            self.status_code = status_code


class NotFound(DomainError):
    status_code, code = 404, "NOT_FOUND"


class Conflict(DomainError):
    status_code, code = 409, "CONFLICT"


class Forbidden(DomainError):
    status_code, code = 403, "FORBIDDEN"


class Unauthorized(DomainError):
    status_code, code = 401, "UNAUTHORIZED"


class TooManyRequests(DomainError):
    status_code, code = 429, "RATE_LIMITED"
