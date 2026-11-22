-- =====================================================================
--  Clínica Vida Plena — Seguridad: roles y permisos
--  Autora: Ibarra Lopez Danna Alejandra
--  Ejecutar después de 05_triggers.sql (normalmente desde ejecutar_todo.sql).
--
--  Reglas cubiertas:
--    RN-19  la recepción no ve datos clínicos
--    RN-18  solo el auditor lee la auditoría; nadie la escribe a mano
--
--  Principio de mínimo privilegio: se le quita TODO a PUBLIC y cada rol
--  recibe solo lo que necesita para su trabajo. La matriz completa está
--  en docs/permisos.md.
--
--  Los cuatro roles son ROLES DE GRUPO: sin LOGIN y sin contraseña.
--  Para dar acceso a una persona real se crea un usuario con LOGIN y se
--  le asigna el grupo, por ejemplo:
--      CREATE ROLE brenda LOGIN PASSWORD '...';   -- nunca en el repositorio
--      GRANT rol_recepcion TO brenda;
--
--  Los roles son objetos GLOBALES del servidor (no de la base): por eso
--  se crean solo si no existen, y pg_dump no los incluye en el respaldo.
--
--  Cómo encaja con los procedimientos y triggers:
--    * Los procedimientos de 04 corren con los permisos de QUIEN LOS
--      LLAMA (SECURITY INVOKER, el valor por defecto). Por eso cada rol
--      necesita permiso sobre las tablas que toca su procedimiento.
--    * Los triggers también corren con los permisos de quien provocó el
--      cambio: si un pago actualiza la factura, la recepción necesita
--      UPDATE sobre esas columnas de factura.
--    * La excepción es fn_trg_auditoria (SECURITY DEFINER): escribe en
--      auditoria con los permisos de su dueño, así nadie más necesita
--      (ni tiene) INSERT sobre esa tabla.
--
--  El script es re-ejecutable: primero revoca todo y luego vuelve a dar.
-- =====================================================================

SET client_min_messages = warning;

-- ---------------------------------------------------------------------
--  1. Crear los roles si no existen
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_rol TEXT;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY['rol_recepcion', 'rol_medico', 'rol_farmacia', 'rol_auditor']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_rol);
        END IF;
    END LOOP;
END;
$$;

COMMENT ON ROLE rol_recepcion IS 'Recepción y caja: pacientes, agenda, facturas y pagos. Sin datos clínicos.';
COMMENT ON ROLE rol_medico    IS 'Médicos: agenda, consultas, diagnósticos y recetas.';
COMMENT ON ROLE rol_farmacia  IS 'Farmacia: recetas, inventario y dispensación.';
COMMENT ON ROLE rol_auditor   IS 'Auditoría: solo lectura de clinica.auditoria.';

-- ---------------------------------------------------------------------
--  2. Partir de cero
--     PUBLIC (todos los usuarios) no puede nada en el esquema clinica.
--     En PostgreSQL, por defecto, PUBLIC puede EJECUTAR cualquier
--     función nueva; también se le quita.
-- ---------------------------------------------------------------------
REVOKE ALL ON SCHEMA clinica FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA clinica FROM PUBLIC, rol_recepcion, rol_medico, rol_farmacia, rol_auditor;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA clinica FROM PUBLIC, rol_recepcion, rol_medico, rol_farmacia, rol_auditor;
REVOKE ALL ON ALL FUNCTIONS  IN SCHEMA clinica FROM PUBLIC, rol_recepcion, rol_medico, rol_farmacia, rol_auditor;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA clinica FROM PUBLIC, rol_recepcion, rol_medico, rol_farmacia, rol_auditor;

-- Lo mismo para los objetos que se creen DESPUÉS en el esquema
ALTER DEFAULT PRIVILEGES IN SCHEMA clinica REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

-- Las funciones de las extensiones (btree_gist, pg_trgm) viven en el
-- mismo esquema y los índices las necesitan al insertar o buscar: se
-- devuelven a todos los roles. No dan acceso a ningún dato.
DO $$
DECLARE
    v_fn TEXT;
BEGIN
    FOR v_fn IN
        SELECT p.oid::regprocedure::text
        FROM pg_proc p
        JOIN pg_depend d ON d.objid = p.oid AND d.deptype = 'e'
        WHERE p.pronamespace = 'clinica'::regnamespace
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rol_recepcion, rol_medico, rol_farmacia, rol_auditor', v_fn);
    END LOOP;
