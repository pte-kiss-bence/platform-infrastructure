# Runbook — Forgejo provisioning (Dokploy remote server)

A [cloud-init.yaml](cloud-init.yaml) és a [docker-compose.yml](docker-compose.yml) körüli kézi lépések. A gépet a meglévő Dokploy (<https://dokploy.pte-dev.hu>) kezeli remote serverként — a Docker/Traefik telepítést és a deployt is a Dokploy végzi, nem a cloud-init (ADR-0003).

Kapcsolódó döntések: [ADR-0002](../../docs/adr/0002-no-secrets-in-cloud-init-user-data.md) (secret-kezelés), [ADR-0003](../../docs/adr/0003-forgejo-dokploy-remote-serverkent.md) (remote server + raw compose). A runner bekötése: [../forgejo-runner/RUNBOOK.md](../forgejo-runner/RUNBOOK.md).

## 1. Dokploy SSH kulcs

Dokploy UI → **Settings → SSH Keys → Create SSH Key** (generáltasd, ne importálj). A public kulcsot másold ki — a VPS-létrehozásnál kell.

## 2. VPS létrehozás

Rackforest panelben: **Ubuntu 24.04 LTS**, minimum **2 vCPU / 4 GiB RAM / 40 GB SSD** (git repók + Postgres nőnek — inkább több disk). User-data mezőbe a `services/forgejo/cloud-init.yaml` tartalma változtatás nélkül (nincs placeholder).

**SSH kulcsmezőbe KÉT kulcs**: a sajátod ÉS a Dokploy public kulcsa (1. lépés). A YAML password authot tilt — kulcs nélkül kizárod magad; Dokploy-kulcs nélkül a remote setup nem tud belépni.

## 3. DNS rekord (amint az IP megvan)

Rackhost DNS: `git.pte-dev.hu` **A** rekord → VPS publikus IP, TTL 300s. (Cert-kéréshez már propagálódnia kell.)

## 4. Remote server felvétele Dokploy-ban

Dokploy UI → **Servers → Add Server**: név `PTE-Forgejo`, IP, port 22, user `root`, SSH kulcs = az 1. lépésben generált. Utána a szerver oldalán **Setup Server** — ez telepíti a Dockert és a Traefiket. Várd meg, míg minden ellenőrzés zöld.

## 5. Forgejo compose deploy

Dokploy UI → projekt → **Create Service → Compose**, szerver: `PTE-Forgejo`, provider: **Raw**, compose típus: **Docker Compose** (alapértelmezés — NE Stack: Swarm módban a `depends_on` feltételek, pl. a db `service_healthy`, némán elvesznek). Illeszd be a [docker-compose.yml](docker-compose.yml) tartalmát változtatás nélkül. **Environment** fülre:

```
POSTGRES_PASSWORD=<openssl rand -base64 24 kimenete>
MAILJET_API_KEY=<Mailjet API key — ugyanaz, mint a Dokploy SMTP-nél>
MAILJET_API_SECRET=<Mailjet API secret>
```

**Deploy**, majd a Logs fülön várd meg, míg a `forgejo` és `db` konténer fut.

## 6. Domain hozzárendelés

A compose service **Domains** fülén: host `git.pte-dev.hu`, service `forgejo`, port `3000`, HTTPS + Let's Encrypt (cert email: `dokploy@pte-dev.hu`). Pár perc múlva: `curl -sI https://git.pte-dev.hu | head -1` → `HTTP/2 200`.

## 7. Bootstrap (admin + runner secret)

SSH be a Forgejo VPS-re root-ként, majd:

```bash
/usr/local/sbin/forgejo-bootstrap.sh
cat /root/forgejo-bootstrap-status        # SUCCESS kell legyen
cat /root/forgejo-admin-credentials       # admin belépés
cat /root/forgejo-runner-secret           # RUNNER_SECRET + RUNNER_UUID a runnerhez
```

A script idempotens: újrafuttatás nem hoz létre második admint, a runner-regisztráció ugyanazzal a secrettel frissít. Belépés: <https://git.pte-dev.hu>, user `forgejo-admin` — első belépéskor jelszócserét kér.

Státuszok: `CONTAINER_WAIT` → `ADMIN_BOOTSTRAP` → `RUNNER_REGISTER` → `SUCCESS`; hibánál `FAILED: <ok>`.

## 8. Bejövő email

ImprovMX-ben vedd fel a `git@pte-dev.hu` aliast (forward a valódi postafiókba). Kimenőt a compose mailer-env intézi (Mailjet) — teszt: Forgejo UI → user Settings → Account → teszt-emaillel, vagy jelszó-visszaállító email.

## 9. Runner bekötése

Folytasd itt: [../forgejo-runner/RUNBOOK.md](../forgejo-runner/RUNBOOK.md) — a 7. lépés `RUNNER_SECRET`/`RUNNER_UUID` értékei kellenek hozzá.

## 10. Verifikáció

```bash
curl -sI https://git.pte-dev.hu | head -1                  # HTTP/2 200
ssh -p 2222 git@git.pte-dev.hu                             # "Hi there" jellegű Forgejo-válasz
```

UI-ban: admin → **Site Administration → Actions → Runners** — a `pte-runner-1` a runner-deploy után Idle állapotú.

## Frissítés

A forrás-igazság a repóbeli compose: tag átírás itt → beillesztés Dokploy-ba → **Redeploy** (ADR-0003).

**Forgejo patch/minor** (major-pin miatt automatikus): Dokploy **Redeploy** — friss image pull, a migráció indulásnál magától lefut.

**Forgejo major** (pl. 15 → 16):

1. **Majort átugrani tilos** — csak egyesével (15→16→17). Release notes breaking changes átnézése: <https://forgejo.org/releases/>.
2. **Backup előtte** — a migráció egyirányú, downgrade nincs:
   ```bash
   mkdir -p /root/backup
   DCID=$(docker ps -q --filter "label=com.docker.compose.service=db")
   FCID=$(docker ps -q --filter "label=com.docker.compose.service=forgejo")
   docker exec "$DCID" pg_dump -U forgejo forgejo > /root/backup/forgejo-$(date +%F).sql
   docker run --rm --volumes-from "$FCID" -v /root/backup:/backup alpine tar czf /backup/forgejo-data-$(date +%F).tgz /data
   ```
3. Compose-ban tag átírás, beillesztés, Redeploy; a Forgejo konténer logjában a migráció végigfutása után UI-ellenőrzés.

**Postgres patch** (18.x): Redeploy elég. **Postgres major** (18 → 19): a 18+ image layout (szülőkönyvtár-mount, verziózott PGDATA) miatt in-place `pg_upgrade` lehetséges — a docker-library postgres README aktuális útmutatója szerint, előtte ugyanúgy `pg_dump` backup. Forgejo-t a Postgres-verzió nem érdekli (követelmény: >=14).

## Hibaelhárítás

- **`FAILED: nem fut forgejo konténer`** — a bootstrap a Dokploy deploy ELŐTT futott. Deployold az 5. lépést, futtasd újra a scriptet.
- **`admin user create hibával állt le`** — nézd a kimenetet; ha a user már létezik, de nincs credentials fájl: hozd létre kézzel a fájlt a saját jelszavaddal, vagy `docker exec -u git <cid> forgejo admin user change-password ...`.
- **Cert nem jön létre** — DNS másik IP-re mutat, vagy a `dokploy-network` hiányzik: a compose-ban a forgejo service-nek rajta kell lennie (raw beillesztésnél ne hagyd le a `networks` blokkot).
- **Compose módosítás** — a forrás-igazság a repóbeli fájl; módosítás után újra beillesztés Dokploy-ba + deploy (ADR-0003, tudatos ár).
