"""Load the SYNTHETIC demo data and create the first accounts.

    python scripts/seed.py                    # first run: block + phone demo set + accounts (passwords printed ONCE and saved to run/)
    python scripts/seed.py --reset            # wipe every table first ("reset demo data")
    python scripts/seed.py --phone-key WRK-SYN-001   # also make a phone API key for that worker (printed once)

Passwords: ADMIN_PASSWORD / DEMO_PASSWORD from the environment, else long random ones. They are printed once and written to
run/demo_credentials.txt (git-ignored, readable only by you). Run `alembic upgrade head` before this (the Docker entrypoint does both)."""
import argparse
import datetime as dt
import os
import secrets
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import func, select  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.core.principal import Principal  # noqa: E402
from app.db.models import Asha, Household, User  # noqa: E402
from app.db.session import get_engine, session_factory  # noqa: E402
from app.services.accounts import service as accounts  # noqa: E402
from app.services.block import seed  # noqa: E402

SYSTEM = Principal("admin", None, "system:seed")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reset", action="store_true", help="delete ALL rows first (users, keys, audit, synced data)")
    ap.add_argument("--no-phone-demo", action="store_true", help="skip the phone app's demo sync set (HH-SYN-*)")
    ap.add_argument("--phone-key", metavar="WORKER_ID", action="append", default=[], help="create a phone API key for this worker")
    ap.add_argument("--if-empty", action="store_true", help="do nothing when households already exist (for container start-up)")
    ap.add_argument("--credentials-file", default=os.path.join(os.path.dirname(get_settings().resolved_public_url_file), "demo_credentials.txt"))
    a = ap.parse_args(argv)
    s = get_settings()
    db = session_factory(get_engine())()
    if a.if_empty and (db.scalar(select(func.count()).select_from(Household)) or 0) > 0:
        print("seed: households already present, nothing to do (--if-empty)")
        return 0
    if a.reset:
        seed.wipe(db)
        print("seed: all tables emptied")
    day = dt.date.fromisoformat(s.demo_today) if s.demo_today else dt.date.today()
    if not os.path.isdir(s.resolved_h5_data):
        print("seed: hackathon pack not found at %s (set H5_DATA)" % s.resolved_h5_data, file=sys.stderr)
        return 2
    print("seed: block", seed.load_block(db, s.resolved_h5_data, day))
    if not a.no_phone_demo:
        r = seed.load_phone_demo(db, s.resolved_dataset_dir)
        rep = r.pop("import_report")
        print("seed: phone demo set", r, "rejected rows:", len(rep.get("rejected", [])))
    lines = []
    if not db.scalar(select(User).where(User.role == "admin")):
        admin_pw = os.environ.get("ADMIN_PASSWORD") or secrets.token_urlsafe(12)
        demo_pw = os.environ.get("DEMO_PASSWORD") or secrets.token_urlsafe(12)
        accounts.create_user(db, SYSTEM, username="admin", display_name="Block admin", role="admin", password=admin_pw)
        accounts.create_user(db, SYSTEM, username="anm.supervisor", display_name="ANM supervisor (demo)", role="supervisor", password=demo_pw)
        accounts.create_user(db, SYSTEM, username="mo.chandrapuri", display_name="Medical Officer (demo)", role="supervisor", password=demo_pw)
        lines += ["admin            %s   (role admin)" % admin_pw, "anm.supervisor   %s   (role supervisor)" % demo_pw,
                  "mo.chandrapuri   %s   (role supervisor)" % demo_pw]
        for asha in db.scalars(select(Asha).where(Asha.source == "block").order_by(Asha.name)):
            uname = "asha." + asha.name.split()[0].lower()
            accounts.create_user(db, SYSTEM, username=uname, display_name=asha.name, role="asha", password=demo_pw, worker_id=asha.worker_id)
            lines.append("%-16s %s   (role asha, %s)" % (uname, demo_pw, asha.worker_id))
        db.commit()
    for wid in a.phone_key:
        row, key = accounts.create_phone_key(db, SYSTEM, worker_id=wid, label="seeded phone " + wid)
        db.commit()
        lines.append("phone key for %s: %s" % (wid, key))
    if lines:
        print("\n=== shown once: store these somewhere safe ===")
        print("\n".join(lines))
        os.makedirs(os.path.dirname(a.credentials_file), exist_ok=True)
        fd = os.open(a.credentials_file, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write("# %s (SYNTHETIC demo server)\n%s\n" % (dt.datetime.now().isoformat(timespec="seconds"), "\n".join(lines)))
        print("(also appended to %s)" % a.credentials_file)
    db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
