# Smart Clipboard

<img src="../../app-icon.png" alt="Smart-Clipboard-Symbol mit Aufnahmerahmen" width="100">

**Auf dem Bildschirm aufnehmen. Als nützlichen Inhalt einfügen.**

Eine unaufdringliche App in der Menüleiste deines Mac, die Bildschirmfotos in Text, Tabellen, strukturierte Daten oder SVG umwandelt. Lege deine Wünsche einmal fest. Danach kannst du aufnehmen und einfügen, ohne die App zu öffnen.

**[Für Mac herunterladen](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon · macOS 14 oder neuer · Signiert und von Apple notarisiert

Aktuelle Version: **[0.4 Vorabversion, Build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. [Bekannte Einschränkungen der Vorabversion](../../releases/v0.4.0-preview.md).

## Erste Schritte

1. **Installieren:** Öffne die DMG-Datei und ziehe Smart Clipboard in **Programme**. Starte die App und suche nach **Clip** in der Menüleiste.
2. **Einmal einrichten:** Öffne **Clip → Einstellungen & Status …**. Wähle unter **Allgemein** das Ausgabeformat und richte bei Bedarf eine KI-Verbindung ein.
3. **Aufnehmen und einfügen:** Schließe die Einstellungen, drücke **⌃⌘R**, markiere einen Bereich und warte auf **Clip ✓**. Drücke dann **⌘V** in deiner Ziel-App.

Mit **⌃⌘W** nimmst du ein Fenster auf. Die **Leertaste** wechselt den Auswahlmodus; **Escape** bricht ab. Deine gespeicherten Kurzbefehle haben Vorrang. Erlaube die Bildschirmaufnahme, wenn macOS danach fragt.

## Wähle, was du einfügen möchtest

[![Allgemeine Einstellungen mit automatischer Formaterkennung und beibehaltener Originalsprache.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Wähle das gewünschte Ergebnis einmal aus. Während der Arbeit können die Einstellungen geschlossen bleiben. Klicke auf ein Bildschirmfoto, um es zu vergrößern. Die abgebildete Benutzeroberfläche ist auf Englisch.*

- **Automatisch erkennen:** Die KI wählt ein sinnvolles Format.
- **Reiner Text, Markdown, HTML, JSON oder YAML:** Wähle ein bestimmtes bearbeitbares Ergebnis.
- **Ohne Umwandlung (Bild):** Behalte das Bild ohne KI-Verarbeitung.
- **SVG:** Vektorisiere Formen auf dem Mac oder rekonstruiere sie mit KI.

Für die KI-Verarbeitung verwendest du dein eigenes Cloud-Konto oder **Lokal / oMLX**. [Verbindung einrichten →](USER-GUIDE.md#lokale-bildverarbeitung-mit-omlx-einrichten)

## Ein Bild in SVG umwandeln

[![SVG-Einstellungen mit lokaler Vektorisierung, Vorlage Foto und Detailgrad Ausgewogen.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Allgemein → SVG → Auf diesem Mac vektorisieren. Kein Konto, Modell oder Server erforderlich.*

Wähle **Foto**, **Logo** oder **Strichzeichnung** und nimm wie gewohnt auf. **Ausgewogen** hält die Dateien kleiner; **Detailliert** erhält mehr Formen und Farben. Füge den SVG-Quelltext ein oder verwende **Verlauf → Öffnen → Sichern …**, um das Ergebnis in einem Vektorprogramm zu öffnen.

Die Vektorisierung erhält den Hintergrund und wandelt Wörter in Pfade um. Für eine Rekonstruktion durch ein Modell wähle **Mit KI rekonstruieren**. [Anleitung zur Vektorisierung →](USER-GUIDE.md#ein-bild-als-svg-vektorisieren)

## Eine Aufnahme erneut verwenden

[![Verlauf mit Beispielaufnahmen und getrennt gespeicherten Versionen als Text, Markdown und auf Französisch.](../../images/history.png)](../../images/history.png)

*Öffne den Verlauf nur bei Bedarf. Verwende das Original erneut, ohne ein weiteres Bildschirmfoto aufzunehmen.*

Wähle ein anderes Format oder eine andere Sprache und starte die Umwandlung. **Gespeicherte Formate** öffnet frühere Ergebnisse; **Kopieren** legt eines davon in die Zwischenablage. Unter **Einstellungen → Verlauf** kannst du das Speicherlimit festlegen oder gespeicherte Aufnahmen löschen.

## Erkennen, wann das Ergebnis bereit ist

**Clip …** bedeutet, dass die Verarbeitung läuft. Bei **Clip ✓** kannst du einfügen. **Clip !** weist auf ein Problem hin: Öffne das Menü, um es nachzulesen.

Unter **Allgemein** kannst du Mitteilungen bei Erfolg oder Fehlern sowie einen Ton aktivieren. Ein Fokus oder eine Bildschirmfreigabe kann diese Hinweise unterdrücken; der Status im Menü bleibt sichtbar. [Hilfe zu Mitteilungen →](USER-GUIDE.md#mitteilungen-bei-erfolg-oder-fehlern)

## Brauchst du Hilfe?

[Bebilderte Anleitung](USER-GUIDE.md) · [Lokale Modelle](USER-GUIDE.md#ein-lokales-modell-auswählen) · [Übersetzung](USER-GUIDE.md#sprachen-und-übersetzung) · [Probleme beheben](USER-GUIDE.md#wenn-die-aufnahme-nicht-funktioniert)

Die App folgt dem hellen oder dunklen Erscheinungsbild von macOS und unterstützt Englisch, Italienisch, Spanisch, Französisch und Deutsch. Aufnahmen behalten ihre Originalsprache, solange du keine Übersetzung aktivierst. Lokale Vektorisierung funktioniert offline; KI-Aufnahmen werden an deine ausgewählte Verbindung gesendet. [Datenschutz und Speicherung](USER-GUIDE.md#datenschutz-und-speicherung).

*Die Bildschirmfotos zeigen die aktuellen Ansichten mit Beispieldaten. Dies ist eine Vorabversion: Prüfe die KI-Ergebnisse. Die Überprüfung aller Cloud-Verbindungen und die vollständige [Abnahme der Barrierefreiheit](../../ACCESSIBILITY.md) stehen noch aus.*

[Problem melden](https://github.com/colombod/smart-clipboard/issues/new) · [Entwicklerdokumentation](../../DEVELOPING.md)
