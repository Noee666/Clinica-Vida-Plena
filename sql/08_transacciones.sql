-- =====================================================================
--  Clínica Vida Plena — Transacciones y concurrencia
--  Autor: Torres Gonzalez Gael Andres
--  Ejecutar después de 05_triggers.sql (normalmente desde ejecutar_todo.sql).
--
--  Cinco demostraciones:
--    1. Reservar cita ......... dos sesiones piden el mismo bloque (RN-08)
--    2. Dispensar receta ...... todo o nada y lote que vence antes (RN-14)
--    3. Registrar pago ........ SAVEPOINT y fallo a mitad del proceso (RN-17)
--    4. Bloqueos .............. SELECT ... FOR UPDATE, NOWAIT, deadlock
--    5. Aislamiento ........... READ COMMITTED contra REPEATABLE READ
--
--  Cómo está armado este script:
--    * Corre en UNA sola sesión de psql y deja la base EXACTAMENTE como
--      estaba: cada demostración abre BEGIN y termina en ROLLBACK.
--      Única excepción: las secuencias IDENTITY. nextval() nunca se
--      revierte (para no bloquear a otras sesiones), así que tras correr
--      el script los siguientes id saltan algunos números. Es normal:
--      un id identifica, no cuenta.
--    * ejecutar_todo.sql usa ON_ERROR_STOP, así que un error "suelto"
--      detendría todo. Los errores que provocamos a propósito se ejecutan
--      dentro de bloques DO con EXCEPTION, que atrapan el error y lo
--      muestran como NOTICE. Un bloque EXCEPTION funciona como un
--      SAVEPOINT implícito: lo hecho dentro del bloque se deshace, pero
--      la transacción de afuera sigue viva.
--    * Las partes que necesitan DOS sesiones al mismo tiempo están como
--      comentarios con los pasos de "Sesión A" y "Sesión B". Abre dos
--      ventanas de psql (o dos consolas de DataGrip) conectadas a
--      `clinica` y ejecútalos en el orden indicado. La salida esperada
--      va anotada en cada paso.
--    * Dentro de PL/pgSQL (un DO o un procedimiento), un parámetro INOUT
--      debe recibir una VARIABLE, no NULL: ahí se escribe el resultado.
--      Desde psql sí se pasa NULL y el resultado se muestra como fila.
--    * psql no sustituye variables (:var) dentro de los bloques $$ ... $$.
--      Para pasar un valor a un DO se guarda con set_config('demo.x', ...)
--      y se lee con current_setting('demo.x').
-- =====================================================================

SET client_min_messages = notice;


-- =====================================================================
--  DEMOSTRACIÓN 1 — Reservar cita                                RN-08
-- =====================================================================
--  Problema: dos recepcionistas reservan el mismo bloque del mismo
--  médico al mismo tiempo. Si el sistema hiciera "¿está libre? → sí →
--  INSERT", las dos verían el bloque libre y las dos lo reservarían.
--
--  Solución: no se pregunta, se inserta. El índice único parcial
--  uq_cita_medico_hora (id_medico, fecha_hora) WHERE estado <> 'cancelada'
--  decide. Con dos INSERT simultáneos, PostgreSQL hace esperar al
--  segundo hasta que el primero confirme o revierta:
--    - si el primero hace COMMIT  → el segundo falla (unique_violation);
--    - si el primero hace ROLLBACK → el segundo sí obtiene el bloque.
-- =====================================================================
\echo
\echo '=== Demostración 1: reservar cita ==='

-- Primer bloque libre del Dr. Salazar (id 19) en los próximos 14 días
SELECT d.fecha_hora AS slot, d.id_sede AS slot_sede
FROM generate_series(CURRENT_DATE + 1, CURRENT_DATE + 14, INTERVAL '1 day') AS g(dia)
CROSS JOIN LATERAL clinica.fn_horarios_disponibles(19, g.dia::date) AS d
ORDER BY d.fecha_hora
LIMIT 1
\gset

\echo 'Bloque libre elegido:' :'slot' 'sede' :slot_sede
SELECT set_config('demo.slot', :'slot', false), set_config('demo.sede', :'slot_sede', false);

BEGIN;

-- La paciente 4 reserva el bloque
CALL clinica.sp_reservar_cita(4, 19, 1, :slot_sede, :'slot', NULL);

-- El paciente 5 intenta el mismo bloque con el mismo médico: se rechaza
DO $$
DECLARE
    v_id INTEGER;   -- recibe el parámetro INOUT del procedimiento
