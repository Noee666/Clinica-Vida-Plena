-- =====================================================================
--  Clínica Vida Plena — Triggers
--  Autor: Cornejo Silva Martin Noe
--  Ejecutar después de 04_funciones_procedimientos.sql.
--
--  Reglas cubiertas:
--    RN-02  menor de edad con responsable adulto
--    RN-07  transiciones válidas del estado de una cita
--    RN-09  cita dentro del horario del médico, nunca en el pasado
--    RN-10  la consulta solo existe para una cita atendida
--    RN-11  exactamente un diagnóstico principal (trigger DIFERIDO)
--    RN-12  una receta surtida o anulada ya no se modifica
--    RN-13  dispensar descuenta stock; nunca de un lote vencido
--    RN-15  precio vigente copiado a la línea de factura
--    RN-16  cobertura del paciente copiada a la factura
--    RN-17  pagos que no superan el saldo; factura pagada automáticamente
--    RN-18  auditoría de cambios en la tabla clinica.auditoria
--
--
--  Conceptos que conviene tener presentes al leer este archivo:
--    * BEFORE vs AFTER. Un trigger BEFORE corre antes de escribir la fila:
--      puede modificar NEW (por ejemplo, llenar un precio) o cancelar la
--      operación con RAISE EXCEPTION. Un trigger AFTER corre cuando la
--      fila ya está escrita: sirve para propagar efectos (recalcular un
--      total, escribir la auditoría).
--    * FOR EACH ROW: la función se ejecuta una vez por fila afectada.
--    * Un RAISE EXCEPTION dentro de un trigger aborta la sentencia
--      completa, incluida la fila que lo disparó y todo lo que hicieron
--      los demás triggers de esa sentencia.
--    * Si una tabla tiene varios triggers del mismo momento y evento,
--      PostgreSQL los ejecuta en orden ALFABÉTICO de nombre.
--    * Los triggers se crean DESPUÉS de cargar los datos (02), así que
--      esos datos no pasaron por estas validaciones: 02 debe dejarlos
--      coherentes por sí mismo (ver README, "Orden de ejecución").
--    * El script es re-ejecutable: CREATE OR REPLACE FUNCTION y
--      DROP TRIGGER IF EXISTS antes de cada CREATE TRIGGER.
-- =====================================================================


-- Oculta los avisos "does not exist, skipping" de DROP ... IF EXISTS.
-- Se restablece al final del archivo para no afectar a los demás scripts.
SET client_min_messages = warning;


CREATE INDEX IF NOT EXISTS ix_auditoria_tabla_fecha
    ON clinica.auditoria (tabla, fecha);


-- =====================================================================
--  1. Pacientes                                                 RN-02
-- =====================================================================

-- ---------------------------------------------------------------------
--  Un menor (menos de 18 años hoy, S-01) debe tener responsable, y el
--  responsable debe ser mayor de edad (S-02). El CHECK
--  ck_paciente_no_autoresponsable ya impide que sea él mismo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_paciente_validar_responsable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF clinica.fn_es_menor(NEW.id_persona) AND NEW.id_responsable IS NULL THEN
        RAISE EXCEPTION 'El paciente % es menor de edad y necesita un responsable', NEW.id_persona
              USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.id_responsable IS NOT NULL AND clinica.fn_es_menor(NEW.id_responsable) THEN
        RAISE EXCEPTION 'El responsable % de un paciente debe ser mayor de edad', NEW.id_responsable
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_paciente_validar_responsable ON clinica.paciente;
CREATE TRIGGER trg_paciente_validar_responsable
    BEFORE INSERT OR UPDATE OF id_persona, id_responsable ON clinica.paciente
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_paciente_validar_responsable();


-- =====================================================================
--  2. Citas                                                RN-07 / RN-09
-- =====================================================================

