-- Clínica Vida Plena — Consultas del proyecto (preguntas 1 a 15)
-- Ejecutar después de 01_schema.sql y 02_datos_ejemplo.sql.
-- Las muestras son ilustrativas; el resultado real depende de los datos
-- cargados y, en consultas con CURRENT_DATE, de la fecha de ejecución.

-- ================================================================
-- Pregunta 1: ¿Qué citas tiene una sede en un rango de fechas, de la más
-- próxima a la más lejana?
-- WHERE filtra por sede y BETWEEN por intervalo; ORDER BY ordena fechas.
-- Muestra: id_cita | fecha_hora | estado | sede
-- ================================================================
SELECT c.id_cita,
       c.fecha_hora,
       c.estado,
       s.nombre AS sede
FROM clinica.cita AS c
JOIN clinica.sede AS s ON s.id_sede = c.id_sede
WHERE c.id_sede = 1
  AND c.fecha_hora BETWEEN TIMESTAMPTZ '2026-11-01 00:00:00-07'
                       AND TIMESTAMPTZ '2026-12-31 23:59:59-07'
ORDER BY c.fecha_hora ASC;

-- ================================================================
-- Pregunta 2: ¿Qué pacientes no tienen aseguradora? Mostrar «Particular».
-- LEFT JOIN conserva pacientes sin aseguradora; IS NULL los selecciona;
-- COALESCE presenta la etiqueta solicitada.
-- Muestra: id_paciente | paciente | aseguradora
-- ================================================================
SELECT pa.id_persona AS id_paciente,
       p.nombres || ' ' || p.apellido_paterno AS paciente,
       COALESCE(a.nombre, 'Particular') AS aseguradora
FROM clinica.paciente AS pa
JOIN clinica.persona AS p ON p.id_persona = pa.id_persona
LEFT JOIN clinica.aseguradora AS a ON a.id_aseguradora = pa.id_aseguradora
WHERE a.id_aseguradora IS NULL
ORDER BY paciente;

-- ================================================================
-- Pregunta 3: ¿Qué pacientes coinciden con un nombre parcial, por páginas
-- de 20 y con el nombre formateado?
-- ILIKE busca sin distinguir mayúsculas; LIMIT/OFFSET implementan páginas.
-- Cambia 'ana' por el texto buscado y OFFSET 20 para la segunda página.
-- Muestra: id_paciente | nombre_formateado
-- ================================================================
SELECT pa.id_persona AS id_paciente,
       INITCAP(p.apellido_paterno || ' ' || COALESCE(p.apellido_materno || ' ', '')
               || ', ' || p.nombres) AS nombre_formateado
FROM clinica.paciente AS pa
JOIN clinica.persona AS p ON p.id_persona = pa.id_persona
WHERE (p.nombres || ' ' || p.apellido_paterno || ' ' || COALESCE(p.apellido_materno, ''))
      ILIKE '%ana%'
ORDER BY p.apellido_paterno, p.nombres
LIMIT 20 OFFSET 0;

-- ================================================================
-- Pregunta 4: ¿Qué especialidades superaron 20 citas por mes en el último año?
-- DATE_TRUNC agrupa por mes; HAVING filtra los grupos con más de 20 citas.
-- Muestra: especialidad | mes | total_citas
-- ================================================================
SELECT e.nombre AS especialidad,
       DATE_TRUNC('month', c.fecha_hora)::date AS mes,
       COUNT(*) AS total_citas
FROM clinica.cita AS c
JOIN clinica.especialidad AS e ON e.id_especialidad = c.id_especialidad
WHERE c.fecha_hora >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY e.nombre, DATE_TRUNC('month', c.fecha_hora)
HAVING COUNT(*) > 20
ORDER BY mes, total_citas DESC;

-- ================================================================
-- Pregunta 5: ¿Cuál es la agenda del día con paciente, médico, especialidad
-- y sede?
-- Los JOIN relacionan la cita con los datos de las cuatro entidades.
-- Muestra: fecha_hora | paciente | medico | especialidad | sede | estado
-- ================================================================
SELECT c.fecha_hora,
       pp.nombres || ' ' || pp.apellido_paterno AS paciente,
       pm.nombres || ' ' || pm.apellido_paterno AS medico,
       e.nombre AS especialidad,
       s.nombre AS sede,
       c.estado
