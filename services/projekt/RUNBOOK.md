# Runbook — Projekt-VPS (Dokploy remote server, projektenként)

Minden app-projekt **már az indulástól** egy dedikált VPS-t kap
(`PTE-<Projekt>`), rajta a projekt mindhárom környezetével (ADR-0009). Ez a
runbook egy **új projekt születésének** egyszeri (~15 perces) eljárása és a
projekten belüli **normál üzem** (új app, env-ek, preview). A csapat saját
belső tool-gépe (`PTE-Shared`, zóna: `shared.pte-dev.hu`) a saját infra
része — technikailag ugyanezzel a sablonnal jön létre, de nem app-projekt:
guest oda sosem kap meghívást.

Névséma: az [ADR-0009](../../docs/adr/0009-projektenkent-dedikalt-vps-es-env-zonak.md)
táblája a forrás-igazság. Példa (`neptun2` projekt, `api` app):
`api.neptun2.pte-dev.hu` (prod), `api.staging.neptun2.pte-dev.hu` (staging),
`pr42-api.preview.neptun2.pte-dev.hu` (preview).

## Új projekt létrehozása

### 1. VPS

Rackforest panelben: **Ubuntu 24.04 LTS**, méret a projekt igénye szerint
(kezdésnek 2 vCPU / 4 GiB / 40 GB). User-data:
`services/projekt/cloud-init.yaml`, **a hostname átírva** `PTE-<Projekt>`-re.

- **SSH kulcsmezőbe KÉT kulcs**: a sajátod ÉS a Dokploy public kulcsa.
- **Csatold a privát L2 hálózatra** (Rackforest → Hálózatok) — a Dokploy ezen
  SSH-zza (ADR-0005).
- Publikus DNS A rekord NEM kell.

### 2. Dokploy remote server

Dokploy UI → **Servers → Add Server**: név `PTE-<Projekt>`, IP: **a privát L2
címe** (nem a publikus!), port 22, user `root`, a meglévő Dokploy SSH
kulccsal. **Setup Server**, várd meg a zöldet (Docker + Traefik felmegy).

### 3. Tailnet-join + hálózati regisztráció

1. Pre-auth kulcs a Headscale gépen, join a projekt-VPS-en
   ([services/headscale/RUNBOOK.md](../headscale/RUNBOOK.md) 5. lépés);
   jegyezd fel a tailnet IP-t.
2. **Tailnet-resolver** — egy sor a Headscale VPS
   `/etc/dnsmasq.d/pte-tailnet.conf`-jába (a teljes projekt-zónát fedi,
   minden env-vel együtt), majd `systemctl restart dnsmasq`:

   ```
   address=/<projekt>.pte-dev.hu/<TAILNET_IP>
   ```

3. **ACL** — a repo [acl-policy.hujson](../headscale/acl-policy.hujson)
   fájljában: host-bejegyzés a projekt-VPS-nek + dst a `dev` csoport
   szabályába (és ha külsős csapat kap hozzáférést, a guest-szabályba is),
   majd másolás a szerverre + HUP.

### 4. Rackhost CNAME-ek (kézzel, egyszer)

Szintenként egy `_acme-challenge` delegálás a deSEC-be — env-zónánként kell
(a cert-challenge nem öröklődik szintek között):

| Rekord                                         | Típus | Érték                              |
| ---------------------------------------------- | ----- | ---------------------------------- |
| `_acme-challenge.<projekt>.pte-dev.hu`         | CNAME | `_acme-challenge.pte-dev.dedyn.io` |
| `_acme-challenge.staging.<projekt>.pte-dev.hu` | CNAME | `_acme-challenge.pte-dev.dedyn.io` |
| `_acme-challenge.preview.<projekt>.pte-dev.hu` | CNAME | `_acme-challenge.pte-dev.dedyn.io` |

### 5. Zóna-cert a Traefiken

**Ez a szakasz a deSEC/Traefik cert-config gazdája** — az infra-gépek
(vpn-átállás 6. fázis) is erre hivatkoznak, csak más SAN-listával.

