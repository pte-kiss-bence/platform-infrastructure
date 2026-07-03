# Automatizált Dokploy admin létrehozás sign-up API-n keresztül

A Dokploy első admin usere alapból kézzel, a `:3000/register` web UI-n jön létre — amíg ez nem történik meg, bárki, aki eléri a portot, admint regisztrálhat magának. Úgy döntöttünk, hogy a cloud-init flow a telepítés után azonnal, gépi úton hozza létre az admint a Dokploy (better-auth alapú) sign-up endpointján keresztül, így a nyitott regisztrációs ablak másodpercekre csökken, és minden további konfiguráció (domain, cert, SMTP) API-ból végezhető.

## Considered Options

- **Manuális első regisztráció** — egyszerűbb, de a regisztrációs ablak addig nyitva marad, amíg valaki oda nem ér böngészővel, és a downstream setup is kézi marad. Elvetve.
- **Automatizált sign-up API hívás** — elfogadva.

## Consequences

- A sign-up endpoint nem hivatalosan dokumentált API-felület; Dokploy verzióváltásnál törhet. A hívást a cloud-init scriptben verzió-pinneléssel és explicit hibajelzéssel kell védeni.