-- ---------------------------------------------------------------------
--  Máquina de estados de la cita (RN-07):
--
--      programada ──► confirmada ──► atendida
--          │              │    └───► no_asistio
--          │              └────────► cancelada
--          ├──► atendida / no_asistio / cancelada
--
--  'cancelada', 'atendida' y 'no_asistio' son estados FINALES: una vez
--  ahí, la cita ya no se modifica (ni estado, ni fecha, ni médico).
--  Para "reagendar" una cita cancelada se crea una cita nueva; así queda
--  la historia completa (en los datos, la cita 23 reemplaza a la 12).
--
--  El CHECK ck_cita_estado solo sabe qué valores existen; no puede saber
--  de qué estado venía la fila. El trigger sí tiene OLD y NEW.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_cita_validar_transicion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.estado IN ('cancelada','atendida','no_asistio') THEN
        RAISE EXCEPTION 'La cita % está % y ya no se puede modificar', OLD.id_cita, OLD.estado
              USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado AND NOT (
           (OLD.estado = 'programada' AND NEW.estado IN ('confirmada','cancelada','atendida','no_asistio'))
        OR (OLD.estado = 'confirmada' AND NEW.estado IN ('cancelada','atendida','no_asistio'))
    ) THEN
        RAISE EXCEPTION 'Transición de estado no permitida para la cita %: % → %',
              OLD.id_cita, OLD.estado, NEW.estado
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cita_validar_transicion ON clinica.cita;
CREATE TRIGGER trg_cita_validar_transicion
    BEFORE UPDATE ON clinica.cita
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)        -- un UPDATE que no cambia nada no molesta
    EXECUTE FUNCTION clinica.fn_trg_cita_validar_transicion();


-- ---------------------------------------------------------------------
--  Horario de la cita (RN-09):
--    - el médico debe estar activo;
--    - no se agendan citas en el pasado;
--    - el bloque de 30 minutos debe caber en un horario del médico en
--      esa sede ese día de la semana (fn_cita_en_horario).
--
--  Se evalúa al insertar y cuando cambian fecha, médico o sede
--  (reagendar). No se evalúa al cancelar: cancelar una cita fuera de
--  horario siempre está permitido.
--
--  El choque con OTRA cita (RN-08) no se revisa aquí: lo hacen los
--  índices únicos parciales, que además son seguros con concurrencia.
--  Como todas las citas empiezan en :00 o :30 y duran 30 minutos (S-05),
--  dos citas se enciman si y solo si empiezan a la misma hora, por eso
--  basta un índice único sobre (id_medico, fecha_hora).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_cita_validar_horario()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado = 'cancelada' THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM clinica.empleado
                   WHERE id_persona = NEW.id_medico AND activo) THEN
        RAISE EXCEPTION 'El médico % no está activo', NEW.id_medico
              USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.fecha_hora < now() THEN
        RAISE EXCEPTION 'No se puede agendar una cita en el pasado (%)', NEW.fecha_hora
              USING ERRCODE = 'check_violation';
    END IF;

    IF NOT clinica.fn_cita_en_horario(NEW.id_medico, NEW.id_sede, NEW.fecha_hora) THEN
        RAISE EXCEPTION 'El médico % no atiende en la sede % el % (hora local %)',
              NEW.id_medico, NEW.id_sede, NEW.fecha_hora,
              to_char(NEW.fecha_hora AT TIME ZONE clinica.fn_zona_horaria(), 'Dy DD/MM HH24:MI')
              USING ERRCODE = 'check_violation',
                    HINT    = 'Consulte clinica.fn_horarios_disponibles().';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cita_validar_horario ON clinica.cita;
CREATE TRIGGER trg_cita_validar_horario
    BEFORE INSERT OR UPDATE OF fecha_hora, id_medico, id_sede ON clinica.cita
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_cita_validar_horario();


-- =====================================================================
--  3. Consultas y diagnósticos                            RN-10 / RN-11
-- =====================================================================

-- ---------------------------------------------------------------------
--  RN-10: solo hay consulta para una cita 'atendida'. El UNIQUE
--  uq_consulta_cita ya garantiza que haya como máximo una por cita.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_consulta_validar_cita()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR;
BEGIN
    SELECT estado INTO v_estado FROM clinica.cita WHERE id_cita = NEW.id_cita;

    IF v_estado IS DISTINCT FROM 'atendida' THEN
        RAISE EXCEPTION 'La cita % está "%"; solo se registra consulta de una cita atendida',
              NEW.id_cita, COALESCE(v_estado, 'inexistente')
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_consulta_validar_cita ON clinica.consulta;
CREATE TRIGGER trg_consulta_validar_cita
    BEFORE INSERT OR UPDATE OF id_cita ON clinica.consulta
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_consulta_validar_cita();


