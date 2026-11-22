-- =====================================================================
--  Clínica Vida Plena — Funciones y procedimientos almacenados
--  Ejecutar después de 01_schema.sql y 02_datos_ejemplo.sql
--
--  Reglas cubiertas:
--    RN-02  fn_edad / fn_es_menor (apoyo para el trigger de menores)
--    RN-06  bloques de 30 minutos en fn_horarios_disponibles
--    RN-08  sp_reservar_cita traduce el choque de horario a un mensaje claro
--    RN-09  fn_cita_en_horario (apoyo para el trigger de horario)
--    RN-10  sp_registrar_consulta (cita atendida + consulta + diagnóstico)
--    RN-13  fn_stock_disponible
--    RN-14  sp_dispensar_receta: lote que vence antes primero, todo o nada
--    RN-15  sp_generar_factura: congela el precio vigente en la línea
--    RN-16  fn_recalcular_factura: parte del seguro y parte del paciente
--    RN-17  sp_registrar_pago
-- =====================================================================


-- =====================================================================
--  1. Funciones de apoyo
-- =====================================================================

-- ---------------------------------------------------------------------
--  Zona horaria de la clínica.
--  cita.fecha_hora es TIMESTAMPTZ (un instante absoluto). Los horarios
--  de los médicos son horas "de pared" (TIME) en Hermosillo. Para saber
--  si una cita cae dentro del horario hay que convertir el instante a la
--  hora local de la clínica. Centralizarlo aquí evita escribir la zona
--  en diez lugares distintos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_zona_horaria()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 'America/Hermosillo'::text;
$$;

COMMENT ON FUNCTION clinica.fn_zona_horaria() IS
    'Zona horaria en la que se interpretan los horarios de la clínica.';


-- ---------------------------------------------------------------------
--  Edad cumplida en años a una fecha (por defecto, hoy).   RN-02 / S-01
--  age() devuelve un intervalo exacto (años, meses, días); nos quedamos
--  con los años cumplidos.
--  STABLE (no IMMUTABLE) porque depende de CURRENT_DATE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_edad(
    p_fecha_nacimiento DATE,
    p_a_la_fecha       DATE DEFAULT CURRENT_DATE
)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM age(p_a_la_fecha, p_fecha_nacimiento))::integer;
$$;


-- ---------------------------------------------------------------------
--  ¿La persona es menor de edad hoy?                         RN-02 / S-01
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_es_menor(p_id_persona INTEGER)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT clinica.fn_edad(p.fecha_nacimiento) < 18
    FROM clinica.persona p
    WHERE p.id_persona = p_id_persona;
$$;


-- ---------------------------------------------------------------------
--  ¿El bloque de 30 minutos que empieza en p_fecha_hora cabe completo
--  dentro de algún horario del médico en esa sede?            RN-09
--
--  Ejemplo: horario 08:00–14:00. Una cita a las 13:30 sí cabe
--  (termina 14:00); una a las 14:00 no.
--  Se usa (hora_fin - hora) >= 30 min en vez de hora + 30 min <= hora_fin
--  porque TIME + INTERVAL "da la vuelta" a medianoche (23:45 + 30 min =
--  00:15) y la comparación saldría mal.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_cita_en_horario(
    p_id_medico  INTEGER,
    p_id_sede    INTEGER,
    p_fecha_hora TIMESTAMPTZ
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_local TIMESTAMP := p_fecha_hora AT TIME ZONE clinica.fn_zona_horaria();
    v_dia   SMALLINT  := EXTRACT(ISODOW FROM v_local);   -- 1 = lunes … 7 = domingo
    v_hora  TIME      := v_local::time;
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM clinica.horario h
        WHERE h.id_medico  = p_id_medico
          AND h.id_sede    = p_id_sede
          AND h.dia_semana = v_dia
          AND v_hora >= h.hora_inicio
          AND (h.hora_fin - v_hora) >= INTERVAL '30 minutes'
    );
END;
$$;