FROM clinica.cita AS c
JOIN clinica.paciente AS pa ON pa.id_persona = c.id_paciente
JOIN clinica.persona AS pp ON pp.id_persona = pa.id_persona
JOIN clinica.medico AS m ON m.id_persona = c.id_medico
JOIN clinica.persona AS pm ON pm.id_persona = m.id_persona
JOIN clinica.especialidad AS e ON e.id_especialidad = c.id_especialidad
JOIN clinica.sede AS s ON s.id_sede = c.id_sede
WHERE c.fecha_hora >= CURRENT_DATE
  AND c.fecha_hora < CURRENT_DATE + INTERVAL '1 day'
ORDER BY c.fecha_hora;

-- ================================================================
-- Pregunta 6: ¿Cuántas citas tuvo cada médico este mes, incluidos los que
-- no tuvieron ninguna?
-- LEFT JOIN conserva todos los médicos; COUNT(id_cita) da cero sin coincidencia.
-- Las condiciones del mes van en ON para no eliminar médicos sin citas.
-- Muestra: id_medico | medico | citas_mes
-- ================================================================
SELECT m.id_persona AS id_medico,
       p.nombres || ' ' || p.apellido_paterno AS medico,
       COUNT(c.id_cita) AS citas_mes
FROM clinica.medico AS m
JOIN clinica.persona AS p ON p.id_persona = m.id_persona
LEFT JOIN clinica.cita AS c
       ON c.id_medico = m.id_persona
      AND c.fecha_hora >= DATE_TRUNC('month', CURRENT_DATE)
      AND c.fecha_hora < DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
GROUP BY m.id_persona, p.nombres, p.apellido_paterno
ORDER BY citas_mes DESC, medico;

-- ================================================================
-- Pregunta 7: ¿Cuántas citas hubo por cada combinación de sede y especialidad,
-- incluidas las que suman cero?
-- CROSS JOIN crea todas las combinaciones; LEFT JOIN agrega las citas existentes.
-- Muestra: sede | especialidad | citas
-- ================================================================
SELECT s.nombre AS sede,
       e.nombre AS especialidad,
       COUNT(c.id_cita) AS citas
FROM clinica.sede AS s
CROSS JOIN clinica.especialidad AS e
LEFT JOIN clinica.cita AS c
       ON c.id_sede = s.id_sede
      AND c.id_especialidad = e.id_especialidad
GROUP BY s.nombre, e.nombre
ORDER BY s.nombre, e.nombre;

-- ================================================================
-- Preguntas 8 a 15

-- ================================================================
-- Pregunta 8: ¿Qué pacientes menores tienen responsable, y quién es?
-- Self join: id_responsable referencia a otra fila de paciente.
-- La condición de edad se calcula a la fecha actual.
-- Muestra: paciente | fecha_nacimiento | responsable
--          Emiliano Castro Valenzuela | 2016-04-10 | Ana Sofía Valenzuela Torres
-- ================================================================
SELECT menor.id_persona AS id_paciente,
       pm.nombres || ' ' || pm.apellido_paterno || ' ' || COALESCE(pm.apellido_materno, '') AS paciente,
       pm.fecha_nacimiento,
       pr.nombres || ' ' || pr.apellido_paterno || ' ' || COALESCE(pr.apellido_materno, '') AS responsable
FROM clinica.paciente AS menor
JOIN clinica.persona AS pm ON pm.id_persona = menor.id_persona
JOIN clinica.paciente AS responsable ON responsable.id_persona = menor.id_responsable
JOIN clinica.persona AS pr ON pr.id_persona = responsable.id_persona
WHERE pm.fecha_nacimiento > CURRENT_DATE - INTERVAL '18 years'
ORDER BY pm.fecha_nacimiento DESC;

-- ================================================================
-- Pregunta 9: ¿Qué medicamentos del catálogo nunca se han recetado?
-- NOT EXISTS descarta medicamentos para los que no existe ninguna línea
-- de receta, sin duplicar medicamentos aunque aparezcan en varias recetas.
-- Muestra: id_medicamento | medicamento | presentación | concentración
-- ================================================================
SELECT m.id_medicamento,
       m.nombre AS medicamento,
       m.presentacion,
       m.concentracion
FROM clinica.medicamento AS m
WHERE NOT EXISTS (
    SELECT 1
    FROM clinica.receta_linea AS rl
    WHERE rl.id_medicamento = m.id_medicamento
)
ORDER BY m.nombre, m.presentacion;

