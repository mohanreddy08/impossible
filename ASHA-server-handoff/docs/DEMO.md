# 3-minute judge demo

Setting: the **server runs on a laptop** at home/venue Wi-Fi, reachable through a Cloudflare quick tunnel; the **phone is on mobile data**
(Wi-Fi off), so the two are on different networks. All data is synthetic.

## Before the judges arrive (10 minutes, once)

1. Laptop: `scripts/dev_setup.sh` (first time only), then `scripts/start_public.sh`. Wait for the box with the address, e.g.
   `https://brave-river-quiet-sun.trycloudflare.com`. Keep the laptop plugged in, lid open (the script keeps it awake).
2. Laptop browser: open that address, sign in as `admin` (password from `run/demo_credentials.txt`).
   *Phones & users* → *Generate a phone API key* → ASHA **Demo worker 001 (WRK-SYN-001)** (the phone app's demo mode works as this worker). Copy the key.
3. Phone: **turn Wi-Fi off** (mobile data on). App → *Settings*: *Server address* = the tunnel address (or scan the QR code on the
   *Settings* page with the camera and copy it), *API key* = the key. Make sure demo mode is on. Tap **Sync** once: it should report success.
4. Laptop: a second browser tab signed in as `anm.supervisor` on **Overview**, a third on **Referrals & escalations**.

## The 3 minutes

| Time | Do | Say / show |
|---|---|---|
| 0:00 | Show the phone's status bar (mobile data, no Wi-Fi) and the laptop on Wi-Fi. | "Different networks. The phone reaches the laptop over HTTPS through a Cloudflare tunnel: no port forwarding, no shared Wi-Fi." |
| 0:20 | Website **Overview** (as the ANM). | Due today / overdue / upcoming from the same VIS visit-list rules the phone uses, open referrals, today's priority-1 list, phones not synced in 48 h. "Synthetic data" banner on every page. |
| 0:45 | Phone: *Households* → **Add family** (village, 4 members, categories) → Save. Show it works offline first if you like (airplane mode, save, then mobile data back on). Tap **Sync**. | "Saved on the phone at once; queued in the outbox; sent when there is signal. Each change has its own id, so a resend after a dropped connection is answered 'duplicate', never stored twice." |
| 1:05 | Website **Households** → search `HH-`, or filter *Village* = the village you chose: the new family is there, tagged *New family registered on a phone*. **Phones & users** shows *Last sync* = just now. | "Seconds after sync. Per-phone key, stored hashed, revocable here." |
| 1:30 | Website **Ask the protocol**: type `8 mahine ki pregnant hai, subah se khoon aa raha hai` → Ask. | Red **REFER IMMEDIATELY** card citing ESC-2.1. "Danger signs are never 'answered', they escalate. Same engine as the phone, checked on 240 questions." Then `scan me ladka hai ya ladki` → **refusal** card. |
| 2:00 | **Referrals & escalations**: the escalation is at the top (time, ESC-2.1, rule id, OPEN). Choose *REFERRED_108* → **Acknowledge**. | "The question text is never stored: only outcome, section ids, time and who handled it." |
| 2:20 | **Houses map** → village → tap a red ▲ house → people and due items → *Open household page* → **Show number**. | "Made-up map, positions not real (banner). Status is colour plus shape plus word. Phone numbers are masked; every reveal is audit-logged (Phones & users → recent admin actions)." |
| 2:45 | Toggle **తెలుగు** in the header. | "English and Telugu. Clinician-assisting only, not a diagnosis." |

## If something goes wrong

- Phone says it cannot reach the server: open the address in the phone's browser; it must show `{"status":"ok"}` at `/health`. If the laptop
  was restarted, the quick-tunnel address changed: re-run `scripts/start_public.sh` and update the phone's *Server address*.
- Sync says *unauthorized*: the key was revoked or typed wrong; generate a new one.
- Website *Settings* → **Check now** tests the public address from the server itself (through the tunnel and back).
- No internet at the venue: run the website on the laptop only (`scripts/dev_run.sh`) and show the phone app offline; the server is optional for the phone.
