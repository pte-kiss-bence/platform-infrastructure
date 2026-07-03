# Runbook — Utólagos konfiguráció élő gépen (cloud-init drift)

A cloud-init **csak az első bootkor fut** — élő gépen soha többé. A konvenció
ettől függetlenül: **a repo cloud-init fájljai mindig a friss célállapotot
írják le** (újra-provisionáláskor egy friss gép kézi lépés nélkül álljon
elő), tehát ha egy változtatás cloud-initet érint, a fájlt akkor is
frissítjük, ha az élő gépeken ugyanazt kézzel kell átvezetni.

Ebből következik a szabály: **minden cloud-init-módosításhoz tartozik egy
utólagos alkalmazási bejegyzés** a lenti drift-naplóban — mit kell az élő
gép(ek)en SSH/VNC-n keresztül elvégezni, hogy a valóság utolérje a kódot.
A napló bejegyzése akkor törölhető, ha minden érintett élő gépen megtörtént
az átvezetés, VAGY a gépet azóta újra-provisionálták.

## Fordítási szabályok (cloud-init elem → élő gépi parancs)

| cloud-init elem     | Élő gépen ugyanez                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `packages`          | `apt-get update && apt-get install -y <csomag>`                                                                                 |
| `write_files`       | a fájl létrehozása azonos tartalommal, jogokkal és tulajdonossal (`install -m <mód> -o <owner>` vagy `umask` + `chmod`/`chown`) |
| `runcmd`            | a parancs egyszeri futtatása SSH-n (figyelj: idempotens-e?)                                                                     |
| `hostname`          | `hostnamectl set-hostname <név>` (utólag ritkán kell)                                                                           |
| sshd config snippet | fájl a `/etc/ssh/sshd_config.d/` alá + `systemctl restart ssh`                                                                  |
| systemd unit/timer  | fájl a `/etc/systemd/system/` alá + `systemctl daemon-reload` (+ `enable --now`, ha a runbook úgy mondja)                       |

Átvezetés után **mindig verifikálj** ugyanúgy, ahogy a cloud-init utáni
runbook-lépés tenné (státusz-fájl, `docker compose ps`, curl, `ufw status`).

## Hozzáférési utak élő géphez

Fontossági sorrendben:

1. **SSH a tailneten** (admin ACL) — a normál út.
2. **SSH a privát L2-n** a szomszéd gépről — ha az adott gép tailscale-je
   halott (ADR-0005).
3. **Rackforest VNC konzol** — végső break-glass, hálózattól független.
   Figyelem: a konzolos belépéshez **jelszó kell** (az SSH-kulcs ott nem
   segít). Ha a gépen nincs használható root/konzol-jelszó, első adandó
   alkalommal állíts be egyet (`passwd`) és tedd jelszókezelőbe — a VNC-út
   enélkül csak recovery-módban használható.

## Drift-napló

> Formátum: dátum · érintett cloud-init · mi változott a kódban · mit kell
> az élő gép(ek)en futtatni · mikor törölhető.

### 2026-07-03 — VPN-átállás (minden gép)

A teljes VPN-átállás maga egy nagy utólagos konfiguráció — az élő gépekre
vonatkozó minden lépését a [vpn-atallas.md](vpn-atallas.md) fedi (privát L2,
tailscale telepítés, /etc/hosts, Traefik wildcard, tűzfal + DOCKER-USER).
Külön kiemelendő driftek, amiket a cloud-initek már tartalmaznak, az élő
gépek viszont nem:

| Gép                                            | Drift a kódban                                                                                           | Élő gépen                                                                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| PTE-Dokploy, PTE-Forgejo, PTE-Forgejo-Runner-1 | `packages: ufw`                                                                                          | `apt-get update && apt-get install -y ufw` — a vpn-átállás 9. fázisa előtt                                                                                                                                                                                                                                                                                                                       |
| PTE-Dokploy                                    | a `dokploy-provision.sh` új változata: az `all` fázis az admin bootstrapnél megáll, új `close3000` fázis | a script cseréje a repóból: másold be a [cloud-init.yaml](../../services/dokploy/cloud-init.yaml) `dokploy-provision.sh` blokkjának tartalmát a `/usr/local/sbin/dokploy-provision.sh`-ba (0700, root) — **vagy** a `close3000` kiváltása közvetlenül: `docker service update --publish-rm published=3000,target=3000,protocol=tcp,mode=host dokploy && ss -tln \| grep 3000` (üres kell legyen) |

Törölhető: ha a vpn-átállás záró állapot-ellenőrzése zöld.