-- ---------------------------------------------------------------------
--  RN-11: cada consulta tiene EXACTAMENTE un diagnóstico principal.
--
--  "Como máximo uno" ya lo garantiza el índice único parcial
--  uq_consulta_diagnostico_principal. Falta "al menos uno", y ahí hay
--  un problema de huevo y gallina: primero se inserta la consulta y
--  DESPUÉS sus diagnósticos. Si se validara al insertar la consulta,
--  siempre fallaría.
--
--  Solución: un CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED.
--  PostgreSQL anota que hay que revisarlo, pero lo ejecuta hasta el
--  COMMIT. Para entonces la transacción ya insertó la consulta y sus
--  diagnósticos. Si al confirmar alguna consulta tocada no tiene
--  exactamente un principal, el COMMIT falla y se revierte todo.
--
--  Se dispara desde las dos tablas:
--    - al insertar una consulta (¿le pusieron diagnóstico principal?);
--    - al insertar, cambiar o borrar diagnósticos (¿quedó uno solo?).
--
--  Si alguna vez se necesita validarlo antes del COMMIT:
--    SET CONSTRAINTS clinica.ctr_consulta_diagnostico_principal IMMEDIATE;
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_validar_diagnostico_principal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_consulta INTEGER;
    v_principales INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_id_consulta := OLD.id_consulta;
    ELSE
        v_id_consulta := NEW.id_consulta;
    END IF;

    -- Si la consulta ya no existe (se borró con sus diagnósticos), no hay nada que validar
    IF NOT EXISTS (SELECT 1 FROM clinica.consulta WHERE id_consulta = v_id_consulta) THEN
        RETURN NULL;
    END IF;

    SELECT count(*) INTO v_principales
    FROM clinica.consulta_diagnostico
    WHERE id_consulta = v_id_consulta
      AND es_principal;

    IF v_principales <> 1 THEN
        RAISE EXCEPTION 'La consulta % debe tener exactamente un diagnóstico principal (tiene %)',
              v_id_consulta, v_principales
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;   -- en triggers AFTER el valor de retorno se ignora
END;
$$;

DROP TRIGGER IF EXISTS ctr_consulta_diagnostico_principal ON clinica.consulta;
CREATE CONSTRAINT TRIGGER ctr_consulta_diagnostico_principal
    AFTER INSERT ON clinica.consulta
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_validar_diagnostico_principal();

DROP TRIGGER IF EXISTS ctr_consulta_diagnostico_principal ON clinica.consulta_diagnostico;
CREATE CONSTRAINT TRIGGER ctr_consulta_diagnostico_principal
    AFTER INSERT OR UPDATE OR DELETE ON clinica.consulta_diagnostico
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_validar_diagnostico_principal();


-- =====================================================================
--  4. Recetas y farmacia                           RN-12 / RN-13 / RN-14
-- =====================================================================

-- ---------------------------------------------------------------------
--  Estados de la receta: pendiente → dispensada | anulada (finales).
--  Para pasar a 'dispensada' debe existir su dispensación (S-11).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_receta_validar_estado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La receta % está % y ya no se puede modificar', OLD.id_receta, OLD.estado
              USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.estado = 'dispensada'
       AND NOT EXISTS (SELECT 1 FROM clinica.dispensacion WHERE id_receta = NEW.id_receta) THEN
        RAISE EXCEPTION 'La receta % no tiene dispensación; use clinica.sp_dispensar_receta', NEW.id_receta
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_receta_validar_estado ON clinica.receta;
CREATE TRIGGER trg_receta_validar_estado
    BEFORE UPDATE ON clinica.receta
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION clinica.fn_trg_receta_validar_estado();