END;
$$;

-- Todos los roles pueden "entrar" al esquema (no da acceso a ninguna tabla)
GRANT USAGE ON SCHEMA clinica TO rol_recepcion, rol_medico, rol_farmacia, rol_auditor;

-- Funciones de apoyo sin datos sensibles: las usan los triggers y los
-- procedimientos de todos los roles
GRANT EXECUTE ON FUNCTION
    clinica.fn_zona_horaria(),
    clinica.fn_edad(DATE, DATE),
    clinica.fn_es_menor(INTEGER),
    clinica.fn_cita_en_horario(INTEGER, INTEGER, TIMESTAMPTZ),
    clinica.fn_medico_disponible(INTEGER, INTEGER, TIMESTAMPTZ),
    clinica.fn_horarios_disponibles(INTEGER, DATE),
    clinica.fn_stock_disponible(INTEGER, INTEGER)
TO rol_recepcion, rol_medico, rol_farmacia;

-- Recalcular totales de factura: solo caja
GRANT EXECUTE ON FUNCTION clinica.fn_recalcular_factura(INTEGER) TO rol_recepcion;

-- Las funciones de trigger no se llaman a mano, pero el trigger se
-- ejecuta con los permisos de quien hace el cambio: necesitan EXECUTE.
DO $$
DECLARE
    v_fn TEXT;
BEGIN
    FOR v_fn IN
        SELECT p.oid::regprocedure::text
        FROM pg_proc p
        WHERE p.pronamespace = 'clinica'::regnamespace
          AND p.prorettype = 'trigger'::regtype
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rol_recepcion, rol_medico, rol_farmacia', v_fn);
    END LOOP;
END;
$$;

-- Catálogos que todos los roles operativos consultan
GRANT SELECT ON clinica.sede, clinica.especialidad, clinica.medico_especialidad,
                clinica.horario, clinica.aseguradora
TO rol_recepcion, rol_medico, rol_farmacia;


-- ---------------------------------------------------------------------
--  3. rol_recepcion — recepción y caja
--     Registra pacientes, agenda citas, cobra.
--     RN-19: NO tiene acceso a consulta_diagnostico, receta ni a las
--     columnas clínicas de consulta (motivo, signos vitales, notas).
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON clinica.persona, clinica.paciente TO rol_recepcion;
GRANT SELECT ON clinica.empleado, clinica.medico, clinica.recepcionista TO rol_recepcion;

-- Agenda: la vista sin datos clínicos, y la tabla para reservar y
-- cambiar el estado (la tabla cita no tiene datos clínicos)
GRANT SELECT ON clinica.v_agenda TO rol_recepcion;
GRANT SELECT, INSERT ON clinica.cita TO rol_recepcion;
GRANT UPDATE (estado, fecha_hora, id_sede) ON clinica.cita TO rol_recepcion;

-- Consulta: SOLO las columnas administrativas que necesita para facturar.
-- Un SELECT notas_clinicas FROM consulta da "permission denied".
GRANT SELECT (id_consulta, id_cita, registrada_en) ON clinica.consulta TO rol_recepcion;

-- Para facturar los medicamentos surtidos (sp_generar_factura) basta
-- saber qué se entregó y a qué precio, no qué diagnóstico lo motivó.
GRANT SELECT (id_receta, id_consulta, estado) ON clinica.receta TO rol_recepcion;
GRANT SELECT ON clinica.dispensacion, clinica.dispensacion_detalle,
                clinica.lote, clinica.medicamento
TO rol_recepcion;

-- Facturación y cobro
GRANT SELECT, INSERT ON clinica.factura, clinica.factura_linea TO rol_recepcion;
GRANT UPDATE (subtotal, monto_seguro, monto_paciente, saldo, estado) ON clinica.factura TO rol_recepcion;
GRANT SELECT, INSERT ON clinica.pago TO rol_recepcion;
GRANT SELECT ON clinica.v_cuentas_por_cobrar TO rol_recepcion;

GRANT EXECUTE ON PROCEDURE
    clinica.sp_reservar_cita(INTEGER, INTEGER, INTEGER, INTEGER, TIMESTAMPTZ, INTEGER),
    clinica.sp_cambiar_estado_cita(INTEGER, VARCHAR),
    clinica.sp_generar_factura(INTEGER, INTEGER),
    clinica.sp_registrar_pago(INTEGER, NUMERIC, VARCHAR, VARCHAR, INTEGER, INTEGER)
