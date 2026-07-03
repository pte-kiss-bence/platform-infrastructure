# Projektenként dedikált VPS és környezetenkénti zónák

Az app-ok nem egy közös app-szerveren laknak (ahogy az ADR-0007 eredetileg
feltette), hanem **minden app-projekt már az indulástól egy saját Dokploy
remote server VPS-t kap** (`PTE-<Projekt>`), rajta a projekt mindhárom
környezetével: **prod, staging, preview** (ephemeral, PR-enként). A csapat
saját belső tooljainak gazdája a `PTE-Shared` — ez a saját infra része
(zónája: `shared.pte-dev.hu`), nem app-projekt: technikailag ugyanezzel a
sablonnal jön létre, de guest oda sosem kap meghívást. A névséma
környezetenkénti zónákkal, ponttal tagolva:

| Env     | Név                                        |
| ------- | ------------------------------------------ |
| Prod    | `<app>.<projekt>.pte-dev.hu`               |
| Staging | `<app>.staging.<projekt>.pte-dev.hu`       |
| Preview | `pr<N>-<app>.preview.<projekt>.pte-dev.hu` |

Így a guest-hozzáférés hálózati szinten lesz projekt-szintű (az ADR-0004
port-szintű ACL-korlátja projekt-VPS-enként érvényesül, nem az összes appra
egyben), az erőforrás-izoláció és a blast radius projektenkénti, és az env-ek
később szétválaszthatók külön gépre (a zóna-wildcard átirányításával) — a
kötőjeles env-jelölés (`api-staging.<projekt>`) ezt nem tudta volna.

## Considered Options

- **Egy közös app-szerver, lapos `*.pte-dev.hu` wildcard** (ADR-0007 eredeti
  következménye) — minden tailnet-tag minden appot elér, egy elszálló app
  mindenkit visz. Elvetve.
- **Kötőjeles env-jelölés egy szinten** (`api-staging.<projekt>.pte-dev.hu`)
  — projektenként 1 CNAME elég lenne, de az env-ek DNS-szinten örökre
  szétválaszthatatlanok. Elvetve.
- **Env-zónák ponttal** — elfogadva; ára projektenként 3 `_acme-challenge`
  CNAME a Rackhostnál (szintenként egy).

## Consequences

- **Új app / új PR-preview egy projekten belül: nulla DNS- és cert-lépés** —
  a tailnet-resolver egyetlen `address=/<projekt>.pte-dev.hu/<IP>` sora a
  teljes részfát fedi (minden env-et), a projekt-VPS Traefik-certje pedig
  három wildcard SAN-nal (`*.<projekt>`, `*.staging.<projekt>`,
  `*.preview.<projekt>`) mindent lefed.
- **Új projekt: egyszeri, kb. 15 perces esemény** — VPS cloud-initből,
  Dokploy remote server, tailnet-join, egy resolver-sor, egy ACL-bejegyzés,
  három CNAME a Rackhostnál, Traefik cert-config
  (services/projekt/RUNBOOK.md).
- A `*.pte-dev.hu` alap-wildcard cert az infra-nevekre (git, dokploy) marad
  a Dokploy- és Forgejo-gép Traefikjén; a projekt-VPS-ek saját zóna-certet
  szereznek.
- **Preview-orkesztráció rés**: a Dokploy preview deployment GitHub-only, a
  Forgejo-támogatás nyitott feature request (Dokploy/dokploy#3828). Az infra
  (DNS + cert) preview-kész; az ephemeral deployt PR-eseményre egy Forgejo
  Actions workflow végzi majd a Dokploy API-n át — külön, későbbi
  implementációs feladat, addig a preview kézi deploy a staging mellé.
