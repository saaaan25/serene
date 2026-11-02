# Métricas pendientes, benchmark y perfilado móvil

## Qué aparece en el JSON

El JSON de diagnóstico móvil y el de evaluación criptográfica contienen `evaluation_metrics`: `host_invoke`, `storage_reduction` y `official_background_peak_ram`. Los valores pendientes son **null**, con estado `pending_external_measurement`; no se representan como cero ni se rellenan con tiempos de otras operaciones. La app no ejecuta el benchmark de Windows ni incorpora automáticamente archivos externos.

El JSON móvil añade `observed_memory_maxima`: máximos entre las muestras disponibles de residente, footprint y PSS, por separado. `background_only: false` indica que no se ha aislado el intervalo de segundo plano. No sustituye el pico oficial, ni garantiza capturar picos entre muestras. La recolección puede suspenderse con la app.

Un reporte independiente reúne resultados externos:

```powershell
python tool/evaluate_performance.py
```

Sin argumentos crea un JSON con las tres métricas pendientes. Cada ejecución escribe `evaluation_results/performance_<UTC>/results.json` y `run.log`; el benchmark añade `invoke_samples.csv`. No sobrescribe reportes móviles ni resultados anteriores. La carpeta está excluida de Git. `status: partial` significa que faltan métricas; `error` indica que falló una operación solicitada. Este script devuelve 0 si termina sin errores, aunque haya métricas pendientes, y 1 ante errores de evaluación (argparse devuelve 2 para argumentos inválidos). Revisar siempre los estados individuales.

## CR: tamaños de artefactos

```powershell
python tool/evaluate_performance.py --float32 "D:\modelos\float32.tflite" --optimized "D:\modelos\optimized.tflite"
```

Calcula `(1 − bytes optimizado / bytes FLOAT32) × 100` y guarda ambos tamaños y hashes SHA-256. Puede ser negativo si el candidato pesa más. El script no comprueba que la referencia sea FLOAT32: debe acreditarse con el proceso de exportación (`reference_dtype_verified: false`). Comparar el mismo modelo y contrato, no IPA/APK, ZIP ni checkpoints de entrenamiento.

## Mediana de invoke en CPU de Windows

Usar un entorno de evaluación con Python 3.11+, NumPy y TensorFlow compatible con el modelo (el exportador actual requiere TensorFlow 2.17.x). Estas dependencias solo se necesitan para `--model/--batches`; no se instalan automáticamente. Registrar sus versiones y las condiciones del equipo. El script registra el sistema, CPU, Python, TensorFlow, NumPy y hashes de modelo/lotes.

Guardar **cada lote original ya preprocesado** del experimento como un `.npy` independiente, con la dimensión de lote intacta:

```python
# Dentro del pipeline original, donde original_batch ya tiene el preprocesado final:
np.save("batches/batch_0001.npy", original_batch)
```

No convertir aquí la carpeta train/val/test a lotes nuevos: eso cambiaría el experimento. No se necesita incluir etiquetas. El modelo debe admitir la forma real del lote; si está exportado con batch fijo 1 y los originales son mayores, el benchmark rechazará el cambio estricto. Se necesita un artefacto compatible y documentado; no se degrada silenciosamente a lote uno. Guardar ambas evaluaciones como experimentos distintos si cambia el contrato.

```powershell
python tool/evaluate_performance.py --model "D:\modelos\optimized.tflite" --batches "D:\experimento\batches" --warmup 5 --repetitions 10
```

Se exige host Windows, una entrada y dtype/rango compatibles. No se convierte dtype, normaliza, rellena ni reagrupa. `num_threads=4` configura el intérprete; no significa que todo el proceso solo use cuatro hilos. Se emplean los delegados CPU predeterminados de TensorFlow, sin cargar un delegado GPU explícito. Registrar si el host es físico o VM y no mezclar ambas condiciones.

Se cronometra únicamente `interpreter.invoke()` con reloj de alta resolución; lectura, carga, resize, allocation, warmup, set/get tensor y comprobación de salidas quedan fuera. El CSV conserva cada tiempo; el JSON contiene mediana global de todos los invokes y mediana por lote, forma, dtype y hashes. No es latencia por ejemplo, de teléfono ni del flujo completo. El script está preparado y sus validaciones probadas, pero el benchmark real requiere tus artefactos y lotes; no se han generado resultados reales en este entorno.

## Al disponer de una Mac e iPhone

