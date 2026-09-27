# Zadání 05: Streamovací download s HTTP Range + náhled videa

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: minimální změny, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers (Postgres, Azurite), komunikace
> česky, kód anglicky. Pokud je něco v zadání nejasné nebo neodpovídá kódu,
> zastav se a zeptej se.

> **Předpoklady:** hotové zadání 04 (náhledy) a rozhodnutí 3.2 v
> `docs/gaps/README.md`, zda smí jít stahovací token v query stringu.
> Pokud rozhodnutí chybí, **nezačínej**. Zeptej se.

## Cíl

Video (mp4/webm/mov s H.264/VP9) a audio se přehrají v aplikaci bez
stažení celého souboru. Přehrávač potřebuje URL, která podporuje HTTP Range
a nepotřebuje autorizační hlavičku.

## Současný stav

- `src/services/Api/Controllers/Storage/StorageController.cs`: chunky se
  čtou po jednom (`download/{fileId}/chunk/{hash}/bytes`, octet-stream),
  bez Range a bez endpointu pro celý soubor. SAS URL
  (`download/{fileId}`) nejdou z prohlížeče kvůli CORS na Blob a nechceme je.
- Soubor = manifest (seznam chunků ~4 MiB v pořadí, SHA-256) + chunky
  `{base}/chunks/{hash}.blk`. Verze určuje `manifestHash`.
- Gateway: `/storage/**` vyžaduje JWT (`ApiGateway/appsettings.json:113`),
  `/storage/shared/**` je anonymní s grantem jen v hlavičce
  `X-Share-Grant`. **Záměrně nikdy v query** (`SharedStorageController.cs:26-28`).
- Vzor podepsaného grantu: `src/shared/ZDrive.Shared/Auth/ShareDownloadGrant.cs`
  (HMAC, TTL).

## Rozsah

1. **Stream token:** `POST /api/v1/storage/download/{fileId}/stream-token`
   (autorizovaný). Vrátí krátkodobý (≤ 5 min) HMAC token vázaný na
   `fileId` + `manifestHash` + uživatele, podle vzoru `ShareDownloadGrant`.
   Varianta pro share link: `POST /shares/link/{token}/stream-grant`.
2. **Stream endpoint:** `GET /api/v1/storage/stream/{fileId}?t=...`, v
   gateway anonymní route, autorizace jen tokenem. Skládá chunky z
   manifestu do jednoho streamu, podporuje `Range: bytes=a-b` (206,
   `Content-Range`, `Accept-Ranges: bytes`) a čte jen chunky, které rozsah
   pokrývá. Nastaví `Content-Type` z `FileNode.MimeType` nebo z přípony a
   `Content-Disposition: inline`. Ověřuje SHA-256 čtených chunků;
   při neshodě ukonči stream chybou.
3. **Neloguj query string** stream route v gateway ani v Api (Serilog
   request logging). Ověř, že se token neobjeví v logu.
4. Rate limit: stejná politika jako `publicShare` nebo nová; zdůvodni.
5. **Klient:** v preview (zadání 04) přidat typ video/audio. Přehrávač
   `video_player` (pro Windows zjisti stav podpory; pokud chybí, na Windows
   použij `media_kit` nebo nabídni jen stažení, zeptej se). Před přehráním
   si klient vyžádá stream token.

## Akceptační kritéria

- [ ] Integrační testy (Azurite): celý soubor, Range uvnitř jednoho chunku,
      Range přes hranici chunků, Range za koncem (416), expirovaný nebo
      cizí token (401/403), token pro jinou verzi.
- [ ] Obsah streamu je bajtově shodný s originálem (vícechunkový soubor).
- [ ] Test, že token není v logu.
- [ ] Video se přehraje na webu (Chrome) a aspoň jedné nativní platformě.
      Postup ověření popiš v PR.

## Výstup

Jeden PR. V popisu uveď bezpečnostní úvahu k tokenu v URL (TTL, vazba,
logování, `Referrer-Policy`).