-- ---------------------------------------------------------------------
--  Las líneas de una receta solo se tocan mientras está pendiente.
--  (Si la receta ya se surtió, cambiar una línea dejaría la receta en
--  desacuerdo con lo que salió de la farmacia.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_receta_linea_validar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR;
    v_fila   clinica.receta_linea;
BEGIN
    IF TG_OP = 'DELETE' THEN v_fila := OLD; ELSE v_fila := NEW; END IF;

    SELECT estado INTO v_estado FROM clinica.receta WHERE id_receta = v_fila.id_receta;

    -- NOT FOUND: la receta se está borrando y estas líneas se van en cascada
    IF FOUND AND v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La receta % está %; sus líneas ya no se pueden modificar',
              v_fila.id_receta, v_estado
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN v_fila;   -- en DELETE debe regresar OLD para que el borrado ocurra
END;
$$;

DROP TRIGGER IF EXISTS trg_receta_linea_validar ON clinica.receta_linea;
CREATE TRIGGER trg_receta_linea_validar
    BEFORE INSERT OR UPDATE OR DELETE ON clinica.receta_linea
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_receta_linea_validar();


-- ---------------------------------------------------------------------
--  Cada fila de dispensacion_detalle es una SALIDA de inventario.
--  Al insertarla:
--    1. el lote no puede estar vencido (RN-13);
--    2. el medicamento del lote debe estar en la receta;
--    3. se descuenta el stock de ese lote en la sede de la dispensación.
--       Si no hay suficiente, el CHECK ck_existencia_stock (stock >= 0)
--       rechaza el UPDATE y con él toda la operación.
--
--  Descontar aquí (y no solo en el procedimiento) garantiza que el
--  inventario cuadre aunque alguien inserte un detalle a mano.
--
--  Los movimientos de inventario son inmutables: no se actualizan ni se
--  borran. Un error se corrige con un ajuste de inventario, no borrando
--  la historia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_dispdet_descontar_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sede        INTEGER;
    v_id_receta      INTEGER;
    v_id_medicamento INTEGER;
    v_vence          DATE;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'Los detalles de dispensación no se modifican ni se borran'
              USING ERRCODE = 'restrict_violation';
    END IF;

    SELECT d.id_sede, d.id_receta INTO v_id_sede, v_id_receta
    FROM clinica.dispensacion d
    WHERE d.id_dispensacion = NEW.id_dispensacion;

    SELECT l.id_medicamento, l.fecha_vencimiento INTO v_id_medicamento, v_vence
    FROM clinica.lote l
    WHERE l.id_lote = NEW.id_lote;

    IF v_vence < CURRENT_DATE THEN
        RAISE EXCEPTION 'El lote % venció el %; no se puede dispensar', NEW.id_lote, v_vence
              USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM clinica.receta_linea
                   WHERE id_receta = v_id_receta AND id_medicamento = v_id_medicamento) THEN
        RAISE EXCEPTION 'El medicamento % del lote % no está en la receta %',
              v_id_medicamento, NEW.id_lote, v_id_receta
              USING ERRCODE = 'check_violation';
    END IF;

    UPDATE clinica.existencia
    SET stock = stock - NEW.cantidad
    WHERE id_lote = NEW.id_lote
      AND id_sede = v_id_sede;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El lote % no tiene existencia en la sede %', NEW.id_lote, v_id_sede
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dispdet_descontar_stock ON clinica.dispensacion_detalle;
CREATE TRIGGER trg_dispdet_descontar_stock
    BEFORE INSERT OR UPDATE OR DELETE ON clinica.dispensacion_detalle
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_dispdet_descontar_stock();


-- =====================================================================
--  5. Facturación y pagos                          RN-15 / RN-16 / RN-17
-- =====================================================================

-- ---------------------------------------------------------------------
--  RN-16 / S-09: al crear la factura se COPIA la aseguradora y el
--  porcentaje de cobertura que el paciente tiene en ese momento. Es la
--  misma idea que el precio congelado (RN-15): si mañana cambia de
--  póliza, las facturas viejas no se recalculan solas.
--  También se fuerzan los totales a 0 y el estado a 'pendiente': los
--  totales solo se llenan a partir de las líneas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_factura_copiar_cobertura()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT p.id_aseguradora, COALESCE(p.porcentaje_cobertura, 0)
    INTO   NEW.id_aseguradora, NEW.porcentaje_cobertura
    FROM clinica.consulta co
    JOIN clinica.cita     ci ON ci.id_cita = co.id_cita
    JOIN clinica.paciente p  ON p.id_persona = ci.id_paciente
    WHERE co.id_consulta = NEW.id_consulta;

    NEW.subtotal       := 0;
    NEW.monto_seguro   := 0;
    NEW.monto_paciente := 0;
    NEW.saldo          := 0;
    NEW.estado         := 'pendiente';

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_factura_copiar_cobertura ON clinica.factura;
CREATE TRIGGER trg_factura_copiar_cobertura
    BEFORE INSERT ON clinica.factura
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_factura_copiar_cobertura();


