# Usar Smart Clipboard

**Configura una vez. Captura. Espera a Clip ✓. Pega.** La app permanece en la barra de menús hasta que quieras abrirla.

Guía de **[0.4 preliminar, compilación 15](https://github.com/colombod/smart-clipboard/releases/tag/v0.4.0-preview.15)**. Las imágenes muestran vistas actuales en inglés con datos de ejemplo; selecciónalas para ampliarlas.

Ir a [IA local](#configurar-omlx), [vectorización](#vectorizar-una-imagen), [traducción](#idiomas-y-traducción) o [solución de problemas](#si-la-captura-no-funciona).

## Instalar y empezar

1. [Descarga el DMG firmado](https://github.com/colombod/smart-clipboard/releases/download/v0.4.0-preview.15/Smart-Clipboard-0.4.0-macOS-arm64.dmg), ábrelo y arrastra **Smart Clipboard** a **Aplicaciones**.
2. Expulsa el DMG, abre la app instalada y busca **Clip** en la barra de menús. No hay icono en el Dock ni ventana que debas mantener abierta.
3. Abre **Clip → Ajustes y estado…**. Activa **Abrir al iniciar sesión** en General si quieres que esté lista al arrancar el Mac.

Requiere Apple Silicon y macOS 14 o posterior. Cerrar los ajustes no desactiva las funciones rápidas; **Clip → Salir de Smart Clipboard** cierra la app.

## Capturar, esperar, pegar

| Paso | Qué hacer |
| --- | --- |
| **Capturar un área** | Pulsa **⌃⌘R** y arrastra un rectángulo. |
| **Capturar una ventana** | Pulsa **⌃⌘W** y haz clic en la ventana. |
| **Esperar** | **Clip …** cambia a **Clip ✓** cuando el resultado está copiado. |
| **Pegar** | Pulsa **⌘V** en la app de destino. |

**⌃⌘R** significa mantener pulsadas **Control + Comando** y pulsar **R**; **⌃⌘W** usa **W**. Son los valores predeterminados desde la compilación 15. Las funciones rápidas guardadas tienen prioridad, incluidas las de versiones anteriores. Puedes verlas o grabar otras en **Ajustes → Funciones rápidas**. **Espacio** cambia de modo y **Escape** cancela. Un error o una cancelación conserva el contenido anterior del portapapeles.

Permite la grabación de pantalla cuando macOS la solicite, o usa **Solicitar acceso a la pantalla** en Funciones rápidas. Vuelve a abrir la app si macOS lo pide. Una captura no abre los ajustes ni el editor.

## Elegir el formato

[![Ajustes generales con detección automática y conservación del idioma original.](../../images/capture-settings.png)](../../images/capture-settings.png)

*Ajustes → General se aplica a las nuevas capturas. El historial tiene opciones independientes para las imágenes guardadas.*

| Formato preferido | Resultado |
| --- | --- |
| **Detección automática** | La IA elige un formato editable a partir de la imagen. |
| **Sin conversión (imagen)** | Imagen original, sin extracción ni IA. |
| **Texto sin formato / Markdown** | Texto, notas, títulos o tablas editables. |
| **JSON / YAML / HTML** | Datos estructurados o código de marcado. |
| **SVG** | Vectorización local de formas o reconstrucción con IA. |
| **Descripción** | Una descripción escrita de la imagen. |

**Instrucción predeterminada** permite añadir indicaciones como «Conserva las columnas de la tabla». Los resultados de IA, HTML y SVG se copian como texto; la app no representa ni ejecuta ese código. Revisa los resultados antes de usarlos.

## Configurar oMLX

[![Conexión local oMLX con dirección del servidor y modelo de visión Qwen3-VL.](../../images/local-connection.png)](../../images/local-connection.png)

*Selecciona Local / oMLX, introduce la dirección de tu servidor y elige un modelo capaz de leer imágenes.*

1. Instala e inicia [oMLX](https://github.com/jundot/omlx). Para empezar, descarga **mlx-community/Qwen3-VL-8B-Instruct-4bit**.
2. En **Ajustes → Conexión**, elige **Local / oMLX**. La dirección debe terminar en `/v1`; `http://127.0.0.1:8999/v1` es un ejemplo, no un puerto universal.
3. Pulsa **Actualizar modelos** y elige el identificador exacto del modelo de visión. El servidor puede omitir el prefijo `mlx-community/`.
4. Si requiere una clave, introdúcela y pulsa **Guardar clave**. Un servidor en otro ordenador requiere clave; usa HTTPS fuera de una red local privada.
5. Pulsa **Probar procesamiento de imágenes**. La prueba usa una imagen generada, no tu pantalla. Elige después el formato en General y cierra los ajustes.

Mantén oMLX abierto para la extracción con IA. Smart Clipboard no descarga modelos, inicia el servidor ni cambia a un proveedor en la nube si falla. **Vectorizar en el dispositivo** y **Sin conversión** funcionan sin oMLX.

### Elegir un modelo local

Empieza por **Qwen3-VL-8B-Instruct-4bit** para texto, tablas y traducción. El modelo **32B** no solucionó los errores de Descripción/SVG en nuestras pruebas. Para vectorizar imágenes, usa **Vectorizar en el dispositivo**: no necesita modelo.

El servidor probado es la versión oficial **[oMLX 0.7.0.dev2](https://github.com/jundot/omlx/releases/tag/v0.7.0.dev2)**. La 0.6.4 tiene un error de salida estructurada con este modelo; uno más grande no lo corrige. Estas pruebas no cubren versiones posteriores del servidor.

<details>
<summary>Tamaño, memoria y resultados de las pruebas</summary>

Son conversiones de MLX Community a 4 bits de modelos Qwen con visión. Usa el identificador completo en el descargador de oMLX:

| Modelo | Descarga | Resultados a 22 de septiembre de 2026 |
| --- | --- | --- |
| [mlx-community/Qwen3-VL-8B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit) | Unos 5,78 GB según la [lista del editor](https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit/tree/main). | Texto, tablas y datos estructurados funcionaron con las imágenes sintéticas probadas. Descripción inventó observaciones ortográficas; SVG alteró proporciones, bordes o diseño. |
| [mlx-community/Qwen3-VL-32B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit) | Descarga verificada: 19.636.446.591 bytes en 19 archivos; unos 19,64 GB / 18,29 GiB. | Con oMLX 0.7.0.dev2 conservó los valores, pero inventó alineaciones en Descripción y añadió una fila y un lienzo incorrecto en SVG. Seis pruebas de instrucciones mejoraron las dimensiones sin corregir contenido y diseño. |

La descarga de 32B corresponde a la [revisión `6e5644d`](https://huggingface.co/mlx-community/Qwen3-VL-32B-Instruct-4bit/tree/6e5644d3ea4b953b5221ffd02339bf897041038a). Estos tamaños son de disco, no de memoria en uso.

**Estimaciones de memoria:** calcula al menos 16 GB de memoria unificada para 8B o 48 GB para 32B, más margen para imágenes, contexto y otras apps. Son estimaciones prudentes, no mínimos comprobados ni garantías de velocidad. Las pruebas usaron un Mac de 128 GiB; no se han validado equipos con menos memoria. Deja espacio para las cachés y empieza con una imagen pequeña sin datos privados.

Ninguno ha superado la evaluación de calidad de todos los formatos. Descripción y SVG siguen siendo experimentales. Consulta las [pruebas locales](../../testing/OMLX.md) para distinguir resultados automáticos y calidad visual.

</details>

## Otras conexiones

Para **OpenAI**, **Anthropic**, **Google Gemini** o **Perplexity**, selecciona el proveedor en Conexión, introduce la clave API, pulsa **Guardar clave**, elige un modelo con visión y ejecuta **Probar procesamiento de imágenes**. El acceso y la facturación de la API son independientes de las suscripciones de chat. Cada proveedor conserva sus propios ajustes y clave.

Para **ChatGPT mediante Codex**, instala o actualiza Codex CLI y pulsa **Iniciar sesión con ChatGPT**. Deja **Ejecutable de Codex** vacío para la detección automática y ejecuta la prueba de imagen. Necesitas una cuenta de Codex apta y la CLI oficial compatible; se aplican los límites de la suscripción.

Si una clave guardada necesita permiso tras una actualización, pulsa **Autorizar clave guardada**. Las capturas en segundo plano no abren diálogos del Llavero. No todas las conexiones en la nube se han probado en uso real; consulta el [estado de los proveedores](../../PROVIDERS.md).

## Vectorizar una imagen

[![Vectorización local configurada con Foto y detalle Equilibrado.](../../images/svg-tracing.png)](../../images/svg-tracing.png)

*Elige Vectorizar en el dispositivo. Reconstruir con IA sigue siendo el método predeterminado tras actualizar.*

### Fotos, logotipos y dibujos

1. En **Ajustes → General**, elige **Formato preferido → SVG** y **Método de SVG → Vectorizar en el dispositivo**.
2. Selecciona **Foto**, **Logotipo** o **Dibujo de líneas** según la imagen.
3. Empieza con **Equilibrado**. **Detallado** conserva más formas y colores, pero genera archivos más grandes.
4. Cierra los ajustes, captura, espera a **Clip ✓** y pega.

Funciona sin conexión con el componente VTracer incluido: no necesita clave, modelo, servidor ni instalación adicional. Sigue las formas visibles, conserva el fondo y convierte las palabras en contornos. No traduce, elimina fondos ni recupera datos de gráficos. Las instrucciones no se aplican y un fallo no cambia a IA.

**Para usar un editor vectorial:** abre la captura en **Historial**, pulsa **Guardar…** e importa el archivo `.svg`. En un editor de texto se pega el código SVG. Los SVG grandes muestran un resumen en la app, pero **Copiar** y **Guardar…** conservan todo el resultado.

### Vectorizar una captura guardada

Abre **Clip → Historial → Abrir**, elige **SVG → Vectorizar en el dispositivo**, ajusta el preajuste y detalle y pulsa **Vectorizar a SVG**. Usa **Copiar** o **Guardar…**. Cada combinación de método, preajuste y detalle tiene su propio resultado. Estas opciones manuales no cambian las preferencias de captura automática.

### Reconstruir con IA

Elige **SVG → Reconstruir con IA** para que tu modelo interprete y reconstruya un diagrama o ilustración. Puede seguir instrucciones e idioma, pero también cambiar o inventar detalles. Prueba primero la conexión y compara con el original.

## Idiomas y traducción

En **General → Idiomas → Resultado de la captura**, elige:

| Opción | Resultado |
| --- | --- |
| **Conservar idioma original** | Mantiene el idioma detectado. Es el valor predeterminado. |
| **Idioma del sistema** | Traduce las capturas con IA al idioma preferido del Mac. |
| **Un idioma concreto** | Traduce con independencia del idioma del Mac. |

La elección explícita tiene prioridad sobre las instrucciones de traducción. Los ajustes antiguos pueden mostrar **Usar instrucciones guardadas** hasta que elijas un idioma. Los cambios se aplican a la siguiente captura. Revisa traducciones y valores extraídos: la calidad depende del modelo.

La interfaz sigue por separado el idioma de macOS: inglés, italiano, español, francés o alemán, con inglés como alternativa. Reinicia la app tras cambiar su idioma. **Sin conversión**, la vectorización local y **Extraer texto en el dispositivo** no traducen. Una descripción en modo de idioma original usa inglés si no hay texto legible que permita identificar el idioma.

## Reutilizar capturas

[![Historial con capturas de ejemplo y versiones separadas por formato e idioma.](../../images/history.png)](../../images/history.png)

*El original y sus versiones permanecen juntos. Abrir el historial no cambia el portapapeles.*

Pulsa **Abrir**, elige otro formato o **Idioma de salida** y pulsa **Convertir con IA**. Para OCR sin conexión, usa **Extraer texto en el dispositivo**; para vectores, **Vectorizar a SVG**. **Formatos guardados** carga un resultado sin repetir el procesamiento.

[![Nota de ejemplo con resultado Markdown editable y controles de idioma, copia y guardado.](../../images/result.png)](../../images/result.png)

*Esta ventana solo se abre cuando lo pides. Las capturas normales se copian en segundo plano.*

Pulsa **Copiar** o activa **Copiar tras la conversión manual**. Repetir el mismo formato e idioma sustituye solo esa versión; las demás permanecen.

En **Ajustes → Historial**, fija el límite (50 por defecto, hasta 500), borra una entrada o vacía todo. Cero borra y desactiva el historial. No se eliminan archivos exportados ni se cambia el portapapeles.

## Notificaciones

En **General → Notificaciones de captura**, pulsa **Activar notificaciones** y permite la solicitud de macOS. Elige éxito, error o ambos; el sonido es opcional. Los avisos solo incluyen estado y formato. La app se abre únicamente si haces clic en ellos.

| Estado | Significado |
| --- | --- |
| **Clip …** | Captura o conversión en curso. |
| **Clip ✓** | Resultado en el portapapeles. |
| **Clip !** | Abre el menú para leer el problema. |

**¿Clip ✓ sin aviso?** Ya puedes pegar. Un modo de concentración o la pantalla compartida o grabada puede silenciar los avisos aunque estén activados. La app respeta esos ajustes. Consulta la [solución de problemas](#si-la-captura-no-funciona).

## Privacidad y almacenamiento

La app solo captura el área o ventana solicitada; no vigila continuamente la pantalla ni el portapapeles. Las capturas con IA van al proveedor elegido. oMLX en `127.0.0.1` procesa en este Mac; un servidor remoto recibe la imagen allí. La conservación en la nube depende del proveedor.

La vectorización local, el modo sin conversión y el OCR de Apple no necesitan proveedor de IA. Las claves se guardan en el Llavero de macOS; Codex conserva las credenciales de ChatGPT.

El historial está en `~/Library/Application Support/Smart Clipboard/History/`, limitado a tu usuario del Mac, sin cifrado adicional. Los archivos exportados y el portapapeles son independientes del historial.

## Actualizaciones

Usa **Clip → Buscar actualizaciones…** o **Acerca de**. Las comprobaciones diarias opcionales añaden un aviso al menú sin abrir ventanas. Conservan preferencias, historial y conexión.

Por defecto se ofrecen versiones estables. Elige **Acerca de → Versiones → Versiones estables y preliminares** para recibir versiones como la compilación 15. Las apps antiguas sin actualizador necesitan una sustitución manual desde el DMG oficial.

## Si la captura no funciona

| Síntoma | Qué revisar |
| --- | --- |
| No aparece Clip | Abre la app instalada; una barra llena puede ocultar iconos. |
| La función rápida no responde | Revisa permisos y conflictos en **Ajustes → Funciones rápidas**. |
| Sigue pidiendo acceso a la pantalla | Cierra y abre la app. Para versiones antiguas de desarrollo, consulta los pasos siguientes. |
| Servidor o modelo no disponible | Inicia oMLX, confirma el puerto, actualiza modelos y elige uno con visión. |
| Texto repetido o conversión incompleta | Comprueba oMLX; la versión 0.6.4 tiene el error descrito arriba. |
| Pega una imagen en vez de texto | Cambia **Formato preferido** de Sin conversión a Detección automática o texto. |
| Pega el contenido anterior | Espera a **Clip ✓**. Un fallo conserva el portapapeles anterior. |
| No hay aviso ni sonido | Revisa concentración y pantalla compartida o grabada. **Clip ✓** sigue indicando que puedes pegar. |

<details>
<summary>Recuperar el permiso tras una versión de desarrollo antigua</summary>

En **Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema**, desactiva y activa solo Smart Clipboard; acepta cerrar y volver a abrir cuando se ofrezca. Si hace falta, elimina la entrada antigua y añade `/Applications/Smart Clipboard.app` con **+**. Si macOS no deja quitarla, solicita ayuda para restablecer solo esta app; no restablezcas permisos de otras apps. Ajustes e historial se conservan.

</details>

<details>
<summary>Por qué desaparecen los avisos al compartir pantalla</summary>

macOS puede ocultar avisos y sonidos al compartir, duplicar o grabar la pantalla, incluso sin un modo de concentración. Detén esa sesión y prueba de nuevo. Permitir avisos mientras compartes es una decisión de privacidad de todo el sistema, no un requisito de captura. El permiso de grabación de Smart Clipboard no significa que grabe continuamente.

</details>

[Informa de un problema](https://github.com/colombod/smart-clipboard/issues/new) con la compilación, versión de macOS, proveedor/modelo y error del menú. No incluyas claves ni capturas privadas. Consulta también el [estado de accesibilidad](../../ACCESSIBILITY.md) y las [limitaciones de la versión preliminar](../../releases/v0.4.0-preview.md).
