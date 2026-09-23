# Smart Clipboard verwenden

**Einmal einrichten. Aufnehmen. Auf Clip ✓ warten. Einfügen.** Die App bleibt in der Menüleiste, bis du sie selbst öffnest.

Diese bebilderte Anleitung gilt für **[0.4 Vorabversion, Build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. Die Bildschirmfotos zeigen die aktuelle Benutzeroberfläche auf Englisch mit Beispieldaten. Klicke auf ein Bild, um es zu vergrößern.

Direkt zu [lokaler KI](#lokale-bildverarbeitung-mit-omlx-einrichten), [Vektorisierung](#ein-bild-als-svg-vektorisieren), [Übersetzung](#sprachen-und-übersetzung) oder [Problemlösungen](#wenn-die-aufnahme-nicht-funktioniert).

## Installieren und starten

1. [Lade die signierte DMG-Datei herunter](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg), öffne sie und ziehe **Smart Clipboard** in **Programme**.
2. Wirf die DMG-Datei aus, öffne die installierte App und suche nach **Clip** in der Menüleiste. Es gibt kein Dock-Symbol und kein Fenster, das offen bleiben muss.
3. Öffne **Clip → Einstellungen & Status …**, um die App einzurichten. Aktiviere unter Allgemein **Bei Anmeldung starten**, wenn die App beim Start deines Mac bereitstehen soll.

Erforderlich sind Apple Silicon und macOS 14 oder neuer. Die Kurzbefehle funktionieren auch bei geschlossenen Einstellungen. **Clip → Smart Clipboard beenden** beendet die App.

## Aufnehmen, warten, einfügen

| Schritt | So geht es |
| --- | --- |
| **Bereich aufnehmen** | Drücke **⌃⌘R** und ziehe ein Rechteck auf. |
| **Fenster aufnehmen** | Drücke **⌃⌘W** und klicke auf das Fenster. |
| **Warten** | Sobald das Ergebnis kopiert wurde, wechselt **Clip …** zu **Clip ✓**. |
| **Einfügen** | Drücke **⌘V** in deiner Ziel-App. |

**⌃⌘R** bedeutet: **Control + Command** gedrückt halten und **R** drücken. Für **⌃⌘W** verwendest du **W**. Diese Standardbelegungen gelten ab Build 15. Gespeicherte Kurzbefehle haben Vorrang, auch solche aus älteren Versionen. Unter **Einstellungen → Kurzbefehle** kannst du sie ansehen oder eine neue Kombination aufnehmen. Die **Leertaste** wechselt den Auswahlmodus; **Escape** bricht ab. Bei einem Fehler oder Abbruch bleibt der bisherige Inhalt deiner Zwischenablage erhalten.

Erlaube die Bildschirmaufnahme, wenn macOS danach fragt. Unter Kurzbefehle kannst du auch **Bildschirmzugriff anfordern** wählen. Öffne die App erneut, falls macOS dich dazu auffordert. Eine Aufnahme öffnet weder die Einstellungen noch den Editor.

## Das Ausgabeformat einmal festlegen

[![Allgemeine Einstellungen mit automatischer Erkennung und beibehaltener Originalsprache.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Einstellungen → Allgemein gilt für jede neue Aufnahme. Im Verlauf wählst du gesondert, wie gespeicherte Bilder erneut verarbeitet werden sollen.*

| Bevorzugtes Format | Ergebnis |
| --- | --- |
| **Automatisch erkennen** | Die KI wählt anhand des Bildes ein sinnvolles, bearbeitbares Format. |
| **Ohne Umwandlung (Bild)** | Das Originalbild ohne Texterkennung oder KI. |
| **Reiner Text / Markdown** | Bearbeitbarer Text, Notizen, Überschriften oder Tabellen. |
| **JSON / YAML / HTML** | Strukturierte Daten oder Auszeichnungssprache als Quelltext. |
| **SVG** | Lokale Vektorisierung von Formen oder Rekonstruktion mit KI. |
| **Beschreibung** | Eine schriftliche Beschreibung des Bildes. |

Mit **Standardanweisung** ergänzt du Vorgaben wie „Tabellenspalten beibehalten“. KI-Ergebnisse, HTML und SVG werden als Text kopiert. Die App stellt erzeugten HTML- oder SVG-Code nicht dar und führt ihn nicht aus. Prüfe KI-Ergebnisse, bevor du sie verwendest.

## Lokale Bildverarbeitung mit oMLX einrichten

[![Lokale oMLX-Verbindung mit einer Serveradresse auf diesem Mac und einem Qwen3-VL-Bildmodell.](../../images/local-connection.png)](../../images/local-connection.png)

*Wähle Lokal / oMLX, gib die Adresse deines Servers ein und wähle ein Modell mit Bildunterstützung.*

1. Installiere und starte [oMLX](https://github.com/jundot/omlx). Lade für den Einstieg **mlx-community/Qwen3-VL-8B-Instruct-4bit** herunter.
2. Wähle unter **Einstellungen → Verbindung** die Option **Lokal / oMLX**. Gib die Serveradresse mit `/v1` am Ende ein. Die abgebildete Adresse `http://127.0.0.1:8999/v1` ist ein Beispiel; dein Server kann einen anderen Port verwenden.
3. Klicke auf **Modelle aktualisieren** und wähle das Bildmodell genau so aus, wie es in der Liste erscheint. Der Server kann den Vorsatz `mlx-community/` weglassen.
4. Falls dein Server einen Schlüssel benötigt, gib ihn ein und wähle **Schlüssel speichern**. Für einen Server auf einem anderen Computer ist ein Schlüssel erforderlich. Verwende außerhalb eines privaten lokalen Netzwerks HTTPS.
5. Klicke auf **Bildverarbeitung testen**. Dabei wird ein erzeugtes Beispielbild verwendet, kein Inhalt deines Bildschirms. Wähle anschließend unter Allgemein dein bevorzugtes Ausgabeformat und schließe die Einstellungen.

Lass oMLX für die KI-Verarbeitung laufen. Smart Clipboard lädt keine Modelle herunter, startet den Server nicht und wechselt nicht zu einem Cloud-Anbieter. **Auf diesem Mac vektorisieren** und **Ohne Umwandlung (Bild)** funktionieren ohne oMLX.

### Ein lokales Modell auswählen

Beginne für Text, Tabellen und Übersetzungen mit **Qwen3-VL-8B-Instruct-4bit**. Das größere **32B**-Modell behob die Fehler bei Beschreibung und SVG in unseren Tests nicht. Für die Vektorisierung eines Bildes nutze **Auf diesem Mac vektorisieren**; dafür brauchst du kein Modell.

Getestet wurde die offizielle Version **[oMLX 0.7.0.dev2](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2)**. Version 0.6.4 hat mit diesem Bildmodell einen Fehler bei strukturierten Ausgaben. Ein größeres Modell behebt diesen Serverfehler nicht. Neuere Serverversionen wurden in diesen Tests nicht untersucht.

<details>
<summary>Modellgrößen, Arbeitsspeicher und Testergebnisse</summary>

Die folgenden Modelle sind 4-Bit-Konvertierungen bildfähiger Qwen-Modelle von MLX Community. Kopiere die vollständige Download-ID in die Downloadfunktion von oMLX:

| Download-ID und Modellbeschreibung | Downloadgröße | Stand vom 22. September 2026 |
| --- | --- | --- |
| [mlx-community/Qwen3-VL-8B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit) | Laut [Dateiliste des Herausgebers](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit/tree/main) etwa 5,78 GB. | Kleineres Modell für erste lokale Tests. Text, Tabellen und strukturierte Daten funktionierten mit den getesteten synthetischen Bildern. Bei Beschreibung erfand das Modell Aussagen zur Rechtschreibung; bei SVG änderte es Seitenverhältnis, Ränder oder Layout. Es hat die Qualitätsabnahme über alle Formate hinweg nicht bestanden. |
| [mlx-community/Qwen3-VL-32B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit) | Verifizierter Download: 19.636.446.591 Bytes in 19 Dateien, etwa 19,64 GB / 18,29 GiB. | Mit oMLX 0.7.0.dev2 getestet. Die Testwerte blieben erhalten, aber bei Beschreibung erfand das Modell Details zur Ausrichtung. Bei SVG verwendete es eine falsche Zeichenfläche und fügte eine Tabellenzeile hinzu. Sechs Varianten der Anweisungen verbesserten die Abmessungen der Zeichenfläche, behoben aber die Fehler in Inhalt und Layout nicht. Es hat die Qualitätsabnahme über alle Formate hinweg nicht bestanden. |

Der gemessene 32B-Download entspricht [Revision `6e5644d` des Herausgebers](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit/tree/6e5644d3ea4b953b5221ffd02339bf897041038a). Diese Größen betreffen den Speicherplatz auf der Festplatte, nicht den Arbeitsspeicher beim Betrieb.

**Schätzungen für die Speicherplanung:** Plane mindestens 16 GB gemeinsamen Arbeitsspeicher für das 8B-Modell oder 48 GB für 32B ein, dazu Reserven für größere Bilder, Kontext und andere Apps. Das sind vorsichtige Schätzungen, keine bestätigten Mindestanforderungen oder Geschwindigkeitsgarantien. Die dokumentierten Tests liefen auf einem Mac mit 128 GiB; Macs mit weniger Arbeitsspeicher wurden nicht geprüft. Halte zusätzlichen Festplattenspeicher für Server-Caches frei. Beginne mit einem kleinen, nicht vertraulichen Beispiel und prüfe das Ergebnis, bevor du dich auf eines der Modelle verlässt.

Beobachtete Ergebnisse und den Unterschied zwischen automatisierten Prüfungen und visueller Qualität findest du in den [lokalen Testnachweisen](../../testing/OMLX.md). Beschreibung und KI-SVG bleiben in dieser Vorabversion experimentell; die Qualitätsabnahme über alle Formate hinweg ist nicht bestanden.

</details>

## Eine andere Verbindung wählen

Wähle für **OpenAI**, **Anthropic**, **Google Gemini** oder **Perplexity** den Anbieter unter Verbindung aus, gib seinen API-Schlüssel ein und klicke auf **Schlüssel speichern**. Wähle ein Modell mit Bildunterstützung und führe **Bildverarbeitung testen** aus. API-Zugriff und Abrechnung sind von privaten Chat-Abonnements getrennt. Für jeden Anbieter werden Einstellungen und Schlüssel getrennt gespeichert.

Für **ChatGPT über Codex** folge **Codex CLI installieren / aktualisieren ↗** und wähle danach **Mit ChatGPT anmelden**. Lass **Ausführbare Codex-Datei** zur automatischen Erkennung leer und teste nach der Anmeldung die Bildverarbeitung. Erforderlich sind ein Konto mit Codex-Zugriff und eine kompatible offizielle CLI. Die Nutzung unterliegt den Grenzen deines Abonnements.

Falls ein gespeicherter Schlüssel nach einem Update eine Freigabe benötigt, wähle ausdrücklich **Gespeicherten Schlüssel freigeben**. Hintergrundaufnahmen öffnen niemals einen Schlüsselbunddialog. Nicht alle Cloud-Verbindungen wurden in dieser Vorabversion mit echten Anfragen überprüft; siehe [Verbindungsstatus](../../PROVIDERS.md).

## Ein Bild als SVG vektorisieren

[![SVG-Verarbeitung mit lokaler Vektorisierung, Vorlage Foto und Detailgrad Ausgewogen.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Wähle Auf diesem Mac vektorisieren ausdrücklich aus. Nach einem Upgrade bleibt Mit KI rekonstruieren die voreingestellte SVG-Methode.*

### Fotos, Logos und Zeichnungen auf dem Mac vektorisieren

1. Wähle unter **Einstellungen → Allgemein** zuerst **Bevorzugtes Format → SVG** und dann **SVG-Methode → Auf diesem Mac vektorisieren**.
2. Wähle passend zum Bild **Foto**, **Logo** oder **Strichzeichnung**.
3. Beginne mit dem Detailgrad **Ausgewogen**. **Detailliert** erhält mehr Formen und Farben, erzeugt aber größere Dateien.
4. Schließe die Einstellungen, nimm auf, warte auf **Clip ✓** und füge das Ergebnis ein.

Die Vektorisierung funktioniert offline mit der enthaltenen VTracer-Komponente. Du brauchst weder API-Schlüssel noch Modell, Server oder zusätzliche Installation. Sie folgt sichtbaren Formen, erhält den Hintergrund und wandelt Wörter in Pfade um. Sie übersetzt nicht, entfernt keine Hintergründe und gewinnt keine Daten aus Diagrammen zurück. Anweisungen werden nicht angewendet. Schlägt die Vektorisierung fehl, wird niemals automatisch zu KI gewechselt.

**Für ein Vektorprogramm:** Öffne die Aufnahme im **Verlauf**, wähle **Sichern …** und öffne oder importiere dann die `.svg`-Datei. Beim Einfügen in einen Texteditor siehst du SVG-Quelltext. Für große SVG-Dateien zeigt Smart Clipboard eine kompakte Zusammenfassung an; das vollständige Ergebnis bleibt zum Kopieren oder Sichern verfügbar.

### Eine frühere Aufnahme vektorisieren

Öffne **Clip → Verlauf → Öffnen**, wähle **SVG → Auf diesem Mac vektorisieren**, lege Vorlage und Detailgrad fest und klicke auf **Als SVG vektorisieren**. Verwende anschließend **Kopieren** oder **Sichern …**. Jede Kombination aus Methode, Vorlage und Detailgrad behält ihr eigenes gespeichertes Ergebnis. Diese manuellen Entscheidungen ändern deine Einstellungen für automatische Aufnahmen nicht.

### Mit deiner KI-Verbindung rekonstruieren

Wähle **SVG → Mit KI rekonstruieren**, damit dein eingerichtetes Modell ein Diagramm oder eine Illustration interpretiert und nachbildet. Dabei können Anweisungen und Sprachwünsche berücksichtigt werden, aber das Modell kann Details verändern oder erfinden. Teste zuerst deine KI-Verbindung und vergleiche das Ergebnis mit dem Original.

## Sprachen und Übersetzung

Wähle unter **Allgemein → Sprachen → Aufnahmeergebnis**:

| Auswahl | Ergebnis |
| --- | --- |
| **Originalsprache beibehalten** | Die im Bild erkannte Sprache bleibt erhalten. Dies ist die Voreinstellung. |
| **Systemsprache** | KI-Aufnahmen werden in die bevorzugte Sprache deines Mac übersetzt. |
| **Eine bestimmte Sprache** | Die Übersetzung erfolgt unabhängig von der Sprache des Mac. |

Eine ausdrückliche Sprachwahl hat Vorrang vor Übersetzungsanweisungen. Bei älteren Einstellungen kann **Gespeicherte Anweisungen verwenden** angezeigt werden, bis du eine Sprache wählst. Änderungen gelten ab der nächsten Aufnahme. Die Qualität hängt vom Modell ab; prüfe Übersetzungen und extrahierte Werte.

Die Sprache der Benutzeroberfläche wird getrennt davon durch macOS bestimmt. Unterstützt werden Englisch, Italienisch, Spanisch, Französisch und Deutsch; andernfalls wird Englisch verwendet. Starte die App neu, nachdem du ihre Oberflächensprache geändert hast. **Ohne Umwandlung (Bild)**, lokale Vektorisierung und **Text auf dem Gerät erkennen** übersetzen nicht. Bei Beschreibungen mit beibehaltener Originalsprache wird Englisch verwendet, wenn kein lesbarer Text die Sprache erkennen lässt.

## Eine frühere Aufnahme erneut verwenden

[![Verlauf mit Beispielaufnahmen und getrennt gespeicherten Format- und Sprachversionen.](../../images/history.png)](../../images/history.png)

*Original und gespeicherte Versionen bleiben zusammen. Das Öffnen des Verlaufs ändert die Zwischenablage nicht.*

Wähle **Öffnen**, ein anderes Format oder eine andere **Ausgabesprache** und dann **Mit KI umwandeln**. Für die Texterkennung ohne Internet wähle **Text auf dem Gerät erkennen**, für Vektorgrafiken **Als SVG vektorisieren**. **Gespeicherte Formate** lädt ein früheres Ergebnis ohne erneute Verarbeitung.

[![Gespeicherte Beispielnotiz neben ihrem bearbeitbaren Markdown-Ergebnis mit Sprachwahl sowie Kopieren und Sichern.](../../images/result.png)](../../images/result.png)

*Dieses Fenster öffnet sich nur auf deinen Wunsch. Bei normalen Aufnahmen wird das Ergebnis direkt im Hintergrund kopiert.*

Wähle **Kopieren**, um das Ergebnis in die Zwischenablage zu legen, oder aktiviere **Nach manueller Umwandlung kopieren**. Eine erneute Umwandlung in dasselbe Format und dieselbe Sprache ersetzt nur diese Version; die anderen bleiben erhalten.

Unter **Einstellungen → Verlauf** kannst du das Limit festlegen, einzelne Einträge löschen oder den ganzen Verlauf leeren. Voreingestellt sind 50 Aufnahmen, möglich sind bis zu 500. Null leert und deaktiviert den Verlauf. Das Löschen des Verlaufs entfernt keine exportierten Dateien und ändert die Zwischenablage nicht.

## Mitteilungen bei Erfolg oder Fehlern

Wähle unter **Allgemein → Aufnahmemitteilungen** die Option **Mitteilungen aktivieren** und erlaube die macOS-Anfrage. Aktiviere Mitteilungen bei Erfolg, bei Fehlern oder für beides; ein Ton ist optional. Mitteilungen enthalten nur Status und Format. Smart Clipboard öffnet sich nur, wenn du darauf klickst.

| Status | Bedeutung |
| --- | --- |
| **Clip …** | Eine Aufnahme oder Umwandlung läuft. |
| **Clip ✓** | Das Ergebnis liegt in deiner Zwischenablage. |
| **Clip !** | Öffne das Menü, um das Problem nachzulesen. |

**Kein Banner, aber Clip ✓?** Du kannst einfügen. Ein Fokus oder eine Bildschirmfreigabe bzw. -aufzeichnung kann Hinweise verbergen oder stummschalten, auch wenn Mitteilungen aktiviert sind. Smart Clipboard respektiert diese Einstellungen. Siehe [Problemlösungen](#wenn-die-aufnahme-nicht-funktioniert).

## Datenschutz und Speicherung

Die App nimmt nur den Bereich oder das Fenster auf, den bzw. das du auswählst. Sie überwacht weder Bildschirm noch Zwischenablage fortlaufend. KI-Aufnahmen werden an deinen ausgewählten Anbieter gesendet. oMLX unter `127.0.0.1` verarbeitet sie auf diesem Mac; bei einem entfernten Server wird die Aufnahme dorthin gesendet. Für die Speicherung in der Cloud gelten die Richtlinien des Anbieters.

Lokale Vektorisierung, **Ohne Umwandlung (Bild)** und Apples Texterkennung benötigen keinen KI-Anbieter. Schlüssel liegen im macOS-Schlüsselbund; ChatGPT-Zugangsdaten bleiben bei Codex.

Der Verlauf wird unter `~/Library/Application Support/Smart Clipboard/History/` gespeichert. Der Zugriff ist auf deinen Mac-Benutzer beschränkt, die Daten sind aber nicht gesondert verschlüsselt. Exportierte Dateien und der Inhalt der Zwischenablage sind unabhängig vom Verlauf.

## Updates

Verwende **Clip → Nach Updates suchen …** oder die Seite **Info**. Optionale tägliche Prüfungen zeigen einen Hinweis im Menü, öffnen aber nicht automatisch ein Updatefenster. Einstellungen, Verlauf und ausgewählte Verbindung bleiben bei Updates erhalten.

Standardmäßig werden stabile Versionen angeboten. Wähle **Info → Versionen → Stabile Versionen und Vorabversionen**, um Vorabversionen wie Build 15 zu erhalten. Ältere Apps ohne Updatefunktion müssen einmal manuell durch die App aus der offiziellen DMG-Datei ersetzt werden.

## Wenn die Aufnahme nicht funktioniert

| Problem | Das kannst du prüfen |
| --- | --- |
| Kein Clip-Menü | Öffne die installierte App. Eine volle Menüleiste kann Einträge verbergen. |
| Kurzbefehl reagiert nicht | Prüfe unter **Einstellungen → Kurzbefehle** die Berechtigung und mögliche Belegungskonflikte. |
| Bildschirmzugriff wird weiterhin als erforderlich angezeigt | Beende die App und öffne sie erneut. Für alte Entwicklungsversionen siehe die Schritte unten. |
| Lokaler Server oder Modell nicht verfügbar | Starte oMLX, prüfe den Port, aktualisiere die Modellliste und wähle ein Modell mit Bildunterstützung. |
| Wiederholter Text oder unvollständige Umwandlung | Prüfe die oMLX-Version. Version 0.6.4 hat den oben beschriebenen Fehler. |
| Ein Bild wird statt Text eingefügt | Ändere **Bevorzugtes Format** von Ohne Umwandlung zu Automatisch erkennen oder einem Textformat. |
| Der vorherige Inhalt der Zwischenablage wird eingefügt | Warte auf **Clip ✓**. Bei einem Fehler bleibt der alte Inhalt erhalten. |
| Kein Fertig-Banner oder Ton | Prüfe Fokus und Bildschirmfreigabe bzw. -aufzeichnung. **Clip ✓** bedeutet weiterhin, dass du einfügen kannst. |

<details>
<summary>Berechtigung zur Bildschirmaufnahme nach einer alten Entwicklungsversion wiederherstellen</summary>

Schalte unter **Systemeinstellungen → Datenschutz & Sicherheit → Aufnahme von Bildschirm & Systemaudio** nur Smart Clipboard aus und wieder ein. Bestätige das Beenden und erneute Öffnen, wenn macOS es anbietet. Entferne bei Bedarf den alten Eintrag und füge `/Applications/Smart Clipboard.app` mit **+** erneut hinzu. Falls macOS den Eintrag nicht entfernen lässt, hole dir Hilfe für ein Zurücksetzen nur dieser App-Berechtigung. Setze nicht die Berechtigungen anderer Apps zurück. Gespeicherte Einstellungen und der Verlauf bleiben erhalten.

</details>

<details>
<summary>Warum Mitteilungen bei einer Bildschirmfreigabe verschwinden können</summary>

macOS kann Banner und Töne unterdrücken, während ein Bildschirm geteilt, gespiegelt oder aufgezeichnet wird, auch ohne aktiven Fokus. Beende diese Sitzung und versuche es erneut. Mitteilungen während einer Freigabe zu erlauben ist eine systemweite Datenschutzentscheidung und für gewöhnliche Aufnahmen nicht erforderlich. Die Erlaubnis zur Bildschirmaufnahme für Smart Clipboard bedeutet allein nicht, dass die App deinen Bildschirm fortlaufend aufzeichnet.

</details>

[Melde ein Problem](https://github.com/colombod/smart-clipboard/issues/new) mit Build-Nummer, macOS-Version, Anbieter und Modell sowie der Fehlermeldung im Menü. Lass Schlüssel und private Bildschirmfotos weg. Der [Stand der Barrierefreiheit](../../ACCESSIBILITY.md) und die [Einschränkungen der Vorabversion](../../releases/v0.4.0-preview.md) beschreiben bekannte Lücken.
