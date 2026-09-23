# Smart Clipboard

<img src="../../app-icon.png" alt="Icono de Smart Clipboard con un marco de captura" width="100">

**Captura lo que ves. Pega lo que necesitas.**

Una app discreta en la barra de menús del Mac que convierte capturas en texto, tablas, datos estructurados o SVG. Configúrala una vez y captura sin abrir la app.

**[Descargar para Mac](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg)** · Apple Silicon · macOS 14 o posterior · Firmada y notarizada

Versión actual: **[0.4 preliminar, compilación 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. [Limitaciones conocidas](../../releases/v0.4.0-preview.md).

## Primeros pasos

1. **Instala:** abre el DMG, arrastra Smart Clipboard a **Aplicaciones** y ábrela. Busca **Clip** en la barra de menús.
2. **Configura una vez:** abre **Clip → Ajustes y estado…**. Elige el formato en **General** y, si hace falta, una conexión de IA.
3. **Captura y pega:** cierra los ajustes, pulsa **⌃⌘R**, selecciona un área, espera a **Clip ✓** y pulsa **⌘V** en la app de destino.

Usa **⌃⌘W** para una ventana. **Espacio** cambia el modo de selección; **Escape** cancela. Tus funciones rápidas guardadas tienen prioridad. Permite la grabación de pantalla cuando macOS lo solicite.

## Elige qué quieres pegar

[![Ajustes generales con detección automática y conservación del idioma original.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Elige el formato una vez. Puedes trabajar con los ajustes cerrados. Selecciona una imagen para ampliarla; las capturas de esta guía muestran la interfaz en inglés.*

- **Detección automática:** la IA elige un formato útil.
- **Texto sin formato, Markdown, HTML, JSON o YAML:** elige un resultado editable concreto.
- **Sin conversión:** conserva la imagen sin usar IA.
- **SVG:** vectoriza las formas en el Mac o reconstruye con IA.

Para usar IA, conecta tu propia cuenta de un proveedor o **Local / oMLX**. [Configurar la conexión →](USER-GUIDE.md#configurar-omlx)

## Convierte una imagen en SVG

[![Ajustes de SVG con vectorización en el dispositivo, preajuste Foto y detalle Equilibrado.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*General → SVG → Vectorizar en el dispositivo. No necesitas cuenta, modelo ni servidor.*

Elige **Foto**, **Logotipo** o **Dibujo de líneas** y captura como siempre. **Equilibrado** genera archivos más pequeños; **Detallado** conserva más formas y colores. Pega el código SVG o usa **Historial → Abrir → Guardar…** para importarlo en un editor vectorial.

La vectorización conserva el fondo y convierte las palabras en contornos. Para que un modelo interprete la imagen, elige **Reconstruir con IA**. [Guía de vectorización →](USER-GUIDE.md#vectorizar-una-imagen)

## Reutiliza una captura

[![Historial con capturas de ejemplo y versiones de texto, Markdown y francés guardadas por separado.](../../images/history.png)](../../images/history.png)

*Abre el historial solo cuando lo necesites. Reutiliza el original sin hacer otra captura.*

Elige otro formato o idioma y convierte. **Formatos guardados** abre resultados anteriores; **Copiar** los lleva al portapapeles. Define el límite o borra las capturas en **Ajustes → Historial**.

## Sabe cuándo está listo

**Clip …** indica que está trabajando. **Clip ✓** significa que puedes pegar. **Clip !** indica un problema: abre el menú para leerlo.

En **General** puedes activar notificaciones de éxito o error y sonido. Un modo de concentración o una pantalla compartida puede ocultar los avisos; el estado del menú sigue disponible. [Ayuda con las notificaciones →](USER-GUIDE.md#notificaciones)

## ¿Necesitas ayuda?

[Guía ilustrada](USER-GUIDE.md) · [Modelos locales](USER-GUIDE.md#elegir-un-modelo-local) · [Traducción](USER-GUIDE.md#idiomas-y-traducción) · [Solución de problemas](USER-GUIDE.md#si-la-captura-no-funciona)

La app sigue el aspecto claro u oscuro de macOS y admite inglés, italiano, español, francés y alemán. Las capturas conservan el idioma original salvo que actives la traducción. La vectorización local funciona sin conexión; las capturas con IA se envían a la conexión elegida. [Privacidad](USER-GUIDE.md#privacidad-y-almacenamiento).

*Las imágenes muestran las vistas actuales con datos de ejemplo. Esta versión es preliminar: revisa los resultados de IA. La verificación de todos los proveedores y la [evaluación completa de accesibilidad](../../ACCESSIBILITY.md) siguen pendientes.*

[Informar de un problema](https://github.com/colombod/smart-clipboard/issues/new) · [Guía para desarrolladores](../../DEVELOPING.md)