BEGIN
    CALL clinica.sp_reservar_cita(5, 19, 1,
                                  current_setting('demo.sede')::int,
                                  current_setting('demo.slot')::timestamptz, v_id);
    RAISE NOTICE 'ERROR DE LA DEMO: la segunda reserva no debió pasar';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'Segunda reserva rechazada (esperado): %', SQLERRM;
END;
$$;

-- Solo hay una cita activa en ese bloque
SELECT id_cita, id_paciente, fecha_hora, estado
FROM clinica.cita
WHERE id_medico = 19 AND fecha_hora = :'slot'::timestamptz;

ROLLBACK;   -- la base queda como estaba

/* ---------------------------------------------------------------------
   Versión con DOS sesiones (para las capturas de evidencia).
   Sustituye <bloque> y <sede> por un bloque libre, por ejemplo:
     SELECT * FROM clinica.fn_horarios_disponibles(19, CURRENT_DATE + 2);

   Sesión A:  BEGIN;
   Sesión A:  CALL clinica.sp_reservar_cita(4, 19, 1, <sede>, '<bloque>', NULL);
              -- p_id_cita = N   (todavía sin confirmar)
   Sesión B:  CALL clinica.sp_reservar_cita(5, 19, 1, <sede>, '<bloque>', NULL);
              -- ... se queda ESPERANDO: el índice único ya tiene una
              --     entrada sin confirmar de la sesión A para ese bloque.
   Sesión A:  COMMIT;
   Sesión B:  -- se libera al instante:
              -- ERROR:  El médico 19 ya tiene una cita activa el <bloque>

   Repite cambiando el COMMIT de A por ROLLBACK: B se libera y obtiene
   el bloque. Ninguna de las dos sesiones vio una cita "a medias".

   Para limpiar: CALL clinica.sp_cambiar_estado_cita(N, 'cancelada');
   (cancelar libera el bloque porque el índice excluye las canceladas)
   --------------------------------------------------------------------- */


-- =====================================================================
--  DEMOSTRACIÓN 2 — Dispensar receta: todo o nada                RN-14
-- =====================================================================
--  La receta 7 pide 1 Paracetamol 500 mg (id 1) y 1 Loratadina (id 15).
--
--  2a. En la sede Sur (farmacéutica 30) hay Paracetamol, pero NO hay
--      Loratadina. El procedimiento descuenta primero el Paracetamol
--      (orden por id_medicamento) y al llegar a la Loratadina lanza un
--      error. Resultado: ni el Paracetamol queda descontado, ni existe la
--      dispensación, ni cambia el estado de la receta.
--
--  2b. En la sede Centro (farmacéutico 28) sí hay de todo. Para ver la
--      regla "el lote que vence antes sale primero", se sube la cantidad
--      de Paracetamol a 45: el lote PAR-2405A (vence 2027-06, 40 piezas)
--      se agota y las 5 restantes salen del PAR-2511B (vence 2028-01).
-- =====================================================================
\echo
\echo '=== Demostración 2: dispensar receta (todo o nada) ==='

BEGIN;

\echo '--- 2a. Stock en sede Sur ANTES del intento'
SELECT m.nombre, clinica.fn_stock_disponible(m.id_medicamento, 3) AS stock_sede_sur
FROM clinica.medicamento m
WHERE m.id_medicamento IN (1, 15)
ORDER BY m.id_medicamento;

DO $$
DECLARE
    v_id INTEGER;   -- recibe el parámetro INOUT del procedimiento
BEGIN
    CALL clinica.sp_dispensar_receta(7, 30, v_id);
    RAISE NOTICE 'ERROR DE LA DEMO: la dispensación no debió pasar';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Dispensación rechazada (esperado): %', SQLERRM;
END;
$$;

\echo '--- 2a. Stock en sede Sur DESPUÉS del intento (debe ser el mismo)'
SELECT m.nombre, clinica.fn_stock_disponible(m.id_medicamento, 3) AS stock_sede_sur
FROM clinica.medicamento m
WHERE m.id_medicamento IN (1, 15)
ORDER BY m.id_medicamento;

SELECT r.id_receta, r.estado,
       (SELECT count(*) FROM clinica.dispensacion d WHERE d.id_receta = r.id_receta) AS dispensaciones
FROM clinica.receta r
WHERE r.id_receta = 7;

\echo '--- 2b. Dispensación correcta en sede Centro, repartida entre lotes'
UPDATE clinica.receta_linea SET cantidad = 45
WHERE id_receta = 7 AND id_medicamento = 1;

CALL clinica.sp_dispensar_receta(7, 28, NULL);

