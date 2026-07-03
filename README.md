# platform-infrastructure

A PTE dev platform infrastruktúrája kódként: Dokploy PaaS, Forgejo + runner,
Headscale VPN és backup — Rackforest VPS-eken. Cloud-init fájlok, compose-ok,
runbookok és döntések laknak itt; a forrás-igazság ez a repo.

**Állapot**: a VPN-átállás (hálózati láthatatlanság, ADR-0004–0009)
folyamatban van — a vezérfonal a
[docs/runbooks/vpn-atallas.md](docs/runbooks/vpn-atallas.md).

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
