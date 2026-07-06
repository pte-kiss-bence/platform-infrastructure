# Runbook — PTE-Headscale (beléptető réteg)

A beléptető réteg (Headscale + Pocket ID + tailnet-resolver) provisionálása és
üzemeltetése. Kapcsolódó ADR-ek: 0004 (VPN), 0005 (dedikált VPS), 0006 (Pocket
ID), 0007 (DNS/cert), 0008 (mentés). A teljes platform átállásának sorrendje:
[docs/runbooks/vpn-atallas.md](../../docs/runbooks/vpn-atallas.md).

## 1. VPS létrehozás

1. Rackforest: új VPS (`PTE-Headscale`), Ubuntu 24.04 LTS, a legkisebb csomag
   elég. **SSH kulcs megadása kötelező** (a cloud-init nem tesz be kulcsot).
2. User-data: a `cloud-init.yaml` tartalma. **NE** csatold a privát L2
   hálózatra (ADR-0005: a beléptető rétegnek nincs dolga a platform belső
   forgalmával), és **NE** vedd fel Dokploy remote serverként.
3. Boot után ellenőrzés SSH-n:
   ```bash
   cat /root/headscale-provision-status   # SUCCESS: ... várható
   tail -50 /var/log/headscale-provision.log
   docker compose -f /opt/headscale/docker-compose.yml ps   # caddy, headscale, pocket-id: Up
   ```

## 2. Publikus DNS rekordok (Rackhost)

A Rackhost DNS zónaszerkesztőjében (kézzel — nincs API):

| Rekord           | Típus | Érték                |
| ---------------- | ----- | -------------------- |
| `vpn.pte-dev.hu` | A     | a VPS publikus IP-je |
| `id.pte-dev.hu`  | A     | a VPS publikus IP-je |

A Caddy magától újrapróbálja a Let's Encrypt certet, amint a nevek
resolválnak; ellenőrzés: `https://vpn.pte-dev.hu` (headscale válasz) és
`https://id.pte-dev.hu` (Pocket ID login).

## 3. Pocket ID initial admin

1. Nyisd meg: `https://id.pte-dev.hu/setup` — itt hozod létre az első admin
   fiókot a saját passkey-eddel. **Ez nyitott regisztrációs ablak** (mint a
   Dokploy `:3000/register`, ADR-0001): a DNS-rekord felvitele után azonnal
   csináld meg.
2. Fiók-helyreállítás (ha passkey vész el):
   ```bash
   docker compose -f /opt/headscale/docker-compose.yml exec pocket-id \
     /app/pocket-id one-time-access-token <email>
   ```
3. **SMTP (Mailjet)** — admin felület → Application Configuration → Email:
   host `in-v3.mailjet.com`, port `587`, STARTTLS; user/password a Mailjet
   API/Secret kulcspár; From: `id@pte-dev.hu`. Kapcsolók: „Emails verified
   by default" + „Email Login Notification" + „Email Login Code from
   Admin" BE (a verified email a headscale user-rekordjába is átkerül —
   az ACL ettől függetlenül a headscale-username `@`-formájával matchel);
   **„Email Login Code Requested by User" mindig KI** —
   emailes passkey-bypass, a platform-identitás erősségét ütné ki
   (ADR-0006). Verifikáció: Send test email.

## 4. Headscale OIDC élesítés

1. Pocket ID admin felület → OIDC Clients → új kliens:
   - Név: `headscale`, callback URL: `https://vpn.pte-dev.hu/oidc/callback`
2. A kapott client ID-t írd a `/opt/headscale/config/headscale.yaml` `oidc`
   blokkjába (`client_id`), a secretet a secret-fájlba:
   ```bash
   ( umask 077; printf '%s' '<CLIENT_SECRET>' > /opt/headscale/config/oidc_client_secret )
   ```
3. Aktiváld az `oidc:` blokkot a configban (vedd le a `#`-eket a blokk elejéről), majd:
   ```bash
   cd /opt/headscale && docker compose restart headscale
   docker compose logs headscale | tail -20    # OIDC issuer discovery OK?
   ```
4. Teszt a saját gépedről: `tailscale up --login-server https://vpn.pte-dev.hu`
   → böngésző → Pocket ID passkey login → a node megjelenik:
   `docker compose exec headscale headscale nodes list`