SELECT m.nombre, l.numero_lote, l.fecha_vencimiento, dd.cantidad AS surtido, e.stock AS stock_restante
FROM clinica.dispensacion d
JOIN clinica.dispensacion_detalle dd ON dd.id_dispensacion = d.id_dispensacion
JOIN clinica.lote                 l  ON l.id_lote = dd.id_lote
JOIN clinica.medicamento          m  ON m.id_medicamento = l.id_medicamento
JOIN clinica.existencia           e  ON e.id_lote = dd.id_lote AND e.id_sede = d.id_sede
WHERE d.id_receta = 7
ORDER BY m.nombre, l.fecha_vencimiento;

ROLLBACK;


-- =====================================================================
--  DEMOSTRACIÓN 3 — Registrar pago                               RN-17
-- =====================================================================
--  Factura 18: consulta de Pediatría ($650), cobertura 60 %.
--  El seguro cubre $390 y la paciente debe $260.
--
--  3a. Abono de $100 → saldo $160.
--  3b. SAVEPOINT: se liquida el resto, la factura pasa sola a 'pagada';
--      luego ROLLBACK TO SAVEPOINT regresa a saldo $160 'pendiente' sin
--      perder el abono de 3a. Un savepoint es un "punto de guardado"
--      dentro de la transacción.
--  3c. Fallo a mitad del proceso: se inserta el pago y, antes de
--      terminar, "se cae la terminal" (se simula con RAISE EXCEPTION).
--      No queda ni el pago ni el cambio de saldo: o se hace todo o nada.
--  3d. Un pago mayor al saldo se rechaza.
-- =====================================================================
\echo
\echo '=== Demostración 3: registrar pago ==='

BEGIN;

SELECT id_factura, subtotal, porcentaje_cobertura, monto_seguro, monto_paciente, saldo, estado
FROM clinica.factura WHERE id_factura = 18;

\echo '--- 3a. Abono de $100'
CALL clinica.sp_registrar_pago(18, 100.00, 'efectivo', NULL, 25, NULL);

\echo '--- 3b. SAVEPOINT y liquidación'
SAVEPOINT antes_de_liquidar;

CALL clinica.sp_registrar_pago(18, 160.00, 'tarjeta', 'TJ-DEMO-01', 25, NULL);
SELECT id_factura, saldo, estado FROM clinica.factura WHERE id_factura = 18;   -- 0.00 | pagada

ROLLBACK TO SAVEPOINT antes_de_liquidar;
SELECT id_factura, saldo, estado FROM clinica.factura WHERE id_factura = 18;   -- 160.00 | pendiente

\echo '--- 3c. Fallo a mitad del proceso'
DO $$
DECLARE
    v_id INTEGER;   -- recibe el parámetro INOUT del procedimiento
BEGIN
    CALL clinica.sp_registrar_pago(18, 160.00, 'tarjeta', 'TJ-DEMO-02', 25, v_id);
    RAISE EXCEPTION 'Simulación: se perdió la conexión con la terminal bancaria';
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Proceso interrumpido: %', SQLERRM;
END;
$$;

SELECT f.id_factura, f.saldo, f.estado,
       (SELECT count(*) FROM clinica.pago p WHERE p.id_factura = f.id_factura) AS pagos
FROM clinica.factura f WHERE f.id_factura = 18;   -- 160.00 | pendiente | 1

\echo '--- 3d. Pago mayor al saldo'
DO $$
DECLARE
    v_id INTEGER;   -- recibe el parámetro INOUT del procedimiento
BEGIN
    CALL clinica.sp_registrar_pago(18, 1000.00, 'efectivo', NULL, 25, v_id);
    RAISE NOTICE 'ERROR DE LA DEMO: el pago no debió pasar';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Pago rechazado (esperado): %', SQLERRM;
END;
$$;

ROLLBACK;

/* ---------------------------------------------------------------------
   Versión con DOS sesiones: dos cajas cobran la misma factura.
   (Los pagos no se pueden borrar, por eso ambas sesiones terminan en
   ROLLBACK; para que queden guardados cambia ROLLBACK por COMMIT.)

   Sesión A:  BEGIN;
   Sesión A:  CALL clinica.sp_registrar_pago(18, 260, 'efectivo', NULL, 25, NULL);
              -- NOTICE: ... saldo 0.00, estado pagada
   Sesión B:  BEGIN;
   Sesión B:  CALL clinica.sp_registrar_pago(18, 260, 'tarjeta', 'TJ-1', 26, NULL);
              -- ... ESPERA: el trigger trg_pago_validar hace
              --     SELECT ... FOR UPDATE sobre la factura 18, que A tiene bloqueada.
   Sesión A:  COMMIT;
   Sesión B:  -- ERROR:  La factura 18 está pagada; no admite pagos
              -- B leyó la versión YA confirmada de la factura, no la vieja.
   Sesión B:  ROLLBACK;
   --------------------------------------------------------------------- */


