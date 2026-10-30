"""Framework-free identity/scoping helpers (no FastAPI import) so services can be tested and ported independently."""
import hashlib
from dataclasses import dataclass
from typing import Optional

from app.core.errors import Forbidden


@dataclass(frozen=True)
class Principal:
    role: str                       # worker | admin | hospital | supervisor
    worker_id: Optional[str]
    name: str                       # "user:<username>", "phone:<key_id>", "<role>:<worker_id|*>" (static keys) or "dev-anonymous"

    @property
    def is_privileged(self) -> bool:
        return self.role in ("admin", "hospital", "supervisor")

    @property
    def is_user(self) -> bool:
        """Signed in to the website (as opposed to a phone or a static API key)."""
        return self.name.startswith("user:")

    @property
    def scope_key(self) -> str:
        """Data scope used to partition stored reports: workers see only their own, privileged roles share 'all'."""
        return "worker:%s" % self.worker_id if self.role == "worker" else "all"


def scoped_worker(p: Principal, requested: Optional[str]) -> Optional[str]:
    """Workers are confined to their own worker_id; privileged roles may pass any/None."""
    if p.role == "worker":
        if requested and requested != p.worker_id:
            raise Forbidden("workers may only access their own records")
        return p.worker_id
    return requested


def hash_installation(installation_id: str, salt: str) -> str:
    return hashlib.sha256((salt + "|" + installation_id).encode()).hexdigest()