## 5. Platform-gépek bekötése (pre-auth kulcsok)

A szerverek nem OIDC-vel, hanem pre-auth kulccsal lépnek be, egy dedikált
`infra` headscale-user alá. A kulcs secret — SSH-n visszük át, cloud-initbe
nem kerül (ADR-0002).

```bash
cd /opt/headscale
docker compose exec headscale headscale users create infra
docker compose exec headscale headscale users list   # az infra numerikus ID-ja kell
# gépenként egy egyszer használatos, rövid életű kulcs (a --user a numerikus
# ID-t várja, nem a nevet — headscale 0.29):
docker compose exec headscale headscale preauthkeys create --user <INFRA_ID> --expiration 1h
```

A cél-gépen (a vpn-átállás runbook szerint):

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --login-server https://vpn.pte-dev.hu --authkey <PREAUTH_KULCS>
```

Szerver-node-ok kulcslejáratának kikapcsolása (ne járjon le a gépek
belépése; emberi node-oknál NEM — ott a 90 napos re-auth védelem marad):

```bash
docker compose exec headscale headscale nodes list   # szerver-node ID-k
docker compose exec headscale headscale nodes expire --identifier <ID> --disable --force
```

(Headscale 0.29-en élesben igazolva, 2026-07-06. Minden ÚJ szerver-node
joinja után ez a lépés is jár — különben 90 nap múlva csendben leesik a
tailnetről.)

## 6. Tailnet-resolver (dnsmasq) és split DNS élesítés

Előfeltétel: az összes platform-gép (és ez a gép is) fent van a tailneten.

1. Ez a gép is tailnet-node:
   ```bash
   docker compose exec headscale headscale preauthkeys create --user <INFRA_ID> --expiration 1h
   tailscale up --login-server https://vpn.pte-dev.hu --authkey <KULCS>
   tailscale ip -4    # ez lesz a __HEADSCALE_TAILNET_IP__
   ```
2. Gyűjtsd ki a tailnet IP-ket: `docker compose exec headscale headscale nodes list`
3. Töltsd ki a placeholdereket:
   - `/etc/dnsmasq.d/pte-tailnet.conf` — minden `__*_TAILNET_IP__`
     placeholder (infra-nevek + a shared zóna; új projektek
     felvétele később: services/projekt/RUNBOOK.md)
   - `/opt/headscale/config/headscale.yaml` — a `dns.nameservers.split` blokk
     aktiválása (a `#`-ek levétele) + `__HEADSCALE_TAILNET_IP__`
4. Indítás + ellenőrzés:
   ```bash
   systemctl enable --now dnsmasq
   cd /opt/headscale && docker compose restart headscale
   # egy tailnet-kliensről:
   dig +short barmi.shared.pte-dev.hu           # → PTE-Shared (zóna-wildcard)
   dig +short barmi.staging.shared.pte-dev.hu   # → ugyanaz (env-zónát is fedi)
   dig +short git.pte-dev.hu                   # → forgejo tailnet IP (infra-név)
   ```

## 7. ACL policy élesítés

A forrás-igazság a repo `services/headscale/acl-policy.hujson` fájlja.

1. Töltsd ki a repo-fájlban a host-IP placeholdereket és a csoport-emaileket
   (a usernevek formátumát a `headscale users list` kimenetével egyeztesd).
2. Másold a szerverre: `/opt/headscale/config/acl-policy.hujson` (felülírva a
   bootstrap policy-t), majd:
   ```bash
   cd /opt/headscale && docker compose kill -s HUP headscale
   docker compose logs headscale | tail -5   # policy load OK?
   ```
3. **Ellenőrzés dev-userrel**: éri a `git.pte-dev.hu`-t, NEM éri a
   `dokploy.pte-dev.hu`-t és a szerverek 22-es portját.

## 8. Tűzfal zárás (utolsó lépés!)

