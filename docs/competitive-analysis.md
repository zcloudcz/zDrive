# zDrive vs. konkurence — srovnávací analýza

**Datum:** 2026-09-26
**Stav zDrive:** klient 0.4.3 (`3533755`), backend po sloučení Auth/File/Storage/Sync do `ZDrive.Api`

Srovnáváme zDrive se třemi zadanými konkurenty (Google Drive, OneDrive, Proton
Drive) a s dalšími, kteří míří na stejné zákazníky: Dropbox a iCloud Drive
(masový B2C trh), pCloud a Tresorit (evropské/švýcarské, důraz na soukromí),
Nextcloud (self-hosted, suverenita dat) a Box (čisté B2B).

> **Ceny** jsou ceníkové v USD k září 2026, převzaté z veřejných ceníků a
> agregátorů (viz Zdroje). V EUR/CZK a podle regionu se liší, často běží
> slevy na první rok. Microsoft ohlásil zdražení od července 2026. Před
> rozhodnutím o vlastní cenotvorbě je ověřte přímo na stránkách poskytovatelů.
>
> **Navazuje:** [`docs/gaps/`](gaps/README.md) obsahuje rozbor nedostatků podle kódu
> a zadání k jejich implementaci. Tvrzení o fotkách a přímém sdílení byla
> 2026-09-27 opravena podle průzkumu kódu.

---

## 1. Shrnutí

- **Kde zDrive dnes je:** funkční MVP úložiště se synchronizací. Má
  blokovou delta synchronizaci, obsahově adresované verze, koš, sdílení
  odkazem včetně zápisu a MCP endpoint pro AI agenty. Běží na webu, Windows,
  Androidu a iOS. Fotky jsou jen DB model bez zpracování a nejsou nasazené, AI chybí. Chybí také E2E šifrování,
  náhledy a editace dokumentů, klient pro Linux a také integrace do OS na
  úrovni systémových placeholderů (Files On-Demand).
- **Proti velkým hráčům (Google, Microsoft, Apple)** zDrive neobstojí šíří
  ekosystému (kancelář, e-mail, AI asistenti) ani cenou za TB. Soupeřit s nimi
  v kategorii „víc místa za méně peněz" nemá smysl.
- **Proti privacy hráčům (Proton, Tresorit, pCloud)** zDrive prohrává na
  hlavním argumentu, tedy zero-knowledge šifrování. Vyhrává ale na plánované
  AI správě fotek, která s E2E šifrováním jde jen obtížně.
- **Realistická pozice:** evropský (česky lokalizovaný) drive pro malé firmy
  a domácnosti, provázaný s identitou ZCLOUD (Entra SSO). Nabízí data
  v EU, sdílení odkazem se zápisem pro spolupráci s externisty a AI přístup
  přes MCP. Podmínkou je dotáhnout základy, které konkurence považuje za
  samozřejmost (viz kap. 6).

---

## 2. Co zDrive skutečně umí (stav repa, ne plán)

| Oblast | Stav | Poznámka |
|---|---|---|
| Web, Windows, Android, iOS | ✅ | Windows: tray, spuštění po přihlášení, auto-update. iOS přes TestFlight |
| macOS | ⚠️ částečně | chybí entitlements a trvalé záložky složek |
| Linux | ❌ | Flutter projekt nemá linux target |
| Synchronizace | ✅ | bloky ~4 MB, SHA-256 adresace, deduplikace, konflikty (LWW + fork) |
| Selektivní sync / „cloud-only" | ⚠️ | výchozí cloud-only, pin „ponechat v zařízení", uvolnit místo. **Na aplikační úrovni**: cloud-only soubor na disku vůbec není, chybí systémový placeholder (Windows Cloud Files API / macOS File Provider) |
| Verze souborů | ✅ | výchozí limit 10 verzí/soubor, obnova verze |
| Koš | ✅ | 30 dní, stránkování, obnova |
| Sdílení odkazem | ✅ | expirace, heslo, **zápis přes odkaz** (upload, nová složka, mazání, nová verze), brandovaná veřejná stránka |
| Přímé sdílení uživateli | ❌ | `SharedWith` se uloží, ale nic ho nečte: chybí přístup příjemce i „sdíleno se mnou" (viz `docs/gaps/`) |
| Vyhledávání | ✅ | názvy a metadata (PostgreSQL tsvector), bez fulltextu obsahu |
| MCP endpoint (AI agenti) | ✅ | přes sdílené odkazy, přímo v gateway. **Unikát v tomto srovnání** |
| Kvóty | ✅ | per-user, výchozí 50 GB |
| Fotky (timeline, alba) | ⚠️ kostra | DB model, CRUD alb a UI existují. Ingest nikdo nevolá, chybí EXIF i miniatury (thumbnail URL míří na neexistující CDN). Nenasazeno, v buildech je vypne `PHOTOS_ENABLED=false` |
| AI fotky (tagy, tváře, vzpomínky) | ❌ | navrženo (fáze 5), neimplementováno |
| Náhledy dokumentů / přehrávání videa | ❌ | klient nemá viewer |
| Online editace (Office/Docs) | ❌ | — |
| E2E / zero-knowledge šifrování | ❌ | jen šifrování Azure „at rest" na straně serveru |
| 2FA | ❌ | vlastní účty bez druhého faktoru. Entra SSO (ZCLOUD) je rozpracované, zatím bez produkční registrace |
| B2B (tenanti, role, audit) | ⚠️ | datový model a role ano, admin UI a audit log ne (fáze 7) |
| Lokalizace | ✅ | 12 jazyků včetně cs, sk |
| Umístění dat | ✅ EU | Azure `westeurope` (Nizozemsko). Poskytovatel je ale americký, takže se na něj vztahuje CLOUD Act |

