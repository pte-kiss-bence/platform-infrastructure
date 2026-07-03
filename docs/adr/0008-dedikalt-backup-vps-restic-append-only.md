# Dedikált backup VPS restic rest-serverrel, append-only módban

A beléptető réteg mutable state-jének (headscale DB, Pocket ID DB) — és később minden platform-mentésnek — a célja egy dedikált `PTE-Backup` VPS, cloud-inittel provisionálva, NEM Dokploy alatt: azt a rendszert, amiből helyreállítunk, nem kezelheti az a rendszer, amit helyreállít (ADR-0005 elve). A mentések restic-kel mennek egy **rest-serverbe, append-only módban**: a küldő gép csak írni tud, törölni nem — egy kompromittált szerver a saját mentéseit nem tudja megsemmisíteni. A restic kliens-oldalon titkosít, így a mentés a cél-gépen is olvashatatlan.

## Considered Options

- **MinIO** — a community kiadást 2025-ben kibelezték (web UI és admin funkciók a fizetős AIStor-ba kerültek), a nyílt verzió jövője kérdéses. Elvetve.
- **Garage** (open source S3) — jó S3, de backuphoz az S3 réteg felesleges absztrakció; akkor kerül elő, ha egy toolnak tényleg S3 API kell.
- **Dump a Dokploy gépre** — működne, de a backup-cél platform-gépen lakna, és a backup nem lenne független attól, amit ment. Elvetve a dedikált gép javára.

## Consequences

- Hálózat: a backup gép a privát L2-n (a platform-gépek ott mentenek) ÉS a tailneten van, admin-only ACL-lel; a `PTE-Headscale` VPS-nek nincs L2 lába, ő a tailneten át tolja a napi dumpot. Publikus port nincs.
- Helyreállítás beléptetőréteg-halálkor: friss VPS + cloud-init + dump visszatöltés, cél ~1 óra. Backup nélkül mind a 30–50 user újra onboardolna.
- Ugyanaz a Rackforest telephely: gép-halál ellen véd, telephely-halál ellen nem — off-site restic copy későbbi bővítés.
- A platform-szintű mentések bekötése (Forgejo adat, app adatbázisok) külön, későbbi feladat; a cél-infrastruktúra ezzel készen áll rá.