TO rol_recepcion;


-- ---------------------------------------------------------------------
--  4. rol_medico — atención clínica
--     Único rol que escribe datos clínicos. No cobra ni toca inventario.
-- ---------------------------------------------------------------------
GRANT SELECT ON clinica.persona, clinica.paciente, clinica.empleado, clinica.medico TO rol_medico;
GRANT SELECT ON clinica.cita, clinica.v_agenda TO rol_medico;
GRANT UPDATE (estado) ON clinica.cita TO rol_medico;

GRANT SELECT, INSERT, UPDATE ON clinica.consulta, clinica.consulta_diagnostico,
                                clinica.receta, clinica.receta_linea
TO rol_medico;
GRANT DELETE ON clinica.consulta_diagnostico, clinica.receta_linea TO rol_medico;
GRANT SELECT ON clinica.diagnostico, clinica.medicamento TO rol_medico;

-- Para recetar sabiendo qué hay en la farmacia
GRANT SELECT ON clinica.v_inventario_vigente TO rol_medico;

GRANT EXECUTE ON PROCEDURE
    clinica.sp_cambiar_estado_cita(INTEGER, VARCHAR),
    clinica.sp_registrar_consulta(INTEGER, VARCHAR, INTEGER, TEXT, SMALLINT, SMALLINT,
                                  SMALLINT, NUMERIC, NUMERIC, NUMERIC, INTEGER)
TO rol_medico;


-- ---------------------------------------------------------------------
--  5. rol_farmacia — farmacia
--     Ve las recetas para surtirlas (lo que se entrega y cómo tomarlo),
--     pero no las notas clínicas ni los diagnósticos.
-- ---------------------------------------------------------------------
GRANT SELECT ON clinica.persona, clinica.paciente, clinica.empleado,
                clinica.farmaceutico, clinica.medico
TO rol_farmacia;
GRANT SELECT (id_cita, id_paciente, id_medico, id_sede, fecha_hora, estado) ON clinica.cita TO rol_farmacia;
GRANT SELECT (id_consulta, id_cita, registrada_en) ON clinica.consulta TO rol_farmacia;

GRANT SELECT ON clinica.receta, clinica.receta_linea TO rol_farmacia;
GRANT UPDATE (estado) ON clinica.receta TO rol_farmacia;

-- Inventario: alta de medicamentos y lotes, entradas de mercancía
GRANT SELECT, INSERT, UPDATE ON clinica.medicamento, clinica.lote, clinica.existencia TO rol_farmacia;
GRANT SELECT, INSERT ON clinica.dispensacion, clinica.dispensacion_detalle TO rol_farmacia;
GRANT SELECT ON clinica.v_inventario_vigente, clinica.v_lote_por_vencer TO rol_farmacia;

GRANT EXECUTE ON PROCEDURE
    clinica.sp_dispensar_receta(INTEGER, INTEGER, INTEGER)
TO rol_farmacia;


-- ---------------------------------------------------------------------
--  6. rol_auditor — solo lectura de la auditoría                  RN-18
--     Nadie tiene INSERT, UPDATE ni DELETE sobre auditoria: la llenan
--     los triggers (SECURITY DEFINER) y no se puede alterar.
-- ---------------------------------------------------------------------
GRANT SELECT ON clinica.auditoria TO rol_auditor;


RESET client_min_messages;

-- ---------------------------------------------------------------------
--  Pruebas (las capturas están en docs/evidencias/permisos/):
--
--    SET ROLE rol_recepcion;
--    SELECT * FROM clinica.v_agenda WHERE fecha = CURRENT_DATE;   -- funciona
--    SELECT notas_clinicas FROM clinica.consulta;                 -- ERROR: permission denied
--    SELECT * FROM clinica.consulta_diagnostico;                  -- ERROR: permission denied
--    RESET ROLE;
--
--    SET ROLE rol_auditor;
--    SELECT count(*) FROM clinica.auditoria;                      -- funciona
--    DELETE FROM clinica.auditoria;                               -- ERROR: permission denied
--    RESET ROLE;
-- ---------------------------------------------------------------------
