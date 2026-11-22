-- =====================================================================
--  Clínica Vida Plena — Vistas e índices de rendimiento
--  Autor: Escobedo Ayala Andres Manuel
--  Ejecutar después de 02_datos.sql (normalmente desde ejecutar_todo.sql).
--
--  Va DESPUÉS de la carga de datos a propósito: crear un índice sobre una
--  tabla ya llena es más rápido que mantenerlo fila por fila durante
--  50,000 INSERT.
--
--  Reglas cubiertas:
--    RN-19  v_agenda: la recepción ve la agenda sin datos clínicos.
--  Vistas de apoyo para los tres problemas del caso:
--    citas duplicadas      -> v_agenda (RN-08 ya lo impide el esquema)
--    medicamentos vencidos -> v_inventario_vigente, v_lote_por_vencer
--    facturas sin cobrar   -> v_cuentas_por_cobrar
--
--  Los planes y tiempos antes y después de los índices están en
--  docs/rendimiento.md.
--
--  El script es re-ejecutable: CREATE OR REPLACE VIEW e IF NOT EXISTS.
-- =====================================================================

-- pg_trgm: búsqueda por "pedazos" de texto (trigramas). Permite que un
-- índice ayude a un ILIKE '%texto%', que un B-tree normal no puede usar
-- porque el patrón empieza con comodín.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA clinica;


-- =====================================================================
--  1. Vistas
-- =====================================================================

-- ---------------------------------------------------------------------
--  Agenda sin datos clínicos                                     RN-19
--  Es lo que ve la recepción: quién, con quién, cuándo, dónde y en qué
--  estado. No toca consulta, consulta_diagnostico ni receta.
--  security_barrier impide que una función en el WHERE de quien consulta
--  la vista "espíe" filas antes de que la vista las filtre.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW clinica.v_agenda
WITH (security_barrier = true) AS
SELECT c.id_cita,
       c.fecha_hora,
       (c.fecha_hora AT TIME ZONE 'America/Hermosillo')::date AS fecha,
       (c.fecha_hora AT TIME ZONE 'America/Hermosillo')::time AS hora,
       c.estado,
       c.id_paciente,
       pp.nombres || ' ' || pp.apellido_paterno
           || COALESCE(' ' || pp.apellido_materno, '')     AS paciente,
       pp.telefono                                          AS telefono_paciente,
       COALESCE(a.nombre, 'Particular')                     AS aseguradora,
       c.id_medico,
       pm.nombres || ' ' || pm.apellido_paterno             AS medico,
       c.id_especialidad,
       e.nombre                                             AS especialidad,
       c.id_sede,
       s.nombre                                             AS sede
FROM clinica.cita         c
JOIN clinica.paciente     pa ON pa.id_persona = c.id_paciente
JOIN clinica.persona      pp ON pp.id_persona = c.id_paciente
LEFT JOIN clinica.aseguradora a ON a.id_aseguradora = pa.id_aseguradora
JOIN clinica.persona      pm ON pm.id_persona = c.id_medico
JOIN clinica.especialidad e  ON e.id_especialidad = c.id_especialidad
JOIN clinica.sede         s  ON s.id_sede = c.id_sede;

COMMENT ON VIEW clinica.v_agenda IS
    'Agenda de citas sin datos clínicos (RN-19). Es la vista de la recepción.';

-- ---------------------------------------------------------------------
--  Inventario surtible: solo lotes no vencidos y con stock          RN-13
--  Una fila por medicamento y sede, con el próximo vencimiento (el lote
--  que sale primero según RN-14).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW clinica.v_inventario_vigente AS
SELECT s.id_sede,
       s.nombre                    AS sede,
       m.id_medicamento,
       m.nombre                    AS medicamento,
       m.presentacion,
       m.concentracion,
       SUM(ex.stock)               AS stock_disponible,
       COUNT(*)                    AS lotes,
       MIN(l.fecha_vencimiento)    AS proximo_vencimiento
FROM clinica.existencia  ex
JOIN clinica.lote        l ON l.id_lote = ex.id_lote
JOIN clinica.medicamento m ON m.id_medicamento = l.id_medicamento
JOIN clinica.sede        s ON s.id_sede = ex.id_sede
WHERE ex.stock > 0
  AND l.fecha_vencimiento >= CURRENT_DATE
GROUP BY s.id_sede, s.nombre, m.id_medicamento, m.nombre, m.presentacion, m.concentracion;

COMMENT ON VIEW clinica.v_inventario_vigente IS
    'Stock que sí se puede surtir: lotes no vencidos y con existencia, por sede.';

-- ---------------------------------------------------------------------
--  Lotes con stock vencidos o por vencer en 90 días
--  Para retirar a tiempo lo que ya no se puede vender.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW clinica.v_lote_por_vencer AS
SELECT s.nombre                               AS sede,
       m.nombre                               AS medicamento,
       m.presentacion,
       l.numero_lote,
       l.fecha_vencimiento,
       l.fecha_vencimiento - CURRENT_DATE     AS dias_restantes,
       ex.stock,
       CASE WHEN l.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
            ELSE 'por vencer' END             AS situacion