-- ================================================================
-- Pregunta 10: ¿Qué médicos facturan más que el promedio de su especialidad?
-- Primero se suma el subtotal de las facturas de consultas atendidas por
-- médico y especialidad; luego se compara cada médico con el promedio de
-- esos totales dentro de la misma especialidad.
-- Muestra: especialidad | médico | total_facturado | promedio_especialidad
-- ================================================================
WITH facturacion_medico AS (
    SELECT me.id_especialidad,
           me.id_medico,
           COALESCE(SUM(f.subtotal), 0) AS total_facturado
    FROM clinica.medico_especialidad AS me
    LEFT JOIN clinica.cita AS ci
      ON ci.id_medico = me.id_medico
     AND ci.id_especialidad = me.id_especialidad
     AND ci.estado = 'atendida'
    LEFT JOIN clinica.consulta AS co ON co.id_cita = ci.id_cita
    LEFT JOIN clinica.factura AS f ON f.id_consulta = co.id_consulta
    GROUP BY me.id_especialidad, me.id_medico
)
SELECT e.nombre AS especialidad,
       p.nombres || ' ' || p.apellido_paterno AS medico,
       fm.total_facturado,
       ROUND(AVG(fm.total_facturado) OVER (PARTITION BY fm.id_especialidad), 2)
           AS promedio_especialidad
FROM facturacion_medico AS fm
JOIN clinica.especialidad AS e ON e.id_especialidad = fm.id_especialidad
JOIN clinica.persona AS p ON p.id_persona = fm.id_medico
WHERE fm.total_facturado > (
    SELECT AVG(fm2.total_facturado)
    FROM facturacion_medico AS fm2
    WHERE fm2.id_especialidad = fm.id_especialidad
)
ORDER BY e.nombre, fm.total_facturado DESC;

-- ================================================================
-- Pregunta 11: ¿Qué personas son empleados y pacientes a la vez?
-- INTERSECT devuelve los IDs presentes en ambos conjuntos.
-- Muestra: id_persona | nombres | apellido_paterno | tipo_empleado
--          19 | Ricardo | Salazar | medico
-- ================================================================
WITH personas_en_ambos AS (
    SELECT id_persona FROM clinica.paciente
    INTERSECT
    SELECT id_persona FROM clinica.empleado
)
SELECT p.id_persona,
       p.nombres,
       p.apellido_paterno,
       e.tipo_empleado
FROM personas_en_ambos AS x
JOIN clinica.persona AS p ON p.id_persona = x.id_persona
JOIN clinica.empleado AS e ON e.id_persona = x.id_persona
ORDER BY p.apellido_paterno, p.nombres;

-- ================================================================
-- Pregunta 12: ¿Qué lotes vencen en los próximos 90 días, por sede y stock?
-- Se incluyen lotes con existencia registrada, incluso si su stock es cero.
-- Cambia el rango si quieres incluir la fecha de hoy o excluir lotes agotados.
-- Muestra: sede | medicamento | lote | vencimiento | stock
-- ================================================================
SELECT s.nombre AS sede,
       m.nombre AS medicamento,
       l.numero_lote,
       l.fecha_vencimiento,
       ex.stock
FROM clinica.lote AS l
JOIN clinica.medicamento AS m ON m.id_medicamento = l.id_medicamento
JOIN clinica.existencia AS ex ON ex.id_lote = l.id_lote
JOIN clinica.sede AS s ON s.id_sede = ex.id_sede
WHERE l.fecha_vencimiento >= CURRENT_DATE
  AND l.fecha_vencimiento < CURRENT_DATE + 90
ORDER BY l.fecha_vencimiento, s.nombre, m.nombre;