---

## 3. Přehled konkurentů

| Služba | Zdarma | Typický placený tarif | Rodina / tým | Šifrování | Jurisdikce | Hlavní síla |
|---|---|---|---|---|---|---|
| **Google Drive** (Google One) | 15 GB (sdíleno s Gmailem a Fotkami) | 2 TB Premium ~$9.99/měs. ($99.99/rok); AI Pro ~$19.99/měs. (Gemini) | sdílení až s 5 členy; Workspace od ~$7/uživ. | server-side; klientské šifrování jen ve Workspace Enterprise | USA | ekosystém, Fotky + AI, Docs/Sheets |
| **OneDrive** (Microsoft 365) | 5 GB | M365 Personal 1 TB $99.99/rok | Family 6× 1 TB $129.99/rok; M365 Business od ~$6/uživ. | server-side; Personal Vault s 2FA | USA | Office, Windows integrace, Files On-Demand |
| **Proton Drive** | 5 GB | Drive Plus 200 GB (~$4–5/měs.); Unlimited 500 GB $9.99/měs. (roční) | Duo, Family; Drive Professional od $7.99/uživ. | **E2E, zero-knowledge** | Švýcarsko | soukromí, balík Mail/VPN/Pass, Docs a Sheets s E2E |
| **Dropbox** | 2 GB | Plus 2 TB $9.99/měs. (roční) | Essentials/Professional 3 TB $19.99/měs.; Business od ~$15/uživ. | server-side | USA | nejlepší sync engine, LAN sync, spolupráce |
| **iCloud Drive** (iCloud+) | 5 GB | 200 GB $2.99, 2 TB $9.99, 6 TB $29.99, 12 TB $59.99/měs. | Family Sharing až 6 osob | Advanced Data Protection (E2E, volitelně) | USA | integrace Apple ekosystému, Fotky |
| **pCloud** | až 10 GB | 500 GB $4.99/měs.; **lifetime** 2 TB $399 jednorázově | Family lifetime; Business | server-side, E2E jako placený doplněk Crypto (€4.99/měs. nebo €150 lifetime) | Švýcarsko (DC v EU nebo USA dle volby) | lifetime licence, virtuální disk |
| **Tresorit** | Basic (malý) | Personal Essential $13.99/měs. | Business Standard $14.50/uživ. (min. 3), Plus $19 | **E2E** | Švýcarsko | compliance (GDPR, HIPAA), B2B bezpečnost |
| **Nextcloud** | self-host zdarma (open source) | — | Enterprise €68.94–204.75/uživ./rok, **min. 100 uživatelů** | server-side + volitelné E2E | kde si hostujete | plná suverenita dat, rozšiřitelnost (Talk, Office) |
| **Box** | 10 GB | — | Business od ~$15–20/uživ. (min. 3) | server-side, KeySafe (BYOK) | USA | enterprise obsahová správa, governance, integrace |
| **zDrive** | *nedefinováno* | *nedefinováno* (výchozí kvóta 50 GB) | tenant model připraven | server-side (Azure) | EU data, US poskytovatel | block delta sync, zápis přes odkaz, MCP, CZ/SK |

---

## 4. Funkční srovnání

Legenda: ✅ ano · ⚠️ částečně/omezeně · ❌ ne · 🗓️ plánováno v zDrive

