# Serene

## Evaluación y reportes

Los JSON incluyen `evaluation_metrics` con valores pendientes explícitos (`null`). Para CR, benchmark de invoke de Windows y captura de RAM oficial, consultar [evaluación de rendimiento, Mac y VM](docs/performance-evaluation.md). `python tool/evaluate_performance.py` crea un reporte independiente; admite artefactos TFLite, lotes `.npy` originales y evidencia externa del perfilador.

Las pruebas criptográficas se ejecutan desde el código, sin herramientas de manipulación en la app final:

```powershell
dart run tool/evaluate_crypto.dart
dart run tool/evaluate_crypto.dart --dataset "D:\datasets\audios" --repetitions 10
```

Cada ejecución guarda JSON, CSV de tiempos y logs en `evaluation_results/<fecha UTC>/` (ignorado por Git). Las dos variantes son alternativas: datos sintéticos o dataset propio. Véase [protocolo, resultados y limitaciones](docs/cryptographic-evaluation.md). Los tiempos corresponden al host, no al teléfono.

En la app, **Settings → Diagnóstico → Diagnóstico de rendimiento** permite iniciar una medición voluntaria y exportar JSON de CPU, memoria, batería, estado térmico y tiempos del procesamiento. No contiene pruebas criptográficas ni mide tráfico de red o cifrado exclusivo. La validación nativa iOS sigue pendiente en un IPA real.

Serene es un prototipo Flutter para monitorear audio ambiental, ejecutar clasificación local de tres categorías y conservar incidentes mediante cifrado autenticado. Las etiquetas del modelo son `no_violence`, `physical_violence` y `verbal_violence`; son predicciones acústicas y no una constatación independiente de violencia.

**Documentación actualizada el 1 de noviembre de 2026.**

## Documentación para la investigación

El documento principal es [Descripción técnica de los módulos implementados](docs/informe-tecnico-tesis.md). Describe la arquitectura, responsabilidades e implementación de cada módulo, flujo de datos, parámetros, pruebas realizadas y evaluación pendiente. Incluye textos adaptables a los apartados de criptografía, almacenamiento e interfaz del informe académico.

Documentos complementarios:

- [Protección de datos, claves y migración](docs/privacy-and-encryption.md).
- [Auditoría, integridad y recuperación](docs/evidence-integrity.md).
- [Retención, capacidad y eliminación](docs/evidence-retention.md).
- [Integración del modelo y prueba sintética](docs/mobile-model-integration.md).
- [Contrato del modelo mixto](docs/mobile-model-contract.json).
- [Política y validación de audio continuo](docs/audio-detection-validation.md).

## Funcionamiento actual

La captura utiliza PCM16 mono a 16 kHz. El análisis utiliza ventanas de cinco segundos, con un avance nominal de un segundo. La aplicación convierte el PCM a flotantes en `[-1,1]` y conserva las muestras recientes en un búfer circular.

Una primera predicción positiva con confianza mínima de 0,60 crea un candidato en RAM. Dos inferencias positivas nuevas, separadas al menos un segundo y dentro de seis, confirman el incidente conservando su inicio. `SignalQuality` rechaza señales inválidas y RMS centrada no superior a una unidad PCM16, sin exigir voz. Las ventanas no clasificadas no son votos; una negativa, señal degenerada o más de seis segundos sin positiva nueva cierran el incidente confirmado. Se añade únicamente PCM nuevo. La política requiere calibración con audio continuo real y puede omitir eventos breves.

El incidente se guarda después de confirmarse, cada quince segundos nuevos y al finalizar. Detener no persiste candidatos sin confirmar. Cada guardado crea una versión cifrada completa; la interfaz muestra la última por incidente. No existe límite predeterminado de duración, pero memoria y almacenamiento son finitos y las versiones intermedias aumentan el espacio ocupado.

Fuera de un incidente no se crean archivos de audio ni registros de evidencia para ventanas negativas. Esto no significa ausencia de toda escritura: preferencias y datos técnicos de recursos también se persisten.

## Acceso, micrófono y reproducción

El acceso inicial utiliza biometría o credenciales del dispositivo. La sesión caduca tras cinco minutos de inactividad y se cierra al pasar la interfaz a segundo plano, salvo durante un diálogo de autenticación registrado. La captura activa y la sesión de interfaz se controlan por separado.

Configuración permite activar o desactivar el monitoreo con una autenticación nueva. Cada activación vuelve a comprobar el permiso del micrófono, lo solicita cuando es posible o permite abrir los ajustes del dispositivo. La desactivación se conserva entre aperturas. La preferencia predeterminada es activada y el arranque intenta iniciar la captura solo si esa configuración y los permisos lo permiten.

Entrar a la lista de grabaciones, escuchar cada audio y confirmar una eliminación requieren autenticación adicional. Cancelar no permite consultar, descifrar o eliminar mediante esos flujos. La reproducción construye PCM/WAV en memoria y utiliza `StreamAudioSource`, sin crear deliberadamente un archivo temporal legible. Se limpian los búferes controlados por la app, sin prometer eliminación de todas las copias del runtime o del sistema operativo.

