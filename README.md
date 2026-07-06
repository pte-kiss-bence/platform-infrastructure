# platform-infrastructure

A PTE dev platform infrastruktúrája kódként: Dokploy PaaS, Forgejo + runner,
Headscale VPN és backup — Rackforest VPS-eken. Cloud-init fájlok, compose-ok,
runbookok és döntések laknak itt; a forrás-igazság ez a repo.

**Állapot**: a VPN-átállás hálózati része kész (ADR-0004–0009;
[vpn-atallas](docs/runbooks/vpn-atallas.md) 0–10. fázis, a backup-lépések
kivételével); az onboarding folyamatban (az első tag sikeresen fent). Hátra:
a PTE-Backup gép felhúzása és a mentés-élesítés (3. fázis backup-lépése +
11. fázis), utána a záró állapot-ellenőrzés. Részletek:
[docs/backlog.md](docs/backlog.md).

## Térkép

| Mit keresel                               | Hol                                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------------- |
| Fogalomtár (a beszélt nyelv)              | [CONTEXT.md](CONTEXT.md)                                                         |
| Hogyan működik az egész (ábrákkal)        | [docs/architektura.md](docs/architektura.md)                                     |
| Miért így döntöttünk                      | [docs/adr/](docs/adr/)                                                           |
| Egy szolgáltatás telepítése, üzemeltetése | `services/<szolgáltatás>/RUNBOOK.md`                                             |
| Tűzfal-zárás közös receptje               | [docs/runbooks/tuzfal-zaras.md](docs/runbooks/tuzfal-zaras.md)                   |
| Élő gép ≠ repo (drift) kezelése           | [docs/runbooks/utolagos-konfiguracio.md](docs/runbooks/utolagos-konfiguracio.md) |
| Nyitott feladatok                         | [docs/backlog.md](docs/backlog.md)                                               |