| Funkce | zDrive | Google Drive | OneDrive | Proton Drive | Dropbox | iCloud | pCloud | Tresorit | Nextcloud |
|---|---|---|---|---|---|---|---|---|---|
| Desktop Windows | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Desktop macOS | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Desktop Linux | ❌ | ❌ | ❌ | ⚠️ jen CLI | ✅ | ❌ | ✅ | ✅ | ✅ |
| Files On-Demand (OS placeholdery) | ❌ (app-level cloud-only) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ virt. disk | ⚠️ | ✅ |
| Blokový (delta) sync | ✅ | ❌ | ⚠️ Office soubory | ❌ | ✅ | ❌ | ⚠️ | ❌ | ❌ |
| Historie verzí | ✅ 10 verzí | ✅ 30 dní/100 verzí | ✅ | ✅ až 365 dní | ✅ 30–365 dní | ⚠️ | ✅ 15–365 dní | ✅ | ✅ |
| Sdílení odkazem, heslo, expirace | ✅ | ⚠️ bez hesla | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| Nahrávání přes odkaz (file request) | ✅ + mazání/verze | ⚠️ Forms | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| Náhled dokumentů/videa v prohlížeči | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Online kancelář | ❌ | ✅ Docs | ✅ Office | ✅ Docs, Sheets (E2E) | ⚠️ Paper/Office | ✅ iWork | ❌ | ❌ | ✅ Office |
| Fotky — timeline, auto-backup | 🗓️ (kostra, nenasazeno) | ✅ | ✅ | ✅ + alba | ⚠️ | ✅ | ✅ | ❌ | ✅ |
| AI fotky (lidé, objekty, vzpomínky) | 🗓️ | ✅ špička trhu | ✅ | ❌ (E2E) | ❌ | ✅ on-device | ❌ | ❌ | ⚠️ Recognize |
| AI asistent nad soubory | ⚠️ MCP pro externí agenty | ✅ Gemini | ✅ Copilot | ⚠️ Lumo | ✅ Dash | ⚠️ | ❌ | ❌ | ⚠️ Assistant |
| E2E / zero-knowledge | ❌ | ❌ | ❌ (Vault ≠ E2E) | ✅ | ❌ | ⚠️ ADP | ⚠️ placené | ✅ | ⚠️ |
| 2FA | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SSO (Entra/SAML) pro firmy | ⚠️ Entra rozprac. | ✅ | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ | ✅ |
| Admin konzole, audit log | 🗓️ | ✅ | ✅ | ✅ | ✅ | ❌ | ⚠️ | ✅ | ✅ |
| Data v EU | ✅ | ⚠️ jen Workspace | ⚠️ EU Data Boundary (firmy) | ✅ CH | ⚠️ Business | ❌ | ✅ volba | ✅ volba | ✅ |
| Čeština | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| Otevřené API | ✅ REST + MCP | ✅ | ✅ Graph | ⚠️ SDK/CLI | ✅ | ❌ | ✅ | ⚠️ | ✅ WebDAV |

*Hodnocení konkurence vychází z veřejně známých vlastností k 2026 a u detailů
(přesné limity verzí, dostupnost v regionu) se může lišit podle tarifu.*

---

## 5. Konkurenti stručně: v čem jsou nebezpeční a kde mají slabiny