-- ---------------------------------------------------------------------
--  ¿El médico puede atender en esa sede y hora?  = está en su horario
--  y no tiene otra cita activa (S-06: activa = no cancelada) a esa hora.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_medico_disponible(
    p_id_medico  INTEGER,
    p_id_sede    INTEGER,
    p_fecha_hora TIMESTAMPTZ
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT clinica.fn_cita_en_horario(p_id_medico, p_id_sede, p_fecha_hora)
       AND NOT EXISTS (
             SELECT 1
             FROM clinica.cita c
             WHERE c.id_medico  = p_id_medico
               AND c.fecha_hora = p_fecha_hora
               AND c.estado    <> 'cancelada');
$$;


-- ---------------------------------------------------------------------
--  Bloques libres de un médico en un día.                RN-06 / RN-09
--  Devuelve una fila por cada bloque de 30 minutos que:
--    - cae dentro de alguno de sus horarios de ese día de la semana,
--    - no tiene ya una cita activa,
--    - todavía no ha pasado.
--
--  Cómo funciona:
--    1. Se toman los horarios del médico para el día de la semana.
--    2. generate_series produce las horas de inicio cada 30 minutos,
--       desde hora_inicio hasta hora_fin - 30 min (el último bloque
--       debe terminar a más tardar en hora_fin).
--    3. "fecha + hora" da un TIMESTAMP local; AT TIME ZONE lo convierte
--       al instante TIMESTAMPTZ que se guarda en cita.fecha_hora.
--    4. NOT EXISTS descarta los bloques ocupados.
--
--  Uso:  SELECT * FROM clinica.fn_horarios_disponibles(19, CURRENT_DATE + 2);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_horarios_disponibles(
    p_id_medico INTEGER,
    p_fecha     DATE
)
RETURNS TABLE (fecha_hora TIMESTAMPTZ, id_sede INTEGER, sede VARCHAR)
LANGUAGE sql
STABLE
AS $$
    SELECT b.inicio, h.id_sede, s.nombre
    FROM clinica.horario h
    JOIN clinica.sede s ON s.id_sede = h.id_sede
    CROSS JOIN LATERAL (
        SELECT gs AT TIME ZONE clinica.fn_zona_horaria() AS inicio
        FROM generate_series(p_fecha + h.hora_inicio,
                             p_fecha + h.hora_fin - INTERVAL '30 minutes',
                             INTERVAL '30 minutes') AS gs
    ) b
    WHERE h.id_medico  = p_id_medico
      AND h.dia_semana = EXTRACT(ISODOW FROM p_fecha)
      AND b.inicio > now()
      AND NOT EXISTS (SELECT 1
                      FROM clinica.cita c
                      WHERE c.id_medico  = p_id_medico
                        AND c.fecha_hora = b.inicio
                        AND c.estado    <> 'cancelada')
    ORDER BY b.inicio;
$$;


-- ---------------------------------------------------------------------
--  Unidades disponibles de un medicamento en una sede.         RN-13
--  Solo cuenta lotes NO vencidos: un lote vencido puede seguir en la
--  tabla existencia (para inventario y merma), pero no se puede surtir.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_stock_disponible(
    p_id_medicamento INTEGER,
    p_id_sede        INTEGER
)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(e.stock), 0)::integer
    FROM clinica.existencia e
    JOIN clinica.lote l ON l.id_lote = e.id_lote
    WHERE l.id_medicamento    = p_id_medicamento
      AND e.id_sede           = p_id_sede
      AND l.fecha_vencimiento >= CURRENT_DATE;
$$;


-- ---------------------------------------------------------------------
--  Recalcula los totales de una factura a partir de sus líneas y pagos.
--                                                        RN-15/16/17
--    subtotal       = suma de los importes de las líneas
--    monto_seguro   = subtotal × cobertura / 100, redondeado a centavos
--    monto_paciente = subtotal − monto_seguro   (así el CHECK de cuadre
--                     seguro + paciente = subtotal se cumple siempre,
--                     sin problemas de redondeo)
--    saldo          = monto_paciente − lo ya pagado
--    estado         = 'pagada' cuando hay pagos y el saldo llega a 0
--
--  La usan los triggers de factura_linea y de pago (05_triggers.sql).
--  Es una sola fuente de verdad: nadie calcula totales "a mano".
--  Si el resultado violara una restricción (por ejemplo, se borra una
--  línea de una factura que ya se pagó y el saldo quedaría negativo),
--  el CHECK ck_factura_saldo rechaza el cambio completo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_recalcular_factura(p_id_factura INTEGER)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal NUMERIC(12,2);
    v_pagado   NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(importe), 0) INTO v_subtotal
    FROM clinica.factura_linea
    WHERE id_factura = p_id_factura;

    SELECT COALESCE(SUM(monto), 0) INTO v_pagado
    FROM clinica.pago
    WHERE id_factura = p_id_factura;

    UPDATE clinica.factura f
    SET subtotal       = v_subtotal,
        monto_seguro   = ROUND(v_subtotal * f.porcentaje_cobertura / 100, 2),
        monto_paciente = v_subtotal - ROUND(v_subtotal * f.porcentaje_cobertura / 100, 2),
        saldo          = v_subtotal - ROUND(v_subtotal * f.porcentaje_cobertura / 100, 2) - v_pagado,
        estado         = CASE
                           WHEN f.estado = 'anulada' THEN 'anulada'
                           WHEN v_pagado > 0
                            AND v_subtotal - ROUND(v_subtotal * f.porcentaje_cobertura / 100, 2) - v_pagado = 0
                             THEN 'pagada'
                           ELSE 'pendiente'
                         END
    WHERE f.id_factura = p_id_factura;
