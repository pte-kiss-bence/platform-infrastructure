# Platform Infrastructure

A PTE dev platform (Dokploy PaaS) provisioning és üzemeltetési infrastruktúrája. Egyetlen Rackforest VPS-en futó Dokploy instance-t ír le kódként.

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
`dokploy@pte-dev.hu` — minden Dokploy-hoz köthető email-identitás: admin user email, Let's Encrypt regisztráció, értesítések feladója. Bejövő: ImprovMX forward; kimenő: Mailjet SMTP.
