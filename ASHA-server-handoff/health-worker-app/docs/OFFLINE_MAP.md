# Offline village map (demo)

One ASHA worker covers one village. The map is a **separate pack** read from the phone's own storage, never a big asset in the APK.

- **Interface:** `OfflineMapSource` (`lib/maps/offline_map_source.dart`): `isAvailable()` and `load()`. Screens only use this, so the real MBTiles pack (5-6 MB at most) can replace the demo reader without touching a screen.
- **Demo pack:** `assets/demo/demo_village.json`, about 4.5 KB: made-up street grid, a main road, PHC / school / temple, and one point per demo household. It is NOT a real place and the screens say so. Make it again with `python3 tool/make_demo_map.py` (also puts `lat`/`lng` on every household in `demo_seed.json`).
- **"Download":** loading the synthetic demo data (or opening the app after an update on a phone that already has it) copies the pack to `<app storage>/maps/village.json`. Until then the Households chip says "Offline map not downloaded" (grey); after, "Offline map available" (green).
- **Drawing:** plain Flutter `CustomPainter` + `InteractiveViewer` (`lib/presentation/widgets/village_map_view.dart`). No network, no map library. APK growth for the whole feature: 68 KB.
- **House position and phone numbers:** two LOCAL-ONLY tables (database migration 6): `household_geo` and `household_contacts`. They are separate from `households` on purpose, because a server pull replaces household rows and would wipe extra columns. Phone numbers are personal data: they are never synced and are removed by "Delete all data on this phone". Nothing changed on the backend.
- **Phone rules:** Phone 1 required, Phone 2 optional; 10 digits starting 6-9 (spaces, dashes, +91, 91 or a leading 0 are accepted and removed). The call button opens the phone's dialer with a `tel:` link (`url_launcher`, already in the app).