END;
$$;


-- =====================================================================
--  2. Procedimientos
-- =====================================================================

-- ---------------------------------------------------------------------
--  Reservar una cita.                                  RN-06/08/09
--
--  Quién garantiza qué:
--    - Bloque de 30 min (RN-06): CHECK ck_cita_bloque_30.
--    - Médico con esa especialidad (RN-09): FK compuesta a
--      medico_especialidad.
--    - Dentro del horario, no en el pasado (RN-09): trigger
--      trg_cita_validar_horario.
--    - Sin dos citas activas a la misma hora (RN-08): índices únicos
--      parciales uq_cita_medico_hora y uq_cita_paciente_hora.
--
--  ¿Por qué NO se pregunta primero "¿está libre?" y luego se inserta?
--  Porque entre la pregunta y el INSERT otra sesión puede ganar el
--  bloque (condición de carrera). El índice único es la única defensa
--  real: si dos sesiones insertan el mismo bloque a la vez, la segunda
--  ESPERA a que la primera termine; si la primera confirma, la segunda
--  recibe unique_violation; si la primera se revierte, la segunda pasa.
--  Aquí solo atrapamos ese error para devolver un mensaje entendible.
--
--  Uso:
--    CALL clinica.sp_reservar_cita(1, 19, 1, 1, '2026-12-07 10:00-07', NULL);
--  El último parámetro (INOUT) regresa el id de la cita creada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_reservar_cita(
    p_id_paciente     INTEGER,
    p_id_medico       INTEGER,
    p_id_especialidad INTEGER,
    p_id_sede         INTEGER,
    p_fecha_hora      TIMESTAMPTZ,
    INOUT p_id_cita   INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_restriccion TEXT;
BEGIN
    INSERT INTO clinica.cita (id_paciente, id_medico, id_especialidad, id_sede, fecha_hora)
    VALUES (p_id_paciente, p_id_medico, p_id_especialidad, p_id_sede, p_fecha_hora)
    RETURNING id_cita INTO p_id_cita;

EXCEPTION
    WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion = 'uq_cita_medico_hora' THEN
            RAISE EXCEPTION 'El médico % ya tiene una cita activa el %',
                  p_id_medico, p_fecha_hora
                  USING ERRCODE = 'unique_violation',
                        HINT    = 'Consulte clinica.fn_horarios_disponibles() para ver los bloques libres.';
        ELSIF v_restriccion = 'uq_cita_paciente_hora' THEN
            RAISE EXCEPTION 'El paciente % ya tiene otra cita activa el %',
                  p_id_paciente, p_fecha_hora
                  USING ERRCODE = 'unique_violation';
        ELSE
            RAISE;   -- cualquier otro choque se propaga tal cual
        END IF;
    WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        IF v_restriccion = 'fk_cita_medico_especialidad' THEN
            RAISE EXCEPTION 'El médico % no tiene la especialidad %',
                  p_id_medico, p_id_especialidad
                  USING ERRCODE = 'foreign_key_violation';
        ELSE
            RAISE;
        END IF;
END;
$$;


-- ---------------------------------------------------------------------
--  Cambiar el estado de una cita.                              RN-07
--  Las transiciones permitidas las valida el trigger
--  trg_cita_validar_transicion; aquí solo se bloquea la fila y se
--  avisa si la cita no existe.
--
--  Uso:  CALL clinica.sp_cambiar_estado_cita(21, 'cancelada');
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_cambiar_estado_cita(
    p_id_cita INTEGER,
    p_estado  VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE clinica.cita
    SET estado = p_estado
    WHERE id_cita = p_id_cita;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la cita %', p_id_cita
              USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
--  Registrar la consulta de una cita.                     RN-10 / RN-11
--
--  Hace tres cosas como una sola unidad:
--    1. Marca la cita como 'atendida' (con su validación de transición).
--    2. Inserta la consulta (el trigger exige que la cita esté atendida).
--    3. Inserta el diagnóstico principal.
--  Si cualquiera falla, no queda nada a medias: ni una cita "atendida"
--  sin consulta, ni una consulta sin diagnóstico principal.
--
--  SELECT ... FOR UPDATE bloquea la cita mientras dura la transacción:
--  si dos médicos (o dos pestañas) intentan registrar la misma consulta,
--  el segundo espera y luego ve que la cita ya está atendida.
--
--  Uso (notación con nombre; los parámetros opcionales se omiten):
--    CALL clinica.sp_registrar_consulta(
--        p_id_cita        => 21,
--        p_motivo         => 'Dolor de cabeza',
--        p_id_diagnostico => 15,
--        p_temperatura_c  => 36.8);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_registrar_consulta(
    p_id_cita             INTEGER,
    p_motivo              VARCHAR,
    p_id_diagnostico      INTEGER,
    p_notas_clinicas      TEXT         DEFAULT NULL,
    p_presion_sistolica   SMALLINT     DEFAULT NULL,
    p_presion_diastolica  SMALLINT     DEFAULT NULL,
    p_frecuencia_cardiaca SMALLINT     DEFAULT NULL,
    p_temperatura_c       NUMERIC      DEFAULT NULL,
    p_peso_kg             NUMERIC      DEFAULT NULL,
    p_talla_cm            NUMERIC      DEFAULT NULL,
    INOUT p_id_consulta   INTEGER      DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR;
BEGIN
    SELECT estado INTO v_estado
    FROM clinica.cita
    WHERE id_cita = p_id_cita
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la cita %', p_id_cita USING ERRCODE = 'no_data_found';
    END IF;

    IF v_estado <> 'atendida' THEN
        UPDATE clinica.cita SET estado = 'atendida' WHERE id_cita = p_id_cita;
    END IF;

    INSERT INTO clinica.consulta
        (id_cita, motivo, presion_sistolica, presion_diastolica, frecuencia_cardiaca,
         temperatura_c, peso_kg, talla_cm, notas_clinicas)
    VALUES
        (p_id_cita, p_motivo, p_presion_sistolica, p_presion_diastolica, p_frecuencia_cardiaca,
         p_temperatura_c, p_peso_kg, p_talla_cm, p_notas_clinicas)
    RETURNING id_consulta INTO p_id_consulta;

    INSERT INTO clinica.consulta_diagnostico (id_consulta, id_diagnostico, es_principal)
    VALUES (p_id_consulta, p_id_diagnostico, true);
END;
$$;


-- ---------------------------------------------------------------------
--  Dispensar una receta completa.                       RN-13 / RN-14
--
--  Regla: para cada medicamento se toma primero el lote que vence antes
--  (FEFO: First Expired, First Out), y si falta stock de CUALQUIER
--  línea no se entrega nada (todo o nada).
--
--  Paso a paso:
--    1. Bloquea la receta (FOR UPDATE) y verifica que esté 'pendiente'.
--       Dos farmacéuticos no pueden surtir la misma receta a la vez:
--       el segundo espera y luego la encuentra 'dispensada'.
--    2. La sede es la del farmacéutico (S-04: trabajan en sede fija).
--    3. Crea el encabezado en dispensacion.
--    4. Por cada línea (en orden de id_medicamento, ver "interbloqueos"):
--         - bloquea las existencias de los lotes vigentes de ese
--           medicamento en la sede, ordenadas por fecha de vencimiento;
--         - va tomando de cada lote lo que haga falta;
--         - cada INSERT en dispensacion_detalle descuenta el stock
--           (lo hace el trigger trg_dispdet_descontar_stock).
--       Si al terminar los lotes todavía falta cantidad → RAISE
--       EXCEPTION. El error deshace TODO lo hecho en la llamada:
--       encabezado, detalles de líneas anteriores y descuentos de stock.
--    5. Marca la receta como 'dispensada'.
--
--  Concurrencia:
--    FOR UPDATE OF e bloquea solo las filas de existencia elegidas.
--    Si otra sesión está surtiendo el mismo lote, esta espera; cuando la
--    otra confirma, PostgreSQL vuelve a evaluar la fila con su stock
--    nuevo (en READ COMMITTED), así que nunca se surte stock "fantasma".
--    Aun así, el CHECK stock >= 0 es la última línea de defensa.
--
--  Interbloqueos (deadlocks):
--    Si la sesión A bloquea Paracetamol y luego pide Amoxicilina, y la
--    sesión B hace lo contrario, cada una espera a la otra para siempre.
--    Recorrer siempre los medicamentos en el mismo orden (id_medicamento)
--    y los lotes en el mismo orden (vencimiento, id_lote) evita el ciclo.
--
--  Uso:  CALL clinica.sp_dispensar_receta(14, 28, NULL);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_dispensar_receta(
    p_id_receta             INTEGER,
    p_id_farmaceutico       INTEGER,
    INOUT p_id_dispensacion INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_receta VARCHAR;
    v_id_sede       INTEGER;
    v_linea         RECORD;
    v_lote          RECORD;
    v_pendiente     INTEGER;
    v_tomar         INTEGER;
BEGIN
    -- 1. Receta bloqueada y pendiente
    SELECT estado INTO v_estado_receta
    FROM clinica.receta
    WHERE id_receta = p_id_receta
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la receta %', p_id_receta USING ERRCODE = 'no_data_found';
    END IF;
    IF v_estado_receta <> 'pendiente' THEN
        RAISE EXCEPTION 'La receta % está %; solo se dispensan recetas pendientes',
              p_id_receta, v_estado_receta;
    END IF;

    -- 2. Sede del farmacéutico (y que siga activo)
    SELECT f.id_sede INTO v_id_sede
    FROM clinica.farmaceutico f
    JOIN clinica.empleado e ON e.id_persona = f.id_persona
    WHERE f.id_persona = p_id_farmaceutico
      AND e.activo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La persona % no es un farmacéutico activo', p_id_farmaceutico;
    END IF;

    -- 3. Encabezado
    INSERT INTO clinica.dispensacion (id_receta, id_farmaceutico, id_sede)
    VALUES (p_id_receta, p_id_farmaceutico, v_id_sede)
    RETURNING id_dispensacion INTO p_id_dispensacion;

    -- 4. Líneas, siempre en el mismo orden
    FOR v_linea IN
        SELECT rl.id_medicamento, rl.cantidad, m.nombre
        FROM clinica.receta_linea rl
        JOIN clinica.medicamento m ON m.id_medicamento = rl.id_medicamento
        WHERE rl.id_receta = p_id_receta
        ORDER BY rl.id_medicamento
    LOOP
        v_pendiente := v_linea.cantidad;

        FOR v_lote IN
            SELECT e.id_lote, e.stock
            FROM clinica.existencia e
            JOIN clinica.lote l ON l.id_lote = e.id_lote
            WHERE l.id_medicamento     = v_linea.id_medicamento
              AND e.id_sede            = v_id_sede
              AND l.fecha_vencimiento >= CURRENT_DATE
              AND e.stock > 0
            ORDER BY l.fecha_vencimiento, l.id_lote
            FOR UPDATE OF e
        LOOP
            v_tomar := LEAST(v_pendiente, v_lote.stock);

            INSERT INTO clinica.dispensacion_detalle (id_dispensacion, id_lote, cantidad)
            VALUES (p_id_dispensacion, v_lote.id_lote, v_tomar);

            v_pendiente := v_pendiente - v_tomar;
            EXIT WHEN v_pendiente = 0;
        END LOOP;

        IF v_pendiente > 0 THEN
            RAISE EXCEPTION 'Stock insuficiente de % (id %) en la sede %: faltan % unidades',
                  v_linea.nombre, v_linea.id_medicamento, v_id_sede, v_pendiente
                  USING ERRCODE = 'check_violation',
                        HINT    = 'No se dispensó ninguna línea de la receta.';
        END IF;
    END LOOP;

    -- 5. Receta surtida
    UPDATE clinica.receta SET estado = 'dispensada' WHERE id_receta = p_id_receta;
END;
$$;


-- ---------------------------------------------------------------------
--  Generar la factura de una consulta.                   RN-15 / RN-16
--
--    1. Encabezado: el trigger trg_factura_copiar_cobertura copia la
--       aseguradora y el porcentaje de cobertura VIGENTES del paciente.
--       Si después cambia su póliza, esta factura no cambia.
--    2. Línea 1: la consulta. precio_unitario va NULL a propósito: el
--       trigger trg_factura_linea_validar lo llena con el precio actual
--       de la especialidad (RN-15, S-07).
--    3. Una línea por cada medicamento dispensado de la receta de esa
--       consulta (si la hubo), al precio de venta actual.
--    4. Los totales los calcula el trigger después de cada línea
--       (fn_recalcular_factura), no este procedimiento.
--
--  S-08: una consulta genera como máximo una factura (UNIQUE en
--  factura.id_consulta). Si ya existe se avisa con un mensaje claro.
--  Nota: se factura lo dispensado al momento de llamar; conviene
--  dispensar primero y facturar después.
--
--  Uso:  CALL clinica.sp_generar_factura(19, NULL);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_generar_factura(
    p_id_consulta      INTEGER,
    INOUT p_id_factura INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clinica.consulta WHERE id_consulta = p_id_consulta) THEN
        RAISE EXCEPTION 'No existe la consulta %', p_id_consulta USING ERRCODE = 'no_data_found';
    END IF;

    SELECT id_factura INTO p_id_factura
    FROM clinica.factura
    WHERE id_consulta = p_id_consulta;

    IF FOUND THEN
        RAISE EXCEPTION 'La consulta % ya tiene la factura %', p_id_consulta, p_id_factura
              USING ERRCODE = 'unique_violation';
    END IF;

    INSERT INTO clinica.factura (id_consulta)
    VALUES (p_id_consulta)
    RETURNING id_factura INTO p_id_factura;

    INSERT INTO clinica.factura_linea (id_factura, numero_linea, concepto, cantidad, precio_unitario)
    VALUES (p_id_factura, 1, 'consulta', 1, NULL);

    INSERT INTO clinica.factura_linea
        (id_factura, numero_linea, concepto, id_medicamento, cantidad, precio_unitario)
    SELECT p_id_factura,
           1 + ROW_NUMBER() OVER (ORDER BY l.id_medicamento),
           'medicamento',
           l.id_medicamento,
           SUM(dd.cantidad),
           NULL
    FROM clinica.receta r
    JOIN clinica.dispensacion         d  ON d.id_receta = r.id_receta
    JOIN clinica.dispensacion_detalle dd ON dd.id_dispensacion = d.id_dispensacion
    JOIN clinica.lote                 l  ON l.id_lote = dd.id_lote
    WHERE r.id_consulta = p_id_consulta
    GROUP BY l.id_medicamento;
END;
$$;


-- ---------------------------------------------------------------------
--  Registrar un pago.                                          RN-17
--
--  Toda la lógica crítica está en los triggers de pago:
--    - BEFORE INSERT bloquea la factura (FOR UPDATE), comprueba que esté
--      pendiente y que el monto no supere el saldo.
--    - AFTER INSERT recalcula saldo y estado (pasa a 'pagada' sola).
--  Así, un pago insertado a mano está igual de protegido. El
--  procedimiento solo agrega una interfaz cómoda y un aviso del saldo.
--
--  Uso:  CALL clinica.sp_registrar_pago(18, 50.00, 'efectivo', NULL, 25, NULL);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE clinica.sp_registrar_pago(
    p_id_factura       INTEGER,
    p_monto            NUMERIC,
    p_metodo           VARCHAR,
    p_referencia       VARCHAR DEFAULT NULL,
    p_id_recepcionista INTEGER DEFAULT NULL,
    INOUT p_id_pago    INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_saldo  NUMERIC(12,2);
    v_estado VARCHAR;
BEGIN
    INSERT INTO clinica.pago (id_factura, monto, metodo, referencia, id_recepcionista)
    VALUES (p_id_factura, p_monto, p_metodo, p_referencia, p_id_recepcionista)
    RETURNING id_pago INTO p_id_pago;

    SELECT saldo, estado INTO v_saldo, v_estado
    FROM clinica.factura
    WHERE id_factura = p_id_factura;

    RAISE NOTICE 'Pago % registrado. Factura %: saldo %, estado %',
                 p_id_pago, p_id_factura, v_saldo, v_estado;
END;
$$;
