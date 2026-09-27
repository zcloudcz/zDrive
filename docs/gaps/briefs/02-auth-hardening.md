# Zadání 02: Zpevnění přihlášení

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, migrace přes
> `--startup-project src/services/Api`, komunikace česky, kód anglicky.
> Pokud je něco v zadání nejasné nebo neodpovídá kódu, zastav se a zeptej se.

## Cíl

Tři konkrétní díry v přihlašování:

1. **Rate limit `/auth/**` je jeden sdílený bucket pro všechny.** Politika
   „auth" (`src/services/ApiGateway/Program.cs:102-110`, fixed window 20/min)
   partitionuje podle `RemoteIpAddress`. `UseForwardedHeaders` ale zapojené
   není, takže za Azure ingressem mají všichni klienti stejnou IP.
   Poznámka v `RateLimiterPartitioning.cs:18-24` to přiznává. Politika
   `publicShare` už bere nejpravější položku `X-Forwarded-For` (ř. 53).
2. **Chybí limit pokusů na účet.** Nic nebrání pomalému brute-force hesla
   jednoho účtu z více IP.
3. **Refresh tokeny nemají detekci znovupoužití.**
   `RefreshTokenCommandHandler.cs:22-63` rotuje (revoke + `ReplacedByToken`),
   ale když přijde již revokovaný token, jen ho odmítne. Ukradený token
   použitý po legitimním se nepozná jako krádež.

## Rozsah

1. **Partitioning politiky auth:** použij stejné pravidlo jako `publicShare`
   (nejpravější `X-Forwarded-For` od důvěryhodného proxy), ideálně
   sdílenou metodou. Proč byla „auth" dřív záměrně ponechána, zjisti
   z komentářů a z historie (`git log -p -- src/services/ApiGateway/RateLimiterPartitioning.cs`).
   Pokud najdeš důvod, který tomu brání, zastav se a napiš ho.
2. **Lockout na účet:** po N neúspěšných pokusech (výchozí 10 za 15 min,
   konfigurovatelné v `appsettings`) dočasně odmítat login pro daný e-mail.
   Odpověď musí být nerozlišitelná od špatného hesla, aby nešlo zjistit,
   které účty existují (dnes 404). Úspěšný login počitadlo nuluje. Počítat
   i neexistující e-maily, ať časování neprozradí existenci účtu. Stav
   ulož do Postgresu (schéma `auth`), Redis zatím není v deployi.
3. **Detekce znovupoužití refresh tokenu:** přijde-li token, který už byl
   rotovaný (`ReplacedByToken != null`), revokuj celou rodinu, tj. řetězec
   `ReplacedByToken` od něj dál, a vrať 401. Pozor na souběh: dva
   paralelní refreshe téhož tokenu z jednoho klienta (Flutter
   `auth_interceptor`) nesmí odhlásit legitimního uživatele. Prozkoumej,
   jestli se to v klientovi může stát (`lib/core/network/auth_interceptor.dart`).
   Pokud ano, navrhni krátké grace okno (např. 10 s), kdy se vrátí stejný
   nástupnický token.
4. Pokud už je hotové zadání 01 (2FA), lockout se vztahuje i na špatné
   TOTP kódy ve `/auth/login/2fa`.

## Mimo rozsah

CAPTCHA, e-mailová upozornění (e-mail zatím neexistuje), Redis.

## Akceptační kritéria

- [ ] Test `RateLimiterPartitioningTests`: dva různé `X-Forwarded-For` =
      dva různé buckety pro auth.
- [ ] Integrační test: 10 špatných hesel → 11. pokus se správným heslem
      odmítnut stejnou odpovědí. Po uplynutí okna projde.
- [ ] Integrační test: refresh A→B, pak znovu A → 401 a B je revokovaný.
- [ ] Test souběžného refreshe podle zvoleného řešení.
- [ ] Všechny existující testy zelené (`dotnet test`, `flutter test`).

## Výstup

Jeden PR. V popisu uveď nové konfigurační klíče a jejich výchozí hodnoty.
