# Pocket ID az egyetlen identitásforrás

Az egyetemi Entra ID identitásforrásként nem elérhető (nincs app-regisztrációs jogunk), a kézenfekvő „Forgejo mint OIDC provider” pedig onboarding-holtpontos: az új tag a tailnetbe OIDC loginnal lépne be, de a login-oldal (a Forgejo) a VPN mögött van, ahová csak a login után jutna el. Ezért az identitásforrás egy dedikált, **publikus**, passkey-alapú **Pocket ID** (`id.pte-dev.hu`) a `PTE-Headscale` VPS-en: a headscale és a Forgejo is ebből authentikál OIDC-vel. Így egyetlen user-adatbázis van — egy embert egy helyen veszünk fel és egy helyen tiltunk le; az offboarding (Pocket ID letiltás + `headscale nodes expire`) a VPN-t és a gitet egyszerre vonja vissza.

## Consequences

- A Dokploy panel loginja lokális email + jelszó (+ 2FA) marad: a Dokploy SSO-ja enterprise-only, open source elvárás mellett nem opció. Védelme a hálózati ACL (csak admin-gépről érhető el); a panel-user 2–3 fő, kézi kezelésük nem teher.
- A `forgejo-admin` lokális fiók megmarad fallbacknek: a beléptető réteg kiesésekor a Forgejo-ba lokálisan be lehet lépni.
- Passkey-only login, jelszavas út nincs. Ha valaha mégis kellene, a jelölt (Kanidm/authentik) mindkettő nehezebb üzemeltetni — tudatos ár.
- A `PTE-Headscale` VPS az emberi hozzáférés SPOF-ja: headscale + Pocket ID + tailnet-resolver egy gépen. Mentése és helyreállítása: ADR-0008.
- Offboarding: runbook-lépés; formális audit-/szabályzati kényszer nincs.
