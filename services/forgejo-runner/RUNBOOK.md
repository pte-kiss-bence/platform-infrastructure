# Runbook — Forgejo Runner provisioning (Dokploy remote server)

A [cloud-init.yaml](cloud-init.yaml) és a [docker-compose.yml](docker-compose.yml) körüli kézi lépések. Előfeltétel: a Forgejo már fut és a bootstrap lefutott — [../forgejo/RUNBOOK.md](../forgejo/RUNBOOK.md) 1–7. lépés (onnan jön a `RUNNER_SECRET` és `RUNNER_UUID`).

Kapcsolódó döntések: [ADR-0002](../../docs/adr/0002-nincs-secret-a-cloud-init-user-databan.md), [ADR-0003](../../docs/adr/0003-forgejo-dokploy-remote-serverkent.md).

> **VPN-világ (ADR-0004–0009):** a runner a `git.pte-dev.hu`-t a privát L2-n
> éri el (`/etc/hosts`), a gép a tailneten is node, publikus portja nincs — a
> hálózati bekötés lépései: [docs/runbooks/vpn-atallas.md](../../docs/runbooks/vpn-atallas.md).

## 1. VPS létrehozás

Rackforest panelben: **Ubuntu 24.04 LTS**, minimum **2 vCPU / 4 GiB RAM / 40 GB SSD** — a CI build-sebessége itt múlik a vCPU-n, a DinD image-cache a disken. User-data: `services/forgejo-runner/cloud-init.yaml` változtatás nélkül.

**SSH kulcsmezőbe KÉT kulcs**: a sajátod ÉS a Dokploy public kulcsa (ugyanaz, mint a Forgejo VPS-nél).

DNS rekord nem kell — a runner kifelé csatlakozik a `git.pte-dev.hu`-ra, bejövő forgalma nincs.

## 2. Remote server felvétele Dokploy-ban

Dokploy UI → **Servers → Add Server**: név `PTE-Forgejo-Runner-1`, IP, port 22, user `root`, a meglévő Dokploy SSH kulccsal. **Setup Server**, várd meg a zöldet.

## 3. Runner compose deploy

Dokploy UI → projekt → **Create Service → Compose**, szerver: `PTE-Forgejo-Runner-1`, provider: **Raw**, compose típus: **Docker Compose** (NE Stack — Swarm módban a `runner-init` `service_completed_successfully` feltétele némán elveszne). Illeszd be a [docker-compose.yml](docker-compose.yml) tartalmát. **Environment** fülre a Forgejo VPS `/root/forgejo-runner-secret` fájljából:

```
RUNNER_SECRET=<secret sor>
RUNNER_UUID=<uuid sor>
FORGEJO_L2_IP=<a Forgejo VPS privát L2 IP-je>
```

A `FORGEJO_L2_IP` a konténer-szintű névfeloldáshoz kell: a dind/runner
konténerek és a job-konténerek NEM öröklik a host `/etc/hosts`-át, a
compose `extra_hosts` + a runner-config `--add-host` ebből az env-ből kapja
a `git.pte-dev.hu` L2 címét (git clone és registry push/pull a CI-ból).

**Deploy**. A `runner-init` egyszer lefut (configot ír), a `runner` és `docker-in-docker` marad futva.

## 4. Verifikáció

Forgejo UI: admin → **Site Administration → Actions → Runners** — `pte-runner-1` **Idle**, labelek: `ubuntu-latest`, `ubuntu-22.04`.

Próba-workflow egy tetszőleges repóban (`.forgejo/workflows/ci.yml`):

```yaml
on: [push]
jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - run: echo "runner OK"
```

## Frissítés

Egyszerűbb, mint a Forgejo-nál — a runnernek nincs megőrzendő állapota a regisztráción túl:

- **Runner** (major-pin `runner:12`): patch/minor = Dokploy **Redeploy**. Major váltásnál (13 megjelenésekor): tag átírás a repo compose-ban → beillesztés → Redeploy. A `runner-data` volume (config + secret) megmarad, újraregisztráció NEM kell. Release notes: <https://code.forgejo.org/forgejo/runner/releases>.
- **Backup nem kell** — worst case a volume eldobható és a runner újraköthető a meglévő secrettel (lásd Hibaelhárítás).
- **Job image-ek** (catthehacker): a DinD magától pullolja a frissebbet, ha a tag mozog; kényszerített frissítés: `docker exec <dind cid> docker pull ghcr.io/catthehacker/ubuntu:act-24.04`.
- Szerver–runner verzió nincs mereven csatolva (Forgejo 15 ↔ runner 12 a dokumentált páros), de Forgejo major-frissítés után nézd meg a runner release notes-t, van-e ajánlott minimum.

## Hibaelhárítás

- **Runner nem jelenik meg / Offline** — runner konténer logja Dokploy-ban. Tipikus: rossz `RUNNER_SECRET`/`RUNNER_UUID` páros. Javítás után: a config csak első indításkor íródik — töröld a régit és redeployolj:
  ```bash
  docker exec <runner-init vagy runner cid> rm /data/runner-config.yml
  ```
  majd Dokploy **Redeploy**. (Vagy a `runner-data` volume törlése.)
- **Secret újragenerálás** — a Forgejo VPS-en töröld a `/root/forgejo-runner-secret` fájlt, futtasd újra a `forgejo-bootstrap.sh`-t (új secretet regisztrál ugyanarra a runner-névre), majd frissítsd a Dokploy env-et és a fenti config-törlés + redeploy.
- **Job docker parancsot futtatna és nem éri el a daemont** — a jobon belüli docker-használathoz plusz config kell (`container.docker_host`, `--add-host`): forgejo.org/docs → admin/actions/docker-access. Alap build/test jobokhoz nem kell.
- **DinD disk telik** — `docker exec <dind cid> docker system prune -af` vagy a `dind-data` volume ürítése; a job-image-ek cache-e ott gyűlik.
