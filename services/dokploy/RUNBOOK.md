# Runbook — Dokploy provisioning (Rackforest VPS)

A [cloud-init.yaml](cloud-init.yaml) körüli kézi lépések. A provisioning flow maga felügyelet nélkül fut első bootkor; ez a dokumentum azt írja le, mit kell tenned előtte, közben és utána.

Kapcsolódó döntések: [ADR-0001](../../docs/adr/0001-automatizalt-dokploy-admin-letrehozas.md) (admin bootstrap), [ADR-0002](../../docs/adr/0002-nincs-secret-a-cloud-init-user-databan.md) (secret-kezelés).

> **VPN-világ (ADR-0004–0009):** a platform átállt hálózati láthatatlanságra — a
> panelnek nincs publikus DNS rekordja, a domain/cert lépések helyett a
> [docs/runbooks/vpn-atallas.md](../../docs/runbooks/vpn-atallas.md) érvényes.
> A **2. és 4. lépés** (publikus DNS + LE HTTP challenge) legacy: friss
> provisionálásnál hagyd ki — az `all` fázis az admin bootstrap után
> `SUCCESS`-szel megáll, a domain/cert/tűzfal (és a `:3000` zárása a
> `close3000` fázissal) a vpn-átállás runbook szerint megy. A panel addig a
> `http://<VPS_IP>:3000` címen érhető el.

## 1. Előkészítés

1. Rackforest panelben hozd létre a VPS-t: **Ubuntu 24.04 LTS**, **minimum 2 vCPU / 4 GiB RAM / 40 GB SSD** (VPS Four). 1 GiB RAM-on a Swarm stack (Postgres + Redis + Dokploy + Traefik) OOM-loopba fut, az install sosem ér véget — és a gépen futnak majd a deployolt appok is. User-data mezőbe a `services/dokploy/cloud-init.yaml` tartalma változtatás nélkül (nincs placeholder).
2. **SSH kulcs mező kitöltése a panelben kötelező** — a panel injektálja a root userhez; a YAML password authot és root jelszavas belépést tiltja, kulcs nélkül kizárod magad.
3. **Miért nem 26.04:** a Dokploy `install.sh` fix Docker verziót pinnel (2026 júliusában: 28.5.0), ami a 26.04 "resolute" Docker repójában nincs meg — a telepítés `'28.5.0' not found amongst apt-cache madison results` hibával elhal. Újabb Ubuntu kiadás előtt ellenőrizd, hogy a pinnelt verzió létezik-e a cél-kiadás repójában, vagy telepíts Dockert előre pin nélkül (`curl -fsSL https://get.docker.com | sh`) — akkor a Dokploy script átugorja a sajátját. A flow pre-flight csak a repo _létezését_ ellenőrzi, a pinnelt verziót nem.

## 2. DNS rekord (amint az IP megvan)

Rackhost DNS-ben vidd fel: `dokploy.pte-dev.hu` **A** rekord → VPS publikus IP, alacsony TTL (300s).

A flow DNS-polling guarddal vár erre max. 30 percet — nem baj, ha a rekord pár perccel a boot után kerül be.

## 3. Állapot követése

SSH be root-ként (`~/.ssh/config`-ban: `User root`), majd:

```bash
cat /root/dokploy-provision-status
tail -f /var/log/dokploy-provision.log
```

Státuszok az `all` fázisban: `INSTALL` → `ADMIN_BOOTSTRAP` → `SUCCESS`. A `DNS_WAIT` → `DOMAIN_ASSIGN` → `CERT_WAIT` → `PORT_CLOSE` lánc csak a legacy `domain` fázisban fut. Hibánál `FAILED: <ok>`.

## 4. PARTIAL: DNS nem állt be időben

Ha a státusz `PARTIAL`, a telepítés és az admin bootstrap kész, csak a domain/cert maradt ki. Vidd fel az A rekordot, várd meg a propagációt, majd:

```bash
/usr/local/sbin/dokploy-provision.sh domain
```

## 5. Admin belépés

```bash
cat /root/dokploy-admin-credentials
```

Belépés friss (VPN-világú) provisionálásnál: `http://<VPS_IP>:3000` — a
`https://dokploy.pte-dev.hu` cím csak a tailnet-elérés élesítése után megy
(vpn-átállás runbook). Email `dokploy@pte-dev.hu` + a generált jelszó. Első
belépés után érdemes a jelszót a UI-ban sajátra rotálni.

## 6. SMTP beállítás (kézi, ADR-0002)

Dokploy UI → **Settings → Notifications → Email**:

| Mező      | Érték                                                              |
| --------- | ------------------------------------------------------------------ |
| SMTP host | `in-v3.mailjet.com`                                                |
| Port      | `587`                                                              |
| Username  | Mailjet API key                                                    |
| Password  | Mailjet API secret                                                 |
| From      | `dokploy@pte-dev.hu`                                               |
| To        | `dokploy@pte-dev.hu` — az ImprovMX továbbítja a valódi postafiókba |

Teszt-emaillel ellenőrizd. (Bejövő irány ImprovMX forward, Dokploy-t nem érinti.)

## 7. Verifikáció

Friss (VPN-világú) provisionálásnál az `all` fázis után:

```bash
cat /root/dokploy-provision-status                   # SUCCESS
curl -sI http://<VPS_IP>:3000/ | head -1             # HTTP/1.1 200 — a panel él
```

A `:3000` ilyenkor **szándékosan nyitva van** — zárása (`close3000` fázis) és a
`dokploy.pte-dev.hu` + wildcard cert élesítése a
[vpn-átállás runbook](../../docs/runbooks/vpn-atallas.md) 6. és 9. fázisa.

Csak a legacy `domain` fázis után értelmes:

```bash
curl -sI https://dokploy.pte-dev.hu | head -1        # HTTP/2 200 vagy 307
curl -m 5 http://<VPS_IP>:3000/ ; echo "exit: $?"    # timeout kell legyen (port zárva)
```

## 8. Hibaelhárítás

- **`FAILED: admin sign-up HTTP ...`** — a nem dokumentált sign-up endpoint változott (ADR-0001 kockázat). Fallback: regisztrálj kézzel a `http://<VPS_IP>:3000/register` címen (**azonnal**, az endpoint addig bárkinek nyitva van!), majd futtasd: `/usr/local/sbin/dokploy-provision.sh domain` — a credentials fájlt előtte hozd létre kézzel a saját jelszavaddal (`/root/dokploy-admin-credentials`, formátum: `password: <jelszó>` sor).
- **`FAILED: Let's Encrypt cert nem jött létre`** — a :3000 nyitva maradt, panel elérhető IP:3000-en. Nézd meg a Traefik logot: `docker service logs dokploy-traefik --tail 100`. Tipikus ok: DNS másik IP-re mutat, vagy LE rate limit.
- **Panel újra kell IP:3000-en** (pl. cert-baj után): `docker service update --publish-add mode=host,published=3000,target=3000 dokploy` — munka végén zárd vissza: `docker service update --publish-rm published=3000,target=3000,protocol=tcp,mode=host dokploy`. (A `--publish-rm` csak a pontosan egyező spec-et veszi le — mode-ostul, protokollostul; eltérésnél némán, exit 0-val nem csinál semmit, ezért zárás után mindig ellenőrizz: `ss -tln | grep 3000` üres kell legyen.)
