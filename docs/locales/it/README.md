# Smart Clipboard

<img src="../../app-icon.png" alt="Icona di Smart Clipboard con cornice di acquisizione" width="100">

**Cattura ciò che vedi. Incolla ciò che ti serve.**

Un’app discreta nella barra dei menu del Mac che trasforma le schermate in testo, tabelle, dati strutturati o SVG. Scegli le preferenze una volta, poi acquisisci e incolla senza aprire l’app.

**[Scarica per Mac](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon · macOS 14 o successivo · Firmata e autenticata da Apple

Versione attuale: **[0.4 in anteprima, build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. [Limiti noti dell’anteprima](../../releases/v0.4.0-preview.md).

## Per iniziare

1. **Installa:** apri il DMG e trascina Smart Clipboard in **Applicazioni**. Avvia l’app e cerca **Clip** nella barra dei menu.
2. **Configura una volta:** apri **Clip → Impostazioni e stato…**. Scegli il formato in **Generali** e, se serve, una connessione IA.
3. **Acquisisci e incolla:** chiudi le impostazioni, premi **⌃⌘R**, seleziona un’area, attendi **Clip ✓** e premi **⌘V** nell’app di destinazione.

Usa **⌃⌘W** per una finestra. **Spazio** cambia modalità di selezione; **Esc** annulla. Le abbreviazioni salvate hanno la precedenza. Consenti la registrazione dello schermo quando macOS lo richiede.

## Scegli cosa incollare

[![Impostazioni generali con rilevamento automatico e mantenimento della lingua originale.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Scegli il risultato una volta. Le impostazioni possono restare chiuse mentre lavori. Seleziona un’immagine per ingrandirla; le schermate della guida mostrano l’interfaccia in inglese.*

- **Rilevamento automatico:** lascia scegliere all’IA un formato utile.
- **Testo semplice, Markdown, HTML, JSON o YAML:** scegli un risultato modificabile preciso.
- **Solo immagine:** conserva l’immagine senza IA.
- **SVG:** vettorizza le forme sul Mac o ricostruisci con l’IA.

Per l’elaborazione IA usa il tuo account di un servizio cloud oppure **Locale / oMLX**. [Configurare la connessione →](USER-GUIDE.md#configurare-omlx)

## Trasforma un’immagine in SVG

[![Impostazioni SVG con vettorizzazione sul dispositivo, profilo Foto e dettaglio Bilanciato.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Generali → SVG → Vettorizza sul dispositivo. Non servono account, modelli o server.*

Scegli **Foto**, **Logo** o **Disegno al tratto**, poi acquisisci come sempre. **Bilanciato** contiene le dimensioni del file; **Dettagliato** conserva più forme e colori. Incolla il codice SVG oppure usa **Cronologia → Apri → Salva…** per importarlo in un editor vettoriale.

La vettorizzazione mantiene lo sfondo e trasforma le parole in contorni. Per usare un modello scegli **Ricostruisci con l’IA**. [Guida alla vettorizzazione →](USER-GUIDE.md#creare-svg-dalle-immagini)

## Riutilizza una schermata

[![Cronologia con schermate di esempio e versioni separate in testo, Markdown e francese.](../../images/history.png)](../../images/history.png)

*Apri la cronologia solo quando serve. Riutilizza l’originale senza acquisirlo di nuovo.*

Scegli un altro formato o una lingua e converti. **Formati salvati** riapre i risultati precedenti; **Copia** li mette negli appunti. Imposta il limite o cancella le schermate in **Impostazioni → Cronologia**.

## Scopri quando è pronto

**Clip …** indica un’elaborazione in corso. **Clip ✓** significa che puoi incollare. **Clip !** segnala un problema: apri il menu per leggerlo.

In **Generali** puoi attivare notifiche di completamento o errore e il suono. Una modalità Full immersion o la condivisione dello schermo può sopprimere gli avvisi; lo stato nel menu resta disponibile. [Aiuto per le notifiche →](USER-GUIDE.md#notifiche)

## Serve una mano?

[Guida illustrata](USER-GUIDE.md) · [Modelli locali](USER-GUIDE.md#scegliere-un-modello-locale) · [Traduzione](USER-GUIDE.md#lingue-e-traduzione) · [Risoluzione dei problemi](USER-GUIDE.md#se-la-cattura-non-funziona)

L’app segue l’aspetto chiaro o scuro di macOS e supporta inglese, italiano, spagnolo, francese e tedesco. Le schermate mantengono la lingua originale, salvo attivare la traduzione. La vettorizzazione locale funziona offline; le immagini elaborate dall’IA vanno alla connessione scelta. [Privacy](USER-GUIDE.md#privacy-e-archiviazione).

*Le immagini mostrano le viste attuali con dati di esempio. È un’anteprima: controlla i risultati dell’IA. La verifica di tutti i servizi cloud e la [valutazione completa dell’accessibilità](../../ACCESSIBILITY.md) non sono ancora concluse.*

[Segnala un problema](https://github.com/colombod/smart-clipboard/issues/new) · [Guida per sviluppatori](../../DEVELOPING.md)
