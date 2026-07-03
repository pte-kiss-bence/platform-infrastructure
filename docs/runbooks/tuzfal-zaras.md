# Runbook — Tűzfal zárás (közös recept)

A platform-gépek tűzfal-zárásának közös receptje: bejövő forgalom csak a
tailnetről és a privát L2-ről (ADR-0004, ADR-0005). **Ez a dokumentum a
gazda** — a [vpn-átállás 9. fázisa](vpn-atallas.md), a
[backup](../../services/backup/RUNBOOK.md) és a
[projekt](../../services/projekt/RUNBOOK.md) runbook erre hivatkozik, és
csak a gépspecifikus eltéréseket mondja el.

Kivétel a `PTE-Headscale`: a beléptető réteg szükségszerűen publikus
(80/443 + STUN 3478/udp), saját receptje a
[services/headscale/RUNBOOK.md](../../services/headscale/RUNBOOK.md) 8. lépése — arra ez a recept NEM érvényes.

## Előfeltételek

- A gép fent van a tailneten, és a **saját géped is** (admin ACL-lel) —
  különben kizárod magad. Végső break-glass: Rackforest VNC
  ([utolagos-konfiguracio.md](utolagos-konfiguracio.md), Hozzáférési utak).
- `ufw` telepítve van (`apt-get update && apt-get install -y ufw`).

## Közös recept

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0
ufw allow from 10.10.0.0/24     # privát L2 (Dokploy SSH, runner→git, mentések)
ufw enable
```

**CSAPDA — a Docker-publikált portokat az ufw NEM védi** (pl. Traefik
80/443, Forgejo git SSH 2222, rest-server 8000): a Docker a saját iptables
NAT-szabályaival az ufw előtt engedi be a forgalmat. Ezért a `DOCKER-USER`
láncba is kell szabály a publikus interfészre:

```bash
PUB_IF=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
iptables -I DOCKER-USER -i "$PUB_IF" -m conntrack --ctstate NEW -j DROP
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
netfilter-persistent save
```

## Verifikáció

- **Kívülről** (nem tailnet, pl. mobilnet): `nmap -Pn <PUBLIKUS_IP>` →
  minden port zárva/filtered.
- **Tailnetről**: SSH és a gép szolgáltatásai mennek.
- **Privát L2-ről**: a szomszéd gépről SSH megy (break-glass út, ADR-0005).

A gépspecifikus verifikáció (melyik szolgáltatásnak kell mennie) a hivatkozó
runbook dolga.
