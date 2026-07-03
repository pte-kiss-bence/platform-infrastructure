# Platform Infrastructure

A PTE dev platform (Dokploy PaaS) provisioning és üzemeltetési infrastruktúrája. Rackforest VPS-eken futó Dokploy instance-t és az általa remote serverként kezelt gépeket (Forgejo, Forgejo Runner) írja le kódként.

## Language

**Provisioning flow**:
A cloud-init által első bootkor végrehajtott, felügyelet nélküli folyamat: Dokploy telepítés, admin bootstrap, domain + cert beállítás, hardening.
_Avoid_: setup script, install flow

**Admin bootstrap**:
Az initial admin user gépi létrehozása a Dokploy sign-up endpointján, host-on generált jelszóval, közvetlenül a telepítés után.
_Avoid_: register, first user setup

**Credentials fájl**:
A `/root/dokploy-admin-credentials` (0600) fájl, ahová a provisioning flow a generált admin jelszót írja; SSH-n olvasható ki.

**DNS-polling guard**:
A provisioning flow lépése, amely addig vár, amíg a `dokploy.pte-dev.hu` a VPS publikus IP-jére nem resolvál, és csak utána kéri a Let's Encrypt certet.

**Runbook**:
A provisioning flow-t körülvevő kézi lépések dokumentuma: DNS rekord felvitel, admin jelszó kiolvasás, Mailjet SMTP beállítás, verifikáció.

**Panel domain**:
`dokploy.pte-dev.hu` — a Dokploy dashboard publikus címe, Let's Encrypt certtel.

**Platform email**:
`dokploy@pte-dev.hu` — minden Dokploy-hoz köthető email-identitás: admin user email, Let's Encrypt regisztráció (minden service certjéhez, a Forgejo-éhoz is), értesítések feladója. Bejövő: ImprovMX forward; kimenő: Mailjet SMTP.

**Remote server**:
Dokploy által SSH-n kezelt további VPS (PTE-Forgejo, PTE-Forgejo-Runner): a Dockert/Traefiket a Dokploy setup telepíti rá, a service-ek Dokploy compose-ként futnak rajta. Cloud-init az ilyen gépen minimál (ADR-0003).
_Avoid_: worker node, satellite server

**Forgejo bootstrap**:
A Forgejo VPS-en futó `forgejo-bootstrap.sh` — az első Dokploy deploy után, SSH-n futtatva hozza létre az initial admint (`forgejo-admin`, credentials: `/root/forgejo-admin-credentials`) és regisztrálja a runner shared secretet. Idempotens.

**Runner shared secret**:
A runner–Forgejo összekötés 40 hex karakteres titka: a bootstrap generálja és `forgejo-cli actions register`-rel regisztrálja, a runner Dokploy env-ből (`RUNNER_SECRET` + `RUNNER_UUID`) kapja. Fájl: `/root/forgejo-runner-secret`.
_Avoid_: registration token (az a lejáró, interaktív flow-é)

**Git domain**:
`git.pte-dev.hu` — a Forgejo publikus címe. Git SSH a host 2222-es portján (`ssh://git@git.pte-dev.hu:2222/...`); a 22 az admin/Dokploy sshd-é. Konvenció: konténer-SSH portok gépenként 2222-től felfelé.

**Git email**:
`git@pte-dev.hu` — a Forgejo email-identitása: admin user email, kimenő levelek feladója (Mailjet, a platform API kulcsával). Bejövő: ImprovMX forward.
