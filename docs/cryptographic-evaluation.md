# Evaluación criptográfica reproducible

Los resultados incorporan `evaluation_metrics` con invoke en Windows, CR y pico oficial de RAM pendientes (`null`): no se derivan de pruebas criptográficas. Para medirlos y reunirlos en otro JSON, véase [evaluación de rendimiento](performance-evaluation.md), incluyendo procedimiento en Mac, plantilla de evidencia y límites de las VM.

La suite se ejecuta desde el código y no añade pruebas destructivas ni botones de criptografía a la aplicación final. Usa `CipherManager` (AES-256-GCM), claves temporales y un isolate de evaluación. Nunca abre la bóveda personal ni usa claves de producción. Los datos originales se leen sin modificarlos.

## Ejecución en el equipo

Desde la raíz del repositorio, con Flutter/Dart en PATH y las dependencias instaladas:

```powershell
flutter pub get
dart run tool/evaluate_crypto.dart
dart run tool/evaluate_crypto.dart --dataset "D:\datasets\audios" --repetitions 10
```

Ejecutar una sola de las dos variantes de evaluación según el objetivo. Sin dataset, genera bytes sintéticos reproducibles de 32 000, 160 000 y 960 000 bytes (tamaños equivalentes a 1, 5 y 30 segundos PCM16 mono a 16 kHz; no son sonidos reales). Con dataset, busca recursivamente `.wav`, `.pcm` y `.raw`, sin seguir enlaces simbólicos. Evalúa los bytes del archivo completo: incluye cabeceras WAV, no decodifica ni convierte el audio. Por ello mide criptografía por tamaño, no el pipeline acústico ni la fidelidad del modelo.

Se omiten archivos vacíos o mayores de 16 MiB, registrando la omisión y marcando la ejecución como parcial. No se copian audios ni claves a la salida. Los archivos se identifican por un ordinal y su SHA-256, sin publicar sus nombres o rutas; el hash permite relacionarlos localmente, pero no debe considerarse información anónima.

`--repetitions` admite 1 a 1000 (10 por defecto). Cada entrada tiene dos cifrados de calentamiento excluidos de los tiempos. `--skip-tests` omite las pruebas de integración y produce un resultado parcial. `--help` muestra las opciones.

## Archivos de salida

Cada ejecución crea una carpeta UTC independiente en `evaluation_results/`, excluida de Git:

- `results.json`: entorno, revisión Git y estado de cambios, hashes del código de cifrado y lockfile, configuración, casos individuales, omisiones, resumen y estado final.
- `encryption_samples.csv`: tiempo de cifrado por entrada y repetición en milisegundos.
- `run.log`: inicio, progreso, resultado de cada entrada y finalización.
- `flutter-tests.jsonl`: eventos originales del runner de pruebas de la aplicación.
- `flutter-tests.stderr.log`: salida de diagnóstico del runner.

Los dos últimos solo se producen si se llega a ejecutar esa fase. El JSON se actualiza al completar cada entrada y al finalizar; una excepción conserva los resultados previos y marca error. Una terminación forzada puede dejar estado `running`: no debe interpretarse como aprobación. La consola previa al arranque de Dart no forma parte de `run.log`.

Códigos de salida: **0** evaluación completa aprobada; **1** fallo/error; **2** parcial por omisiones o `--skip-tests`; **64** argumentos inválidos. Los argumentos inválidos no crean una ejecución. Los errores previos a iniciar Dart tampoco producen archivos. Revisar siempre `status`, las omisiones y `application_tests`; no basta con ver archivos generados.

## Casos y fórmulas

Para cada entrada y repetición se cifra y descifra con una clave válida, comparando todos los bytes recuperados con el original. Después se comprueba, en copias independientes, el rechazo de un cambio de un bit en ciphertext, nonce, tag y AAD, y el rechazo con otra clave. También se comprueba que no se repitan nonces dentro de las operaciones observadas; esto no demuestra matemáticamente ausencia futura de colisiones.

**Tasa de descifrado exitoso (%) = recuperaciones exactas / intentos válidos × 100.** No incluye ataques ni calentamientos. Los rechazos de manipulación se informan por separado: rechazarlos es el resultado esperado. No hay tasa cuando no existen intentos válidos.

El cronómetro se inicia y detiene **dentro del isolate** alrededor de `CipherManager.encryptInMemory`. Incluye la operación y construcción del resultado en memoria; excluye lectura del archivo, generación de claves, mensajes entre isolates, descifrado, comparación y persistencia. Es tiempo transcurrido, no tiempo exclusivo de CPU. Se conservan muestras, mediana y p95 (rango más próximo). No equivale al tiempo total de guardar un incidente ni al cifrado completo de todos sus sobres y eventos.

Se ejecutan además las pruebas existentes de `test/core/crypto`, `evidence_storage_guard_test.dart` y datos/dominio de `evidence_vault`. Cubren recuperación, metadatos autenticados, persistencia y reapertura, auditoría, WAL, staging, eliminación y capacidad. Sus eventos y código de salida se conservan sin inventar una tasa de recuperación del dataset a través de Hive. El dataset evalúa `CipherManager`; las pruebas de persistencia usan sus propias fixtures y almacenamiento seguro simulado.

## Relación con evaluación móvil y metodología

Esta herramienta corre en la VM Dart del **host**. Windows no mide latencia de Android/iOS, consumo móvil, rendimiento AOT, `invoke` TFLite, red ni RAM máxima del teléfono. No acredita admisibilidad jurídica. No evalúa resistencia a extracción de claves en un dispositivo comprometido.

La app final conserva únicamente **Settings → Diagnóstico → Diagnóstico de rendimiento**: muestreo voluntario cada 5 segundos, hasta 15 minutos, y exportación JSON. Incluye CPU de proceso, memoria disponible mediante las APIs nativas, batería, estado térmico y tiempos de inicialización, inferencia y guardado. El tiempo de guardado no es latencia exclusiva de cifrado. Excluye audio, GPS y predicciones. Las muestras pueden retrasarse al suspenderse la app; su máximo observado puede omitir picos y no sustituye Android Studio Profiler/Xcode Instruments. La implementación iOS requiere validación en un IPA real.

Para reportar latencia criptográfica móvil debe ejecutarse un harness de evaluación en el teléfono con el mismo alcance del cronómetro y exportar sus resultados; este script de host no lo proporciona. El tráfico requiere una captura externa controlada y atribución a la app; no se mide ni se asume cero. El benchmark `invoke` de Windows con cuatro hilos y la reducción de tamaño entre TFLite FLOAT32 y optimizado son experimentos separados. CR (%) = (1 − tamaño optimizado / tamaño FLOAT32) × 100.

Registrar dispositivo/host, versiones, modo de compilación, cantidad y tamaños de entradas, repeticiones y condiciones térmicas. Conservar los resultados originales de cada ejecución fuera de Git. El cierre real del proceso, pérdida de energía, almacenamiento seguro del sistema y reglas de backup requieren validación adicional en dispositivos.
