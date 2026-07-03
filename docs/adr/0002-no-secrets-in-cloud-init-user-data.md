# Nincs secret a cloud-init user-data-ban

A cloud-init user-data plaintextben látható a Rackforest panelben és a VPS metadata service-ében, ezért oda semmilyen secret (admin jelszó, SMTP/Mailjet kulcs) nem kerülhet. Az admin jelszót a provisioning flow a hoston generálja (`openssl rand`) és a `/root/dokploy-admin-credentials` fájlba írja; a Mailjet SMTP beállítás kézi, UI-ból történik első belépés után, mert külső, hosszú életű secretet gépi úton csak a metadata-n keresztül tudnánk bejuttatni.

## Consequences

- Két kézi runbook-lépés marad: admin jelszó kiolvasása SSH-n, és SMTP konfiguráció a UI-ban.
- A user-data szabadon verziózható a repóban, placeholder csak az SSH public kulcs.