-- ---------------------------------------------------------------------
--  Líneas de factura, ANTES de escribirse:
--    - la factura debe estar 'pendiente' (una factura pagada o anulada
--      ya no cambia);
--    - si precio_unitario viene NULL, se llena con el precio VIGENTE
--      (RN-15): el de la especialidad de la cita para 'consulta', el de
--      venta del medicamento para 'medicamento'. Desde ese momento el
--      precio queda congelado en la línea (desnormalización controlada).
--
--  Detalle técnico: precio_unitario es NOT NULL, pero PostgreSQL revisa
--  NOT NULL y CHECK DESPUÉS de los triggers BEFORE. Por eso el INSERT
--  con NULL funciona: cuando llega la revisión, el trigger ya lo llenó.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_factura_linea_validar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado     VARCHAR;
    v_id_factura INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN v_id_factura := OLD.id_factura; ELSE v_id_factura := NEW.id_factura; END IF;

    SELECT estado INTO v_estado FROM clinica.factura WHERE id_factura = v_id_factura;

    IF FOUND AND v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La factura % está %; sus líneas ya no se pueden modificar',
              v_id_factura, v_estado
              USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF NEW.precio_unitario IS NULL THEN
        IF NEW.concepto = 'consulta' THEN
            SELECT e.precio_consulta INTO NEW.precio_unitario
            FROM clinica.factura      f
            JOIN clinica.consulta     co ON co.id_consulta = f.id_consulta
            JOIN clinica.cita         ci ON ci.id_cita = co.id_cita
            JOIN clinica.especialidad e  ON e.id_especialidad = ci.id_especialidad
            WHERE f.id_factura = NEW.id_factura;
        ELSE
            SELECT m.precio_venta INTO NEW.precio_unitario
            FROM clinica.medicamento m
            WHERE m.id_medicamento = NEW.id_medicamento;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_factura_linea_validar ON clinica.factura_linea;
CREATE TRIGGER trg_factura_linea_validar
    BEFORE INSERT OR UPDATE OR DELETE ON clinica.factura_linea
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_factura_linea_validar();


-- ---------------------------------------------------------------------
--  Líneas de factura, DESPUÉS de escribirse: recalcular los totales
--  del encabezado (subtotal, seguro, paciente, saldo, estado).
--  Si una línea se mueve de factura (UPDATE de id_factura) se
--  recalculan las dos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_factura_linea_recalcular()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN
        PERFORM clinica.fn_recalcular_factura(OLD.id_factura);
    END IF;
    IF TG_OP IN ('INSERT','UPDATE') AND (TG_OP = 'INSERT' OR NEW.id_factura <> OLD.id_factura) THEN
        PERFORM clinica.fn_recalcular_factura(NEW.id_factura);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_factura_linea_recalcular ON clinica.factura_linea;
CREATE TRIGGER trg_factura_linea_recalcular
    AFTER INSERT OR UPDATE OR DELETE ON clinica.factura_linea
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_factura_linea_recalcular();


-- ---------------------------------------------------------------------
--  Pagos, ANTES de insertarse (RN-17, S-10):
--
--    1. SELECT ... FOR UPDATE sobre la factura. Este bloqueo es la
--       clave de la concurrencia: si dos recepcionistas cobran la misma
--       factura al mismo tiempo, la segunda ESPERA a que la primera
--       termine y entonces lee el saldo ya actualizado. Sin él, las dos
--       verían saldo $500, las dos cobrarían $500 y se cobraría doble.
--    2. La factura debe estar 'pendiente'.
--    3. El monto no puede superar el saldo.
--
--  Además el CHECK ck_factura_saldo (saldo >= 0) es una segunda red:
--  aunque esta validación faltara, el recálculo fallaría.
--
--  Los pagos son inmutables: un error se corrige con otro movimiento,
--  no editando ni borrando el pago (queda el rastro en auditoría).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_pago_validar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado VARCHAR;
    v_saldo  NUMERIC(12,2);
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'Los pagos no se modifican ni se borran'
              USING ERRCODE = 'restrict_violation';
    END IF;

    SELECT estado, saldo INTO v_estado, v_saldo
    FROM clinica.factura
    WHERE id_factura = NEW.id_factura
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la factura %', NEW.id_factura
              USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF v_estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La factura % está %; no admite pagos', NEW.id_factura, v_estado
              USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.monto > v_saldo THEN
        RAISE EXCEPTION 'El pago de % supera el saldo de la factura % (%)',
              NEW.monto, NEW.id_factura, v_saldo
              USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pago_validar ON clinica.pago;
