# Kétszintű hálózat: platform belső forgalma privát L2-n, beléptető réteg dedikált VPS-en

A szerver↔szerver forgalom (Dokploy → remote serverek SSH-ja, runner → Forgejo, mentések) a Rackforest projekt-szintű **privát L2** hálózatán megy RFC 1918 címeken, nem a tailneten: a platform belső működése (deploy, CI, health check) így nem függ a VPN-rétegtől — a Headscale kiesése csak az emberi hozzáférést állítja meg, a platformot nem. Az ember → szerver forgalom a tailneten megy, tailscaled fut mind a négy platform-gépen. A **beléptető réteg** (Headscale + Pocket ID + tailnet-resolver) egy dedikált `PTE-Headscale` VPS-en fut, cloud-inittel provisionálva, NEM Dokploy alatt: _a platform függhet a beléptető rétegtől, de a beléptető réteg nem függhet a platformtól_ — különben a „VPN leállt” hibát a VPN mögé zárt eszközzel kellene javítani (az ADR-0003 önhivatkozási holtpontjának hálózati megfelelője).

## Considered Options

- **Minden forgalom a tailneten** (szerverek egymás közt is) — a platform belső működése a Headscale-től függene; break-glass szempontból elfogadhatatlan. Elvetve.
- **Subnet router** (egyetlen gateway hirdeti a privát hálózatot a tailnetbe, a platform-gépekre nem kell tailscale) — SPOF az összes emberi hozzáférésre, és a per-node ACL is elveszne. Elvetve.
- **Kétszintű modell** — elfogadva.

## Consequences

- A Dokploy a remote servereket a privát L2 címükön SSH-zza; a szerverek egymást `/etc/hosts`-ból (cloud-init) oldják fel (pl. `git.pte-dev.hu` → privát IP).
- A `PTE-Headscale` VPS nincs a privát L2-n — a platform belső forgalmához semmi köze. Ő maga tailnet-node (a tailnet-resolver és a mentés-push miatt).
- Egyetlen gép tailscale-hibája sosem teljes kizárás: a gép a többi felől privát L2-n SSH-zható, végső esetben Rackforest VNC.
- A meglévő gépeket kézzel kell a Rackforest privát hálózatra csatolni (runbook-lépés); minden gép egy projektben van, így ez lehetséges.
