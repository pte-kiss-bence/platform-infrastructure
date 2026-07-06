# Onboarding — új csapattag a PTE dev platformon

Két rész: az **adminisztrátor** előkészítő lépései (~5 perc), majd az **új
tag** saját gépes beállítása (~10 perc). A platform VPN mögött él
(ADR-0004): minden szolgáltatás csak a tailnetről érhető el, publikus
útvonal nincs.

A fogalmak a [CONTEXT.md](../CONTEXT.md)-ben; az admin-lépések gazdája a
[services/headscale/RUNBOOK.md](../services/headscale/RUNBOOK.md)
(Onboarding/offboarding szakasz).

## 1. Admin-lépések (a tag érkezése ELŐTT)

1. **Pocket ID user**: `https://id.pte-dev.hu` admin felület → új user a
   tag email-címével.
2. **ACL-csoport**: a repo
   [services/headscale/acl-policy.hujson](../services/headscale/acl-policy.hujson)
   fájljában vedd fel a taget a megfelelő csoportba (tipikusan
   `group:dev`). **Figyelem**: a headscale a usert a headscale-oldali
   usernevén ismeri, `@`-végződéssel (`headscale users list`, Username
   oszlop) — nem a Pocket ID-s emailen. A user először az első
   VPN-belépéskor jön létre, ezért az ACL-be vétel mehet UTÁNA is.
3. Repo-fájl másolása a szerverre + reload:
   ```bash
   # a repo acl-policy.hujson tartalmát a szerverre, majd:
   ssh pte-headscale
   cd /opt/headscale && docker compose kill -s HUP headscale
   docker compose logs headscale | tail -3   # policy reload OK?
   ```
4. **Forgejo jogok**: a megfelelő org/repo-khoz hozzáférés (a tag első
   pocket-id-s belépése után látszik a user).

## 2. A tag gépén

### 2.1 Tailscale kliens + VPN-belépés

1. Tailscale kliens telepítés: <https://tailscale.com/download>
   (Tailscale-fiók NEM kell).
2. Terminálból:
   ```
   tailscale up --login-server https://vpn.pte-dev.hu
   ```
3. A megnyíló böngészőben Pocket ID login → **passkey regisztráció**
   (ujjlenyomat / Windows Hello / hardverkulcs). Ez lesz minden későbbi
   belépés kulcsa — jelszó nincs.
4. Ellenőrzés:
   ```
   tailscale status          # saját node látszik
   nslookup git.pte-dev.hu   # tailnet IP-t ad (100.64.0.x)
   ```

### 2.2 Forgejo (git) belépés

1. Böngészőben `https://git.pte-dev.hu` → **Sign in with pocket-id** →
   passkey. Első belépéskor a fiók automatikusan létrejön.
2. **SSH-kulcs a git-műveletekhez** (a VPN-belépéstől független!):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/pte-forgejo -C "<neved>@forgejo"
   ```
   Windows/PowerShellben a `~` nem megbízható, és a `.ssh` mappát kézzel
   kell létrehozni:
   ```powershell
   mkdir $env:USERPROFILE\.ssh -Force
   ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\pte-forgejo -C "<neved>@forgejo"
   ```
   A publikus felét (`~/.ssh/pte-forgejo.pub`) Forgejo → Settings →
   SSH / GPG Keys → Add Key.
3. `~/.ssh/config`-ba:
   ```
   Host git.pte-dev.hu
       Port 2222
       User git
       IdentityFile ~/.ssh/pte-forgejo
       IdentitiesOnly yes
   ```
4. Próba:
   ```bash
   git clone git@git.pte-dev.hu:<owner>/<repo>.git
   ```

A git remote-ok formátuma mindenkinél ugyanaz, VPN-en kívülről egyszerűen
nem oldódik fel a név — meglévő clone-okat átállítani nem kell.

### 2.3 WSL-ben dolgozóknak (Windows)

A Tailscale a Windows-oldalon fut; a WSL2 alapból NEM látja a split DNS-t
(`Temporary failure in name resolution`). Megoldás — **mirrored
networking** (Windows 11): `%UserProfile%\.wslconfig`:

```
[wsl2]
networkingMode=mirrored
```

majd PowerShellből `wsl --shutdown`, WSL újraindítás. Gyorstapasz helyette:
`echo "100.64.0.3  git.pte-dev.hu" | sudo tee -a /etc/hosts` a WSL-ben —
de a mirrored mód a tartós út (a tailnet IP-k változhatnak).

## 3. Verifikáció (a tag gépéről)

- [ ] `tailscale status` — belépve, node online
- [ ] `https://git.pte-dev.hu` böngészőben megnyílik, lakat, cert-hiba nincs
- [ ] `git clone` + push megy SSH-n
- [ ] Belső toolok (`*.shared.pte-dev.hu`) elérhetők
- [ ] Dev-userként a `https://dokploy.pte-dev.hu` és a gépek SSH-ja (22-es
      port) **NEM** érhető el — ha igen, ACL-hiba, szólj az adminnak!

## 4. Gyakori hibák

| Tünet | Ok / megoldás |
| --- | --- |
| `You're not allowed to access this service` a Pocket ID-nál | Az OIDC kliens Restricted és a user nincs engedélyezett groupban — admin: kliens Unrestricted vagy group-tagság. |
| `Permission denied (publickey)` git-nél | A kulcs nincs fent a Forgejo-fiókban, vagy az ssh nem azt ajánlja fel — `IdentityFile` + `IdentitiesOnly yes` a configban. |
| Nevek nem oldódnak fel WSL-ben | Lásd 2.3 — mirrored networking. |
| `curl`-lel megy, böngészőből `DNS_PROBE_FINISHED_NXDOMAIN` | A böngésző saját DoH-t (Secure DNS) használ, megkerüli a split DNS-t — Chrome/Edge: Settings → Security → „Use secure DNS" KI; Firefox: DNS over HTTPS Off. Böngésző-újraindítás. |
| `ERR_TUNNEL_CONNECTION_FAILED` böngészőből az IRODAI hálózaton (curl közben megy; mobilnetről minden jó) | A céges GPO minden gépre PAC-ot tesz (`HKCU\...\Internet Settings\AutoConfigURL` → `https://pteproxy.pte.hu/proxy.pac`); a PAC csak az irodai hálózaton tölthető le — ott a böngésző a PTE-proxyn át próbálja a `*.pte-dev.hu` neveket, amiket az nem ér el. Irodán kívül a PAC-letöltés hibája miatt a böngésző DIRECT-re esik vissza, ezért ott működik. **Tartós fix: PTE-IT ticket — `*.pte-dev.hu` → `DIRECT` a proxy.pac-ban.** Átmenetileg irodában: Firefox „No proxy" módban (saját beállítás, a GPO-s PAC-tól független), vagy mobilnet. A reg-kulcs kézi törlése nem megoldás — a GPO visszaírja. A VPN-forgalmat az irodai hálózat nem bántja (DERP 443-on relayel). |
| Semmi nem elérhető | Fut a Tailscale kliens? `tailscale up --login-server https://vpn.pte-dev.hu` újra; 90 naponta re-auth kell (passkey). |

## Offboarding

Gazda-eljárás:
[services/headscale/RUNBOOK.md](../services/headscale/RUNBOOK.md)
(Onboarding/offboarding): Pocket ID letiltás + `headscale nodes expire` +
ACL-csoportból kivétel.
