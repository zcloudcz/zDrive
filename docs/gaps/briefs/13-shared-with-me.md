# Zadání 13: Přímé sdílení uživateli a „Sdíleno se mnou"

> Pracuješ v repozitáři zDrive (.NET 8 backend + Flutter klient). Nejdřív si
> přečti `CLAUDE.md` a dodržuj ho: Clean Architecture, MediatR, testy
> `{Method}_{Scenario}_{Expected}`, integrační testy přes
> `WebApplicationFactory` + Testcontainers, komunikace česky, kód anglicky.
>
> **Než začneš psát kód, pošli návrh modelu oprávnění (bod 2) a počkej na
> schválení.** Mění, kdo smí číst cizí soubory, a to je bezpečnostně
> citlivé.

## Cíl

Vlastník nasdílí soubor nebo složku konkrétnímu uživateli (podle e-mailu)
s právem čtení nebo zápisu. Příjemce to vidí v sekci „Sdíleno se mnou",
může procházet, stahovat a (se zápisem) nahrávat.

## Současný stav

- `POST /api/v1/shares` (`src/services/Api/Controllers/Files/SharesController.cs:30-43`)
  přijímá `SharedWith` (Guid?) a `CreateShareCommandHandler.cs:33` ho uloží.
  **Nic ho nečte:** neexistuje dotaz „sdíleno se mnou", query souborů
  filtrují `f.TenantId == tenantId && f.UserId == userId` (např.
  `ListChildrenQueryHandler`) a `PublicShareAccess.cs:43` sdílení
  s `SharedWith` pro odkazy odmítá.
- Klient `sharedWith` nikde nepoužívá. Share dialog:
  `lib/features/files/presentation/widgets/share_dialog.dart`.
- Každý uživatel má vlastní tenant (`RegisterCommandHandler.cs:48`), takže
  sdílení je **napříč tenanty**.
- Uživatelé jsou v Auth modulu (schéma `auth`), soubory ve File modulu
  (schéma `files`). Oba běží v `ZDrive.Api`.
- Existující vzor přístupu přes odkaz: `PublicShareAccess`, `ListSharedChildren`,
  `SharedStorageController` (grant pro storage). Inspiruj se jím.

## Rozsah

1. **Vyhledání příjemce podle e-mailu:** přes Auth application query, ne
   přímým čtením cizího schématu. Pokud e-mail neexistuje, vrať stejnou
   odpověď jako při úspěchu, nebo explicitní chybu? Rozhodni to v návrhu
   s ohledem na enumeraci účtů.
2. **Model přístupu (návrh):** jedna služba „může uživatel U číst/zapisovat
   uzel N?" = vlastník, nebo existuje nerevokované, neexpirované
   `Share(SharedWith=U)` na N nebo předkovi. Musí ji použít všechny
   dotazy a příkazy, kterých se sdílení týká: children, metadata, download
   (manifest a chunky ve Storage), upload a nová verze (kvóta se účtuje
   **vlastníkovi**), rename, delete (zvaž, zda ho zápis zahrnuje).
   Ověř, že se tenant filtr neobejde jinde.
3. **API:**
   - `GET /api/v1/shares/with-me`: kořeny sdílené se mnou (název,
     vlastník, oprávnění, datum).
   - Procházení a akce přes stávající file endpointy s kontrolou přes bod 2,
     nebo přes samostatné `/shares/with-me/{shareId}/...`. Zvol a zdůvodni
     v návrhu. Méně nových rout je lepší.
   - `GET /api/v1/files/{id}/shares`: vlastník vidí, komu sdílel, a může
     revokovat (`DELETE /shares/{id}` existuje).
4. **Change feed:** příjemce zatím změny sdílených položek v feedu nevidí.
   Nesynchronizují se na desktop, je to jen online přístup. Uveď to v PR.
5. **Klient:** v share dialogu záložka „Lidé" (e-mail + oprávnění), sekce
   „Sdíleno se mnou" v navigaci, prohlížení a akce podle oprávnění
   (read-only UI pro čtení). Lokalizace do `.arb`.

## Mimo rozsah

Pozvánky e-mailem (e-mail neexistuje, viz zadání 03), sdílení do skupin,
synchronizace sdílených složek na desktop, notifikace.

## Akceptační kritéria

- [ ] Integrační testy: A sdílí složku B pro čtení → B vidí v `with-me`,
      prochází, stahuje. Upload od B → 403. Po změně na zápis upload projde
      a počítá se do kvóty A. Po revokaci → 404/403 všude (včetně chunků
      ve Storage). Třetí uživatel C → nic nevidí.
- [ ] Negativní testy pro každý endpoint, kterého se změna kontroly
      přístupu týká.
- [ ] Flutter testy share dialogu (záložka Lidé) a stránky „Sdíleno se mnou".
- [ ] Všechny existující testy zelené.

## Výstup

PR (doporučeno dva: backend, klient). V popisu tabulka „endpoint →
kontrola přístupu".
