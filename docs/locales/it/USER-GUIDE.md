# Usare Smart Clipboard

**Configura una volta. Acquisisci. Attendi Clip ✓. Incolla.** L’app resta nella barra dei menu finché non chiedi di aprirla.

Guida alla **[0.4 in anteprima, build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. Le immagini mostrano le viste attuali in inglese con dati di esempio; selezionale per ingrandirle.

Vai a [IA locale](#configurare-omlx), [vettorizzazione](#creare-svg-dalle-immagini), [traduzione](#lingue-e-traduzione) o [risoluzione dei problemi](#se-la-cattura-non-funziona).

## Installare e avviare

1. [Scarica il DMG firmato](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg), aprilo e trascina **Smart Clipboard** in **Applicazioni**.
2. Espelli il DMG, avvia l’app installata e cerca **Clip** nella barra dei menu. Non ci sono icone nel Dock o finestre da tenere aperte.
3. Apri **Clip → Impostazioni e stato…**. Attiva **Avvia al login** in Generali per trovarla pronta all’avvio del Mac.

Richiede Apple Silicon e macOS 14 o successivo. Chiudere le impostazioni lascia attive le abbreviazioni; **Clip → Esci da Smart Clipboard** termina l’app.

## Acquisire, attendere, incollare

| Passaggio | Cosa fare |
| --- | --- |
| **Acquisire un’area** | Premi **⌃⌘R** e trascina un rettangolo. |
| **Acquisire una finestra** | Premi **⌃⌘W** e fai clic sulla finestra. |
| **Attendere** | **Clip …** diventa **Clip ✓** quando il risultato è copiato. |
| **Incollare** | Premi **⌘V** nell’app di destinazione. |

**⌃⌘R** significa tenere premuti **Control + Comando** e premere **R**; **⌃⌘W** usa **W**. Sono le combinazioni predefinite dalla build 15. Le abbreviazioni salvate, anche da versioni precedenti, hanno la precedenza. Controllale o registra una sostituzione in **Impostazioni → Abbreviazioni**. **Spazio** cambia modalità; **Esc** annulla. Errori e annullamenti conservano il contenuto precedente degli appunti.

Consenti la registrazione dello schermo quando macOS lo chiede, oppure usa **Richiedi accesso allo schermo** in Abbreviazioni. Riapri l’app se richiesto. L’acquisizione non apre impostazioni o editor.

## Scegliere il formato

[![Impostazioni generali con rilevamento automatico e lingua originale selezionati.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Impostazioni → Generali vale per ogni nuova acquisizione. La cronologia ha scelte separate per rielaborare le immagini salvate.*

| Formato preferito | Risultato |
| --- | --- |
| **Rilevamento automatico** | L’IA sceglie un formato modificabile dall’immagine. |
| **Solo immagine (originale)** | L’immagine originale, senza estrazione o IA. |
| **Testo semplice / Markdown** | Parole, appunti, titoli o tabelle modificabili. |
| **JSON / YAML / HTML** | Dati strutturati o codice di markup. |
| **SVG** | Vettorizzazione locale delle forme o ricostruzione con IA. |
| **Descrizione** | Una descrizione scritta dell’immagine. |

**Istruzioni predefinite** aggiunge indicazioni, come «Mantieni le colonne della tabella». Risultati IA, HTML e SVG vengono copiati come testo; l’app non visualizza né esegue il markup generato. Controlla il risultato prima di usarlo.

## Configurare oMLX

[![Connessione locale oMLX con indirizzo del server e modello visivo Qwen3-VL.](../../images/local-connection.png)](../../images/local-connection.png)

*Scegli Locale / oMLX, inserisci l’indirizzo del tuo server e seleziona un modello capace di leggere immagini.*

1. Installa e avvia [oMLX](https://github.com/jundot/omlx). Per iniziare scarica **mlx-community/Qwen3-VL-8B-Instruct-4bit**.
2. In **Impostazioni → Connessione**, scegli **Locale / oMLX**. L’indirizzo deve terminare con `/v1`; `http://127.0.0.1:8999/v1` è un esempio, non una porta universale.
3. Premi **Aggiorna modelli** e seleziona l’identificatore esatto del modello visivo. Il server può omettere il prefisso `mlx-community/`.
4. Se serve una chiave, inseriscila e premi **Salva chiave**. Un server su un altro computer richiede una chiave; usa HTTPS fuori da una rete locale privata.
5. Premi **Prova elaborazione immagini**. Usa un campione generato, non il tuo schermo. Scegli poi il formato in Generali e chiudi le impostazioni.

Lascia oMLX in esecuzione per l’estrazione con IA. Smart Clipboard non scarica modelli, avvia il server o passa al cloud in caso di errore. **Vettorizza sul dispositivo** e **Solo immagine** funzionano senza oMLX.

### Scegliere un modello locale

Inizia con **Qwen3-VL-8B-Instruct-4bit** per testo, tabelle e traduzione. Il modello **32B** più grande non ha risolto gli errori di Descrizione/SVG nei nostri test. Per vettorizzare immagini scegli **Vettorizza sul dispositivo**: non serve un modello.

Il server provato è il pacchetto ufficiale **[oMLX 0.7.0.dev2](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2)**. La versione 0.6.4 ha un errore nell’output strutturato con questo modello; uno più grande non lo risolve. I test non coprono versioni successive del server.

<details>
<summary>Dimensioni, memoria e risultati dei test</summary>

Sono conversioni MLX Community a 4 bit di modelli Qwen con capacità visive. Usa l’identificatore completo nel downloader di oMLX:

| Modello | Download | Risultati al 22 settembre 2026 |
| --- | --- | --- |
| [mlx-community/Qwen3-VL-8B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit) | Circa 5,78 GB secondo l’[elenco del distributore](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit/tree/main). | Testo, tabelle e dati strutturati hanno funzionato sulle immagini sintetiche provate. Descrizione ha inventato osservazioni ortografiche; SVG ha alterato proporzioni, bordi o disposizione. |
| [mlx-community/Qwen3-VL-32B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit) | Download verificato: 19.636.446.591 byte in 19 file, circa 19,64 GB / 18,29 GiB. | Con oMLX 0.7.0.dev2 ha conservato i valori, ma Descrizione ha inventato allineamenti e SVG ha usato un’area errata e aggiunto una riga. Sei prove delle istruzioni hanno migliorato le dimensioni senza risolvere contenuto e disposizione. |

Il download 32B corrisponde alla [revisione `6e5644d`](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit/tree/6e5644d3ea4b953b5221ffd02339bf897041038a). Le dimensioni riguardano il disco, non la memoria durante l’uso.

**Stime di memoria:** considera almeno 16 GB di memoria unificata per 8B o 48 GB per 32B, più margine per immagini grandi, contesto e altre app. Sono stime prudenti, non requisiti minimi verificati o garanzie di velocità. I test usavano un Mac da 128 GiB; i Mac con meno memoria non sono stati validati. Lascia spazio per le cache e inizia da una piccola immagine senza dati privati.

Nessuno dei due ha superato la valutazione di qualità di tutti i formati. Descrizione e SVG restano sperimentali. Consulta le [prove locali](../../testing/OMLX.md) per distinguere controlli automatici e qualità visiva.

</details>

## Altre connessioni

Per **OpenAI**, **Anthropic**, **Google Gemini** o **Perplexity**, seleziona il servizio in Connessione, inserisci la chiave API, premi **Salva chiave**, scegli un modello visivo ed esegui **Prova elaborazione immagini**. Accesso e fatturazione API sono separati dagli abbonamenti alle chat. Ogni servizio conserva le proprie impostazioni e la propria chiave.

Per **ChatGPT tramite Codex**, installa o aggiorna Codex CLI e scegli **Accedi con ChatGPT**. Lascia **Eseguibile Codex** vuoto per il rilevamento automatico, poi esegui la prova dell’immagine. Servono un account Codex idoneo e la CLI ufficiale compatibile; valgono i limiti dell’abbonamento.

Se una chiave salvata richiede approvazione dopo un aggiornamento, premi **Autorizza chiave salvata**. Le acquisizioni in background non aprono finestre del Portachiavi. Non tutte le connessioni cloud sono state verificate dal vivo: consulta lo [stato dei servizi](../../PROVIDERS.md).

## Creare SVG dalle immagini

[![Vettorizzazione sul dispositivo con profilo Foto e dettaglio Bilanciato.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Scegli esplicitamente Vettorizza sul dispositivo. Ricostruisci con l’IA resta il metodo predefinito dopo un aggiornamento.*

### Foto, loghi e disegni

1. In **Impostazioni → Generali**, scegli **Formato preferito → SVG** e **Metodo SVG → Vettorizza sul dispositivo**.
2. Seleziona **Foto**, **Logo** o **Disegno al tratto** in base all’immagine.
3. Parti da **Bilanciato**. **Dettagliato** conserva più forme e colori, ma crea file più grandi.
4. Chiudi le impostazioni, acquisisci, attendi **Clip ✓** e incolla.

Funziona offline con il componente VTracer incluso: non servono chiave API, modello, server o installazioni aggiuntive. Segue le forme visibili, conserva lo sfondo e trasforma le parole in contorni. Non traduce, rimuove sfondi o recupera dati dai grafici. Le istruzioni non si applicano e un errore non fa passare all’IA.

**Per un editor vettoriale:** apri la schermata in **Cronologia**, premi **Salva…** e importa il file `.svg`. In un editor di testo viene incollato il codice SVG. Per SVG grandi l’app mostra un riepilogo compatto; **Copia** e **Salva…** mantengono il risultato completo.

### Vettorizzare una schermata salvata

Apri **Clip → Cronologia → Apri**, scegli **SVG → Vettorizza sul dispositivo**, imposta profilo e dettaglio, poi premi **Vettorizza in SVG**. Usa **Copia** o **Salva…**. Ogni combinazione di metodo, profilo e dettaglio conserva il proprio risultato. Queste scelte manuali non cambiano le preferenze delle acquisizioni automatiche.

### Ricostruire con IA

Scegli **SVG → Ricostruisci con l’IA** per far interpretare e ricostruire un diagramma o un’illustrazione al modello configurato. Può seguire istruzioni e preferenze linguistiche, ma anche cambiare o inventare dettagli. Prova prima la connessione e confronta il risultato con l’originale.

## Lingue e traduzione

In **Generali → Lingue → Risultato dell’acquisizione**, scegli:

| Scelta | Risultato |
| --- | --- |
| **Mantieni lingua originale** | Conserva la lingua rilevata nell’immagine. È l’opzione predefinita. |
| **Lingua di sistema** | Traduce le acquisizioni IA nella lingua preferita del Mac. |
| **Una lingua specifica** | Traduce indipendentemente dalla lingua del Mac. |

Una scelta esplicita prevale sulle istruzioni di traduzione. Le impostazioni precedenti possono mostrare **Usa istruzioni salvate** finché non scegli una lingua. I cambiamenti valgono dalla prossima acquisizione. Controlla traduzioni e valori estratti: la qualità dipende dal modello.

L’interfaccia segue separatamente macOS in inglese, italiano, spagnolo, francese o tedesco, con l’inglese come alternativa. Riavvia l’app dopo averne cambiato la lingua. **Solo immagine**, la vettorizzazione locale ed **Estrai testo sul dispositivo** non traducono. Le descrizioni in modalità lingua originale usano l’inglese quando non c’è testo leggibile per identificare la lingua.

## Riutilizzare le schermate

[![Cronologia con schermate di esempio e versioni separate per formato e lingua.](../../images/history.png)](../../images/history.png)

*L’originale e le sue versioni restano insieme. Aprire la cronologia non cambia gli appunti.*

Premi **Apri**, scegli un altro formato o **Lingua del risultato**, poi **Converti con IA**. Per OCR offline scegli **Estrai testo sul dispositivo**; per i vettori, **Vettorizza in SVG**. **Formati salvati** carica un risultato senza rielaborarlo.

[![Nota di esempio con risultato Markdown modificabile e controlli di lingua, copia e salvataggio.](../../images/result.png)](../../images/result.png)

*Questa finestra si apre solo su richiesta. Le normali acquisizioni copiano direttamente in background.*

Premi **Copia** o attiva **Copia dopo la conversione manuale**. Ripetere lo stesso formato e lingua sostituisce solo quella versione; le altre restano.

In **Impostazioni → Cronologia**, scegli il limite (50 per impostazione predefinita, fino a 500), elimina una voce o cancella tutto. Zero svuota e disattiva la cronologia. File esportati e appunti restano invariati.

## Notifiche

In **Generali → Notifiche di acquisizione**, scegli **Abilita notifiche** e consenti la richiesta di macOS. Seleziona completamento, errore o entrambi; il suono è facoltativo. Le notifiche includono solo stato e formato. Aprono l’app soltanto se fai clic.

| Stato | Significato |
| --- | --- |
| **Clip …** | Acquisizione o conversione in corso. |
| **Clip ✓** | Risultato negli appunti. |
| **Clip !** | Apri il menu per leggere il problema. |

**Clip ✓ senza banner?** Puoi incollare. Full immersion o la condivisione/registrazione dello schermo possono nascondere o silenziare gli avvisi anche se abilitati. L’app rispetta queste impostazioni. Consulta la [risoluzione dei problemi](#se-la-cattura-non-funziona).

## Privacy e archiviazione

L’app acquisisce solo l’area o la finestra richiesta; non sorveglia continuamente schermo o appunti. Le immagini elaborate dall’IA vanno al servizio scelto. oMLX su `127.0.0.1` resta su questo Mac; un server remoto riceve lì la schermata. La conservazione nel cloud dipende dalle regole del servizio.

Vettorizzazione locale, solo immagine e OCR Apple non richiedono un servizio IA. Le chiavi sono nel Portachiavi macOS; le credenziali ChatGPT restano in Codex.

La cronologia è in `~/Library/Application Support/Smart Clipboard/History/`, accessibile al tuo utente Mac ma senza cifratura separata. File esportati e appunti sono indipendenti dalla cronologia.

## Aggiornamenti

Usa **Clip → Cerca aggiornamenti…** oppure **Informazioni**. I controlli giornalieri facoltativi aggiungono un avviso al menu senza aprire finestre. Preferenze, cronologia e connessione scelta vengono conservate.

Le versioni stabili sono predefinite. Scegli **Informazioni → Versioni → Versioni stabili e di anteprima** per ricevere anteprime come la build 15. Le vecchie app senza aggiornamento integrato richiedono una sostituzione manuale dal DMG ufficiale.

## Se la cattura non funziona

| Sintomo | Cosa controllare |
| --- | --- |
| Il menu Clip manca | Apri l’app installata; una barra affollata può nascondere le icone. |
| L’abbreviazione non risponde | Controlla permessi e conflitti in **Impostazioni → Abbreviazioni**. |
| L’accesso allo schermo risulta ancora necessario | Esci e riapri. Per vecchie build di sviluppo, vedi il recupero qui sotto. |
| Server o modello non disponibile | Avvia oMLX, verifica la porta, aggiorna i modelli e scegli un modello visivo. |
| Testo ripetuto o conversione incompleta | Controlla oMLX: la 0.6.4 ha il problema descritto sopra. |
| Viene incollata un’immagine invece del testo | Cambia **Formato preferito** da Solo immagine a Rilevamento automatico o testo. |
| Viene incollato il contenuto precedente | Attendi **Clip ✓**. Un errore conserva gli appunti precedenti. |
| Non arrivano banner o suoni | Controlla Full immersion e condivisione/registrazione. **Clip ✓** significa comunque pronto. |

<details>
<summary>Ripristinare il permesso dopo una vecchia build di sviluppo</summary>

In **Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo e audio di sistema**, disattiva e riattiva solo Smart Clipboard, accettando di uscire e riaprire quando proposto. Se necessario, rimuovi la vecchia voce e aggiungi `/Applications/Smart Clipboard.app` con **+**. Se macOS non permette di rimuoverla, chiedi assistenza per un ripristino limitato a questa app; non azzerare i permessi delle altre. Preferenze e cronologia restano conservate.

</details>

<details>
<summary>Perché gli avvisi possono sparire durante la condivisione</summary>

macOS può sopprimere banner e suoni durante condivisione, duplicazione o registrazione dello schermo, anche senza Full immersion. Interrompi la sessione e riprova. Consentire notifiche durante la condivisione è una scelta di privacy dell’intero sistema, non un requisito per acquisire schermate. Il permesso di Smart Clipboard non significa che registri continuamente.

</details>

[Segnala un problema](https://github.com/colombod/smart-clipboard/issues/new) indicando build, versione macOS, servizio/modello ed errore del menu. Non includere chiavi o immagini private. Consulta lo [stato dell’accessibilità](../../ACCESSIBILITY.md) e i [limiti dell’anteprima](../../releases/v0.4.0-preview.md).