-- ================================================================
-- Pregunta 13: ¿Cómo cambian las citas por especialidad entre este mes y el
-- anterior, incluidas las que solo aparecen en uno de los dos meses?
-- Los CTE generan el conteo mensual; FULL OUTER JOIN conserva las
-- especialidades que solo tienen citas en uno de los periodos.
-- Muestra: especialidad | citas_mes_anterior | citas_mes_actual | diferencia
-- ================================================================
WITH limites AS (
    SELECT DATE_TRUNC('month', CURRENT_DATE)::date AS inicio_actual,
           (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month')::date AS inicio_anterior
), conteos AS (
    SELECT ci.id_especialidad,
           DATE_TRUNC('month', ci.fecha_hora)::date AS mes,
           COUNT(*) AS total_citas
    FROM clinica.cita AS ci
    CROSS JOIN limites AS l
    WHERE ci.fecha_hora >= l.inicio_anterior
      AND ci.fecha_hora < l.inicio_actual + INTERVAL '1 month'
    GROUP BY ci.id_especialidad, DATE_TRUNC('month', ci.fecha_hora)::date
), anterior AS (
    SELECT c.id_especialidad, c.total_citas
    FROM conteos AS c CROSS JOIN limites AS l
    WHERE c.mes = l.inicio_anterior
), actual AS (
    SELECT c.id_especialidad, c.total_citas
    FROM conteos AS c CROSS JOIN limites AS l
    WHERE c.mes = l.inicio_actual
)
SELECT e.nombre AS especialidad,
       COALESCE(a.total_citas, 0) AS citas_mes_anterior,
       COALESCE(h.total_citas, 0) AS citas_mes_actual,
       COALESCE(h.total_citas, 0) - COALESCE(a.total_citas, 0) AS diferencia
FROM anterior AS a
FULL OUTER JOIN actual AS h ON h.id_especialidad = a.id_especialidad
JOIN clinica.especialidad AS e
  ON e.id_especialidad = COALESCE(a.id_especialidad, h.id_especialidad)
ORDER BY e.nombre;

-- ================================================================
-- Pregunta 14: ¿Cuál es el ranking de médicos por citas atendidas dentro de
-- cada especialidad?
-- DENSE_RANK asigna el mismo puesto a los empates y no deja huecos en el
-- ranking. Se incluyen también médicos con cero citas atendidas.
-- Muestra: especialidad | puesto | médico | citas_atendidas
-- ================================================================
WITH citas_medico AS (
    SELECT me.id_especialidad,
           me.id_medico,
           COUNT(ci.id_cita) AS citas_atendidas
    FROM clinica.medico_especialidad AS me
    LEFT JOIN clinica.cita AS ci
      ON ci.id_medico = me.id_medico
     AND ci.id_especialidad = me.id_especialidad
     AND ci.estado = 'atendida'
    GROUP BY me.id_especialidad, me.id_medico
)
SELECT e.nombre AS especialidad,
       DENSE_RANK() OVER (
           PARTITION BY cm.id_especialidad
           ORDER BY cm.citas_atendidas DESC
       ) AS puesto,
       p.nombres || ' ' || p.apellido_paterno AS medico,
       cm.citas_atendidas
FROM citas_medico AS cm
JOIN clinica.especialidad AS e ON e.id_especialidad = cm.id_especialidad
JOIN clinica.persona AS p ON p.id_persona = cm.id_medico
ORDER BY e.nombre, puesto, medico;

-- ================================================================
-- Pregunta 15: ¿Cuál fue la última consulta de cada paciente?
-- ROW_NUMBER ordena las consultas de cada paciente de más reciente a más
-- antigua; se conserva la primera. Los pacientes sin consulta no aparecen.
-- Muestra: paciente | fecha_consulta | motivo | médico | especialidad
-- ================================================================
WITH consultas_ordenadas AS (
    SELECT ci.id_paciente,
           co.id_consulta,
           co.registrada_en,
           co.motivo,
           ci.id_medico,
           ci.id_especialidad,
           ROW_NUMBER() OVER (
               PARTITION BY ci.id_paciente
               ORDER BY co.registrada_en DESC, co.id_consulta DESC
           ) AS numero
    FROM clinica.consulta AS co
    JOIN clinica.cita AS ci ON ci.id_cita = co.id_cita
)
SELECT p.nombres || ' ' || p.apellido_paterno AS paciente,
       q.registrada_en AS fecha_consulta,
       q.motivo,
       pm.nombres || ' ' || pm.apellido_paterno AS medico,
       e.nombre AS especialidad
FROM consultas_ordenadas AS q
JOIN clinica.persona AS p ON p.id_persona = q.id_paciente
JOIN clinica.persona AS pm ON pm.id_persona = q.id_medico
JOIN clinica.especialidad AS e ON e.id_especialidad = q.id_especialidad
WHERE q.numero = 1
ORDER BY paciente;
