# Platform Infrastructure

A PTE dev platform (Dokploy PaaS) provisioning és üzemeltetési infrastruktúrája. Rackforest VPS-eken futó Dokploy instance-t és az általa remote serverként kezelt gépeket (Forgejo, Forgejo Runner) írja le kódként.

## Language

**Provisioning flow**:
A cloud-init által első bootkor végrehajtott, felügyelet nélküli folyamat: Dokploy telepítés, admin bootstrap, hardening. (A domain + cert beállítás a VPN-átállás óta a vpn-átállás runbook lépése, nem a flow-é.)
_Avoid_: setup script, install flow

**Admin bootstrap**:
Az initial admin user gépi létrehozása a Dokploy sign-up endpointján, host-on generált jelszóval, közvetlenül a telepítés után.
_Avoid_: register, first user setup

**Credentials fájl**:
A hoston őrzött, csak root által olvasható fájl, ahová a provisioning flow a generált Dokploy admin jelszót írja; SSH-n olvasható ki. Pontos helye: services/dokploy/RUNBOOK.md.

**DNS-polling guard**:
A provisioning flow lépése, amely addig vár, amíg a `dokploy.pte-dev.hu` a VPS publikus IP-jére nem resolvál, és csak utána kéri a Let's Encrypt certet. A VPN-átállás óta csak a legacy `domain` fázis használja.

**Runbook**:
A provisioning flow-t körülvevő kézi lépések dokumentuma: admin jelszó kiolvasás, Mailjet SMTP beállítás, verifikáció. (Publikus DNS-lépése a VPN-átállás óta csak a beléptető réteg neveinek van; a platform-nevek DNS-e a tailnet-resolver dolga.)

**Panel domain**:
`dokploy.pte-dev.hu` — a Dokploy dashboard címe; csak a tailneten belül oldódik fel és érhető el (ADR-0004), a wildcard cert fedi.

**Platform email**:
`dokploy@pte-dev.hu` — minden Dokploy-hoz köthető email-identitás: admin user email, Let's Encrypt regisztráció (minden service certjéhez, a Forgejo-éhoz is), értesítések feladója. Bejövő: ImprovMX forward; kimenő: Mailjet SMTP.

**Remote server**:
Dokploy által SSH-n (a privát L2-n) kezelt további VPS (PTE-Forgejo, PTE-Forgejo-Runner-1, PTE-Shared, projekt-VPS-ek): a Dockert/Traefiket a Dokploy setup telepíti rá, a service-ek Dokploy compose-ként futnak rajta. Cloud-init az ilyen gépen minimál (ADR-0003).
_Avoid_: worker node, satellite server

**Forgejo bootstrap**:
A Forgejo VPS-en futó `forgejo-bootstrap.sh` — az első Dokploy deploy után, SSH-n futtatva hozza létre az initial admint (`forgejo-admin`) és regisztrálja a runner shared secretet. Idempotens; futtatása és a credentials-fájl helye: services/forgejo/RUNBOOK.md.

**Runner shared secret**:
A runner–Forgejo összekötés titka: a Forgejo bootstrap generálja és regisztrálja a Forgejo-oldalon, a runner Dokploy env-ből kapja. Mechanika és fájlhelyek: services/forgejo/RUNBOOK.md 7. lépés és services/forgejo-runner/RUNBOOK.md 3. lépés.
_Avoid_: registration token (az a lejáró, interaktív flow-é)

**Git domain**:
`git.pte-dev.hu` — a Forgejo címe; embernek a tailneten, szervernek a privát L2-n oldódik fel (ADR-0004, ADR-0005). A git SSH a host 2222-es portján él, a 22 az admin/Dokploy sshd-é; konvenció: konténer-SSH portok gépenként 2222-től felfelé.

**Registry**:
A platform docker registry-je: a Forgejo beépített OCI (package) registry-je, `git.pte-dev.hu/<owner>/<image>` címzéssel. Auth Forgejo-tokennel (a platform-identitáshoz kötve); a CI push és a Dokploy pull a privát L2-n megy. Külön registry-szolgáltatás nincs.
_Avoid_: külön registry VPS, Harbor

**Git email**:
`git@pte-dev.hu` — a Forgejo email-identitása: admin user email, kimenő levelek feladója (Mailjet, a platform API kulcsával). Bejövő: ImprovMX forward.

**Hálózati láthatatlanság**:
A platform biztonsági alapelve: egyetlen szolgáltatásnak sincs publikus portja — kifelé csak a beléptető réteg létezik, minden más a tailnet + privát L2 mögött van (ADR-0004).
_Avoid_: IP allowlist, zero trust

