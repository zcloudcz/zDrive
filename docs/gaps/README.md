# Analýza nedostatků zDrive a zadání pro implementaci

**Datum:** 2026-09-27
**Vychází z:** [`docs/competitive-analysis.md`](../competitive-analysis.md), kap. 6, a z průzkumu kódu na `3533755`

Tento dokument rozebírá nedostatky, které analýza konkurence označila za
blokující, a to podle skutečného stavu kódu. Ke každému nedostatku, který lze
implementovat bez dalšího lidského rozhodnutí, je v [`briefs/`](briefs/)
samostatné zadání. Je psané tak, aby se dalo celé vložit jako první zpráva
nové session s modelem Sonnet.

---

## 1. Opravy předchozí analýzy

Průzkum kódu ukázal, že dvě tvrzení v `competitive-analysis.md` byla
nadsazená. V tomto PR jsou opravená i tam.

- **Fotky nejsou „hotové, jen nenasazené".** `POST /photos/ingest` pouze
  vloží řádek `Photo`. Nečte EXIF, negeneruje miniatury, nemá AI ani
  background worker. Datum pořízení odhaduje regexem z názvu souboru
  (`IngestPhotoCommandHandler.cs`). Ingest nikdo nevolá, klient ani server.
  Endpoint `storage/thumbnail/{id}` jen skládá URL na neexistující
  `https://cdn.zdrive.io`.
- **Přímé sdílení uživateli neexistuje.** `Share.SharedWith` se uloží, ale nic
  ho nečte. Neexistuje dotaz „sdíleno se mnou", příjemce nemá přístupovou
  cestu a `PublicShareAccess.cs:43` takové sdílení u odkazu výslovně odmítá.

---

## 2. Nedostatky podle oblastí

### 2.1 Přihlášení a účty

