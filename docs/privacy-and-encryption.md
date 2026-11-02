# Protección de registros locales

## Evaluación separada de la aplicación

El [protocolo criptográfico reproducible](cryptographic-evaluation.md) utiliza claves temporales, sin abrir la bóveda personal ni modificar el dataset. Conserva resúmenes, hashes de entradas y logs en `evaluation_results/`, excluido de Git; no conserva claves ni audio. Los hashes permiten correlacionar entradas y no constituyen anonimización. La salida debe revisarse antes de compartirla. El diagnóstico móvil es voluntario y exporta métricas de proceso sin audio, ubicación ni predicciones; no mide tráfico saliente ni acredita ausencia de comunicaciones.

El audio seleccionado y sus metadatos críticos se protegen con AES-GCM de 256 bits antes de persistirse. El audio y los metadatos usan bloques cifrados separados y vinculados: los metadatos canónicos son datos autenticados adicionales del audio. Cada operación obtiene un nonce aleatorio de la biblioteca criptográfica. Esta generación reduce probabilísticamente las colisiones; no se afirma una garantía matemática de unicidad global.

El identificador lógico, el identificador del incidente, las fechas, la clasificación, la confianza y la ubicación autorizada permanecen cifrados. Hive y los archivos de preparación usan una referencia aleatoria independiente. Esta referencia técnica, la versión del formato, los tamaños, los nonces, las etiquetas y el hash complementario son visibles. La referencia técnica no es el identificador lógico del registro.

Se conserva el SHA-256 del audio cifrado como comprobación complementaria. AES-GCM autentica los datos al descifrarlos; SHA-256 no es una firma digital ni certifica autoría. La auditoría cifrada también conserva resúmenes de los contenedores completos. Estos mecanismos no certifican validez jurídica ni custodia forense.

La clave maestra no se persiste en texto plano: se entrega a flutter_secure_storage, configurado con EncryptedSharedPreferences en Android y Keychain en iOS. Base64 solo serializa la clave. Los bytes de la clave existen en memoria durante las operaciones; se limpian las copias modificables controladas por la aplicación, sin prometer eliminación de todas las copias del runtime o del sistema operativo. El almacenamiento seguro no implica por sí mismo que cada uso de la clave solicite biometría; la aplicación controla el acceso y autentica de nuevo antes de reproducir.

## Actualización de formatos antiguos

Al abrir el almacén verificado se convierten los registros con metadatos sin cifrar y los contenedores anteriores que usaban el identificador lógico como referencia externa. Se verifican el hash disponible y AES-GCM del audio original; se preservan sus identificadores lógicos, fechas y contenido. Se genera una referencia externa nueva, se vuelve a cifrar y se verifica que el audio resultante coincide antes de confirmar el reemplazo.

El reemplazo usa el diario transaccional cifrado y la recuperación de auditoría. Una interrupción deja el original o una transacción recuperable; una nueva apertura termina o reintenta la migración. Si falta espacio o la verificación falla, no se confirma la sustitución. El nuevo cifrado no acredita retrospectivamente la autenticidad de metadatos antiguos que no estaban autenticados.

Tras confirmar la sustitución se solicita compactación de Hive. Si falla, se reintenta después. Esto no garantiza eliminar bloques antiguos, copias de seguridad o snapshots externos.

## Selección de audio

El monitoreo usa ventanas completas de cinco segundos y pasos nominales de uno. Una primera positiva retiene un candidato solo en RAM; una segunda inferencia positiva nueva, separada al menos un segundo y dentro de seis, confirma y permite persistir el incidente con su inicio. Solo se agrega PCM nuevo. Una negativa, señal degenerada o más de seis segundos sin nueva positiva cierran el incidente confirmado. Las ventanas omitidas no reutilizan votos. Detener descarta candidatos sin confirmar. Fuera de un incidente confirmado no se crean archivos de audio ni evidencias para ventanas negativas.

## Acceso y control del micrófono

Configuración incluye un interruptor de monitoreo. Activar y desactivar requieren una autenticación nueva con biometría o credenciales del dispositivo. Cada activación consulta el permiso actual del micrófono; si falta, solicita autorización cuando el sistema lo permite o muestra un acceso a los ajustes del dispositivo. Si se cancela la autenticación o no se concede permiso, no se activa la captura. El estado desactivado se conserva entre aperturas de la aplicación. Este interruptor controla la captura de Serene, no revoca el permiso concedido por el sistema operativo.

Entrar desde otra pestaña a Grabaciones exige autenticación. La pantalla del repositorio no consulta registros antes de aceptarla. Cambiar de pestaña invalida ese acceso; regresar desde el reproductor conserva el acceso a la lista. Abrir cada audio conserva su autenticación adicional. Cancelar mantiene la lista bloqueada con una opción para reintentar.

Eliminar requiere confirmar el diálogo y una autenticación nueva antes de llamar al repositorio. Si se cancela, no se borra ningún registro. Abrir cada audio solicita otra autenticación antes de descifrarlo. PCM y WAV descifrados se procesan en memoria: el PCM se limpia al construir el WAV, el reproductor recibe un flujo de vistas del búfer y el WAV se limpia al cerrar la pantalla. No se crea un archivo temporal legible; solo los contenedores cifrados se conservan en el almacén. Esto no garantiza eliminar todas las copias internas del runtime o del sistema operativo.

No hay límite predeterminado de duración. Se conserva un incidente visible con puntos de recuperación cifrados cada quince segundos y un guardado final. Los puntos anteriores consumen almacenamiento adicional; la memoria y el disco siguen siendo finitos. Una interrupción puede perder el audio posterior al último guardado confirmado.
