# Runbook — VPN-átállás (a teljes platform hálózati láthatatlanság mögé)

A három élő gép (PTE-Dokploy, PTE-Forgejo, PTE-Forgejo-Runner-1) és a három új
gép (PTE-Headscale, PTE-Backup, PTE-Shared — a csapat belső tool-gépe) átállítása
az ADR-0004–0009 szerinti célállapotra. **A fázisok sorrendje kötött**: a publikus utak végig
élnek, amíg az új utak nem bizonyítottak — a visszavonhatatlan lépés (tűzfal +
DNS-törlés) a legvégén van.

Cél-verifikáció minden fázis végén van; ha elakadsz, a fázis elején lévő
állapot még teljesen működőképes.

## 0. fázis — Előkészületek (gép-munka nélkül)

1. **deSEC fiók + zóna**: regisztrálj a <https://desec.io>-n, hozz létre egy
   zónát `pte-dev.dedyn.io` néven, és generálj hozzá API tokent. A token
   secret — jelszókezelőbe. (A zónanevet a CNAME-receptek — lent és a
   [projekt RUNBOOK](../../services/projekt/RUNBOOK.md) 4. lépésében — fixen
   használják; más név választásánál mindet át kell írni.)
2. **Rackhost DNS** (kézzel, nincs API):
   - CNAME: `_acme-challenge.pte-dev.hu` → `_acme-challenge.pte-dev.dedyn.io`
   - Ellenőrzés: `dig +short CNAME _acme-challenge.pte-dev.hu @1.1.1.1`
3. A meglévő publikus rekordokhoz (git, dokploy) **még nem nyúlunk**.

## 1. fázis — Privát L2 hálózat

1. Rackforest → Hálózatok → új privát hálózat: pl. `pte-platform`,
   `10.10.0.0/24`.
2. Csatold rá a három meglévő gépet (PTE-Dokploy, PTE-Forgejo,
   PTE-Forgejo-Runner-1). Ha a csatoláshoz újraindítás kell, gépenként,
   egyesével.
3. Gépenként ellenőrizd, hogy a második interfész kapott-e címet (`ip a`);
   ha nem, netplan config a második interfészre (DHCP vagy statikus a
   Rackforest által adott tartományból), majd `netplan apply`.
4. **Verifikáció**: a három gép pingeli egymást a `10.10.0.x` címeken.

Írd fel a privát IP-ket — a továbbiakban `<*_L2_IP>` néven hivatkozunk rájuk.

## 2. fázis — Beléptető réteg felhúzása