1. Instalar Xcode compatible con el iOS del teléfono y Flutter compatible con el proyecto. Conectar el iPhone por USB, aceptar confianza y habilitar Developer Mode cuando corresponda. Abrir `ios/Runner.xcworkspace`, seleccionar el equipo de firma y el **iPhone físico**.
2. Preparar una compilación **Profile** de Flutter (`flutter build ios --profile` en la Mac). En el esquema Runner, revisar que la acción Profile use esa configuración. Iniciar el perfilado mediante **Product → Profile**. No usar Debug para la medición definitiva; registrar configuración y versión.
3. En Instruments seleccionar el proceso Runner/Serene y un instrumento que exponga memoria física/footprint (por ejemplo, VM Tracker según la versión). No usar el total de objetos de Allocations como si fuera toda la memoria del proceso. Registrar el nombre exacto de la métrica y unidad que muestra la herramienta.
4. Protocolo sugerido: dejar estabilizar 60 segundos, activar monitoreo con permisos concedidos, iniciar captura, enviar la app al segundo plano y medir un intervalo definido, por ejemplo 300 segundos. Marcar su inicio/fin y comprobar que el monitoreo siguió activo. Si iOS lo suspende o termina el proceso, registrar el hecho; no interpretar ausencia de muestras como consumo cero.
5. Seleccionar **solo el intervalo de segundo plano** y extraer su máximo. Repetir al menos tres veces bajo las mismas condiciones de carga, batería, temperatura y audio. Guardar cada sesión por separado, sin mezclar arranque y segundo plano.
6. Guardar la sesión `.trace`, capturas de la selección y versión de Instruments. Comprimir el bundle `.trace` en ZIP para conservarlo e identificarlo mediante hash. No es necesario automatizar `xctrace`: sus plantillas y esquemas dependen de la versión; consultar `xcrun xctrace help` y `xcrun xctrace list templates` en esa Mac si se desea automatización posterior.

El diagnóstico de la app puede acompañar la sesión, pero añade trabajo: declarar si estuvo activo y usar la misma condición entre repeticiones. Para comprobar continuidad también hacer una sesión sin Instruments/depurador, ya que el entorno de perfilado puede modificar el comportamiento.

## Incorporar la RAM oficial al JSON

Copiar `tool/templates/ram_evidence.json` a una carpeta dentro de `evaluation_results/` y completar sus campos con la captura. `peak_bytes` debe ser un entero positivo en bytes: MiB × 1 048 576; MB decimal × 1 000 000. No convertir unidades sin revisar qué presenta la herramienta. Indicar `memory_metric`, modelo físico, OS, app, modo, herramienta/versión, fecha UTC e intervalo. `evidence_file` es la ruta del ZIP/export relativo a ese JSON.

```powershell
python tool/evaluate_performance.py --ram-evidence "evaluation_results\sesion_ios\ram_evidence.json"
```

El script comprueba campos y existencia del archivo y calcula su SHA-256. Guarda estado `externally_reported_not_independently_verified`: vincula la transcripción a una evidencia, pero no analiza automáticamente la traza ni certifica que el máximo sea correcto. Nunca rellenar la plantilla con valores del simulador o inventados.

Para un **único JSON con las tres métricas**, ejecutar en Windows con los artefactos, lotes y copia de la evidencia obtenida en la Mac:

```powershell
python tool/evaluate_performance.py --float32 "D:\modelos\float32.tflite" --optimized "D:\modelos\optimized.tflite" --model "D:\modelos\optimized.tflite" --batches "D:\experimento\batches" --ram-evidence "evaluation_results\sesion_ios\ram_evidence.json"
```

Para Android seguir el mismo protocolo temporal con teléfono físico y Android Studio Profiler, capturando memoria del proceso en una compilación perfilable de evaluación. Exportar la captura oficial y declarar RSS/PSS u otra métrica exacta; no mezclarlas como magnitudes idénticas. La plantilla admite `platform: android` y `profiler: Android Studio Profiler`. Guardar una ejecución por dispositivo/plataforma.

## ¿Sirve una VM?

- **Windows en una VM:** puede ejecutar el benchmark del host, pero sus tiempos incluyen el entorno virtual. Registrar vCPU, memoria asignada e hipervisor, y reportarlo como host virtualizado. No representa un teléfono.
- **macOS virtualizado sobre hardware Apple:** puede ser una opción según compatibilidad de Xcode, acceso al dispositivo y condiciones de licencia aplicables. Hay que comprobar emparejamiento y acceso al iPhone; no se garantiza acceso USB ni perfilado desde cualquier VM. Para esta evaluación es preferible Instruments en la Mac anfitriona con el iPhone conectado.
- **Una VM macOS en tu PC Windows no es el procedimiento soportado que se propone aquí.** Xcode requiere macOS; el simulador tampoco reproduce memoria/rendimiento del iPhone. La vía práctica es una Mac física prestada o acceso a una Mac con el teléfono conectado y control del perfilado. Un servicio que solo compila el IPA no mide tu iPhone.

Referencias: [Apple: perfilado en dispositivo](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance/), [Flutter: usar dispositivos físicos y modo Profile](https://docs.flutter.dev/perf/ui-performance), [Apple: virtualización](https://developer.apple.com/documentation/virtualization), [condiciones de licencia del software Apple](https://www.apple.com/legal/sla/), [Android: memoria del proceso](https://developer.android.com/topic/performance/memory/manage-app-memory).