**Google Drive.** 15 GB zdarma a Google Fotky jsou nejsilnější lákadlo na
trhu. Photos AI (vyhledávání „pes na pláži", tváře, vzpomínky) je přesně to,
co zDrive plánuje v roadmapě jako „Google Photos-level". *Slabina:* soukromí
a reklamní model, data mimo EU pro běžné uživatele, v desktop klientovi chybí
delta sync.

**OneDrive.** Jde s Windows a Office „zadarmo" a 1 TB v M365 Personal je pro
většinu domácností dost. Files On-Demand a známé složky (Plocha, Dokumenty)
jsou laťka pro desktop UX. *Slabina:* agresivní upselling, nepřehledné sdílení,
zdražování (2026) a rušení samostatných OneDrive for Business plánů. Tlačí
zákazníky do celého M365.

**Proton Drive.** Hlavní argument je zero-knowledge E2E a švýcarská
jurisdikce. V roce 2026 výrazně zrychlil, přidal alba a Proton Sheets a bundluje
se s Mail/VPN/Pass. *Slabina:* bez nativního Linux klienta (jen CLI), E2E
znemožňuje serverové AI nad fotkami a fulltextové vyhledávání v obsahu, sdílení
a spolupráce jsou pomalejší než u velkých hráčů.

**Dropbox.** Nejvyspělejší synchronizační engine (bloková delta, LAN sync)
a Linux klient. *Slabina:* drahý (2 TB je nejmenší placený tarif), jen 2 GB
zdarma, bez fotek na úrovni Google.

**iCloud Drive.** Pro uživatele Apple je bezkonkurenční díky integraci a
volitelnému E2E (Advanced Data Protection). *Slabina:* Windows a Android jsou
druhořadé, sdílení odkazem je slabé a firemní funkce chybí.

**pCloud.** Lifetime licence je jedinečný obchodní model, oblíbený mezi
lidmi, kteří nesnášejí předplatné. Umožňuje volbu datacentra v EU. *Slabina:*
E2E je placený doplněk jen pro jednu složku a spolupráce je slabší.

**Tresorit.** E2E pro firmy s compliance nároky (právníci, zdravotnictví),
švýcarsko-maďarský původ. *Slabina:* drahý, minimum 3 uživatelé, slabé
multimédia.

**Nextcloud.** Referenční volba pro „suverénní" evropské nasazení (veřejná
správa, školy, firmy s vlastní infrastrukturou). *Slabina:* provoz leží na
zákazníkovi. Enterprise podpora začíná na 100 uživatelích, takže malé firmy
platí za prázdná místa nebo jedou bez podpory.

**Box.** Enterprise content management a governance. Pro zDrive je relevantní
jen v B2B fázi 7+. Malé a střední firmy v ČR ho používají zřídka.

---

## 6. Pozice zDrive

### 6.1 Reálné diferenciátory (už v kódu)

1. **Zápis přes sdílený odkaz** (upload, složky, mazání, nové verze) na
   brandované stránce. Běžní konkurenti umí buď jen „file request" (upload),
   nebo plnou editaci jen pro přihlášené účty. Pro spolupráci s externisty
   (klient nahrává podklady, účetní vrací zpracované) je to silný argument.
2. **MCP endpoint nad sdílenými složkami.** AI agent (Claude, ChatGPT,
   Copilot…) pracuje se složkou přes odkaz bez vlastního účtu. Google
   a Microsoft staví AI dovnitř svého ekosystému, zDrive je otevřený pro
   libovolného agenta. V tomto srovnání to nemá nikdo jiný v podobné formě.
3. **Bloková delta synchronizace s deduplikací.** Na úrovni Dropboxu a nad
   Google Drive, Proton i iCloud. U velkých souborů, které se mění (PST, VM
   image, databáze, video projekty), znatelně šetří přenos.
4. **Data v EU + čeština/slovenština + identita ZCLOUD.** Dává smysl jako
   součást širší nabídky ZCLOUD pro české a slovenské SMB, ne jako
   samostatný B2C produkt.

### 6.2 Mezery, které zákazník uvidí hned (bez nich produkt neprodáte)

| # | Mezera | Proč je kritická | Srovnání |
|---|---|---|---|
| 1 | **2FA** a produkční SSO | Bezpečnostní minimum. Bez něj neprojdete žádnou firemní prověrkou | mají všichni |
| 2 | **Náhled souborů** (obrázky, PDF, video, Office) v prohlížeči i v aplikaci | Uživatel musí stahovat každý soubor, aby viděl obsah | mají všichni |
| 3 | **Files On-Demand na úrovni OS** (Windows Cloud Files API, macOS File Provider) | Současný cloud-only režim soubor z disku úplně skryje, takže uživatel v Průzkumníku nevidí celý drive. Laťku tu nastavuje OneDrive | mají všichni desktopoví |
| 4 | **Dokončit macOS** | Polovina cílové skupiny SMB/kreativců | — |
| 5 | **Nasadit fotky** (timeline, mobilní auto-backup) | Hlavní slib produktu („Google Photos-level"). Existuje jen kostra: chybí ingest, EXIF, miniatury a nasazení | Google, OneDrive, iCloud, Proton |
| 6 | **Ceník a free tarif** | Bez něj nelze pozicovat | viz kap. 3 |

### 6.3 Strategická rozhodnutí k diskusi

Tato rozhodnutí patří vlastníkovi produktu. Uvádím je s doporučením,
nejsou to hotová rozhodnutí:

1. **E2E šifrování ano/ne.** E2E by zDrive postavilo proti Protonu
   a Tresoritu. Zároveň by ale znemožnilo serverové AI nad fotkami
   (fáze 5), fulltext a MCP přístup, tedy tři z hlavních diferenciátorů.
   *Doporučení:* nedělat E2E plošně. Zvážit volitelný „trezor" (šifrovaná
   složka, jako pCloud Crypto nebo OneDrive Personal Vault) až po fázi 8
   a v marketingu nepředstírat zero-knowledge.
