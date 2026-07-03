# A teljes platform hálózati láthatatlanság mögött — Headscale VPN

A platform minden szolgáltatása — a három infra service (Dokploy, Forgejo, Runner) és minden deployolt app — VPN mögé kerül: publikus portja egyik gépnek sincs, a csapat (6 fő ma, 30–50 egy éven belül, egyetlen admin) Tailscale kliensekkel, self-hosted Headscale kontrolplane-en keresztül éri el. A cél a **hálózati láthatatlanság**: a szolgáltatások a szkennelő botok és az auth-bypass CVE-k számára nem léteznek. Egy identity-aware proxy csak a HTTP-t védte volna — a git SSH (2222) és az admin SSH (22) számára így is külön megoldás kellett volna, azaz két rendszert üzemeltetnénk egy helyett.

## Considered Options

- **Identity-aware proxy** (Authelia/authentik forward-auth a Traefik előtt, vagy Cloudflare Access) — a HTTP-réteget védi, a TCP-t (SSH) nem; a portok publikusan látszanak. Elvetve.
- **Tailscale SaaS** — a legkisebb üzemeltetési teher, de 30–50 főre ~180–300 USD/hó, és open source elvárás volt. Elvetve.
- **NetBird self-hosted** — beépített web admin UI, cserébe 4+ komponens a Headscale egy binárisa + SQLite-ja helyett. Elvetve.
- **Headscale + hivatalos Tailscale kliensek** — elfogadva: egy bináris, a policy fájl a repóban verziózható, a kliensek minden OS-en kiforrottak.

## Consequences

- Publikus kivétel kettő marad, mindkettő a beléptető rétegé: Headscale (`vpn.pte-dev.hu`, 80/443 + STUN 3478/udp; a DERP maga a 443-on megy, a 80 a Caddy LE HTTP challenge-e és redirectje miatt kell) és Pocket ID (`id.pte-dev.hu`, ugyanazon a Caddy 80/443-on) — a beléptető rétegnek definíció szerint a kapun kívül kell lennie (ADR-0006).
- Git SSH és admin SSH is csak a tailnet + privát L2 felől érhető el; break-glass: Rackforest VNC konzol (működése ellenőrizve).
- Hozzáférés: háromszintű ACL (admin / dev / guest) a repóban verziózott headscale policy fájlban. A Dokploy panelt hálózati szinten is csak admin éri el; a guest csak a meghívott projekt-VPS(eke)t (ADR-0009). Az ACL port-szintű — projekten belüli per-app guest-korlátozás app-oldali OIDC-vel oldandó meg, ha majd kell.
- A Let's Encrypt HTTP challenge és a publikus app-DNS eltörik — kezelésük: ADR-0007.
- A szerverek tailnet-regisztrációja pre-auth kulccsal történik: gépenként egyszeri kézi runbook-lépés (a kulcs secret, ADR-0002 szerint nem mehet a cloud-init user-datába).
