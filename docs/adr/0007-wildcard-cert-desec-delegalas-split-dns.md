# Wildcard cert deSEC-delegált DNS-01-gyel és wildcard split DNS

> **Részben módosítva: [ADR-0009](0009-projektenkent-dedikalt-vps-es-env-zonak.md)** — az
> app-ok nem egy közös gépen laknak, hanem projektenként dedikált VPS-en,
> környezetenkénti zónákkal; a mechanika (deSEC-delegált DNS-01, dnsmasq
> wildcard, CT-log védelem) változatlan, a lenti 2–3. következmény helyett a
> 0009 érvényes.

A VPN mögött a Let's Encrypt HTTP challenge eltörik (a 80-as port publikusan zárva), a `pte-dev.hu` zóna gazdájának (Rackhost) pedig nincs DNS API-ja, és a Traefik cert-motorja (lego) sem támogatja. Ezért egyetlen **`*.pte-dev.hu` wildcard cert** készül DNS-01 challenge-dzsel, a `_acme-challenge.pte-dev.hu` rekordot CNAME-mel a **deSEC**-be (ingyenes, nonprofit, API-s DNS szolgáltató, lego-támogatással) delegálva. Publikus DNS rekord csak a beléptető rétegé marad (`vpn.`, `id.` + a delegáló CNAME); a tailneten belül a neveket a **tailnet-resolver** (dnsmasq a `PTE-Headscale` VPS-en) oldja fel: `*.pte-dev.hu` → a közös app-gép (a döntéskor `PTE-Apps-1` néven tervezve; az ADR-0009 óta projektenkénti zóna-wildcardok), explicit kivételekkel a git/dokploy nevekre. Így új app deploy = **nulla DNS- és cert-lépés** (a Dokploy-ban felvett domaint a wildcard cert és a wildcard DNS már fedi), és az app-nevek a Certificate Transparency logba sem kerülnek — per-app cert publikusan hirdetné a belső szolgáltatásneveket, a hálózati láthatatlanság (ADR-0004) ellen dolgozva.

## Considered Options

- **Self-hosted acme-dns** a Headscale VPS-en — nulla külső függés, cserébe plusz egy publikusan kiszolgált DNS (53) egyetlen adminnak. Elvetve a deSEC javára.
- **A teljes zóna átköltöztetése** API-képes szolgáltatóhoz — nameserver-váltás olyan rugalmasságért, amire publikus rekordok híján nincs szükség. Elvetve.
- **Headscale MagicDNS `extra_records`** a tailnet-nevekre — csak exact-match, app-onkénti kézi rekord kellene, pont a kiiktatandó kézi lépés. Elvetve a dnsmasq wildcard javára.

## Consequences

- A deSEC API token minden Traefiket futtató szerveren jelen van (Dokploy env-ben, ADR-0002 szerint user-datába nem kerül). Blast radius: kompromittált szerver legfeljebb certet állíttathat ki a domainre — a zónát átirányítani nem tudja.
- A wildcard egy IP-re mutat: az app-ok egy gépen (`PTE-Apps-1`) laknak. Több app-szerver esetén szerverenkénti wildcard-zóna vagy app-onkénti explicit resolver-sor kell — akkor döntendő el.
- A wildcard egy szintet fed: az app-nevek közvetlenül a `pte-dev.hu` alatt élnek (`valami.pte-dev.hu`).
- Minden Traefik saját wildcard certet szerez be — a LE duplicate-limit (5/hét azonos névkészletre) alatt marad.