1. A Traefik konténer kapja meg a deSEC tokent env-ként (`DESEC_TOKEN`) — a
   Dokploy UI Traefik-beállításain keresztül, vagy a konténer újraindítása
   env-vel (ellenőrzés: `docker inspect <traefik cid> | grep -A5 Env`).
2. A gépen az `/etc/dokploy/traefik/traefik.yml`-ben a resolver és az
   entrypoint default certje:

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: dokploy@pte-dev.hu
      storage: /etc/dokploy/traefik/dynamic/acme.json
      dnsChallenge:
        provider: desec
        delayBeforeCheck: 90 # a deSEC + CNAME propagációnak idő kell

entryPoints:
  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
        domains:
          - main: <projekt>.pte-dev.hu
            sans:
              - "*.<projekt>.pte-dev.hu"
              - "*.staging.<projekt>.pte-dev.hu"
              - "*.preview.<projekt>.pte-dev.hu"
```

Infra-gépen (Dokploy, Forgejo) a `domains` blokk ehelyett:
`main: pte-dev.hu`, `sans: ["*.pte-dev.hu"]`.

Traefik restart, majd: `docker logs <traefik> 2>&1 | grep -i acme` — kiállt-e
a cert.

### 6. Tűzfal zárás

A közös recept
([docs/runbooks/tuzfal-zaras.md](../../docs/runbooks/tuzfal-zaras.md)):
ufw (tailscale0 + privát L2) **és** a DOCKER-USER lánc szabálya — a
Docker-publikált portokat az ufw egyedül nem védi.

### 7. Verifikáció

- Tailnet dev-userről: `dig +short proba.<projekt>.pte-dev.hu` → a gép
  tailnet IP-je (és a `proba.staging.` / `pr1-proba.preview.` változat is).
- Publikus internetről: egyetlen port sem válaszol, a nevek nem resolválnak.
- Egy próba-app deploy (lásd lent) HTTPS-sel, cert-hiba nélkül.

## Normál üzem

### Új app (nulla DNS/cert lépés)

1. Dokploy: Create Service a projekt szerverére, domain a névséma szerint
   (`<app>.<projekt>.pte-dev.hu`), certificate: **none** — a zóna-wildcard
   cert fedi, per-app certet nem kérünk (CT-log leak, ADR-0007).
2. Deploy — kész. Se DNS-, se cert-teendő.

App-oldali auth: belső toolnak nem kötelező (a tailnet maga a beléptetés);
ha kell — pl. guest-szűkítés vagy audit — a Pocket ID-ban regisztrálj neki
OIDC klienst.

### Environmentek

- **Prod és staging**: a Dokploy-ban külön environment/service, csak a domain
  különbözik (`<app>.` vs `<app>.staging.`); env-változók env-enként a
  Dokploy Environment fülén.
- **Preview (ephemeral)**: az infra kész rá (a `*.preview.<projekt>` zónát a
  wildcard DNS és cert fedi), de a Dokploy natív preview deploymentje
  GitHub-only (ADR-0009) — az automatizálás Forgejo Actions + Dokploy API
  glue, **későbbi implementációs feladat**
  ([docs/backlog.md](../../docs/backlog.md)). Addig: kézi deploy
  `pr<N>-<app>.preview.<projekt>.pte-dev.hu` domainnel, PR-zárás után kézi
  törlés.

### Guest-hozzáférés (más PTE-s csapat)

Az ACL guest-szabályának dst-jéhez add hozzá **ennek a projektnek** a gépét —
a vendég csak ezt a projektet éri el, a többi gép a számára nem is látszik
(ADR-0009). Per-app szűkítés a projekten belül: app-oldali Pocket ID OIDC.

### Env szétválasztás (ha egy projekt kinövi az egy gépet)

Új VPS ugyanezzel a runbookkal, majd a tailnet-resolverben az adott env-zóna
átirányítása (pl. `address=/staging.<projekt>.pte-dev.hu/<ÚJ_IP>` — a
hosszabb egyezés nyer), és a cert-SAN-ok szétosztása a két gép Traefikje
között. A névséma nem változik, a userek semmit nem vesznek észre.
