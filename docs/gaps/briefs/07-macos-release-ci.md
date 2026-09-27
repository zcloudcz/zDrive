# Zadání 07: macOS release v CI (build, podpis, notarizace)

> Pracuješ v repozitáři zDrive. Nejdřív si přečti `CLAUDE.md` a dodržuj ho:
> minimální změny, komunikace česky, kód anglicky. Pokud je něco v zadání
> nejasné nebo neodpovídá kódu, zastav se a zeptej se.

> **Předpoklady:** hotové zadání 06. **Rozhodnuto vlastníkem (2026-09-27):**
> Apple Developer ID certifikát a notarizační credentials budou k
> dispozici. **Názvy GitHub secrets si nevymýšlej.** Na začátku navrhni
> jejich seznam (p12 certifikát base64, heslo, App Store Connect API key
> nebo Apple ID + app-specific password, team id), nech ho potvrdit a
> počkej, až je vlastník vloží. Mezitím můžeš připravit workflow, který
> bez secrets podpis přeskočí.

## Cíl

Workflow `release-clients.yml` kromě Androidu, iOS a Windows vydá i
podepsaný a notarizovaný macOS build (`.dmg` nebo `.zip` s `.app`) jako
součást stejného release.

## Současný stav

- `.github/workflows/release-clients.yml`: joby android, ios (macos-15,
  ~ř. 146), windows (~ř. 195-230), testflight. **macOS desktop job
  neexistuje.**
- `macos/Runner.xcodeproj/project.pbxproj`: `CODE_SIGN_IDENTITY "-"` (ad-hoc).
- iOS signing v CI existuje. Inspiruj se jeho načítáním certifikátů do
  dočasné keychain.
- Windows updater (`lib/core/update/`, `packaging/windows/`) stahuje
  release assety. Zjisti, jestli auto-update na macOS dává smysl v tomto
  kroku. Nejspíš ne: jen vydat artefakt a update nechat na později. Uveď to
  v PR.

## Rozsah

1. Nový job `macos` (runner `macos-15`): `flutter build macos --release` se
   stejnými `--dart-define` jako ostatní desktop buildy.
2. Import certifikátu do dočasné keychain, `codesign --deep --options runtime
   --timestamp` s entitlements z `macos/Runner/Release.entitlements`.
3. Notarizace přes `xcrun notarytool submit --wait` a `xcrun stapler staple`.
4. Balení do `.dmg` (`hdiutil`) nebo `.zip` (`ditto -c -k --keepParent`),
   podepsat a notarizovat i dmg. Upload do stejného GitHub release jako
   ostatní platformy.
5. Job musí na PR bez secrets přeskočit podpis, ale build udělat, aby PR
   neblokoval. Řiď se tím, jak to dělá iOS job.

## Akceptační kritéria

- [ ] Na tagu vznikne notarizovaný artefakt. `spctl -a -vv` na stažené
      aplikaci hlásí „accepted, source=Notarized Developer ID".
- [ ] Na PR job proběhne bez secrets (build bez podpisu).
- [ ] Žádné secrets v logu.

## Výstup

Jeden PR. V popisu uveď seznam požadovaných secrets a jak je získat.