| Zjištění | Kde | Dopad |
|---|---|---|
| Bez 2FA | `LoginCommandHandler.cs` vydá tokeny hned po ověření hesla | Neprojde bezpečnostní prověrkou, všichni konkurenti 2FA mají |
| Bez obnovy hesla | žádný endpoint, **žádné odesílání e-mailů v celém repu** | Zapomenuté heslo = ztracený účet |
| Rate limit `/auth/**` je jeden sdílený bucket | `RateLimiterPartitioning.cs:18-31`, `UseForwardedHeaders` není zapojené | Za ingressem sdílí 20 req/min všichni klienti: jeden útočník zablokuje přihlášení všem |
| Bez limitu pokusů na účet | — | Brute-force hesel jednoho účtu omezuje jen sdílený limit |
| Refresh tokeny bez detekce znovupoužití | `RefreshTokenCommandHandler.cs:22-63` | Ukradený refresh token lze používat souběžně s legitimním |
| Entra SSO | kód hotový (#70, #72, #74), `Entra:Enabled=false` | Chybí **lidské kroky**: produkční app registrace a přidání platformy „Mobile and desktop" (ADR 0002 krok 1, ADR 0003) |

### 2.2 Náhledy souborů

| Zjištění | Kde |
|---|---|
| Klepnutí na soubor ho rovnou stáhne, jiná akce neexistuje | `file_browser_page.dart:494-500` |
| Klient nemá žádný image, PDF ani video balíček | `pubspec.yaml` |
| Stahování jde přes manifest + ověřené chunky (`assembleVerifiedFileStream`), vždy s JWT hlavičkou | `file_upload_data_source.dart:205-410` |
| Neexistuje URL použitelná v `<img>`/`<video>` bez hlavičky; SAS URL nejdou z prohlížeče kvůli CORS na Blob | `StorageController.cs:82-129` |
| Chybí HTTP Range i streamování celého souboru s content-type | `DownloadChunkQueryHandler` |
| **Klient při uploadu neposílá `mimeType`**, v DB je většinou `null` | `file_repository_impl.dart:278-284` |

Závěr: obrázky, text a PDF lze zobrazovat čistě na klientovi přes existující
stahování do paměti (s limitem velikosti). Video potřebuje nový
streamovací endpoint s Range (token v query schválen, viz 3.2).

### 2.3 Desktop (Windows a macOS)

| Zjištění | Kde |
|---|---|
| Cloud-only položka nemá na disku **nic**, ani placeholder | `pull_sync_service.dart:63-69` |
| Žádný nativní kód kromě tray a kanálu `quit`, žádné FFI | `windows/runner/*` |
| Windows instalátor je IExpress (bez MSIX, bez identity balíčku) a cesta k exe se mění s každou verzí | `packaging/windows/*` |
| **macOS release nemá `network.client` entitlement**, sandboxovaná aplikace nemůže volat API | `macos/Runner/Release.entitlements` |
| macOS nemá security-scoped bookmarky, po restartu ztratí přístup ke sync složce | žádný kód, cesta je jen string v Hive |
| macOS nemá tray a končí po zavření okna | `AppDelegate.swift:6-8` |
| CI nebuilduje macOS desktop, nemá podpis ani notarizaci | `release-clients.yml` |
| Linux target v Flutter projektu vůbec není | — |

Placeholdery ve Windows (Cloud Files API) jsou technicky nejrizikovější
položka: nativní C++ plugin, registrace sync root bez identity balíčku a
přeregistrace při každém updatu. Zadání je proto formulované jako **spike
+ ADR**, ne jako plná implementace.

### 2.4 Fotky

| Zjištění | Kde |
|---|---|
| PhotoService má jen DB model a CRUD, bez EXIF, miniatur a workeru | `ZDrive.PhotoService.*` |
| Nemá závislosti na blob, message bus ani AI, stačí DB + JWT klíč | `PhotoService.Api/Program.cs` |
| Produkce = 2 App Service (`zdrive-auth` s merged Api, `zdrive-gateway`), nasazované ručně ZIPem | `docs/plans/2026-09-22-merge-backend-services.md:545-583` |
| Gateway routuje `/photos`, `/albums`, `/memories` na `localhost:5105`, nasazené vrací 502 | `ApiGateway/appsettings.json:132-198` |
| Na mobilu neexistuje auto-backup kód | — |
| Change feed `GET /files/changes` (ADR 0001) existuje a hodí se jako zdroj ingestu | `docs/adr/0001-*` |

Doporučená cesta: PhotoService připojit do `ZDrive.Api` stejně jako
Auth, File, Storage a Sync (šetří App Service). Ingest řídit background
workerem nad change feedem, EXIF číst přes MetadataExtractor
(Apache-2.0) a miniatury dělat přes SkiaSharp (MIT). ImageSharp ne, protože
jeho Split License vyžaduje komerční licenci od určitého obratu.

### 2.5 Verze, sdílení, B2B

| Zjištění | Kde |
|---|---|
| Retence jen podle počtu (10), ne podle stáří | `CreateFileVersionCommandHandler.cs:90-104` |
| Kvóta počítá všechny verze **i koš** | `StorageQuota.cs:21-33` |
| Role (owner/admin/member/viewer) se **nikde nevynucují**, `ClaimsHelper.GetRole` nemá volající | `shared/ZDrive.Shared/Auth/ClaimsHelper.cs:20` |
| Každá registrace = nový tenant, soubory jsou per-user, ne per-tenant | `RegisterCommandHandler.cs:48` |
| Bez tenant/member endpointů, bez audit logu, bez EF global query filtrů (filtr ručně v handlerech) | — |

---

## 3. Rozhodnutí

Stav k 2026-09-27 po odpovědích vlastníka.

| # | Rozhodnutí | Stav | Dopad |
|---|---|---|---|
| 3.1 | Poskytovatel e-mailu | ✅ **MailNotify** (centrální služba ZCLOUD, `zcloudcz/MailNotify`) | [03](briefs/03-password-reset.md) přepsané na MailNotify (`POST /api/email`, Entra app token, role `Notify.Send`). Člověk musí připravit app registraci a `Senders` |
| 3.2 | Smí stahovací token jít v query stringu? | ✅ **ano** (TTL ≤ 5 min, vazba na soubor, verzi a uživatele, nelogovat) | [05](briefs/05-video-streaming.md) odblokované |
| 3.3 | Windows placeholdery: Cloud Files API, nebo app-level cloud-only? | ⏳ po spiku | Nejdřív [08](briefs/08-windows-placeholders-spike.md), rozhodnout podle ADR |
| 3.4 | Apple Developer ID certifikát + notarizace | ✅ **dodá vlastník** | [07](briefs/07-macos-release-ci.md): Sonnet navrhne názvy secrets a počká na jejich vložení |
| 3.5 | Produkční Entra | ✅ **zdarma** (do 50 000 MAU), ale **bez TOTP a záložních kódů** | Doporučeno držet obojí: vlastní přihlášení + TOTP a Entra jako SSO. Rozbor a lidské kroky v [`entra-external-id.md`](entra-external-id.md) |
| 3.6 | B2B model | ⏸️ **zatím neřešit**, témata rozvíjet | Katalog témat a otázek v [`b2b.md`](b2b.md) |
| 3.7 | Ceník a free tarif | ⏳ otevřené | Mimo kód |
| 3.8 | Retence verzí podle stáří: hodnoty per tarif | ⏳ otevřené | [12](briefs/12-version-retention-by-age.md) jde implementovat bez nich |

---

## 4. Zadání

| # | Zadání | Velikost | Závisí na | Paralelně s |
|---|---|---|---|---|
| 01 | [TOTP 2FA](briefs/01-totp-2fa.md) | M | — | vše |
| 02 | [Zpevnění přihlášení (rate limit, lockout, reuse refresh tokenu)](briefs/02-auth-hardening.md) | S–M | ideálně po 01 (stejné soubory) | 04, 06, 09, 12, 13 |
| 03 | [Obnova hesla e-mailem (MailNotify)](briefs/03-password-reset.md) | M | po 02; app registrace pro MailNotify | 04, 06, 09 |
| 04 | [Náhledy obrázků, textu a PDF](briefs/04-file-preview.md) | M | — | vše |
| 05 | [Streamování s Range + náhled videa](briefs/05-video-streaming.md) | M | 04 | — |
| 06 | [macOS desktop: entitlements, bookmarky, menu bar](briefs/06-macos-desktop.md) | M | — | vše |
| 07 | [macOS release v CI (podpis, notarizace)](briefs/07-macos-release-ci.md) | S | 06, vložené secrets | — |
| 08 | [Spike: Windows Cloud Files API placeholdery](briefs/08-windows-placeholders-spike.md) | M (spike) | — | vše |
| 09 | [Fotky backend: modul v Api, ingest z change feedu, EXIF, miniatury](briefs/09-photos-backend.md) | L | — | vše |
| 10 | [Fotky klient: timeline s miniaturami, zapnutí v buildech](briefs/10-photos-client.md) | M | 09 nasazené | — |
| 11 | [Mobilní auto-backup fotek](briefs/11-mobile-photo-backup.md) | L | 09 | 10 |
| 12 | [Retence verzí podle stáří](briefs/12-version-retention-by-age.md) | S | — | vše |
| 13 | [Přímé sdílení a „Sdíleno se mnou"](briefs/13-shared-with-me.md) | L | — | vše kromě 09 (oba mění FileService queries) |

**Bez zadání:** B2B/admin (zatím neřešit, témata v [`b2b.md`](b2b.md)), Linux klient (nízká priorita, po 06,
protože sdílí desktop sync kód), E2E šifrování (analýza konkurence doporučuje
ho nedělat plošně), ceník (3.7).

### Doporučené vlny

```
Vlna 1 (paralelně):  01 TOTP · 04 náhledy · 06 macOS · 09 fotky backend · 12 retence
Vlna 2:              02 zpevnění auth · 08 spike Windows · 13 sdílení · 10 fotky klient (po nasazení 09)
Vlna 3:              03 obnova hesla · 05 video · 07 macOS CI (po vložení secrets) · 11 auto-backup
```

### Jak zadání použít

1. Otevřete novou session (Claude Code, model Sonnet) nad repem `zcloudcz/zDrive`
   z aktuálního `main`.
2. Jako první zprávu vložte **celý obsah** souboru zadání.
3. Každé zadání končí PR. Podle `CLAUDE.md` ho před merge musí zrevidovat Hydra
   a CI musí projít zeleně.
4. Zadání 08 končí ADR + prototypem, ne produkční změnou.
