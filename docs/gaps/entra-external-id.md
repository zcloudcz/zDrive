# Entra External ID vs. vlastní přihlášení

**Datum:** 2026-09-27
**Otázka vlastníka:** Je produkční Entra zdarma? Pokud ne, nebo pokud má
omezení (např. u 2FA), nemělo by smysl zaměřit se na vlastní službu?

## Krátká odpověď

**Ano, pro zDrive je Entra External ID zdarma.** Základ je zdarma do
50 000 aktivních uživatelů měsíčně (MAU), a to včetně MFA a Conditional
Access. Tenant `zcloudcz.ciamlogin.com` už existuje: používá ho zcloud-login
i MailNotify. Produkční app registrace pro zDrive je jen konfigurace a nic
nestojí.

**Omezení existují a týkají se právě 2FA:** Entra External ID **nepodporuje
autentikátorovou aplikaci (TOTP) ani záložní kódy**. SMS je placený
doplněk.

**Doporučení: nevybírat mezi nimi, držet obojí.** Oba způsoby už v kódu
jsou. Vlastní přihlášení zůstává hlavní cestou a dostane TOTP (zadání 01).
Entra zůstává volitelné tlačítko „Přihlásit účtem ZCLOUD" pro SSO napříč
aplikacemi ZCLOUD. Zaměřit se jen na vlastní službu by znamenalo ztratit
SSO. Zaměřit se jen na Entra by znamenalo vzdát se TOTP a být závislý na
Microsoftu.

## Fakta (Microsoft Learn, září 2026)

| Oblast | Stav v external tenantu | Cena |
|---|---|---|
| Základ (přihlášení, user flows, branding, tokeny) | ✅ | zdarma do 50 000 MAU, nad limitem se platí za MAU |
| MFA a Conditional Access | ✅ | v rámci free tieru (prvních 50 000 MAU má i P1/P2 funkce MFA) |
| MFA: e-mailový jednorázový kód | ✅ (jen pokud primární metoda je e-mail + heslo) | zdarma |
| MFA: passkey (FIDO2) | ✅ pro účty e-mail + heslo; ne pro účty přes externí IdP | zdarma |
| MFA: SMS | ✅ jen jako druhý faktor | **placený doplněk** bez free tieru, cena podle země, nutná navázaná Azure subscription |
| MFA: autentikátorová aplikace (TOTP) | ❌ nepodporováno | — |
| Záložní kódy | ❌ | — |
| Samoobslužný reset hesla | ✅ e-mailem (zdarma) nebo SMS (placené) | — |
| ID Protection (rizikové přihlášení) | ❌ v external tenantu není | — |
| MAU | počítají se jen uživatelé, kteří se přes Entra **přihlásí**. Kdo se přihlašuje vlastním heslem zDrive, se nepočítá | — |

Aktuální ceník nad 50 000 MAU a ceny SMS: [aka.ms/ExternalIDPricing](https://aka.ms/ExternalIDPricing).
Před překročením limitu ho ověřte.

## Co to znamená pro zDrive

| Varianta | Pro | Proti |
|---|---|---|
| **A: jen vlastní přihlášení** | plná kontrola, TOTP + záložní kódy, žádná závislost | ztráta SSO s ostatními aplikacemi ZCLOUD; brute-force ochranu, reset hesla, e-maily a passkeys si musíme udělat a udržovat sami (zadání 02, 03) |
| **B: jen Entra** | Microsoft řeší hesla, reset, MFA, lockout; SSO | bez TOTP a záložních kódů, SMS stojí peníze, přihlašovací stránka na doméně `ciamlogin.com` s omezeným brandingem, 24h strop refresh tokenu (ADR 0003), macOS/Linux dnes bez Entra (ADR 0003) |
| **C: obojí (doporučeno, dnešní stav kódu)** | uživatel si vybere; SSO pro ekosystém ZCLOUD; vlastní účty s TOTP | dvě identity pro jeden e-mail vrací 409 (bez propojení účtů, viz ADR 0002); dvě cesty k testování |

Varianta C nestojí žádný nový vývoj navíc. Kód pro Entra je hotový (#70,
#72, #74). Zbývají jen lidské kroky:

1. Produkční SPA app registrace zDrive v `zcloudcz.ciamlogin.com` s redirect
   URI webu. Použít existující user flow `zcloud_signin` (ADR 0002,
   Migration order, krok 1).
2. Na stejné registraci přidat platformu „Mobile and desktop applications",
   redirect `cz.zcloud.zdrive://auth` a `http://localhost` (ADR 0003).
3. `Entra:Enabled=true` + `TenantId`, `Audience`, `RequiredScope` v App
   Service. Build define `ENTRA_CLIENT_ID` a `ENTRA_API_SCOPE` v CI.
4. **MFA pro Entra účty:** v Entra admin centru zapnout metodu Email OTP
   (a volitelně passkeys) a Conditional Access politiku „Require MFA" pro
   aplikaci zDrive. Zdarma. Zvažte, zda politika nemá platit pro celý
   `zcloud_signin`, tedy i pro ostatní aplikace ZCLOUD.

## Otevřené body

- **Propojení účtů:** dnes se e-mail registrovaný heslem nedá přihlásit
  přes Entra (409). Pokud mají být obě cesty rovnocenné, bude potřeba
  zadání „propojit Entra identitu s existujícím účtem po ověření hesla".
  Zatím nepřipravené, rozhodněte až podle zpětné vazby.
- **Firemní SSO** (zákazník přihlašuje zaměstnance vlastním Entra ID,
  Google Workspace nebo SAML) je jiná věc než External ID tenant ZCLOUD.
  Patří do témat pro firmy, viz [`b2b.md`](b2b.md).

## Zdroje

- [Entra External ID FAQ: pricing](https://learn.microsoft.com/entra/external-id/customers/faq-customers#external-id-pricing)
- [External ID pricing and billing overview](https://learn.microsoft.com/entra/external-id/external-identities-pricing)
- [Multifactor authentication in external tenants](https://learn.microsoft.com/entra/external-id/customers/concept-multifactor-authentication-customers)
- [Add MFA to an app (external tenants)](https://learn.microsoft.com/entra/external-id/customers/how-to-multifactor-authentication-customers)
- [MFA licensing: first 50,000 MAU](https://learn.microsoft.com/entra/identity/authentication/concept-mfa-licensing#available-versions-of-microsoft-entra-multifactor-authentication)
- [Supported features in workforce and external tenants](https://learn.microsoft.com/entra/external-id/customers/concept-supported-features-customers#general-feature-comparison)
- [Microsoft Q&A: Authenticator/TOTP not supported for local accounts](https://learn.microsoft.com/answers/a/2062924)
