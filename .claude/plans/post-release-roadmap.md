Status: Active
Last Updated: 2026-03-21
Owner: Maintainers
Related: [release-1.0.md](./release-1.0.md), [enterprise-xml-roadmap/README.md](./enterprise-xml-roadmap/README.md)

# Post-Release Roadmap

## Scopo

Mantenere un ponte leggero tra la roadmap storica di rilascio e la roadmap enterprise di medio-lungo termine, senza duplicare la nuova fonte di verita'.

## Contesto

Questo file non sostituisce il pacchetto documentale `enterprise-xml-roadmap`. Serve come punto di aggancio per chi arriva dai piani post-release e deve essere reindirizzato rapidamente alla documentazione aggiornata.

Baseline pubblico da usare in tutta la pianificazione:

- ultima release pubblica verificata: `1.1.0`
- ogni riferimento a `1.2.0+` va trattato come locale o pianificato finche' non esiste una release pubblica reale

Roadmap principale da consultare:

- [enterprise-xml-roadmap/README.md](./enterprise-xml-roadmap/README.md)

## Snapshot Post-Release

| Area | Stato | Nota |
| --- | --- | --- |
| Release pubblicata | `1.1.0` | baseline pubblico verificato |
| `1.2.0` | `Locale / non pubblicata` | puo' esistere in piani, changelog o branch locali |
| Fasi successive | `Locale / pianificate` | la fonte primaria e' la roadmap enterprise |

## Uso Corretto Di Questo File

- usarlo come entrypoint storico, non come fonte primaria della roadmap futura
- usare il pacchetto `enterprise-xml-roadmap` per decisioni su core completeness, ecosystem topology, capability matrix, milestone e stop condition
- mantenere qui solo il minimo contesto necessario a non perdere il filo tra release passate e piani futuri

## Decisioni O Implicazioni

- Questo file deve restare corto e stabile.
- Le modifiche di sostanza alla roadmap futura vanno fatte nei file sotto `enterprise-xml-roadmap/`.

## Riferimenti

- [release-1.0.md](./release-1.0.md)
- [enterprise-xml-roadmap/README.md](./enterprise-xml-roadmap/README.md)
