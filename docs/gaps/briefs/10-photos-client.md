# Zadání 10: Fotky klient (timeline s miniaturami, zapnutí v buildech)

> Pracuješ v repozitáři zDrive (Flutter klient v `src/client/zdrive_app`).
> Nejdřív si přečti `CLAUDE.md` (sekce Build-time defines) a dodržuj ho:
> Bloc/Cubit, feature-first, testy, komunikace česky, kód anglicky.

> **Předpoklad:** zadání 09 je mergnuté a nasazené (timeline API vrací
> zpracované fotky, `GET /photos/{id}/thumbnail/{size}` funguje).

## Cíl

Záložka Fotky je ve výchozím buildu zapnutá a ukazuje timeline
s miniaturami, detail fotky a alba.

## Současný stav

- `lib/features/photos/`: timeline, alba, memories stránky, bloc, repository.
  `photo_remote_data_source.dart` má čtecí endpointy a CRUD alb.
- Gating: `kPhotosEnabled = bool.fromEnvironment('PHOTOS_ENABLED')`
  (`photos_support.dart:7`), výchozí `false`. Použití v `app_router.dart:140,160`
  a `home_page.dart:97,105`.
- Miniatury potřebují JWT hlavičku, takže `Image.network` bez hlavičky
  nepůjde.

## Rozsah

1. Načítání miniatur přes Dio (auth interceptor) s paměťovou LRU cache
   (limit v MB) a na nativních platformách i diskovou cache. Stačí jednoduchý
   `ImageProvider`, který volá repository. Nepřidávej těžký balíček, pokud
   nestačí vlastní provider o pár desítkách řádků.
2. Timeline: mřížka seskupená podle dne/měsíce (podle `takenAt`), lazy
   loading po stránkách podle API, placeholder při načítání.
3. Detail: velká miniatura (1024), swipe mezi fotkami, akce Stáhnout originál
   (existující download flow) a Přidat do alba.
4. Memories: pokud API vrací prázdno (generátor neexistuje), záložku nebo
   sekci skryj, ať nevzniká prázdná obrazovka.
5. Změnit výchozí `PHOTOS_ENABLED` na `true` **až v posledním commitu PR**.
   Aktualizuj tabulku v `CLAUDE.md` a CI (`deploy-web.yml`), pokud flag
   předává.
6. Lokalizace do `.arb`.

## Akceptační kritéria

- [ ] Widget testy: timeline seskupení, prázdný stav, chyba + retry, detail.
- [ ] Test image provideru (cache hit/miss, auth hlavička).
- [ ] Ručně ověřeno proti běžícímu backendu (docker-compose). Postup
      v PR.
- [ ] `flutter analyze` + `flutter test` zelené.

## Výstup

Jeden PR se screenshoty.
