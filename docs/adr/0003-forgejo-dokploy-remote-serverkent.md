# Forgejo és Runner Dokploy remote serverként, raw compose-zal

A Forgejo (git.pte-dev.hu) és a Forgejo Runner egy-egy dedikált Rackforest VPS-en fut, de a telepítés gazdája NEM a cloud-init, hanem a meglévő Dokploy: mindkét gép Dokploy **remote server**, a Dockert/Traefiket a Dokploy setup telepíti, a Forgejo és a runner Dokploy **compose service**. A cloud-init mindkét gépen minimál (hostname, SSH hardening, a Forgejo gépen plusz a bootstrap script kiírása) — így a deploy, redeploy, log, domain és cert egységesen Dokploy-ból megy, és nem duplikáljuk a Dokploy-gép provisioning flow-ját.

A compose fájlok Dokploy-ba **raw beillesztéssel** kerülnek, nem git-forrásként: hosszú távon minden repo a Forgejo-ra költözik, és a git-szervert nem szabad saját magából deployolni — Forgejo-leálláskor a Dokploy nem tudná pullolni a compose-t, amivel a Forgejo-t helyre kellene állítani (önhivatkozási holtpont).

Gépi bootstrap a Dokploy-mintára (ADR-0001 szellemében, de dokumentált felülettel): az initial admint a `forgejo-bootstrap.sh` hozza létre `forgejo admin user create`-tel, a runnert a dokumentált, idempotens shared-secret regisztráció köti be (`forgejo-cli actions register` + a secret a runner configjában). Secretek helye: hoston generált fájlok (`/root/forgejo-*`) és Dokploy env — cloud-init user-datába semmi (ADR-0002).

## Consequences

- Kézi lépések: Dokploy SSH kulcs public fele a Rackforest panelbe második kulcsként; remote server felvétel + setup; compose beillesztés env-ekkel; bootstrap script futtatása SSH-n; secret/uuid átmásolása a runner env-be.
- Compose-módosításnál a repo a forrás-igazság, de Dokploy-ba kézzel kell újra beilleszteni — tudatos ár az önhivatkozási holtpont elkerüléséért.
- A CI jobok DinD-ben futnak a runner gépen, a Dokploy által kezelt host Dockerhez nem érnek hozzá.
- Git SSH a host 2222-n (a 22 az admin/Dokploy sshd-é); konvenció: konténer-SSH portok gépenként 2222-től.