CREATE TRIGGER trg_pago_validar
    BEFORE INSERT OR UPDATE OR DELETE ON clinica.pago
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_pago_validar();


-- ---------------------------------------------------------------------
--  Pagos, DESPUÉS de insertarse: recalcular saldo y estado.
--  Cuando el saldo llega a 0 la factura pasa sola a 'pagada' (RN-17).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_pago_actualizar_factura()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM clinica.fn_recalcular_factura(NEW.id_factura);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_pago_actualizar_factura ON clinica.pago;
CREATE TRIGGER trg_pago_actualizar_factura
    AFTER INSERT ON clinica.pago
    FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_pago_actualizar_factura();


-- =====================================================================
--  6. Auditoría genérica                                         RN-18
-- =====================================================================

-- ---------------------------------------------------------------------
--  Una sola función sirve para todas las tablas auditadas:
--    - TG_TABLE_NAME y TG_OP dicen qué tabla y qué operación la disparó;
--    - to_jsonb(OLD) / to_jsonb(NEW) convierten la fila completa a JSON,
--      sin importar qué columnas tenga la tabla;
--    - session_user es el usuario que abrió la conexión (S-13). Se usa en
--      lugar de current_user porque current_user cambia dentro de una
--      función SECURITY DEFINER (y con SET ROLE);
--    - txid_current() agrupa todos los cambios de una misma transacción:
--      por ejemplo, una dispensación genera filas en dispensacion,
--      existencia y receta con el mismo id_transaccion.
--
--  SECURITY DEFINER: la función corre con los permisos de su DUEÑO, no
--  de quien hace el cambio. Así un recepcionista puede provocar una fila
--  de auditoría sin tener permiso de INSERT sobre `auditoria` (y por
--  tanto no puede escribir ni falsear registros directamente).
--  SET search_path fija dónde se buscan los objetos: es la práctica
--  recomendada en toda función SECURITY DEFINER, para que nadie pueda
--  "colar" una tabla o función propia con el mismo nombre.
--
--  Los UPDATE que no cambian nada no se registran.
--  Es un trigger AFTER: si la operación falla, no queda auditoría de
--  algo que nunca ocurrió (y si la transacción se revierte, la fila de
--  auditoría también se revierte con ella).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinica.fn_trg_auditoria()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO clinica.auditoria (tabla, operacion, datos_nuevos)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        IF to_jsonb(OLD) = to_jsonb(NEW) THEN
            RETURN NULL;
        END IF;
        INSERT INTO clinica.auditoria (tabla, operacion, datos_anteriores, datos_nuevos)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
    ELSE
        INSERT INTO clinica.auditoria (tabla, operacion, datos_anteriores)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$;

-- Se crea el mismo trigger en cada tabla con datos sensibles o de dinero.
DO $$
DECLARE
    v_tabla TEXT;
BEGIN
    FOREACH v_tabla IN ARRAY ARRAY[
        'paciente', 'cita', 'consulta', 'consulta_diagnostico',
        'receta', 'dispensacion', 'existencia', 'medicamento',
        'factura', 'pago']
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_zz_auditoria ON clinica.%I', v_tabla);
        EXECUTE format(
            'CREATE TRIGGER trg_zz_auditoria
                 AFTER INSERT OR UPDATE OR DELETE ON clinica.%I
                 FOR EACH ROW EXECUTE FUNCTION clinica.fn_trg_auditoria()', v_tabla);
    END LOOP;
END;
$$;
-- El prefijo "zz" hace que, entre los triggers AFTER de una tabla, la
-- auditoría corra al final (orden alfabético) y registre la fila ya
-- con todos los efectos de los demás triggers.


-- ---------------------------------------------------------------------
--  Para consultar la auditoría, por ejemplo:
--    SELECT fecha, usuario, operacion,
--           datos_anteriores ->> 'estado' AS antes,
--           datos_nuevos     ->> 'estado' AS despues
--    FROM clinica.auditoria
--    WHERE tabla = 'cita' AND datos_nuevos ->> 'id_cita' = '21'
--    ORDER BY fecha;
-- ---------------------------------------------------------------------

RESET client_min_messages;
