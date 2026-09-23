# Smart Clipboard

<img src="../../app-icon.png" alt="Icône Smart Clipboard avec un cadre de capture" width="100">

**Capturez ce que vous voyez. Collez ce dont vous avez besoin.**

Une app discrète dans la barre des menus du Mac pour transformer une capture en texte, tableau, données structurées ou SVG. Réglez vos préférences une fois, puis capturez et collez sans ouvrir l’app.

**[Télécharger pour Mac](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon · macOS 14 ou ultérieur · App signée et notariée

Version actuelle : **[0.4 en préversion, build 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. [Limites connues](../../releases/v0.4.0-preview.md).

## Premiers pas

1. **Installez :** ouvrez le DMG et glissez Smart Clipboard dans **Applications**. Lancez l’app et repérez **Clip** dans la barre des menus.
2. **Réglez une fois :** ouvrez **Clip → Réglages et état…**. Choisissez le format dans **Général** et, si nécessaire, une connexion IA.
3. **Capturez et collez :** fermez les réglages, appuyez sur **⌃⌘R**, sélectionnez une zone, attendez **Clip ✓**, puis faites **⌘V** dans l’app de destination.

Utilisez **⌃⌘W** pour une fenêtre. **Espace** change le mode de sélection ; **Échap** annule. Vos raccourcis enregistrés sont prioritaires. Autorisez l’enregistrement de l’écran lorsque macOS le demande.

## Choisissez ce que vous voulez coller

[![Réglages généraux avec détection automatique et conservation de la langue d’origine.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Choisissez le format une fois. Les réglages peuvent rester fermés pendant votre travail. Sélectionnez une image pour l’agrandir ; les captures du guide montrent l’interface en anglais.*

- **Détection automatique :** l’IA choisit un format utile.
- **Texte brut, Markdown, HTML, JSON ou YAML :** choisissez un résultat modifiable précis.
- **Image seule :** gardez l’image sans IA.
- **SVG :** vectorisez les formes sur le Mac ou reconstituez-les avec l’IA.

Pour l’IA, utilisez votre propre compte auprès d’un fournisseur cloud ou **Local / oMLX**. [Configurer la connexion →](USER-GUIDE.md#configurer-omlx)

## Transformez une image en SVG

[![Réglages SVG avec vectorisation sur l’appareil, préréglage Photo et détail Équilibré.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Général → SVG → Vectoriser sur cet appareil. Aucun compte, modèle ou serveur nécessaire.*

Choisissez **Photo**, **Logo** ou **Dessin au trait**, puis capturez comme d’habitude. **Équilibré** réduit la taille du fichier ; **Détaillé** conserve davantage de formes et de couleurs. Collez le code SVG ou utilisez **Historique → Ouvrir → Enregistrer…** pour l’importer dans un éditeur vectoriel.

La vectorisation conserve le fond et transforme les mots en contours. Pour faire interpréter l’image par un modèle, choisissez **Reconstituer avec l’IA**. [Guide de vectorisation →](USER-GUIDE.md#vectoriser-une-image)

## Réutilisez une capture

[![Historique avec captures d’exemple et versions texte, Markdown et françaises enregistrées séparément.](../../images/history.png)](../../images/history.png)

*Ouvrez l’historique seulement quand vous en avez besoin. Réutilisez l’original sans refaire la capture.*

Choisissez un autre format ou une langue, puis convertissez. **Formats enregistrés** ouvre les résultats précédents ; **Copier** les place dans le presse-papiers. Réglez la limite ou effacez les captures dans **Réglages → Historique**.

## Sachez quand le résultat est prêt

**Clip …** indique un traitement en cours. **Clip ✓** signifie que vous pouvez coller. **Clip !** signale un problème : ouvrez le menu pour le lire.

Dans **Général**, activez si vous le souhaitez les notifications de réussite ou d’échec et leur son. Un mode de concentration ou le partage d’écran peut masquer les alertes ; l’état du menu reste disponible. [Aide sur les notifications →](USER-GUIDE.md#notifications)

## Besoin d’aide ?

[Guide illustré](USER-GUIDE.md) · [Modèles locaux](USER-GUIDE.md#choisir-un-modèle-local) · [Traduction](USER-GUIDE.md#langues-et-traduction) · [Dépannage](USER-GUIDE.md#si-la-capture-ne-fonctionne-pas)

L’app suit l’apparence claire ou sombre de macOS et prend en charge l’anglais, l’italien, l’espagnol, le français et l’allemand. Les captures conservent leur langue d’origine sauf si vous activez la traduction. La vectorisation locale fonctionne hors ligne ; les captures avec IA sont envoyées à la connexion choisie. [Confidentialité](USER-GUIDE.md#confidentialité-et-stockage).

*Les images montrent les vues actuelles avec des données d’exemple. Cette version est préliminaire : vérifiez les résultats de l’IA. La validation de tous les fournisseurs cloud et l’[évaluation complète de l’accessibilité](../../ACCESSIBILITY.md) restent inachevées.*

[Signaler un problème](https://github.com/colombod/smart-clipboard/issues/new) · [Guide de développement](../../DEVELOPING.md)
