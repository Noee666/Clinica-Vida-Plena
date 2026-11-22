-- =====================================================================
--  Pruebas de permisos con SET ROLE
--  Ejecutar en la base `clinica` ya reconstruida, con un superusuario:
--      psql -U postgres -d clinica -f docs/evidencias/permisos/pruebas_permisos.sql
--  Todo corre dentro de una transacción que termina en ROLLBACK: la base
--  queda igual. La salida esperada está en pruebas_permisos_salida.txt.
--
--  Cada prueba que DEBE fallar se ejecuta en un bloque DO que atrapa el
--  error insufficient_privilege y lo muestra como NOTICE "DENEGADO".
-- =====================================================================
\set ON_ERROR_STOP on
\pset footer off

BEGIN;

-- Prueba de acceso: intenta ejecutar `sentencia`; dice si se permitió
CREATE FUNCTION pg_temp.probar(etiqueta TEXT, sentencia TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE sentencia;
    RETURN format('PERMITIDO  %s', etiqueta);
EXCEPTION WHEN insufficient_privilege THEN
    RETURN format('DENEGADO   %s  (%s)', etiqueta, SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.probar(TEXT, TEXT) TO PUBLIC;
-- El esquema temporal de esta sesión se llama pg_temp_N; se da acceso
-- a él para que los roles de prueba puedan llamar a probar()
DO $$ BEGIN
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO PUBLIC', pg_my_temp_schema()::regnamespace);
END $$;

\echo
\echo '############ 1. rol_recepcion ############'
SET ROLE rol_recepcion;
SELECT current_user AS rol_activo;

-- Puede: ver la agenda sin datos clínicos
SELECT fecha, hora, paciente, medico, especialidad, sede, estado
FROM clinica.v_agenda
WHERE fecha = CURRENT_DATE + 2
ORDER BY hora LIMIT 3;

-- Puede: registrar un paciente nuevo
INSERT INTO clinica.persona (documento, nombres, apellido_paterno, fecha_nacimiento, sexo, telefono)
VALUES ('PRUEBA-0001', 'Paciente', 'De Prueba', DATE '1990-05-05', 'F', '662-000-0000');
INSERT INTO clinica.paciente (id_persona)
SELECT id_persona FROM clinica.persona WHERE documento = 'PRUEBA-0001';

-- Puede: reservar una cita en el primer bloque libre del Dr. Salazar
SELECT d.fecha_hora AS bloque, d.id_sede AS sede_bloque
FROM generate_series(CURRENT_DATE + 1, CURRENT_DATE + 14, INTERVAL '1 day') AS g(dia)
CROSS JOIN LATERAL clinica.fn_horarios_disponibles(19, g.dia::date) AS d
ORDER BY d.fecha_hora LIMIT 1
\gset
SELECT id_persona AS nuevo_paciente FROM clinica.persona WHERE documento = 'PRUEBA-0001'
\gset
CALL clinica.sp_reservar_cita(:nuevo_paciente, 19, 1, :sede_bloque, :'bloque', NULL);

-- No puede: datos clínicos (RN-19)
SELECT pg_temp.probar('leer consulta.notas_clinicas', 'SELECT notas_clinicas FROM clinica.consulta LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer consulta.motivo',         'SELECT motivo FROM clinica.consulta LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer consulta_diagnostico',    'SELECT * FROM clinica.consulta_diagnostico LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer receta_linea',            'SELECT * FROM clinica.receta_linea LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer receta.indicaciones',     'SELECT indicaciones FROM clinica.receta LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer auditoria',               'SELECT * FROM clinica.auditoria LIMIT 1')
UNION ALL
SELECT pg_temp.probar('escribir en auditoria',        $$INSERT INTO clinica.auditoria (tabla, operacion, datos_nuevos) VALUES ('x','INSERT','{}')$$)
UNION ALL
SELECT pg_temp.probar('modificar existencias',        'UPDATE clinica.existencia SET stock = stock + 1 WHERE false')
UNION ALL
SELECT pg_temp.probar('borrar pagos',                 'DELETE FROM clinica.pago WHERE false');
RESET ROLE;

\echo
\echo '############ 2. rol_medico ############'
SET ROLE rol_medico;
SELECT current_user AS rol_activo;

-- Puede: atender la cita 21 (confirmada) y registrar la consulta con
-- su diagnóstico principal; la cita pasa a 'atendida'
CALL clinica.sp_registrar_consulta(21, 'Prueba de permisos: control', 2,
                                   'Nota clínica de prueba', NULL);
SELECT c.id_cita, c.estado, co.id_consulta, co.motivo
FROM clinica.cita c JOIN clinica.consulta co ON co.id_cita = c.id_cita
WHERE c.id_cita = 21;

-- Puede: emitir una receta para esa consulta
INSERT INTO clinica.receta (id_consulta, indicaciones)
SELECT id_consulta, 'Prueba' FROM clinica.consulta WHERE id_cita = 21;
INSERT INTO clinica.receta_linea (id_receta, numero_linea, id_medicamento, dosis, frecuencia, cantidad)
SELECT r.id_receta, 1, 1, '1 tableta', 'Cada 8 horas', 1
FROM clinica.receta r JOIN clinica.consulta co ON co.id_consulta = r.id_consulta
WHERE co.id_cita = 21;

-- No puede: cobrar, tocar inventario ni ver la auditoría
SELECT pg_temp.probar('registrar un pago',    $$CALL clinica.sp_registrar_pago(18, 10, 'efectivo')$$)
UNION ALL
SELECT pg_temp.probar('leer facturas',        'SELECT * FROM clinica.factura LIMIT 1')
UNION ALL
SELECT pg_temp.probar('modificar existencias','UPDATE clinica.existencia SET stock = 0 WHERE false')
UNION ALL
SELECT pg_temp.probar('leer auditoria',       'SELECT * FROM clinica.auditoria LIMIT 1');
RESET ROLE;

\echo
\echo '############ 3. rol_farmacia ############'
SET ROLE rol_farmacia;
SELECT current_user AS rol_activo;

-- Puede: ver la receta (qué entregar) y surtirla en la sede Centro
SELECT rl.numero_linea, m.nombre, rl.dosis, rl.frecuencia, rl.cantidad
FROM clinica.receta r
JOIN clinica.consulta co ON co.id_consulta = r.id_consulta
JOIN clinica.receta_linea rl ON rl.id_receta = r.id_receta
JOIN clinica.medicamento m ON m.id_medicamento = rl.id_medicamento
WHERE co.id_cita = 21;
SELECT r.id_receta AS receta_prueba
FROM clinica.receta r JOIN clinica.consulta co USING (id_consulta) WHERE co.id_cita = 21
\gset
CALL clinica.sp_dispensar_receta(:receta_prueba, 28, NULL);

-- No puede: notas clínicas, diagnósticos ni cobro
SELECT pg_temp.probar('leer consulta.notas_clinicas', 'SELECT notas_clinicas FROM clinica.consulta LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer consulta_diagnostico',    'SELECT * FROM clinica.consulta_diagnostico LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer facturas',                'SELECT * FROM clinica.factura LIMIT 1')
UNION ALL
SELECT pg_temp.probar('crear citas',                  'INSERT INTO clinica.cita (id_paciente) SELECT 1 WHERE false');
RESET ROLE;

\echo
\echo '############ 4. rol_recepcion cobra la consulta ############'
SET ROLE rol_recepcion;
SELECT id_consulta AS consulta_prueba FROM clinica.consulta WHERE id_cita = 21
\gset
CALL clinica.sp_generar_factura(:consulta_prueba, NULL);
SELECT f.id_factura, f.subtotal, f.porcentaje_cobertura, f.monto_paciente, f.saldo, f.estado
FROM clinica.factura f JOIN clinica.consulta co USING (id_consulta) WHERE co.id_cita = 21
\gset f_
CALL clinica.sp_registrar_pago(:f_id_factura, :f_monto_paciente, 'tarjeta', 'TJ-PRUEBA', 25, NULL);
SELECT id_factura, subtotal, monto_paciente, saldo, estado
FROM clinica.factura WHERE id_factura = :f_id_factura;
RESET ROLE;

\echo
\echo '############ 5. rol_auditor ############'
SET ROLE rol_auditor;
SELECT current_user AS rol_activo;

-- Puede: ver quién cambió qué. Los cambios de esta prueba aparecen con
-- el usuario de la sesión (session_user, S-13) aunque se hicieron con SET ROLE.
SELECT tabla, operacion, usuario, count(*) AS cambios
FROM clinica.auditoria
WHERE id_transaccion = txid_current()
GROUP BY tabla, operacion, usuario
ORDER BY tabla, operacion;

-- No puede: alterar la auditoría ni leer datos de pacientes
SELECT pg_temp.probar('borrar auditoria',    'DELETE FROM clinica.auditoria WHERE false')
UNION ALL
SELECT pg_temp.probar('modificar auditoria', $$UPDATE clinica.auditoria SET usuario = 'nadie' WHERE false$$)
UNION ALL
SELECT pg_temp.probar('leer pacientes',      'SELECT * FROM clinica.paciente LIMIT 1')
UNION ALL
SELECT pg_temp.probar('leer consultas',      'SELECT * FROM clinica.consulta LIMIT 1');
RESET ROLE;

ROLLBACK;
\echo
\echo 'ROLLBACK: la base quedó sin cambios.'