A [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 1–4.
lépése: VPS, publikus DNS (`vpn.`, `id.`), Pocket ID `/setup`, headscale OIDC.

**Verifikáció**: a saját gépeddel fent vagy a tailneten Pocket ID loginnal
(`tailscale status` mutatja a node-ot). A platform még érintetlen.

## 3. fázis — Új gépek: PTE-Backup és PTE-Shared

1. [services/backup/RUNBOOK.md](../../services/backup/RUNBOOK.md) 1. lépés
   (VPS + privát L2 csatolás).
2. [services/projekt/RUNBOOK.md](../../services/projekt/RUNBOOK.md) 1–2.
   lépés a PTE-Shared géppel — ez a csapat belső tool-gépe, technikailag a
   projekt-sablonnal jön létre (VPS + privát L2 + Dokploy remote server
   felvétel **már a privát L2 IP-vel**). A projekt-runbook 4. lépését (a
   három `_acme-challenge.{,staging.,preview.}shared.pte-dev.hu` CNAME a
   Rackhostnál) is most vidd fel, hogy a 6. fázisra propagálódjon.

## 4. fázis — Minden gép a tailnetre

A [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 5.
lépése szerint, gépenként egy friss pre-auth kulccsal (SSH-n átvíve, ADR-0002):
Dokploy, Forgejo, Runner, Shared, Backup, és maga a Headscale VPS is.

**Verifikáció**: `headscale nodes list` — mind a 6 node látszik. Írd fel a
tailnet IP-ket (`<*_TAILNET_IP>`).

## 5. fázis — Tailnet-resolver, split DNS, ACL

A [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 6–7.
lépése: dnsmasq placeholderek kitöltése, split DNS élesítés, a repo
`acl-policy.hujson`-jának kitöltése (tailnet IP-k + emailek) és élesítése.

**Verifikáció tailnet-kliensről**:

```bash
dig +short dokploy.pte-dev.hu   # → dokploy tailnet IP
dig +short git.pte-dev.hu       # → forgejo tailnet IP
dig +short barmi.shared.pte-dev.hu  # → PTE-Shared (zóna-wildcard)
```

**Ezután azonnal zárd a két új, nem-Dokploy gép tűzfalát** — a tailnet-elérés
és az ACL innentől bizonyított, publikus portnak nincs több dolga:

- **PTE-Headscale**: [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 8. lépés (a 80/443/3478 nyitva marad — az a beléptető réteg dolga).
- **PTE-Backup**: [services/backup/RUNBOOK.md](../../services/backup/RUNBOOK.md) 4. lépés — a rest-server 8000-e a compose miatt eddig publikusan nyitva
  volt (üres htpasswd-vel, auth nélkül használhatatlanul, de nyitva).

A publikus elérés a platform-gépeken még él — a webes forgalom innentől már
mehet a tailneten, de a cert még a régi (per-domain LE), ezért előbb:

## 6. fázis — Wildcard cert (deSEC DNS-01) a Traefikekben

A Dokploy által kezelt Traefik minden érintett gépen fut; a configja a gépen
az `/etc/dokploy/traefik/traefik.yml`. Az **infra-gépek** (Dokploy, Forgejo)
az alábbi `*.pte-dev.hu` alap-wildcardot kapják (ez fedi a `git.` és
`dokploy.` neveket); a **zóna-certes gépek** (most: PTE-Shared, később minden projekt-VPS) ugyanezzel a
mechanikával a saját zóna-certjüket, a SAN-lista a
[services/projekt/RUNBOOK.md](../../services/projekt/RUNBOOK.md) 5. lépése
szerint. Gépenként:

1. A cert-config receptje (resolver + wildcard-kérő file-provider router +
   acme.json-takarítás) a
   [services/projekt/RUNBOOK.md](../../services/projekt/RUNBOOK.md) 5.
   lépésében lakik — az a gazda-dokumentum. Infra-gépen a `domains` blokk:
   `main: pte-dev.hu`, `sans: ["*.pte-dev.hu"]`.
2. A Traefik MINDEN gépen sima konténer (`dokploy-traefik` — a Dokploy gépen
   is: a Dokploy v0.29 már nem Swarm service-ként futtatja; 2026-07-06-án
   élesben ellenőrizve). A `DESEC_TOKEN` bejuttatása ezért mindenhol azonos:
   konténer újra-létrehozás env-vel (recreate előtt `docker inspect` a
   bindek/portok/hálózat visszaépítéséhez — a dokploy-network tagság fix
   IP-vel jön, `docker network connect --ip <eredeti IP>`). Utána ellenőrizd:
   `docker inspect dokploy-traefik | grep DESEC_TOKEN`. **Figyelem:** az
   env-nek a konténer újra-létrehozását is túl kell élnie (ha a Dokploy
   újrahúzza a Traefiket és az env elveszik, a cert-megújítás ~60 nap múlva
   csendben elhal) — Traefik-újrahúzás után az inspect-ellenőrzést ismételd meg.
3. A logból ellenőrizd a DNS-01 challenge sikerét
   (`docker logs dokploy-traefik 2>&1 | grep -i acme`).
4. Dokploy UI-ban a meglévő domainek (dokploy.pte-dev.hu a Web Server-en,
   git.pte-dev.hu a Forgejo service-en) certificate beállítása **none**-ra —
   per-domain certet többé nem kérünk (CT-log leak, ADR-0007).

**Verifikáció tailnet-kliensről**: `curl -v https://git.pte-dev.hu 2>&1 | grep
subject` → `CN=*.pte-dev.hu` (vagy `pte-dev.hu`), böngészőben nincs cert-hiba.

## 7. fázis — Belső útvonalak a privát L2-re

1. **Dokploy → remote serverek**: Dokploy UI → Servers → a Forgejo és a
   Runner szerverbejegyzés IP-jét írd át a `<*_L2_IP>`-re (a Shared már a 3. fázisban L2 IP-vel került fel). Ellenőrzés: a szerver-oldalon zöld,
   egy próba-redeploy lefut.
2. **`/etc/hosts` minden platform-gépen** (Dokploy, Runner, Shared — a git-et
   L2-n érjék el, ne a tailneten és pláne ne publikusan):
   ```
   <FORGEJO_L2_IP>  git.pte-dev.hu
   ```
3. **Runner: konténer-szintű feloldás.** A dind/runner/job konténerek NEM
   öröklik a host `/etc/hosts`-át (a Docker embedded DNS a resolv.conf-ot
   használja) — az élő runner még a régi compose-zal fut, amiben nincs erre
   megoldás. A repo compose-a `extra_hosts` + `--add-host` úton oldja, a
   `FORGEJO_L2_IP` env-ből:
   1. Dokploy UI → runner compose service → **Environment**:
      `FORGEJO_L2_IP=<FORGEJO_L2_IP>` hozzáadása.
   2. A repo [docker-compose.yml](../../services/forgejo-runner/docker-compose.yml)
      újra-beillesztése (ADR-0003: kézi re-paste a forrás-igazságból).
   3. A runner-config csak első indításkor íródik — töröld, hogy az
      `--add-host` bekerüljön (runner RUNBOOK, Hibaelhárítás):
      `docker exec <runner cid> rm /data/runner-config.yml`, majd **Redeploy**.
4. **A Forgejo compose-t az átálláshoz NEM kell újra beilleszteni**: a repo
   VPN-kori változásai ott nem szükségesek élő gépen (a registry-env explicit
   default, a `postgres:18` → `18-alpine` váltás pedig élő volume-on
   collation-kockázat, glibc → musl — az alpine-ra váltás a következő
   tervezett Postgres-karbantartás dolga, dump/restore úton,
   [services/forgejo/RUNBOOK.md](../../services/forgejo/RUNBOOK.md), Frissítés).
5. **Verifikáció**: a runner gépről `curl -s https://git.pte-dev.hu/ -o
/dev/null -w '%{http_code}\n'` → 200; a konténeren **belül**
   `docker exec <dind cid> getent hosts git.pte-dev.hu` → a `<FORGEJO_L2_IP>`;
   és egy push utáni CI job zöld. (A CI zöldje önmagában itt még NEM
   bizonyíték — a publikus DNS él, a job azon át is elérheti a gitet; a
   konténeren belüli `getent` a döntő.)

## 8. fázis — Forgejo login Pocket ID-ról

1. Pocket ID → OIDC Clients → új kliens `forgejo`, callback:
   `https://git.pte-dev.hu/user/oauth2/pocket-id/callback`
2. Forgejo (admin belépéssel): Site Administration → Identity & Access →
   Authentication sources → Add: típus **OAuth2**, provider **OpenID
   Connect**, név `pocket-id`, client ID/secret a Pocket ID-ból,
   auto-discovery URL: `https://id.pte-dev.hu/.well-known/openid-configuration`
3. **A `forgejo-admin` lokális fiók marad** — ez a fallback, ha a beléptető
   réteg fekszik (ADR-0006).
4. **Verifikáció**: kijelentkezés → „Sign in with pocket-id” → passkey →
   belépve. Meglévő userek a fiók-beállításokban linkelhetik a Pocket ID-t.

## 9. fázis — Tűzfal zárás (az irreverzibilis rész eleje)

Előfeltétel-checklista — CSAK akkor kezdd, ha mind igaz:

- [ ] minden szolgáltatás elérhető és működik tailneten át (web, git SSH, CI),
- [ ] a Dokploy a remote servereket L2-n éri el,
- [ ] a saját géped a tailneten van, és admin-csoportban vagy az ACL-ben,
- [ ] a Rackforest VNC konzolba be tudsz lépni (break-glass próba!).

Gépenként (sorrend: Shared → Runner → Forgejo → Dokploy; a Headscale és a
Backup gép az 5. fázis végén már zárult), SSH-val a gépen.

A három régi gépen az `ufw` még nincs telepítve (drift — a cloud-initek már
tartalmazzák, az élő gépek nem, lásd
[utolagos-konfiguracio.md](utolagos-konfiguracio.md)):

```bash
apt-get update && apt-get install -y ufw
```

Majd a közös recept (ufw + a DOCKER-USER csapda — a Docker-publikált
portokat, pl. Traefik 80/443 és Forgejo 2222, az ufw egyedül nem védi):
**[tuzfal-zaras.md](tuzfal-zaras.md)** — az a gazda-dokumentum.

A Dokploy gépen zárd a 3000-et is (ha még nyitva volt). **Figyelem, drift:**
az élő gépen még a régi provision script fut, amiben nincs `close3000` fázis
— előbb frissítsd a scriptet a repóból, vagy futtasd közvetlenül a záró
parancsot ([utolagos-konfiguracio.md](utolagos-konfiguracio.md), drift-napló):

```bash
/usr/local/sbin/dokploy-provision.sh close3000   # ha a script már friss
# vagy közvetlenül:
docker service update --publish-rm published=3000,target=3000,protocol=tcp,mode=host dokploy
ss -tln | grep 3000   # üres kell legyen
```

**Verifikáció gépenként, MIELŐTT a következőre lépsz**:

- kívülről (nem tailnet, pl. mobilnet): `nmap -Pn <PUBLIKUS_IP>` → minden port
  zárva/filtered; a git SSH publikusan NEM megy;
- tailnetről: SSH, web, git SSH (2222) megy; a CI zöld; Dokploy redeploy megy.

## 10. fázis — Publikus DNS takarítás (Rackhost)

Törlendő: a `git.pte-dev.hu` és `dokploy.pte-dev.hu` A rekordok.
Marad: `vpn.`, `id.` A rekordok + a `_acme-challenge` CNAME (+ MX/ImprovMX,
azok a levelezéshez kellenek, nem érintettek).

**Verifikáció**: `dig +short git.pte-dev.hu @1.1.1.1` → üres;
tailnet-kliensről továbbra is resolvál (split DNS).

## 11. fázis — Mentés élesítés

1. [services/backup/RUNBOOK.md](../../services/backup/RUNBOOK.md) 3. lépés
   (repo-user a beléptető rétegnek — a tűzfal az 5. fázisban már zárult).
2. [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 9.
   lépés (restic init + timer + próba-mentés).
3. **Visszaállítási próba kötelező** (backup RUNBOOK, Verifikáció szakasz).

## 12. fázis — Csapat-onboarding

Emberenként az [onboarding-doksi](../onboarding.md) szerint (admin-lépések
gazdája: [services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md),
Onboarding szakasz). Átállás-specifikus jó hír: a git remote-ok a
userek gépein változatlanok (`git.pte-dev.hu` — a split DNS miatt ugyanaz a
név megy tovább).

## Záró állapot-ellenőrzés (a teljes átállás definition of done)

- [ ] Kívülről kizárólag a `vpn.pte-dev.hu:80/443`, `id.pte-dev.hu:80/443` és
      a STUN `:3478/udp` válaszol — semmi más, egyik gépen sem.
- [ ] Tailnet dev-user: Forgejo web + git SSH + app-ok mennek; a Dokploy
      panel és a gépek SSH-ja NEM megy (ACL).
- [ ] Tailnet admin: minden megy.
- [ ] CI: push → runner job zöld (runner → git a privát L2-n).
- [ ] Új app deploy Dokploy-ból: domain + cert nulla kézi lépéssel
      (services/projekt/RUNBOOK.md, „Új app” szakasz).
- [ ] Napi mentés fut, visszaállítási próba megvolt.
- [ ] Break-glass próba: Rackforest VNC-vel be tudsz lépni egy gépre, és a
      szomszéd gép L2-n SSH-zható.
- [ ] CONTEXT.md és az ADR-ek tükrözik a valóságot.
