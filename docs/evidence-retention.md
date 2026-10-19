# Política de retención, capacidad y eliminación

| Aspecto | Política aplicada |
| --- | --- |
| Retención predeterminada | Hasta eliminación manual por el usuario. Sin vencimiento por antigüedad. |
| Revisión y eliminación automática | No se implementa borrado automático de evidencias. Se recomienda revisión manual periódica, por ejemplo mensual, y antes de quedarse sin espacio. La recuperación y limpieza de temporales confirmados son mantenimiento, no eliminación automática de evidencias. |
| Duración máxima por incidente almacenado | 5 minutos. Una detección continuada genera registros consecutivos con IDs diferentes; el límite no apaga el monitoreo. Las muestras que cruzan el límite pasan al siguiente registro sin duplicarse cuando las ventanas incluyen sus índices de muestra, como ocurre en el flujo real de captura. |
| Falta de espacio | Antes de guardar se consulta el volumen correspondiente. Se exige margen de 100 MiB más una estimación conservadora para la escritura, cifrado/JSON, WAL e importación. No se reemplazan ni se borran evidencias para liberar espacio. |
| Diario temporal | Archivos cifrados de transferencia entre el servicio y el almacén definitivo. Sin caducidad automática de archivos completos pendientes. Se retiran tras importación auditada confirmada. |
| Eliminación | Eliminar un registro visible elimina todas las versiones de ese incidente, registra la operación en la auditoría y solicita compactación de Hive. No elimina otros incidentes ni segmentos consecutivos con otro ID. |
| Limitación | La eliminación lógica o física realizada por la app no garantiza remover copias internas gestionadas por el sistema operativo, el sistema de archivos, la memoria flash, backups o copias previas externas. |

## Por qué cinco minutos

Es una decisión operativa inicial, no un requisito legal ni un límite científicamente validado del clasificador. El audio actual es PCM de 16 bits, mono, a 16 kHz: 32 000 bytes por segundo. Cinco minutos requieren 9 600 000 bytes de audio (aproximadamente 9,16 MiB). Diez minutos duplicarían el buffer en RAM y, al conservar snapshots completos, aumentarían aún más el almacenamiento acumulado.

Con un primer guardado de cinco segundos, avances cada quince segundos y un guardado final, las versiones de una grabación de cinco minutos pueden sumar alrededor de 104 MB de audio cifrado, antes de añadir metadatos, JSON, WAL y marcos obsoletos de Hive. Por tanto, cinco minutos limita el crecimiento de cada buffer, pero no constituye una cuota global. Se debe validar este valor con duración de escenarios representativos, memoria, espacio y tiempos reales de guardado del teléfono objetivo. La constante está en `EvidencePolicy.maximumIncidentDuration`.

Los límites se calculan por muestras, no por el reloj de pared. Si persiste la detección, se continúa en un nuevo registro. No se incorpora de nuevo la ventana solapada de cinco segundos. Cuando la detección deja de ser positiva, se mantiene el comportamiento existente de cierre tras tres segundos negativos dentro del registro activo.

## Comportamiento ante falta de espacio

`EvidenceStorageGuard` consulta el espacio libre de la ruta de persistencia con `disk_space_2`. El margen de 100 MiB es una condición de admisión; no es un archivo reservado ni una garantía de que otra app no consuma espacio posteriormente.

La dependencia se fija en `disk_space_2` 1.0.12: la versión 1.0.13 no aplica el plugin Kotlin requerido por su configuración Android en este proyecto.

La comprobación se realiza antes de crear un archivo temporal completo del servicio y antes de escribir el WAL de una nueva operación auditada. El guardado del servicio incluye una estimación adicional para su futura importación. Si falla la consulta o el espacio es insuficiente, el guardado se rechaza de forma explícita.

El controlador detiene la captura, libera recursos y muestra el mensaje de falta de espacio. No intenta guardar repetidamente en el volumen lleno ni reinicia automáticamente ese monitoreo por el evento de reanudación de la app. Tras liberar espacio, el usuario puede reiniciarlo. Se conservan las versiones ya confirmadas. El audio aún no confirmado entre el último avance y el fallo puede perderse: no se afirma que se pueda persistir cuando ya no hay capacidad.

Los errores del sistema operativo que indican disco lleno se traducen también a ese estado. Si se interrumpe una escritura después de anclar su WAL, se conserva su estado pendiente para recuperarla cuando haya espacio. Una escritura pendiente que no puede completarse puede requerir liberar espacio fuera de la app antes de permitir nuevas operaciones.

La eliminación manual requiere espacio para su pequeño evento y WAL, pero no exige el margen de admisión de 100 MiB. Si no hay espacio ni para registrar la eliminación, la app informa del fallo y no confirma el borrado.