2. **Cílový trh B2C vs. SMB.** V B2C je cenová válka o $/TB (Google 2 TB
   ~$99/rok, pCloud lifetime) a zDrive na Azure Blob nemá strukturu
   nákladů na to, aby ji vyhrál. *Doporučení:* primárně SMB v CZ/SK
   v balíčku ZCLOUD (Entra SSO, tenanti, data v EU, sdílení s externisty,
   MCP). B2C mít jen jako rodinný tarif pro fotky.
3. **Suverenita dat.** Data jsou v EU, ale Azure je americký poskytovatel
   (CLOUD Act). Proti Nextcloudu, Protonu a Tresoritu to v tendrech veřejné
   správy nemusí stačit. *Doporučení:* v komunikaci říkat přesně „data
   v EU (Azure West Europe)", ne „suverénní cloud". Pokud má být veřejná
   správa cílem, řešit to jako samostatné rozhodnutí o infrastruktuře.
4. **Verze a retence jako prodejní argument.** Limit 10 verzí je pod
   konkurencí (Proton až 365 dní, Dropbox 180–365 dní). Retence podle času
   (např. 30/180 dní podle tarifu) je snadný upsell a konkurence ji takto
   komunikuje.

### 6.4 Navrhované pořadí (dopad × úsilí)

```
1. 2FA (TOTP) + dotažení Entra SSO        → základ bezpečnosti, odblokuje B2B
2. Náhledy (obrázky, PDF, video)           → nejviditelnější UX mezera
3. Fotky: ingest, EXIF, miniatury, nasazení → hlavní slib produktu, dnes jen kostra
4. Ceník + free tarif                      → nutné pro go-to-market
5. Windows Cloud Files API placeholdery    → parita s OneDrive na hlavní platformě
6. macOS dokončení (+ File Provider)       → druhá desktopová platforma
7. Časová retence verzí dle tarifu         → upsell, malý zásah
8. Admin UI + audit log (fáze 7)           → prodej SMB
```

---

## Zdroje

- Google One: [plány](https://one.google.com/about/plans), [Android Authority — Google One 2026](https://www.androidauthority.com/google-one-plans-confusion-2026-3669231/), [9to5Google — nabídka 2026](https://9to5google.com/2026/01/15/google-one-2026-offer/), [Internxt — Google One pricing](https://blog.internxt.com/google-one-pricing/)
- OneDrive / Microsoft 365: [plány OneDrive](https://www.microsoft.com/en-us/microsoft-365/onedrive/onedrive-plans-and-pricing), [Microsoft 365 Family](https://www.microsoft.com/en-us/microsoft-365/p/microsoft-365-family/cfq7ttc0k5dm), [Internxt — OneDrive pricing 2026](https://blog.internxt.com/onedrive-pricing/)
- Proton Drive: [ceník](https://proton.me/drive/pricing), [roadmapa jaro/léto 2026](https://proton.me/blog/2026-spring-summer-roadmaps), [Q1 2026 recap](https://proton.me/blog/drive-2026-q1-recap), [Thurrott — Proton Drive 2026](https://www.thurrott.com/cloud/334907/proton-drive-has-already-had-a-great-2026), [Capterra](https://www.capterra.com/p/10029940/Proton-Drive/pricing/)
- Dropbox: [Cloudwards — Dropbox pricing](https://www.cloudwards.net/dropbox-pricing/), [G2](https://www.g2.com/products/dropbox/pricing)
- iCloud+: [Apple iCloud](https://www.apple.com/icloud/), [MacObserver — iCloud plans](https://www.macobserver.com/tips/round-ups/icloud-storage-price-plans/)
- pCloud: [ceník](https://www.pcloud.com/cloud-storage-pricing-plans), [Internxt — pCloud pricing](https://blog.internxt.com/pcloud-pricing/)
- Tresorit: [business ceník](https://tresorit.com/pricing/business), [Capterra](https://www.capterra.com/p/150689/Tresorit/pricing/)
- Nextcloud: [Enterprise ceník](https://nextcloud.com/pricing/), [Toolradar](https://toolradar.com/tools/nextcloud/pricing)
- zDrive: `docs/mvp-completion.md`, `docs/superpowers/specs/2026-06-04-zdrive-platform-design.md`, historie commitů do `3533755`
