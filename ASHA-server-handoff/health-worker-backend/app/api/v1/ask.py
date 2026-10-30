from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.dashboard import AskIn, AskOut
from app.services.ask import service

router = APIRouter(tags=["ask (h5 protocol engine)"])


@router.post("/ask", response_model=AskOut,
             summary="Ask the protocol book: the h5 engine, identical to the phone. Danger signs escalate (REFER IMMEDIATELY), out-of-scope is refused. "
                     "Clinician-assisting only, not a diagnosis. The question text is never stored or logged.")
def ask(body: AskIn, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    return service.ask(db, p, s, body.question, "web" if p.is_user else "api", body.household_id)
