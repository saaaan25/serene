# Detección continua y validación con audio del celular

La app usa PCM16 mono a 16 kHz, ventanas completas de 5 s y avance de 1 s.
La normalización estadística y softmax siguen dentro del modelo. No se han
cambiado sus pesos ni el umbral de clasificación (0.60).

## Política implementada

- Se rechazan muestras inválidas y señales cuya RMS, después de quitar la media,
  no supera una unidad PCM16 (`1/32768`). Esto detecta silencio, desplazamiento
  constante y señales numéricamente degeneradas. No es un filtro de voz ni un
  umbral de ruido ambiental calibrado; no garantiza rechazar ruido cotidiano.
- Una primera inferencia positiva crea un candidato solo en RAM. Una segunda
  inferencia positiva, con al menos 1 s de PCM nuevo y dentro de 6 s, confirma el
  incidente. Una predicción negativa o señal degenerada descarta el candidato.
- El audio inicial se conserva y se guarda al confirmar. Detener el monitoreo
  no convierte un candidato sin confirmar en una grabación.
- Las ventanas sin inferencia conservan PCM, pero no son votos positivos ni
  negativos. Un incidente confirmado termina si pasan más de 6 s de audio sin
  una nueva predicción positiva, o si llega una negativa/señal degenerada.
- Las decisiones usan posiciones de muestras, no el reloj del dispositivo.
  Se conservan muestras PCM partidas entre bloques y se emiten todos los pasos
  de un bloque grande. Los segmentos limitados por duración no repiten ni omiten
  audio de un incidente confirmado.

Los intervalos de 1 y 6 s son una política inicial, **no parámetros acreditados
con grabaciones del celular**. Las ventanas solapadas están correlacionadas:
dos positivos no son dos pruebas independientes y un falso positivo persistente
puede seguir confirmándose. Exigir confirmación puede omitir incidentes breves.
En teléfonos cuya inferencia tarde demasiado también puede expirar un candidato.
Por eso se deben medir recall, falsas alarmas y demora antes de afirmar una mejora
de calidad. Subir la confianza no soluciona errores del modelo con confianza alta.

## Preparar grabaciones

Se necesitan WAV **continuos**, mono PCM16 a 16 kHz, preferiblemente con contexto
antes y después de cada evento. No basta exportar solo las grabaciones que la app
ya detectó: eso oculta los incidentes omitidos. Incluir periodos largos normales
(conversación, TV, cocina, transporte, manipulación del celular y silencio), además
de eventos anotados. No se requiere provocar situaciones peligrosas.

No concatenar clips de entrenamiento ni rellenar clips cortos y presentar eso
como una validación del celular. Archivos menores de 5 s quedan sin evaluar;
un único paso de 5 s no puede confirmar. Mantener fuentes/grabaciones separadas
entre validación y test. Ajustar con validación y evaluar test después de fijar
la política, sin volver a elegir parámetros por sus resultados.

Ejemplo de `manifest.json` junto a los WAV (los tiempos son segundos desde el
inicio; `events: []` significa que toda la grabación fue revisada como negativa):

```json
{
  "recordings": [
    {
      "id": "android_cocina_01",
      "path": "android_cocina_01.wav",
      "split": "validation",
      "events": []
    },
    {
      "id": "ios_evento_01",
      "path": "ios_evento_01.wav",
      "split": "validation",
      "events": [
        {"start_seconds": 12.4, "end_seconds": 14.1, "label": "physical_violence"}
      ]
    }
  ]
}
```

También se acepta `verbal_violence`. Los eventos deben estar dentro de la duración
del archivo. Marcar todas las ocurrencias; una anotación incompleta falsea las
métricas. Usar IDs distintos y conservar las anotaciones originales.

## Ejecutar

Con un entorno existente que tenga NumPy y TensorFlow:

```powershell
python -B tool/predict_mobile_recordings.py --manifest ruta/manifest.json --split validation --output build/phone_predictions.jsonl
dart tool/evaluate_audio_detection.dart build/phone_predictions.jsonl
```

En este equipo se puede usar `../training/.env/Scripts/python.exe` en el primer
comando. La herramienta ejecuta el modelo real incluido en assets, lote uno,
ventanas de 5 s y paso de 1 s. Rechaza formatos distintos en vez de remuestrear
o rellenar silenciosamente. `--inference-stride-seconds 2` permite repetir con
pasos sin clasificar para explorar dispositivos lentos; no simula la latencia
real del teléfono. Guarda hash del modelo y del PCM, estadísticas y probabilidades,
sin copiar audio, rutas completas ni GPS al JSONL.

El evaluador Dart reutiliza `DetectionPolicy`, `SignalQuality` y las constantes
de la app. Informa detecciones, eventos omitidos, precisión/recall binarios de
eventos y demora de confirmación. Empareja cada detección con un evento distinto
que intersecte la ventana que confirmó el incidente. Una segunda detección del
mismo evento cuenta como alarma adicional. No son métricas de clasificación
física/verbal ni confianza calibrada.

Las falsas alarmas por hora se calculan solo sobre grabaciones enteramente
negativas, excluyendo los primeros 5 s de llenado del buffer. Si no hay horas
negativas o eventos anotados, la métrica correspondiente es `null`, no éxito.
Los archivos sin ventanas evaluables no entran al recall agregado.

La evaluación en host verifica audio y política, no permisos, micrófono,
interrupciones, latencia o consumo nativos. En una compilación debug, los logs
`AudioDetection` muestran posición PCM, RMS centrada, probabilidades nuevas y
decisión, sin incluir muestras ni ubicación; no se generan en release. Comparar
las capturas reales de Android e iOS y revisar especialmente eventos breves.

## Evidencia y límites actuales

Antes de este cambio el modelo empaquetado devolvió aproximadamente 0.9981 de
violencia física para silencio y una señal constante de una unidad PCM. Ambas
señales se rechazan ahora antes de inferir. Las pruebas cubren señal débil variable,
impactos, candidatos aislados, votos repetidos, expiración, continuidad, límites
de duración y alineación de bloques. Esto acredita correcciones del flujo, no
que desaparezcan todas las falsas alarmas del modelo.

La medición previa con 150 audios originales completos de validación en host y
lote uno obtuvo F1 macro 0.9201, con 2/50 falsos positivos binarios a umbral 0.60.
Ese experimento no utilizó esta confirmación ni grabaciones continuas del celular.
**La validación y calibración final con esas grabaciones sigue pendiente.**