FROM clinica.existencia  ex
JOIN clinica.lote        l ON l.id_lote = ex.id_lote
JOIN clinica.medicamento m ON m.id_medicamento = l.id_medicamento
JOIN clinica.sede        s ON s.id_sede = ex.id_sede
WHERE ex.stock > 0
  AND l.fecha_vencimiento < CURRENT_DATE + 90;

COMMENT ON VIEW clinica.v_lote_por_vencer IS
    'Lotes con stock que ya vencieron o vencen en los próximos 90 días.';

-- ---------------------------------------------------------------------
--  Cuentas por cobrar: facturas con saldo del paciente               RN-17
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW clinica.v_cuentas_por_cobrar AS
SELECT f.id_factura,
       f.fecha_emision,
       CURRENT_DATE - (f.fecha_emision AT TIME ZONE 'America/Hermosillo')::date AS dias_vencida,
       p.id_persona                                         AS id_paciente,
       p.nombres || ' ' || p.apellido_paterno               AS paciente,
       p.telefono,
       s.nombre                                             AS sede,
       f.subtotal,
       f.monto_paciente,
       f.monto_paciente - f.saldo                           AS pagado,
       f.saldo
FROM clinica.factura  f
JOIN clinica.consulta co ON co.id_consulta = f.id_consulta
JOIN clinica.cita     c  ON c.id_cita = co.id_cita
JOIN clinica.persona  p  ON p.id_persona = c.id_paciente
JOIN clinica.sede     s  ON s.id_sede = c.id_sede
WHERE f.estado = 'pendiente'
  AND f.saldo > 0;

COMMENT ON VIEW clinica.v_cuentas_por_cobrar IS
    'Facturas pendientes con saldo a cargo del paciente.';


-- =====================================================================
--  2. Índices de rendimiento
--
--  El esquema ya trae los índices de las PK, de los UNIQUE y los únicos
--  parciales de RN-08 y RN-11. PostgreSQL NO crea índices para las FK
--  por su cuenta: aquí se agregan los que piden las consultas de
--  07_consultas.sql, los procedimientos y los triggers.
-- =====================================================================

-- Citas por sede en un rango de fechas (pregunta 1) y agenda por sede
CREATE INDEX IF NOT EXISTS ix_cita_sede_fecha
    ON clinica.cita (id_sede, fecha_hora);

-- Citas por fecha: agenda del día, este mes, mes anterior
-- (preguntas 4, 5, 6 y 13)
CREATE INDEX IF NOT EXISTS ix_cita_fecha
    ON clinica.cita (fecha_hora);

-- Citas atendidas por médico y especialidad (preguntas 10 y 14).
-- Parcial: solo indexa el ~73 % de las filas que interesa.
CREATE INDEX IF NOT EXISTS ix_cita_medico_esp_atendida
    ON clinica.cita (id_medico, id_especialidad)
    WHERE estado = 'atendida';

-- Historial de citas de un paciente (pregunta 15). El índice único
-- uq_cita_paciente_hora no sirve aquí porque excluye las canceladas.
CREATE INDEX IF NOT EXISTS ix_cita_paciente
    ON clinica.cita (id_paciente, fecha_hora DESC);

-- Búsqueda por nombre parcial con ILIKE '%...%' (pregunta 3).
-- La expresión es EXACTAMENTE la del WHERE de la consulta: si no
-- coincide, el planificador no puede usar el índice.
CREATE INDEX IF NOT EXISTS ix_persona_nombre_trgm
    ON clinica.persona
    USING gin ((nombres || ' ' || apellido_paterno || ' ' || COALESCE(apellido_materno, ''))
               clinica.gin_trgm_ops);

-- ¿Este medicamento se ha recetado alguna vez? (pregunta 9)
CREATE INDEX IF NOT EXISTS ix_receta_linea_medicamento
    ON clinica.receta_linea (id_medicamento);

-- Lotes por vencer (pregunta 12, v_lote_por_vencer)
CREATE INDEX IF NOT EXISTS ix_lote_vencimiento
    ON clinica.lote (fecha_vencimiento);

-- Existencias de una sede (dispensación, inventario)
CREATE INDEX IF NOT EXISTS ix_existencia_sede
    ON clinica.existencia (id_sede);

-- Pagos de una factura: el trigger de pagos suma los de la factura en
-- cada INSERT; sin índice, cada pago recorrería toda la tabla.
CREATE INDEX IF NOT EXISTS ix_pago_factura
    ON clinica.pago (id_factura);

-- Facturas pendientes (v_cuentas_por_cobrar). Parcial: son pocas.
CREATE INDEX IF NOT EXISTS ix_factura_pendiente
    ON clinica.factura (fecha_emision)
    WHERE estado = 'pendiente';

-- FK sin índice que se recorren al consultar o al borrar el padre
CREATE INDEX IF NOT EXISTS ix_consulta_diagnostico_diagnostico
    ON clinica.consulta_diagnostico (id_diagnostico);
CREATE INDEX IF NOT EXISTS ix_dispensacion_detalle_lote
    ON clinica.dispensacion_detalle (id_lote);
CREATE INDEX IF NOT EXISTS ix_paciente_responsable
    ON clinica.paciente (id_responsable)
    WHERE id_responsable IS NOT NULL;

-- Estadísticas al día para que el planificador estime bien tras la carga
ANALYZE;
