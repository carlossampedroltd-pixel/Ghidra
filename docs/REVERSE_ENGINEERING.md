# Ingeniería inversa del Boya Notra NEO

Objetivo: averiguar **cómo pide la app oficial de Boya la lista de grabaciones y
cómo las descarga por Bluetooth LE**, para rellenar el *Perfil BLE* de NotraFree.
Después la app descarga tus audios sin la nube ni la suscripción de Boya.

> Legalidad: la ingeniería inversa con fines de **interoperabilidad** con un
> dispositivo que es tuyo está amparada en la UE (Directiva 2009/24/CE, art. 6) y
> en EE. UU. (DMCA §1201(f)). No redistribuyas el código ni el firmware de Boya;
> NotraFree solo contiene código propio.

---

## 0. Antes de nada: ¿hace falta Bluetooth?

Prueba primero las vías fáciles. Si alguna funciona, la app ya sirve **hoy**
(pestaña Notas › Importar):

1. **USB-C → iPhone 15/16/17 (o Mac/PC).** Conecta la grabadora con un cable
   USB-C. Si aparece en la app Archivos como unidad (almacenamiento masivo), tus
   grabaciones (`.wav`/`.mp3`/`.opus`) se pueden importar directamente.
2. **Exportar desde la app de Boya.** Normalmente permite compartir el audio
   original aunque no pagues la transcripción: Compartir › Guardar en Archivos o
   abrir con NotraFree.
3. **Modo grabación Bluetooth/llamada.** Si solo te interesa grabar, NotraFree
   también graba con el micro del iPhone.

Si nada de eso basta, sigue.

---

## 1. Capturar el tráfico BLE de la app oficial

### Opción A — Android (la más sencilla)
1. Instala la app de Boya en un Android.
2. Opciones de desarrollador › **Habilitar registro de Bluetooth HCI snoop**.
   Apaga y enciende el Bluetooth.
3. En la app oficial: conecta la grabadora, **abre la lista de grabaciones** y
   **descarga una grabación corta** (anota su duración y su posición en la lista).
4. Saca el log: `adb bugreport bug.zip` → dentro está
   `FS/data/misc/bluetooth/logs/btsnoop_hci.log`.
5. Analízalo:
   ```bash
   python3 tools/btsnoop_att.py btsnoop_hci.log --stats   # qué handle mueve más bytes = audio
   python3 tools/btsnoop_att.py btsnoop_hci.log | less     # cronología de comandos
   ```
   O ábrelo en **Wireshark** con el filtro `btatt`.

### Opción B — iPhone
1. Instala el *Bluetooth logging profile* de Apple
   (developer.apple.com › Bug Reporter › Profiles and Logs › Bluetooth for iOS).
2. Reproduce el uso en la app oficial, genera un sysdiagnose y ábrelo con
   **PacketLogger** (Additional Tools for Xcode) en un Mac.

### Opción C: directo con NotraFree, nRF Connect o un ordenador
- **nRF Connect** (gratis en la App Store) muestra en el iPhone todos los
  servicios y características de la grabadora, y permite escribir y suscribirse.
  Es la forma más rápida de obtener los UUID sin ordenador.
- NotraFree › Grabadora › *Explorador GATT* lista servicios/características, se
  suscribe a todas las notificaciones y guarda un log exportable.
- `python3 tools/ble_probe.py scan | dump <MAC> | talk ...` hace lo mismo desde
  un Mac/PC (`pip install bleak`).

---

## 2. Interpretar la captura

Busca este patrón en la cronología:

| Paso | Qué verás | Campo del perfil |
|---|---|---|
| Conexión | `WRITE_REQ` al descriptor CCCD (`01 00`) del handle de notificación | `notifyUUID` |
| Handshake / hora | un `WRITE_CMD` corto al conectar (a menudo incluye la fecha/hora) | — (añádelo si hace falta) |
| Lista de archivos | `WRITE_CMD` corto → varias `NOTIFY` con nombres/tamaños/fechas | `listCommandHex` |
| Descarga | `WRITE_CMD` con el índice o nombre del archivo → **ráfaga de cientos de `NOTIFY`** | `downloadCommandHex` |
| Cabecera por paquete | los primeros bytes de cada NOTIFY cambian como un contador | `headerBytesPerPacket` |
| ACK | la app responde con un `WRITE_CMD` cada N paquetes | `ackCommandHex` |
| Fin | un NOTIFY distinto (p. ej. `aa 55 ff ...`) | `endOfTransferHex` |

Para mapear handles → UUID: en Wireshark mira los `READ_BY_TYPE_RSP` del
descubrimiento, o usa `ble_probe.py dump` (muestra `handle=` junto a cada UUID).

