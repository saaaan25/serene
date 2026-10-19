# Integridad y trazabilidad local de evidencias

La política operativa de duración, espacio, temporales y eliminación se detalla en [evidence-retention.md](evidence-retention.md).

La implementación ofrece un **mecanismo técnico de integridad y trazabilidad reforzada**. Funciona localmente, sin roles, servidores ni firmas digitales por hardware. No establece validez judicial, autoría independiente ni la exactitud del reloj del dispositivo.

## Registros nuevos: esquema 2

Cada guardado produce una versión con UUID propio. El identificador del incidente, fecha de inicio UTC, fecha de guardado UTC, versión anterior, etiqueta, confianza, GPS, versión instalada de la aplicación, SHA-256 del archivo `model.tflite` y formato PCM se serializan como JSON canónico: claves ordenadas recursivamente y codificación UTF-8.

Esos bytes son el AAD del audio AES-256-GCM y, por separado, el contenido de un sobre AES-256-GCM de metadatos. El sobre usa como AAD su propósito, esquema e identificador de versión. Cada operación genera un nonce independiente. Hive y los archivos del servicio conservan únicamente el UUID de versión, esquema, audio cifrado, sobre cifrado y sus nonces/tags. Los campos descriptivos del adaptador antiguo quedan vacíos; los metadatos se reconstruyen en memoria.

La versión y número de compilación se consultan con `package_info_plus`, por lo que también reflejan los cambios de versión realizados al compilar. El hash del modelo se calcula sobre el asset real, no sobre una etiqueta declarada manualmente.

La bóveda consulta el repositorio, muestra solamente la última versión por incidente e identifica explícitamente los registros anteriores. Todas las versiones permanecen almacenadas hasta eliminar el incidente. Las estadísticas cuentan incidentes y suman los bytes de audio cifrado de todas sus versiones. Conservar snapshots completos aumenta el uso de espacio, especialmente en incidentes largos.

## Auditoría y escritura recuperable

`EvidenceLocalDataSourceImpl` es el único escritor de Hive y de auditoría en el isolate de la interfaz. Una cola compartida serializa altas, importaciones, consultas verificadas y eliminaciones. El servicio de segundo plano escribe versiones inmutables en archivos; nunca abre Hive.

Cada evento contiene ID único, secuencia, fecha UTC, operación (`create`, `new_version`, `delete` o `legacy_import`), incidente, IDs y digests de las versiones afectadas y hash del evento anterior. El cuerpo del evento está cifrado y autenticado con AES-GCM. La secuencia y hash previo son su AAD; el SHA-256 de su representación canónica enlaza el siguiente evento. El hash y secuencia finales se conservan en `flutter_secure_storage`, separados de Hive.

Una modificación de audio, sobre, evento o cadena, un borrado sin evento de eliminación, el intercambio de eventos y el recorte del final provocan un error de verificación frente a esa referencia protegida. La aplicación no reestablece silenciosamente una cadena rota. La reproducción vuelve a verificar la persistencia y auditoría antes de descifrar el audio.

La escritura sigue estas etapas:

1. Guardar y hacer `flush` de una transacción de recuperación (WAL) cifrada que contiene el evento y las modificaciones previstas.
2. Guardar en almacenamiento seguro la referencia a la transacción pendiente y su digest, manteniendo la cabeza anterior.
3. Añadir el evento y hacer `flush` de la auditoría.
4. Aplicar la inserción de versiones nuevas o eliminación de todas las versiones del incidente, y hacer `flush` de evidencias.
5. Actualizar la cabeza protegida y retirar el WAL.

Si la ejecución se interrumpe después del paso 2, la siguiente apertura comprueba el WAL y termina la misma transacción de manera idempotente. Antes del paso 2, un WAL huérfano se descarta: no existió una confirmación de guardado. Un WAL o evento pendiente alterado se rechaza.

En el servicio, un `.tmp` completo y cifrado puede recuperarse si hubo cierre antes de renombrarlo. Un `.tmp` truncado nunca confirmado se descarta. Un archivo final o reclamado permanece hasta completar su importación auditada. Las importaciones se ordenan por fecha autenticada; se comprueba la existencia de la versión predecesora. Repetir una importación idéntica no añade eventos ni versiones. Una importación posterior de un incidente eliminado se descarta para evitar su resurrección.

Eliminar un incidente elimina sus versiones activas y conserva el evento de eliminación, con IDs y digests, sin conservar el audio en el evento. Es una eliminación lógica del almacén: no se afirma borrado forense de bloques, copias previas o backups.

## Compatibilidad anterior

El adaptador mantiene los campos Hive 0–8 y añade campos 9–18 con valores por defecto explícitos. Los registros reales de nueve campos se leen como esquema 1. Se conserva el descifrado AES-GCM original sin AAD y la comprobación SHA-256 anterior. Los archivos JSON antiguos del servicio también se importan.

La primera apertura incorpora los registros antiguos como una base auditada `legacy_import`. Esto acredita continuidad **desde la incorporación**, no demuestra que sus metadatos anteriores fueran auténticos. Sus metadatos antiguos siguen en su formato previo; la interfaz los marca como registros sin metadatos autenticados. No se modifica retroactivamente su significado ni se presentan como esquema 2.

Si dos archivos antiguos del servicio reutilizan el mismo ID con contenidos diferentes, el segundo se conserva como una versión legacy con ID determinístico derivado de su digest. Cuando los snapshots antiguos comparten fecha, la bóveda elige el audio más completo, sin reemplazar la otra versión.

## Alcance de las garantías

La auditoría es append-only a través de la aplicación y permite detectar cambios respecto de su referencia local protegida; no convierte los archivos del sistema operativo en inmutables. El modelo de amenaza supone que un atacante puede alterar Hive o los archivos del servicio, pero no controlar simultáneamente la clave, la referencia protegida y el proceso de la aplicación. Restaurar una copia antigua coherente de todo el estado, incluido el almacenamiento seguro, queda fuera de la detección local. Tampoco se puede demostrar que nunca existió un archivo del servicio eliminado antes de su incorporación a la auditoría, aunque la ausencia de un predecesor se detecta si llega una versión posterior.

## Verificación reproducible

Las pruebas de `evidence_integrity_test.dart` alteran cada campo AAD, ciphertext de audio, tag y nonce; alteran el sobre, eventos, orden y cabeza; manipulan el WAL y simulan cierres en cada etapa, reabriendo Hive con la misma referencia protegida. También comprueban guardados concurrentes, borrado del incidente y lectura de registros escritos con el adaptador original de nueve campos.

`background_evidence_journal_test.dart` cubre metadatos ocultos en staging, versiones conservadas, orden de importación, reintentos, archivos reclamados, recuperación temporal, predecesores ausentes y prevención de resurrección. `vault_integrity_ui_test.dart` comprueba que la interfaz usa los metadatos del repositorio, identifica registros antiguos y muestra un error cuando la verificación falla.

Ejecutar:

```powershell
flutter test --no-pub test/core/crypto test/features/evidence_vault/data test/features/evidence_vault/domain test/features/evidence_vault/presentation/evidence_controller_test.dart test/features/evidence_vault/presentation/vault_integrity_ui_test.dart
```

Estas son pruebas automatizadas con almacenamiento seguro simulado. El cierre de proceso real, corte de alimentación y funcionamiento de los plugins deben validarse también en el dispositivo de destino.
