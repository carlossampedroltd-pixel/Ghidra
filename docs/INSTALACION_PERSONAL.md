# Instalar NotraFree solo en tu iPhone (sin App Store)

No hace falta publicar la app ni pasar la revisión de Apple. Xcode firma la app
con un *perfil de aprovisionamiento* que lleva dentro el identificador (UDID)
de **tus** iPhones: iOS se niega a abrirla en cualquier otro dispositivo. Esa
restricción la impone el propio sistema, no la app.

## Qué cuenta usar

| | Apple ID gratis | Apple Developer Program (99 $/año) |
|---|---|---|
| Revisión de Apple | No | No (instalación de desarrollo / Ad Hoc) |
| Solo en tus dispositivos | Sí | Sí (los UDID que registres, máx. 100) |
| Caducidad | **7 días**: hay que reinstalar desde Xcode | **1 año** |
| Apps a la vez | 3 (las dos versiones caben) | sin límite práctico |
| Necesitas un Mac | Sí | Sí, para compilar |

**Recomendación:** la cuenta de pago si vas a usarla a diario, porque no caduca
cada semana. Con la gratuita funciona igual, pero cada 7 días tienes que
conectar el iPhone al Mac y darle a ▶︎ otra vez. SideStore/AltStore pueden
renovarla automáticamente si no quieres pagar.

> No uses TestFlight para esto: incluso para ti solo exige subir la app a App
> Store Connect y, para testers externos, pasa una revisión.

## Pasos

1. **Mac con Xcode compatible con iOS 27.** Para instalar en un iPhone que lleva
   iOS 27.x (el iPhone Duo sale con iOS 27.1), necesitas la versión de Xcode
   que incluye ese SDK. Instálala desde la App Store del Mac.
2. Xcode › Settings › Accounts › **+** › añade tu Apple ID.
   Copia tu **Team ID** (10 caracteres).
3. Edita `NotraFree/Config/Personal.xcconfig`:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BUNDLE_PREFIX = com.tunombre
   ```
4. Google Drive: en Google Cloud Console crea **dos** OAuth clients de tipo iOS,
   uno por app (Google valida el bundle ID):
   - `com.tunombre.notrafree.promax` → pega el prefijo del Client ID en
     `Config/ProMax.xcconfig` (`GOOGLE_CLIENT_ID = 1234-abcd`)
   - `com.tunombre.notrafree.duo` → en `Config/Duo.xcconfig`

   Deja la pantalla de consentimiento en modo "Testing" con tu email como único
   usuario de prueba: así solo tu cuenta de Google puede iniciar sesión.
5. Genera el proyecto:
   ```bash
   brew install xcodegen
   cd NotraFree && xcodegen generate && open NotraFree.xcodeproj
   ```
6. En el iPhone: Ajustes › Privacidad y seguridad › **Modo desarrollador** › activar
   (se reinicia). Conecta el iPhone al Mac por cable.
7. En Xcode, arriba, elige el esquema:
   - **NotraFreeProMax** con tu iPhone 17 Pro Max conectado, o
   - **NotraFreeDuo** con tu iPhone Duo conectado

   y pulsa ▶︎. Xcode registra el UDID del iPhone en tu cuenta y firma la app.
8. Primera vez con cuenta gratuita: en el iPhone, Ajustes › General › VPN y
   gestión de dispositivos › confía en tu certificado de desarrollador.

Las dos apps tienen bundle IDs distintos, así que puedes tener ambas instaladas
a la vez ("Notra Pro Max" y "Notra Duo"). Cada una guarda su propia biblioteca
local. Si las dos usan la misma carpeta de Drive, comparten las notas a través
de Drive.

## Cuando llegue el iPhone Duo

1. Conéctalo al Mac, actívale el Modo desarrollador y ejecuta el esquema
   **NotraFreeDuo** (paso 7). Con cuenta gratuita el nuevo UDID se registra
   solo; con la de pago, también (firma automática).
2. Inicia sesión en Google en la app. En la pestaña Drive, toca ⬇︎ en las notas
   que quieras traer del Pro Max.
3. Si el umbral de "abierto/cerrado" no encaja con la pantalla real, cámbialo
   en `DuoRootView.unfoldedMinWidth` (700 pt por defecto).
