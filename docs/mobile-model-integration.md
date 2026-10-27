# Modelo mixto: contrato de inferencia móvil

La app utiliza el modelo de `exports_tflite_mixed`. El archivo empaquetado y el de exportación se compararon por SHA-256:

`f5b94431cada8c946f3c3d87922908740f29e99882abefe22ec70dfff6df693d`

El contrato original se conserva en [mobile-model-contract.json](mobile-model-contract.json). No es necesario reentrenar ni sustituir el modelo para adaptar las entradas.

| Tensor | Tipo | Datos enviados por la app |
| --- | --- | --- |
| `serving_default_pcm:0` | float32 | `[1, 80000]`: audio mono a 16 kHz, cinco segundos, escala `[-1,1]` |
| `serving_default_valid_samples:0` | int32 | `[1]`, contenido `[80000]` |
| Salida de probabilidades | float32 | `[1,3]`: no_violence, physical_violence, verbal_violence |

El tensor PCM comienza con forma `[1,1]` y firma `[-1,-1]`. El motor identifica las entradas por nombre, comprueba tipos y rangos del contrato, redimensiona ambas entradas y reasigna los tensores antes de inferir. Los índices de la API Flutter son posiciones de entrada/salida; el índice interno 1405 de la salida en el archivo no se pasa como índice de salida a `runForMultipleInputs`.

La conversión de PCM16 a float32 divide por 32768. No se aplica normalización estadística adicional: la media y varianza sobre muestras válidas se procesan dentro del modelo. Tampoco se aplica un segundo softmax; el motor conserva las probabilidades originales, rechaza valores no finitos o fuera de `[0,1]` y exige una suma cercana a uno. El umbral configurado de la app se aplica sobre esas probabilidades.

El flujo móvil actual usa solo ventanas completas de 80000 muestras. No rellena todas las entradas hasta las 224000 muestras máximas del exportador ni trunca silenciosamente entradas de otra longitud. El contrato dinámico del modelo no implica que la app soporte duraciones arbitrarias para cada inferencia.

## Validación realizada

Las pruebas Dart ejecutan el motor con un intérprete simulado y verifican redimensionamiento, orden de entradas incluso si se invierten, `Int32List` para longitudes, conservación de probabilidades, etiquetas y rechazo de contratos incompatibles.

Además se ejecutó el archivo real con TensorFlow 2.19.0 en el equipo, dos hilos CPU y lote uno. Se probó la asignación inicial que hace `tflite_flutter`, después el redimensionamiento y la inferencia de cinco segundos. Resultados observados:

| Señal sintética | Sin violencia | Física | Verbal |
| --- | ---: | ---: | ---: |
| Silencio absoluto | 0.00117439 | 0.99806505 | 0.00076050 |
| Seno de 440 Hz | 0.99764258 | 0.00102552 | 0.00133186 |
| Ruido uniforme, semilla 42 | 0.99762446 | 0.00099326 | 0.00138231 |

Los resultados demuestran ejecución, formas y salida numérica; no acreditan calidad de clasificación. El resultado de silencio es un falso positivo sintético. El controlador ya evita invocar el modelo con ventanas exactamente nulas; esto no valida ruido ambiental ni sonidos de bajo volumen. Deben medirse sensibilidad, falsos positivos y comportamiento por clase con audio real, ventanas de cinco segundos y lote uno.

La prueba nativa de iOS y el rendimiento en el iPhone siguen pendientes. Cambiar el código requiere compilar e instalar un nuevo `.ipa`; no modifica la app ya instalada.

Para repetir la prueba del archivo real, usando un entorno existente con TensorFlow y NumPy:

```powershell
python -B tool/check_mobile_model.py
```

El exportador histórico `tool/export_wav2vec_tflite.py` utiliza otro contrato (entrada única fija y logits). No debe reemplazar automáticamente el modelo mixto desplegado sin adaptar y verificar su contrato.