La ubicación tiene una preferencia independiente, desactivada por defecto y con cambio autenticado. Solicita permiso desde la interfaz y distingue bloqueo y GPS apagado. Inicio puede restablecer permisos faltantes de preferencias habilitadas. Volver del reproductor conserva el acceso a la lista; cada audio mantiene su autenticación. La reproducción permite pausa, salto al soltar la barra, retorno al inicio y repetición.

Los logos viven en `assets/icons`, con variantes claras/oscuras: cabeceras horizontales y cubierta de privacidad normal. Los íconos de instalación proceden de `logo_wo_text.png`, sin texto y sobre blanco, mediante `tool/generate_launcher_icons.ps1`.

## Protección y almacenamiento

El audio y los metadatos críticos se cifran con AES-256-GCM antes de persistirse. Los metadatos se vinculan al audio mediante AAD y se protegen en un sobre cifrado separado. Los identificadores lógicos quedan cifrados; la persistencia utiliza una referencia técnica aleatoria independiente. Se conserva SHA-256 del audio cifrado como comprobación complementaria.

La clave maestra y la referencia final de la auditoría se conservan mediante `flutter_secure_storage`. Hive almacena objetos con campos protegidos; no se cifra todo el archivo de base de datos. Las escrituras emplean auditoría cifrada y un WAL recuperable. Los formatos antiguos se migran después de verificar el audio, sin acreditar retrospectivamente sus metadatos anteriores.

Los incidentes se conservan hasta su eliminación manual. El borrado retira todas sus versiones activas, registra el evento y solicita compactación. No se promete borrado forense, autoría certificada, inmutabilidad del sistema de archivos ni validez jurídica. El control de espacio no elimina incidentes para admitir nuevas grabaciones.

## Modelo desplegado

El modelo actual es el artefacto mixto cuyo SHA-256 es:

```text
f5b94431cada8c946f3c3d87922908740f29e99882abefe22ec70dfff6df693d
```

El motor redimensiona las dos entradas dinámicas antes de la inferencia móvil:

| Tensor | Datos |
| --- | --- |
| `pcm` | float32 `[1,80000]`, mono a 16 kHz |
| `valid_samples` | int32 `[1]`, contenido `[80000]` |
| Probabilidades | float32 `[1,3]`, en el orden de `assets/labels/labels.txt` |

La normalización estadística y softmax están incluidos en el grafo. La aplicación no los repite. La forma inicial `[1,1]` es una dimensión dinámica y no implica que el modelo solo acepte una muestra.

`tool/export_wav2vec_tflite.py` es una herramienta anterior para un checkpoint Wav2Vec2-base, con entrada única fija y salida de logits. No debe utilizarse para reemplazar automáticamente el modelo mixto actual sin adaptar y validar su contrato.

## Ejecución móvil y compilación

Preparar las dependencias Flutter antes de compilar:

```sh
flutter pub get
```

Android utiliza un servicio de micrófono con notificación persistente. El servicio escribe contenedores cifrados en un diario de transferencia y la interfaz los importa mediante el escritor de Hive. No abre la caja de evidencias concurrentemente desde ambos motores. La acción de detener de la notificación es distinta del cambio autenticado y persistente de Configuración. No se configura arranque automático del micrófono al encender el dispositivo.

iOS declara el modo de audio en segundo plano y utiliza una sesión de audio activa. Bloqueo, llamadas, permisos revocados y terminación del proceso pueden interrumpirla. El comportamiento debe probarse en un iPhone real; no hay garantía de monitoreo ininterrumpido.

Para el flujo iOS con CocoaPods, ejecutar desde la raíz después de obtener dependencias:

```sh
ruby tool/align_tflite_ios_podspec.rb
```

El script alinea el plugin con TensorFlow Lite 2.17.0. En un entorno macOS/Xcode, después de generar la configuración Flutter correspondiente, el flujo de [Codemagic](codemagic.yaml) actualiza y comprueba `TensorFlowLiteSwift` y `TensorFlowLiteC`, compila sin firma y empaqueta `serene-unsigned.ipa`. La firma y distribución son pasos adicionales. No se puede compilar iOS nativamente desde Windows.

En Android la configuración actual de release utiliza la firma de depuración. El repositorio describe un prototipo; no acredita una publicación de producción. Es necesario instalar una compilación nueva para verificar los cambios de esta versión.

## Verificación

```sh
flutter test --no-pub
flutter analyze --no-pub
```

El 27 de octubre de 2026 finalizaron correctamente **159 pruebas**. Incluyen señal, contrato del intérprete simulado, incidentes, criptografía, auditoría, recuperación, migración, acceso, eliminación y limpieza de búferes de reproducción. El resultado no sustituye la validación nativa del dispositivo.

Para ejecutar el archivo real del modelo con señales sintéticas de cinco segundos y lote uno, en un entorno con TensorFlow y NumPy:

```sh
python -B tool/check_mobile_model.py
```

La prueba registrada ejecutó tres señales sintéticas, sin acreditar calidad con audio real. El silencio produjo un falso positivo del modelo; ahora la app rechaza señales degeneradas mediante RMS centrada y exige confirmación temporal. Siguen pendientes calibración con grabaciones continuas, rendimiento, consumo y continuidad en la nueva compilación móvil.