Compara **dos descargas de grabaciones distintas**: los bytes que cambian en el
comando son el índice (o id). Si va en little-endian de 2 bytes usa `{idx16le}`
en `downloadCommandHex`; hay también `{idx16be}`, `{idx32le}`, `{idx32be}`.

### Formato del audio
Vuelca la ráfaga y mira los primeros bytes:
```bash
python3 tools/btsnoop_att.py btsnoop_hci.log --dump 0x0012 --strip 4 -o dump.bin
xxd dump.bin | head
```
- `52 49 46 46` (`RIFF`) → WAV → `audioFormat: rawFile`
- `4f 67 67 53` (`OggS`) → Opus en Ogg → `rawFile`, extensión `ogg`
- `ff fb` / `49 44 33` → MP3 → `rawFile`, extensión `mp3`
- nada reconocible → prueba `ffplay -f s16le -ar 16000 -ac 1 dump.bin`.
  Si se oye bien: `audioFormat: pcm16`. Si suena a ruido, probablemente Opus
  "crudo" o ADPCM → la app guarda el volcado y hay que implementar el decoder
  (abre un issue con 5 s de muestra).

Dato útil: la duración de la grabación × tasa de bits ≈ bytes recibidos
(16 kHz/16 bit PCM = 32 KB/s; Opus 16–32 kbps ≈ 2–4 KB/s).

---

## 3. Si el protocolo está cifrado u ofuscado: Ghidra + jadx

Si los comandos parecen aleatorios entre sesiones (cifrado AES, token por
sesión, CRC), toca leer el código de la app.

1. Descarga el APK oficial (desde tu propio Android: `adb shell pm path <paquete>`
   y `adb pull`).
2. **jadx-gui** sobre el APK: busca `UUID.fromString`, `BluetoothGattCharacteristic`,
   `writeCharacteristic`, `setValue(byte[])`, `Cipher.getInstance`, `CRC`.
   Las clases que construyen `byte[]` antes de escribir son el protocolo.
3. Si la lógica está en nativo (`lib/arm64-v8a/*.so`, típico en SDKs Flutter/
   React-Native o del fabricante del chip — JieLi, Actions, Bluetrum, BES):
   - Abre el `.so` en **Ghidra** (este repo), deja que lo analice.
   - Copia `tools/ghidra/FindBleProtocol.java` a `~/ghidra_scripts` y ejecútalo
     (Script Manager › Notra). Marca UUIDs, cadenas como `opus`, `file_list`,
     `crc`, `aes` y quién las referencia.
   - Sigue las referencias hasta las funciones que montan los paquetes:
     cabecera mágica, longitud, opcode, payload, checksum.
   - Si hay una clave AES estática, búscala junto a la llamada a `AES_set_*`
     o `EVP_EncryptInit`.
4. Muchos de estos chips usan un protocolo de fabricante (p. ej. JieLi "RCSP")
   con cabecera `FE DC BA` … `EF`. Si la ves, busca su documentación pública:
   te ahorra la mitad del trabajo.

Implementa lo que encuentres en `NotraFree/NotraFree/BLE/` (por ejemplo una
clase `NotraNeoProtocol` que calcule checksum/cifrado) si el perfil JSON no basta.

---

## 4. Meter el resultado en la app

En el iPhone: Ajustes › Perfil BLE, pega algo como esto (valores de ejemplo,
**no** reales):

```json
{
  "name": "Boya Notra NEO",
  "namePrefixes": ["NOTRA"],
  "serviceUUID": "0000AE00-0000-1000-8000-00805F9B34FB",
  "writeUUID":   "0000AE01-0000-1000-8000-00805F9B34FB",
  "notifyUUID":  "0000AE02-0000-1000-8000-00805F9B34FB",
  "writeWithResponse": false,
  "listCommandHex": "aa 55 01 00",
  "downloadCommandHex": "aa 55 02 02 {idx16le}",
  "ackCommandHex": null,
  "endOfTransferHex": "aa 55 ff",
  "headerBytesPerPacket": 4,
  "idleTimeout": 3,
  "audioFormat": "rawFile",
  "fileExtension": "opus",
  "sampleRate": 16000,
  "channels": 1
}
```

Luego: Grabadora › conecta › elige el nº de grabación › *Descargar*. La app la
transcribe en el iPhone, la resume con Apple Intelligence (si tu iPhone lo
admite) y la sube a tu carpeta de Google Drive.

Si consigues un perfil que funcione, cambia `DeviceProfile.notraNeoDraft` en
`DeviceProfile.swift` para que sea el valor por defecto.
