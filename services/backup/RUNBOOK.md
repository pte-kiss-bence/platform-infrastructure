# Runbook — PTE-Backup (restic rest-server, append-only)

A platformtól független mentéscél (ADR-0008). Első lakó: a beléptető réteg
napi dumpja (services/headscale/RUNBOOK.md 9. lépés); később ide kötendők a
platform-szintű mentések (Forgejo adat, app adatbázisok) is.

## 1. VPS létrehozás

1. Rackforest: új VPS (`PTE-Backup`), Ubuntu 24.04 LTS — a diszk méretezése a
   lényeg (kezdésnek 40–80 GB), CPU/RAM minimális lehet. **SSH kulcs kötelező.**
2. User-data: `services/backup/cloud-init.yaml` változtatás nélkül.
3. **Csatold a privát L2 hálózatra** (a platform-gépek ezen mentenek), és
   **NE** vedd fel Dokploy remote serverként (ADR-0008).
4. Ellenőrzés: `cat /root/backup-provision-status` → `SUCCESS: ...`,
   `docker compose -f /opt/backup/docker-compose.yml ps` → rest-server Up.

## 2. Tailnet-join

Pre-auth kulccsal (services/headscale/RUNBOOK.md 5. lépés), majd a tailnet
IP-t írd be a tailnet-resolver `backup.pte-dev.hu` sorába és az ACL
`hosts.backup` bejegyzésébe.

## 3. Repo-userek (mentést küldő gépenként egy)

Minden küldő gép saját htpasswd-usert és saját repót kap (`--private-repos`):

```bash
# jelszó generálás + user felvétel (példa: a beléptető réteg usere)
PW=$(openssl rand -base64 24)
htpasswd -B -b /opt/backup/data/.htpasswd headscale "$PW"
echo "$PW"   # ezt írd a küldő gép /root/restic-*-repo URL-jébe, majd felejtsd el
```

A repo URL a küldő gépen: `rest:http://<user>:<pw>@backup.pte-dev.hu:8000/<user>`
(tailneten át) vagy `rest:http://<user>:<pw>@<PRIVÁT_L2_IP>:8000/<user>`
(privát L2-n mentő platform-gépeknek).

## 4. Tűzfal zárás

Előfeltétel: a gép fent van a tailneten, és a saját géped is.

A közös recept (ufw + a `DOCKER-USER` csapda — a Docker-publikált portokat,
itt a rest-server 8000-ét, az ufw egyedül nem védi):
**[docs/runbooks/tuzfal-zaras.md](../../docs/runbooks/tuzfal-zaras.md)**.
Gépspecifikus delta nincs: a privát L2-t engedő sor adja a 8000-et a mentő
platform-gépeknek és a break-glass SSH-t.

Ellenőrzés: publikus IP-ről a 8000 és a 22 zárva (`nmap` kívülről); tailnetről
és a privát L2-ről a 8000 megy.

## Append-only karbantartás

Az append-only mód miatt a küldő gépek nem tudnak régi snapshotot törölni —
ez szándékos (kompromittált gép nem semmisítheti meg a saját mentéseit). A
retention ezért ITT, a backup gépen fut, adminként (a rest-servert
megkerülve, közvetlenül a repón):

```bash
restic -r /opt/backup/data/<repo> --password-file <a repo jelszava> \
  forget --keep-daily 14 --keep-weekly 8 --prune
```

Ezt eleinte kézzel, negyedévente elég; ha a diszk telik, systemd timerbe.

## Verifikáció (visszaállítási próba — az első éles mentés után kötelező)

```bash
restic -r /opt/backup/data/headscale --password-file <jelszó> snapshots
restic -r /opt/backup/data/headscale --password-file <jelszó> \
  restore latest --target /tmp/restore-proba && ls -R /tmp/restore-proba | head
```

Mentés jelszó nélkül = nincs mentés: minden repo restic-jelszava legyen meg a
gépeken KÍVÜL is (jelszókezelőben).

## Frissítés (image pin-bump)

A pin gazdája a repo `cloud-init.yaml`-je (`restic/rest-server`); élő gépen
kézi átvezetés + drift-napló
([utólagos-konfiguráció](../../docs/runbooks/utolagos-konfiguracio.md)).

1. Changelog-check (rest-server ritkán, de tudott breaking flaget hozni).
2. Pin átírása a repóban → `/opt/backup/docker-compose.yml` a gépen, majd
   `cd /opt/backup && docker compose pull && docker compose up -d`.
3. Verifikáció egy küldő gépről: `restic ... snapshots` megy, egy
   próba-mentés lefut. A repo-adat a `./data` bind mountban van, az
   image-csere nem érinti.
4. Rollback: pin vissza + `docker compose up -d`.

## Ismert korlát

Ugyanaz a Rackforest telephely, mint a többi gép: gép-halál ellen véd,
telephely-halál ellen nem. Off-site bővítés (restic copy külső célra):
későbbi feladat (ADR-0008, [docs/backlog.md](../../docs/backlog.md)).