**Beléptető réteg**:
A `PTE-Headscale` VPS-en futó, szükségszerűen publikus komponensek (Headscale, Pocket ID, tailnet-resolver), amelyeken keresztül a csapat a platformra belép. A platform függhet tőle; ő a platformtól nem függhet (ADR-0005).
_Avoid_: VPN szerver

**Tailnet**:
A Headscale által koordinált privát mesh-hálózat: az ember → szerver forgalom útja. Belépés Tailscale klienssel, Pocket ID loginnal.

**Privát L2**:
A Rackforest projekt-szintű privát hálózata: a szerver ↔ szerver forgalom (Dokploy SSH, runner → Forgejo, mentések) útja — a beléptető réteg kiesésekor is működik (ADR-0005).
_Avoid_: belső VLAN

**Platform-identitás**:
A Pocket ID-ban vezetett egyetlen, passkey-alapú user-adatbázis: a tailnet-belépés és a Forgejo login közös forrása (ADR-0006). Egy embert egy helyen veszünk fel és egy helyen tiltunk le.
_Avoid_: Forgejo user mint identitásforrás

**VPN domain**:
`vpn.pte-dev.hu` — a Headscale publikus címe; a két publikus kivétel egyike.

**Identitás domain**:
`id.pte-dev.hu` — a Pocket ID publikus címe; a másik publikus kivétel.

**Háromszintű ACL**:
Az admin / dev / guest hozzáférési csoportok a repóban verziózott headscale policy fájlban. Dokploy panel és SSH: csak admin; guest: csak a meghívott projekt-VPS(ek) — a guest-hozzáférés projekt-szintű (ADR-0009).

**Wildcard cert**:
DNS-01 challenge-dzsel (deSEC-be delegálva) szerzett Let's Encrypt cert (ADR-0007): az infra-gépeken `*.pte-dev.hu`, a projekt-VPS-eken a projekt-zóna három env-wildcardja egy certben (ADR-0009); új appnak nincs cert-teendője.
_Avoid_: per-app cert

**Tailnet-resolver**:
A beléptető rétegen futó dnsmasq: a tailnet-klienseknek projektenként egy wildcard-sorral a projekt-VPS-re oldja fel a projekt-zónát, explicit kivételekkel az infra-nevekre (git, dokploy, backup) és a beléptető réteg publikus neveire (vpn, id) (ADR-0007, ADR-0009).
_Avoid_: MagicDNS extra_records

**MagicDNS-domain**:
`ts.pte-dev.hu` — a headscale MagicDNS base_domainje: minden tailnet-node automatikus neve `<node>.ts.pte-dev.hu`. Csak a tailneten belül létezik; a szolgáltatásnevek nem ezt használják, hanem a tailnet-resolvert.

**Projekt-VPS**:
`PTE-<Projekt>` — egy app-projekt dedikált Dokploy remote servere, rajta a projekt mindhárom környezete; minden app-projekt már az indulástól saját VPS-t kap (ADR-0009). A Dokploy gépen app nem fut.
_Avoid_: app-szerver, PTE-Apps-1

**Shared gép**:
`PTE-Shared` — a csapat saját belső tooljainak gépe, a saját infra része (zónája: `shared.pte-dev.hu`); technikailag a projekt-sablonnal jön létre, de nem app-projekt, guest sosem éri el (ADR-0009).
_Avoid_: közös projekt

**Projekt-zóna**:
A `<projekt>.pte-dev.hu` névtér env-zónákkal — prod: `<app>.`, staging: `<app>.staging.`, preview: `pr<N>-<app>.preview.` —; egyetlen resolver-sor és egy három env-wildcardos zóna-cert fedi az egészet (ADR-0009).

**Backup gép**:
`PTE-Backup` — a platformtól független (nem Dokploy alatti) VPS, restic rest-serverrel append-only módban; a beléptető réteg dumpjainak és később minden platform-mentésnek a célja (ADR-0008).

**Break-glass**:
Az adminisztrációs menekülőút a beléptető réteg kiesésekor: Rackforest VNC konzol + SSH a szomszéd gépről a privát L2-n.

**Offboarding**:
Távozó tag hozzáférés-visszavonása: letiltás a Pocket ID-ban + headscale node expire. Runbook-lépés; formális audit-kényszer nincs.

**Utólagos konfiguráció**:
Cloud-init-módosítás kézi átvezetése élő gépen SSH/VNC-n (a cloud-init csak első bootkor fut). A cloud-init fájl ilyenkor is frissül a repóban, és minden módosításhoz drift-napló bejegyzés jár (docs/runbooks/utolagos-konfiguracio.md).
_Avoid_: kézi hack, hotfix a szerveren
