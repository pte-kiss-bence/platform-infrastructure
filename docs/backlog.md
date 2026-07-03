# Backlog — nyitott infra-feladatok

A dokumentációban „későbbi feladat”-ként hivatkozott tételek egy helyen.
A [vpn-átállás](runbooks/vpn-atallas.md) záró állapot-ellenőrzése után a
tételek Forgejo issue-kba migrálhatók; addig ez a fájl a követés helye.
Új tétel: forráslinkkel együtt vedd fel.

## 1. Preview-orkesztráció (Forgejo Actions + Dokploy API glue)

A Dokploy natív preview deploymentje GitHub-only; az ephemeral
PR-preview-khoz (`pr<N>-<app>.preview.<projekt>.pte-dev.hu`) saját workflow
kell: PR-eseményre deploy a Dokploy API-n át, PR-zárásra törlés. Az infra
(DNS + cert) preview-kész. Upstream feature request: Dokploy/dokploy#3828.

- Forrás: [ADR-0009](adr/0009-projektenkent-dedikalt-vps-es-env-zonak.md),
  [services/projekt/RUNBOOK.md](../services/projekt/RUNBOOK.md) (Environmentek)
- Addig: kézi preview-deploy + kézi törlés.

## 2. Platform-szintű mentések bekötése

Ma csak a beléptető réteg ment (napi timer). A Forgejo adat (git repók +
Postgres) és az app-adatbázisok restic-mentése a backup gépre (privát L2-n)
nincs bekötve — a topológia-ábrán az él szaggatott, amíg ez él nem lesz.

- Forrás: [ADR-0008](adr/0008-dedikalt-backup-vps-restic-append-only.md),
  [architektura.md](architektura.md) 4. flow
- Minta: `services/headscale/cloud-init.yaml` `beleptetoreteg-backup.sh`.

## 3. Off-site backup másolat

Minden gép ugyanazon a Rackforest telephelyen — telephely-halál ellen nincs
védelem. `restic copy` külső célra (másik szolgáltató vagy otthoni gép).

- Forrás: [ADR-0008](adr/0008-dedikalt-backup-vps-restic-append-only.md),
  [services/backup/RUNBOOK.md](../services/backup/RUNBOOK.md) (Ismert korlát)

## 4. Runbook-takarítás: VPN-first átírás az átállás zárása után

A Dokploy és Forgejo RUNBOOK ma callout-mintával él: a törzsszöveg még a
publikus (átállás előtti) világot írja le, a „VPN-világ" blokk mondja meg,
mit hagyj ki. Az átállás záró állapot-ellenőrzése után a friss provisionálás
legyen a fő szöveg: legacy lépések (publikus DNS, LE HTTP cert, `domain`
fázis) törlése (a git history őrzi), callout-blokkok ki. Ugyanekkor
törölhető a CONTEXT.md „DNS-polling guard" szócikke, és átnézendő a
provision script legacy `domain` fázisának sorsa.

- Forrás: [services/dokploy/RUNBOOK.md](../services/dokploy/RUNBOOK.md),
  [services/forgejo/RUNBOOK.md](../services/forgejo/RUNBOOK.md),
  [runbooks/vpn-atallas.md](runbooks/vpn-atallas.md) (záró állapot-ellenőrzés)
- Addig: a callout-minta a valóságot dokumentálja — nem nyúlunk hozzá.

## 5. Szerver node-key lejárat: eldöntendő eljárás

A headscale RUNBOOK 5. lépése feltételesen fogalmaz („ha a verzió
támogatja”) a szerver-node-ok kulcslejáratának kikapcsolásáról. A telepített
headscale-verzión (0.29) ki kell próbálni az `expire --expiry 0` utat, és a
runbookba a működő eljárást beírni — különben 90 naponta kézzel kell minden
szerver-node-ot újra beléptetni.

- Forrás: [services/headscale/RUNBOOK.md](../services/headscale/RUNBOOK.md) 5. lépés
