from fastapi import APIRouter

from app.api.v1 import admin, ask, auth, dashboard, health_qa, households, protocols, referrals, reports, speech_models, sync, visits
from app.schemas.common import ErrorResponse

_ERR = {401: dict(model=ErrorResponse, description="Missing or invalid X-API-Key (auth_mode=api_key)"),
        403: dict(model=ErrorResponse, description="Role or ownership forbids this action"),
        404: dict(model=ErrorResponse, description="Not found (also returned for records owned by another worker)"),
        409: dict(model=ErrorResponse, description="Version/state conflict or duplicate"),
        422: dict(model=ErrorResponse, description="Validation failed (VALIDATION_ERROR or a domain rule code)"),
        500: dict(model=ErrorResponse, description="Unexpected error (generic message, no internals)")}
api_router = APIRouter(prefix="/api/v1", responses=_ERR)
for m in (health_qa, protocols, households, visits, referrals, reports, sync, speech_models, auth, ask, dashboard, admin):
    api_router.include_router(m.router)