Csak akkor, ha a 6–7. lépés kész, és **a saját géped a tailneten van** —
különben kizárod magad (végső break-glass: Rackforest VNC).

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0
ufw allow 80/tcp    # Caddy — LE HTTP challenge + redirect
ufw allow 443/tcp   # Caddy — headscale + Pocket ID
ufw allow 3478/udp  # STUN (DERP)
ufw enable
# ellenőrzés: SSH tailneten át működik, publikus IP-ről a 22 zárva
```

## 9. Napi mentés élesítés (a PTE-Backup gép után)

Előfeltétel: a backup gép fut, rajta repo-user a beléptető rétegnek
(services/backup/RUNBOOK.md).

```bash
( umask 077
  openssl rand -base64 32 > /root/restic-headscale-password
  echo 'rest:http://headscale:<HTPASSWD_JELSZO>@backup.pte-dev.hu:8000/headscale' \
    > /root/restic-headscale-repo )
restic -r "$(cat /root/restic-headscale-repo)" \
  --password-file /root/restic-headscale-password init
systemctl enable --now headscale-backup.timer
# próba + visszaolvasás:
systemctl start headscale-backup.service
restic -r "$(cat /root/restic-headscale-repo)" \
  --password-file /root/restic-headscale-password snapshots
```

**A restic jelszót tedd el a gépen kívül is** (jelszókezelő) — nélküle a
mentés visszaállíthatatlan, és pont akkor kell, amikor ez a gép halott.

## Frissítés (image pin-bump)

A pinek gazdája a repo `cloud-init.yaml` compose-blokkja
(`caddy`, `headscale/headscale`, `ghcr.io/pocket-id/pocket-id`);
élő gépen a módosítás kézi átvezetés + drift-napló
([utólagos-konfiguráció](../../docs/runbooks/utolagos-konfiguracio.md)).

1. **Changelog-check kötelező.** A headscale 0.x minorok között is hoz
   breaking config-változásokat; a Pocket ID major-váltásnál migrációs guide
   van (v1→v2: kötelező `ENCRYPTION_KEY`, lásd
   pocket-id.org/docs/setup/major-releases). Előbb changelog, aztán pin.
2. **Mentés előbb**: `systemctl start headscale-backup.service` — a
   DB-migráció visszafelé nem garantált, a dump a rollback-út.
3. Pin átírása a repóban → átvezetés a gépen
   (`/opt/headscale/docker-compose.yml`), majd:
   ```bash
   cd /opt/headscale && docker compose pull && docker compose up -d
   ```
4. **Verifikáció**: `docker compose ps` (mindhárom Up), `headscale nodes
list`, `https://id.pte-dev.hu` login egy tailnet-kliensről, `tailscale
status` egy kliensen.
5. **Rollback**: pin vissza + `docker compose up -d`; ha a DB már migrált,
   a 2. pont dumpja a visszaút.

## Onboarding / offboarding

- **Onboarding**: Pocket ID admin → új user (email) → a user belép a Tailscale
  klienssel (`--login-server https://vpn.pte-dev.hu`), passkey-t regisztrál.
  Vedd fel a megfelelő csoportba az `acl-policy.hujson`-ban (repo → szerver →
  HUP), és Forgejóban ossz jogot.
- **Offboarding**: Pocket ID-ban letiltás + a node-jai kiléptetése:
  ```bash
  docker compose exec headscale headscale nodes list   # keresd a userét
  docker compose exec headscale headscale nodes expire --identifier <ID>
  ```
  Végül vedd ki az ACL-csoportból (repo → szerver → HUP).

## Helyreállítás (a gép halála esetén)

1. Új VPS a `cloud-init.yaml`-lal (1. lépés) — a publikus IP változhat:
   Rackhost A rekordok átírása.
2. A legutóbbi dump visszatöltése a backup gépről:
   ```bash
   restic -r rest:http://headscale:<PW>@<BACKUP_L2_VAGY_PUBLIKUS_UTVONAL>/headscale \
     --password-file <jelszó> restore latest --target /tmp/restore
   ```
   Vigyázat: a backup gép tailneten érhető el, ami ilyenkor épp halott — a
   helyreállításhoz a backup gép VNC/SSH-ján keresztül húzd ki a dumpot
   (break-glass útvonal), vagy ideiglenesen nyisd a 8000-et a publikus IP-dre.
3. `/tmp/restore` → `/opt/headscale/data` + `config`, majd `docker compose up -d`.
4. A kliensek maguktól visszatalálnak (a node-kulcsok a DB-vel együtt jönnek
   vissza); ellenőrzés: `headscale nodes list`.
