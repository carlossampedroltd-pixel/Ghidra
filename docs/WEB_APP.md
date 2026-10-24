# NotraFree web: sin Mac, sin Xcode, sin App Store

La versión web hace lo mismo que la app nativa y se instala en el iPhone desde
Safari ("Añadir a pantalla de inicio"). Se ve y funciona como una app. Una
sola web sirve para los dos iPhones:

- **iPhone 17 Pro Max / Duo cerrado:** pestañas abajo y la nota a pantalla completa.
- **Duo abierto (o en horizontal):** barra lateral, lista y nota, con
  **resumen y transcripción uno al lado del otro**.

Dirección (cuando esté activada): **https://carlossampedroltd-pixel.github.io/Ghidra/**

## Qué funciona y dónde

| Función | Safari (iPhone) | Bluefy (iPhone) |
|---|---|---|
| Importar audios (Archivos, USB-C, exportados de la app de Boya) | ✅ | ✅ |
| Grabar con el micro del iPhone | ✅ | ✅ |
| Transcripción con Whisper **en el propio iPhone**, gratis y sin límite | ✅ | ✅ |
| Resumen automático (puntos clave + tareas) | ✅ | ✅ |
| Subir / bajar de tu Google Drive | ✅ | ✅ |
| Conectar con la Notra NEO por Bluetooth | ❌ Apple no lo permite en webs | ✅ |

Bluefy es un navegador gratuito de la App Store que añade Web Bluetooth. Abre la
misma dirección en Bluefy solo cuando quieras descargar de la grabadora. Las
notas de cada navegador se guardan por separado, pero las dos sincronizan con
la misma carpeta de Drive.

La primera transcripción descarga el modelo Whisper (40–250 MB según el que
elijas en Ajustes) y lo guarda en el navegador. Las siguientes no descargan
nada. Usa WebGPU si el iPhone lo tiene; si no, la CPU.

## Puesta en marcha (una vez, desde cualquier ordenador o el propio iPhone)

### 1. Activar la web (GitHub Pages)
1. Abre https://github.com/carlossampedroltd-pixel/Ghidra/settings/pages
2. En **Build and deployment › Source** elige **GitHub Actions**.
3. Ve a la pestaña **Actions** › "Deploy web app to GitHub Pages" › **Run workflow**.
   En 1–2 minutos la web está en la dirección de arriba. Cada cambio que se
   suba a `web/` se publica solo.

### 2. Google Drive (Client ID gratuito)
1. https://console.cloud.google.com/ → crea un proyecto → **APIs y servicios ›
   Biblioteca** → activa **Google Drive API**.
2. **Pantalla de consentimiento OAuth**: tipo *Externo*, deja el estado en
   **Testing** y añade **solo tu email** como usuario de prueba. Así nadie más
   puede iniciar sesión en tu app.
3. **Credenciales › Crear credenciales › ID de cliente de OAuth › Aplicación web**
   - Orígenes de JavaScript autorizados: `https://carlossampedroltd-pixel.github.io`
4. Copia el **Client ID** y pégalo en la web: **Ajustes › Client ID de Google ›
   Guardar ajustes**.

### 3. Instalar en el iPhone
1. Abre la dirección en **Safari** → botón Compartir → **Añadir a pantalla de
   inicio**.
2. Ábrela desde el icono → Drive → **Iniciar sesión con Google**.
3. Ajustes → idioma y modelo (Base va bien; Small es más preciso pero más lento).

## ¿Es "solo para mí"?

- La web es pública (cualquiera puede abrir la página), pero **no contiene
  datos**: tus audios viven en tu iPhone (almacenamiento del navegador) y en tu
  Google Drive.
- Solo tu cuenta de Google puede iniciar sesión, porque el OAuth está en modo
  Testing con tu email como único usuario.
- No hay servidor: nadie, ni siquiera GitHub, ve tus grabaciones.

## Límites conocidos

- **Grabaciones largas:** el navegador tiene que decodificar el audio entero en
  memoria. Hasta ~1 hora va bien en un iPhone reciente. Si una muy larga falla,
  usa el modelo Tiny o córtala.
- **La sesión de Google dura 1 hora** (así funciona el login web). Cuando caduque,
  toca "Iniciar sesión" otra vez; si ya diste permiso, es un toque.
- **El resumen** es extractivo (frases clave + tareas detectadas), no un LLM.
  Gratis y sin conexión, pero menos elaborado que el de Boya.
- **Safari puede borrar los datos de una web** que no abres en semanas. La app
  pide almacenamiento persistente, y tus notas están en Drive si activas la
  subida automática.

## Bluetooth en Bluefy: qué cambia respecto a la app nativa

Web Bluetooth solo deja ver los servicios cuyo UUID se declara antes de
conectar. Por eso, antes de usar la consola:

1. Instala **nRF Connect** (gratis, App Store) en el iPhone, conecta con la
   Notra NEO y anota los **UUID de los servicios** que aparecen.
2. En la web: Ajustes › Perfil BLE → pon el principal en `serviceUUID` y los
   demás en `exploreServiceUUIDs` (por ejemplo `["ae00", "180a"]`).
3. Grabadora › Buscar y conectar → ya verás las características y podrás
   enviar comandos. El resto del proceso está en `REVERSE_ENGINEERING.md`.