-- =====================================================================
--  DEMOSTRACIÓN 4 — Bloqueos con SELECT ... FOR UPDATE
-- =====================================================================
--  SELECT ... FOR UPDATE lee filas y las bloquea hasta el final de la
--  transacción. Otra sesión puede LEERLAS normalmente (un SELECT común
--  no espera), pero si intenta modificarlas o bloquearlas, espera.
--
--  En una sola sesión no se puede "ver" a alguien esperando, pero sí se
--  puede ver qué bloqueos tiene la transacción en pg_locks.
--  Nota: los bloqueos de FILA no aparecen uno por uno en pg_locks
--  (PostgreSQL los marca en la propia fila); lo que se ve es el bloqueo
--  de TABLA RowShareLock que los acompaña. Una fila sí aparece en
--  pg_locks (locktype = 'tuple' / 'transactionid') cuando otra sesión
--  está esperando por ella.
-- =====================================================================
\echo
\echo '=== Demostración 4: bloqueos ==='

BEGIN;

SELECT e.id_lote, l.numero_lote, e.id_sede, e.stock
FROM clinica.existencia e
JOIN clinica.lote l ON l.id_lote = e.id_lote
WHERE e.id_lote = 10 AND e.id_sede = 1
FOR UPDATE OF e;

SELECT l.locktype, c.relname AS objeto, l.mode, l.granted
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
WHERE l.pid = pg_backend_pid()
  AND (c.relname IS NULL OR c.relname NOT LIKE 'pg\_%')
ORDER BY l.locktype, objeto;

ROLLBACK;   -- al terminar la transacción se liberan todos los bloqueos

/* ---------------------------------------------------------------------
   4a. Espera y re-evaluación (dos sesiones).
       La receta 14 pide 1 Salbutamol; en la sede Centro solo está el
       lote SAL-2410 (id 10) con 12 piezas.

   Sesión A:  BEGIN;
   Sesión A:  SELECT stock FROM clinica.existencia
              WHERE id_lote = 10 AND id_sede = 1 FOR UPDATE;      -- 12
   Sesión B:  BEGIN;
   Sesión B:  CALL clinica.sp_dispensar_receta(14, 28, NULL);
              -- ... ESPERA en el SELECT ... FOR UPDATE del procedimiento
   Sesión C (opcional, para ver quién bloquea a quién):
              SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, wait_event_type, state, query
              FROM pg_stat_activity
              WHERE datname = 'clinica' AND pid <> pg_backend_pid();
   Sesión A:  UPDATE clinica.existencia SET stock = 0
              WHERE id_lote = 10 AND id_sede = 1;                  -- "se acabó"
   Sesión A:  COMMIT;
   Sesión B:  -- ERROR:  Stock insuficiente de Salbutamol (id 8) en la sede 1: faltan 1 unidades
              -- Al liberarse, PostgreSQL volvió a evaluar la fila con su
              -- valor NUEVO (stock = 0) y la descartó por "stock > 0".
              -- B nunca surtió algo que ya no existía.
   Sesión B:  ROLLBACK;
   Limpieza:  UPDATE clinica.existencia SET stock = 12 WHERE id_lote = 10 AND id_sede = 1;

   4b. No esperar para siempre.
   Sesión A:  BEGIN;
              SELECT * FROM clinica.existencia WHERE id_lote = 10 AND id_sede = 1 FOR UPDATE;
   Sesión B:  SELECT * FROM clinica.existencia WHERE id_lote = 10 AND id_sede = 1 FOR UPDATE NOWAIT;
              -- ERROR:  could not obtain lock on row in relation "existencia"   (inmediato)
   Sesión B:  SET lock_timeout = '3s';
              SELECT * FROM clinica.existencia WHERE id_lote = 10 AND id_sede = 1 FOR UPDATE;
              -- ERROR:  canceling statement due to lock timeout             (a los 3 s)
   Sesión B:  RESET lock_timeout;
   Sesión A:  ROLLBACK;

   4c. Interbloqueo (deadlock): cada sesión bloquea un lote y luego pide
       el de la otra.
   Sesión A:  BEGIN;
              UPDATE clinica.existencia SET stock = stock WHERE id_lote = 1 AND id_sede = 1;
   Sesión B:  BEGIN;
              UPDATE clinica.existencia SET stock = stock WHERE id_lote = 2 AND id_sede = 1;
   Sesión A:  UPDATE clinica.existencia SET stock = stock WHERE id_lote = 2 AND id_sede = 1;
              -- ... espera a B
   Sesión B:  UPDATE clinica.existencia SET stock = stock WHERE id_lote = 1 AND id_sede = 1;
              -- tras ~1 s (deadlock_timeout) PostgreSQL detecta el ciclo y
              -- aborta UNA de las dos:
              -- ERROR:  deadlock detected
              -- DETAIL: Process ... waits for ShareLock on transaction ...; blocked by process ...
   Ambas:     ROLLBACK;
   Por eso sp_dispensar_receta recorre medicamentos y lotes siempre en
   el mismo orden: si todos piden los bloqueos en el mismo orden, el
   ciclo no puede formarse.
   --------------------------------------------------------------------- */