La consulta nativa está soportada por el complemento en Android, iOS, Windows y Linux. Una plataforma sin implementación no debe asumir capacidad ilimitada: se rechaza el guardado hasta disponer de una medición soportada. El entorno objetivo principal y las exclusiones de backup verificadas en este cambio son Android.

## Qué es el diario temporal

El servicio Android y la interfaz ejecutan motores distintos. Para evitar que ambos escriban la misma base de datos simultáneamente, el servicio deja cada versión cifrada en `background_evidence` y la interfaz la importa a Hive con su evento de auditoría. Ese conjunto de archivos es el **diario temporal**.

Su tratamiento es:

1. Un `.tmp` completo se recupera si hubo un cierre antes de renombrarlo. Un `.tmp` incompleto, que nunca confirmó un guardado, se descarta.
2. Un archivo completo pendiente o `.claimed.json` se conserva mientras su importación no termine.
3. Tras confirmar evidencia y auditoría, se elimina ese archivo del diario.
4. Los duplicados idénticos no crean nuevas versiones. Los archivos correspondientes a un incidente cuya eliminación ya consta en la auditoría se descartan al importarlos, para impedir su reaparición.
5. Un archivo final alterado o inválido no se borra silenciosamente como si se hubiese importado; la validación informa del error.

Hay otro temporal distinto: el **WAL cifrado** dentro del almacén de auditoría. Permite terminar una operación interrumpida. Se elimina después de confirmar el guardado o borrado. No debe confundirse con los eventos de auditoría, que se conservan como historial.

## Qué elimina la app y qué puede permanecer

Antes de este ajuste, la eliminación retiraba todas las versiones activas del incidente y añadía un evento auditado. Hive puede conservar marcos antiguos en sus archivos aunque el registro ya no aparezca en la bóveda. El WAL eliminado también puede dejar marcos cifrados obsoletos en el archivo de auditoría.

Ahora, después de confirmar el borrado, se compactan los archivos de evidencias y auditoría cuando hay espacio para reescribir sus marcos vigentes. El archivo reescrito ya no conserva esos marcos obsoletos. Si no hay espacio o la compactación falla, el borrado lógico sigue confirmado y queda marcada una tarea de mantenimiento para reintentar en una apertura verificada posterior. La compactación conserva la cadena y el hash de auditoría; no elimina sus eventos.

La auditoría conserva IDs, fecha, operación y digests de las versiones eliminadas dentro de eventos cifrados. Es trazabilidad residual deliberada, no el audio. Las claves maestras siguen disponibles para descifrar otros incidentes; no se implementa destrucción de una clave independiente por incidente.

La reproducción descifra el audio en memoria y no crea un archivo de audio en claro. La pantalla limpia su buffer al cerrarse. Eso tampoco garantiza borrar todas las copias transitorias de memoria administradas por el runtime o el sistema.

El manifiesto y las reglas Android excluyen los datos de la app de Auto Backup y de la transferencia estándar entre dispositivos. Esto reduce nuevas copias automáticas de Hive, temporales y preferencias seguras. No elimina backups anteriores ni cubre herramientas de terceros, dispositivos modificados o implementaciones particulares del fabricante. No se afirma que la misma configuración Android controle backups de iOS.

El sistema de archivos puede mantener bloques o snapshots anteriores; la memoria flash puede remapear escrituras a bloques diferentes; puede existir una copia de seguridad hecha antes de borrar. Retirar o reescribir un archivo de la app no permite inspeccionar y eliminar todas esas copias. Por eso no se promete borrado forense irrecuperable. Sobrescribir un archivo con ceros tampoco proporciona por sí solo esa garantía.

Una mejora futura, si se exige mayor capacidad de revocación, es cifrar cada incidente con una clave independiente y destruir esa clave al eliminarlo. Requiere rediseñar la gestión y recuperación de claves y analizar sus backups; tampoco debe presentarse como garantía sobre copias de claves que ya existieran.

## Fuentes técnicas

- [Hive Box y compactación](https://pub.dev/documentation/hive/latest/hive/Box-class.html).
- [Configuración de Auto Backup y transferencia Android](https://developer.android.com/identity/data/autobackup?hl=en).
- [Complemento de medición de espacio por ruta](https://pub.dev/packages/disk_space_2).
- [NIST SP 800-88 Rev. 2: límites de sanitización y borrado criptográfico](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-88r2.pdf).

## Validación

Las pruebas simulan falta de espacio en admisión, desconocimiento de capacidad, errores de disco lleno, borrado manual con poco espacio, compactación diferida y reintento. La grabación se comprueba con límites en segundos y fracciones de segundo para detectar duplicación o pérdida de muestras al crear el siguiente registro. La saturación física del almacenamiento y las reglas de backup deben probarse adicionalmente en el teléfono objetivo.