-- =====================================================================
--  DEMOSTRACIÓN 5 — Niveles de aislamiento
-- =====================================================================
--  READ COMMITTED (el predeterminado de PostgreSQL): cada SENTENCIA ve
--  los datos confirmados en el momento en que empieza. Dentro de una
--  misma transacción, dos SELECT iguales pueden dar resultados distintos
--  si otra sesión confirmó algo en medio ("lectura no repetible").
--
--  REPEATABLE READ: la TRANSACCIÓN entera ve una foto (snapshot) tomada
--  en su primera consulta. Las lecturas no cambian. Si intenta modificar
--  una fila que otra sesión cambió y confirmó después de la foto, falla
--  con "could not serialize access due to concurrent update" y la
--  aplicación debe reintentar la transacción completa.
--
--  (SERIALIZABLE va un paso más allá: además detecta combinaciones de
--  lecturas y escrituras que no podrían ocurrir en ningún orden en serie.)
-- =====================================================================
\echo
\echo '=== Demostración 5: niveles de aislamiento ==='

SHOW default_transaction_isolation;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT current_setting('transaction_isolation') AS nivel_de_esta_transaccion;
-- Dentro de esta transacción, now() también queda fijo: es la hora de
-- inicio de la transacción, no la del reloj (eso sería clock_timestamp()).
SELECT now() = transaction_timestamp() AS now_es_inicio_de_transaccion;
ROLLBACK;

/* ---------------------------------------------------------------------
   5a. READ COMMITTED: lectura no repetible.
       Se usa el stock del lote PAR-2511B (id 2) en la sede Centro: 100.

   Sesión A:  BEGIN;   -- READ COMMITTED por defecto
   Sesión A:  SELECT stock FROM clinica.existencia WHERE id_lote = 2 AND id_sede = 1;   -- 100
   Sesión B:  UPDATE clinica.existencia SET stock = stock - 10
              WHERE id_lote = 2 AND id_sede = 1;                                     -- autocommit
   Sesión A:  SELECT stock FROM clinica.existencia WHERE id_lote = 2 AND id_sede = 1;   -- 90  ← cambió
   Sesión A:  COMMIT;

   5b. REPEATABLE READ: la foto no cambia.
   Sesión A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
   Sesión A:  SELECT stock FROM clinica.existencia WHERE id_lote = 2 AND id_sede = 1;   -- 90
   Sesión B:  UPDATE clinica.existencia SET stock = stock - 10
              WHERE id_lote = 2 AND id_sede = 1;                                     -- autocommit
   Sesión A:  SELECT stock FROM clinica.existencia WHERE id_lote = 2 AND id_sede = 1;   -- 90  ← igual
   Sesión A:  UPDATE clinica.existencia SET stock = stock - 1
              WHERE id_lote = 2 AND id_sede = 1;
              -- ERROR:  could not serialize access due to concurrent update
              -- A iba a restar sobre un 90 que ya no es real (hay 80).
              -- En READ COMMITTED, ese mismo UPDATE habría esperado/leído
              -- el valor nuevo y restado sobre 80.
   Sesión A:  ROLLBACK;

   Limpieza:  UPDATE clinica.existencia SET stock = 100 WHERE id_lote = 2 AND id_sede = 1;

   Conclusión para el proyecto: las operaciones de la clínica usan
   READ COMMITTED + bloqueos explícitos (FOR UPDATE en recetas, facturas
   y existencias) + restricciones (índices únicos, CHECK stock >= 0,
   CHECK saldo >= 0). Es la combinación más simple que evita citas
   dobles, stock negativo y cobros dobles sin obligar a reintentar.
   REPEATABLE READ es útil para REPORTES que leen muchas tablas y deben
   ser coherentes entre sí (por ejemplo, un corte de caja).
   --------------------------------------------------------------------- */

RESET client_min_messages;

\echo
\echo '=== Fin de las demostraciones: la base quedó sin cambios ==='
