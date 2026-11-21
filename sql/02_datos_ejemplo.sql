-- =====================================================================
--  Clínica Vida Plena — Datos de ejemplo (PostgreSQL)
--  Ejecutar después de 01_schema.sql
--
--  El script es re-ejecutable: vacía las tablas, inserta los datos con
--  IDs explícitos (para que las referencias sean fáciles de leer) y al
--  final reajusta las secuencias IDENTITY.
-- =====================================================================

BEGIN;

TRUNCATE
    clinica.pago, clinica.factura_linea, clinica.factura,
    clinica.dispensacion_detalle, clinica.dispensacion,
    clinica.receta_linea, clinica.receta,
    clinica.existencia, clinica.lote, clinica.medicamento,
    clinica.consulta_diagnostico, clinica.diagnostico, clinica.consulta,
    clinica.cita, clinica.horario, clinica.medico_especialidad, clinica.especialidad,
    clinica.farmaceutico, clinica.recepcionista, clinica.medico, clinica.empleado,
    clinica.paciente, clinica.aseguradora, clinica.persona, clinica.sede
RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------
--  Sedes
-- ---------------------------------------------------------------------
INSERT INTO clinica.sede (id_sede, nombre, direccion, telefono) VALUES
    (1, 'Vida Plena Centro', 'Blvd. Hidalgo 245, Col. Centro, Hermosillo, Son.',          '662-210-4500'),
    (2, 'Vida Plena Norte',  'Blvd. Colosio 1820, Col. Pitic, Hermosillo, Son.',           '662-218-7731'),
    (3, 'Vida Plena Sur',    'Blvd. Solidaridad 3105, Col. Las Quintas, Hermosillo, Son.', '662-260-1190');

-- ---------------------------------------------------------------------
--  Aseguradoras (nombres ficticios)
-- ---------------------------------------------------------------------
INSERT INTO clinica.aseguradora (id_aseguradora, nombre, telefono) VALUES
    (1, 'Seguros Monarca',           '800-111-2200'),
    (2, 'Aseguradora del Pacífico',  '800-333-4400'),
    (3, 'Salud Integral SA',         '800-555-6600'),
    (4, 'Protección Médica Norte',   NULL);

-- ---------------------------------------------------------------------
--  Personas
--    1–18  pacientes
--    19–24 médicos
--    25–27 recepcionistas
--    28–30 farmacéuticos
-- ---------------------------------------------------------------------
INSERT INTO clinica.persona
    (id_persona, documento, nombres, apellido_paterno, apellido_materno,
     fecha_nacimiento, sexo, telefono, email, direccion) VALUES
    ( 1, 'LOOM880314MSRPRR01', 'Mariana',         'López',      'Ortega',     '1988-03-14', 'F', '662-145-2201', 'mariana.lopez@correo.mx',     'Calle Rosales 120, Col. Centro'),
    ( 2, 'HERJ610722HSRRMS02', 'José Luis',       'Hernández',  'Ramírez',    '1961-07-22', 'M', '662-178-3302', 'jl.hernandez@correo.mx',      'Av. Juárez 45, Col. San Benito'),
    ( 3, 'VATA851102MSRLRN03', 'Ana Sofía',       'Valenzuela', 'Torres',     '1985-11-02', 'F', '662-190-4403', 'anasofia.vt@correo.mx',       'Calle Olivos 88, Col. Los Arcos'),
    ( 4, 'MOCG920530MSRRSB04', 'Gabriela',        'Moreno',     'Castro',     '1992-05-30', 'F', '662-133-5504', 'gaby.moreno@correo.mx',       'Calle Reforma 310, Col. Modelo'),
    ( 5, 'DUFC790909HSRRLR05', 'Carlos Alberto',  'Duarte',     'Félix',      '1979-09-09', 'M', '662-121-6605', 'carlos.duarte@correo.mx',     'Calle Pino 14, Col. Villa Satélite'),
    ( 6, 'ROLD950118HSRBGG06', 'Diego Armando',   'Robles',     'Lugo',       '1995-01-18', 'M', '662-167-7706', 'diego.robles@correo.mx',      'Calle Yáñez 501, Col. Centenario'),
    ( 7, 'GASE701205MSRSTL07', 'María Elena',     'Gastélum',   'Soto',       '1970-12-05', 'F', '662-155-8807', NULL,                          'Calle Galeana 77, Col. Centro'),
    ( 8, 'EIAR580427HSRNMB08', 'Roberto',         'Encinas',    'Amaya',      '1958-04-27', 'M', '662-142-9908', 'roberto.encinas@correo.mx',   'Calle Sufragio 230, Col. San Benito'),
    ( 9, 'IAMD010813MSRBNN09', 'Daniela',         'Ibarra',     'Montaño',    '2001-08-13', 'F', '662-188-1009', 'dani.ibarra@correo.mx',       'Calle Tamaulipas 19, Col. Pitic'),
    (10, 'AONV830219MSRCVR10', 'Verónica',        'Acosta',     'Navarro',    '1983-02-19', 'F', '662-174-2110', 'vero.acosta@correo.mx',       'Calle Sahuaro 402, Col. Las Quintas'),
    (11, 'CAPL991003HSRZXS11', 'Luis Fernando',   'Cázares',    'Peña',       '1999-10-03', 'M', '662-163-3211', 'luisf.cazares@correo.mx',     NULL),
    (12, 'BORH740611HSRJSC12', 'Héctor Manuel',   'Bojórquez',  'Ríos',       '1974-06-11', 'M', '662-149-4312', 'hector.bojorquez@correo.mx',  'Calle Mina 66, Col. Balderrama'),
    (13, 'MOVR520308MSRLGS13', 'Rosa Isela',      'Molina',     'Vega',       '1952-03-08', 'F', '662-212-5413', NULL,                          'Calle Garmendia 150, Col. Centro'),
    (14, 'TACA901224HSRPRL14', 'Alejandro',       'Tapia',      'Corral',     '1990-12-24', 'M', '662-136-6514', 'alex.tapia@correo.mx',        'Calle Nogal 8, Col. Valle Verde'),
    (15, 'UILP680715HSRRYT15', 'Patricio',        'Urías',      'Leyva',      '1968-07-15', 'M', '662-171-7615', 'patricio.urias@correo.mx',    'Calle Matamoros 290, Col. El Ranchito'),
    (16, 'CAVE160410HSRSLM16', 'Emiliano',        'Castro',     'Valenzuela', '2016-04-10', 'M', NULL,           NULL,                          'Calle Olivos 88, Col. Los Arcos'),
    (17, 'CAVV190925MSRSLL17', 'Valentina',       'Castro',     'Valenzuela', '2019-09-25', 'F', NULL,           NULL,                          'Calle Olivos 88, Col. Los Arcos'),
    (18, 'DULR120214MSRRZG18', 'Regina',          'Duarte',     'Lizárraga',  '2012-02-14', 'F', NULL,           NULL,                          'Calle Pino 14, Col. Villa Satélite'),
    (19, 'SAMR750830HSRLRC19', 'Ricardo',         'Salazar',    'Murrieta',   '1975-08-30', 'M', '662-200-1119', 'r.salazar@vidaplena.mx',      'Calle Encinas 35, Col. Pitic'),
    (20, 'MEAL820117MSRNGR20', 'Laura',           'Méndez',     'Aguilar',    '1982-01-17', 'F', '662-200-1120', 'l.mendez@vidaplena.mx',       'Calle Chihuahua 12, Col. San Benito'),
    (21, 'OABF690504HSRCSR21', 'Fernando',        'Ochoa',      'Bustamante', '1969-05-04', 'M', '662-200-1121', 'f.ochoa@vidaplena.mx',        NULL),
    (22, 'RUEP771021MSRZSL22', 'Patricia',        'Ruiz',       'Esquer',     '1977-10-21', 'F', '662-200-1122', 'p.ruiz@vidaplena.mx',         NULL),
    (23, 'VICA860312HSRLNN23', 'Andrés',          'Villa',      'Contreras',  '1986-03-12', 'M', '662-200-1123', 'a.villa@vidaplena.mx',        NULL),
    (24, 'QUSJ801129HSRNVR24', 'Jorge',           'Quintero',   'Saavedra',   '1980-11-29', 'M', '662-200-1124', 'j.quintero@vidaplena.mx',     NULL),
    (25, 'ROFC940606MSRMLL25', 'Claudia',         'Romero',     'Félix',      '1994-06-06', 'F', '662-200-1125', 'c.romero@vidaplena.mx',       NULL),
    (26, 'YOLB970223MSRCLR26', 'Brenda',          'Yocupicio',  'Leal',       '1997-02-23', 'F', '662-200-1126', 'b.yocupicio@vidaplena.mx',    NULL),
    (27, 'GAOM910914HSRLCR27', 'Martín',          'Galaz',      'Ochoa',      '1991-09-14', 'M', '662-200-1127', 'm.galaz@vidaplena.mx',        NULL),
    (28, 'PERK890402MSRRZR28', 'Karla Elizabeth', 'Peralta',    'Ruiz',       '1989-04-02', 'F', '662-200-1128', 'k.peralta@vidaplena.mx',      NULL),
    (29, 'VAMO871212HSRLRS29', 'Óscar',           'Valdez',     'Moreno',     '1987-12-12', 'M', '662-200-1129', 'o.valdez@vidaplena.mx',       NULL),
    (30, 'AICT840707MSRRMR30', 'Teresa',          'Arvizu',     'Campa',      '1984-07-07', 'F', '662-200-1130', 't.arvizu@vidaplena.mx',       NULL);

-- ---------------------------------------------------------------------
--  Pacientes
--    Los responsables se insertan antes que los menores (FK a paciente).
-- ---------------------------------------------------------------------
INSERT INTO clinica.paciente
    (id_persona, id_responsable, id_aseguradora, numero_poliza, porcentaje_cobertura, fecha_registro) VALUES
    ( 1, NULL, 1,    'MON-458812',  80.00, '2024-02-10'),
    ( 2, NULL, 2,    'PAC-102934',  70.00, '2023-08-15'),
    ( 3, NULL, 1,    'MON-771203',  90.00, '2022-11-03'),
    ( 4, NULL, NULL, NULL,          NULL,  '2025-01-20'),
    ( 5, NULL, 3,    'SIN-330021',  60.00, '2023-05-09'),
    ( 6, NULL, NULL, NULL,          NULL,  '2026-10-01'),
    ( 7, NULL, 4,    'PMN-009871',  50.00, '2024-07-30'),
    ( 8, NULL, 2,    'PAC-118450',  70.00, '2021-03-17'),
    ( 9, NULL, NULL, NULL,          NULL,  '2026-10-20'),
    (10, NULL, 3,    'SIN-345566',  60.00, '2025-09-12'),
    (11, NULL, NULL, NULL,          NULL,  '2026-10-28'),
    (12, NULL, 1,    'MON-562290',  80.00, '2024-12-05'),
    (13, NULL, 4,    'PMN-011234',  75.00, '2022-06-21'),
    (14, NULL, NULL, NULL,          NULL,  '2026-11-05'),
    (15, NULL, 2,    'PAC-130077',  70.00, '2025-03-02'),
    (19, NULL, NULL, NULL,          NULL,  '2026-11-01'),   -- el Dr. Salazar también es paciente
    -- Menores: usan la póliza de su responsable
    (16, 3,    1,    'MON-771203',  90.00, '2022-11-03'),
    (17, 3,    1,    'MON-771203',  90.00, '2022-11-03'),
    (18, 5,    3,    'SIN-330021',  60.00, '2023-05-09');

-- ---------------------------------------------------------------------
--  Empleados y sus subtipos
-- ---------------------------------------------------------------------
INSERT INTO clinica.empleado (id_persona, numero_empleado, tipo_empleado, fecha_contratacion, activo) VALUES
    (19, 'EMP-0001', 'medico',        '2015-03-01', true),
    (20, 'EMP-0002', 'medico',        '2016-08-15', true),
    (21, 'EMP-0003', 'medico',        '2014-01-10', true),
    (22, 'EMP-0004', 'medico',        '2018-05-02', true),
    (23, 'EMP-0005', 'medico',        '2021-02-01', true),
    (24, 'EMP-0006', 'medico',        '2019-09-16', true),
    (25, 'EMP-0007', 'recepcionista', '2020-06-01', true),
    (26, 'EMP-0008', 'recepcionista', '2023-01-09', true),
    (27, 'EMP-0009', 'recepcionista', '2022-04-18', true),
    (28, 'EMP-0010', 'farmaceutico',  '2017-11-20', true),
    (29, 'EMP-0011', 'farmaceutico',  '2019-02-04', true),
    (30, 'EMP-0012', 'farmaceutico',  '2018-07-23', true);

INSERT INTO clinica.medico (id_persona, cedula_profesional) VALUES
    (19, '4587123'),
    (20, '5123987'),
    (21, '3398451'),
    (22, '6012478'),
    (23, '9874512'),
    (24, '7741236');

INSERT INTO clinica.recepcionista (id_persona, id_sede) VALUES
    (25, 1),
    (26, 2),
    (27, 3);

INSERT INTO clinica.farmaceutico (id_persona, id_sede, licencia_sanitaria) VALUES
    (28, 1, 'COFEPRIS-SON-1187'),
    (29, 2, 'COFEPRIS-SON-1342'),
    (30, 3, 'COFEPRIS-SON-1590');

-- ---------------------------------------------------------------------
--  Especialidades, médico–especialidad y horarios
-- ---------------------------------------------------------------------
INSERT INTO clinica.especialidad (id_especialidad, nombre, precio_consulta) VALUES
    (1, 'Medicina General', 500.00),
    (2, 'Pediatría',        650.00),
    (3, 'Cardiología',      900.00),
    (4, 'Ginecología',      800.00),
    (5, 'Dermatología',     750.00),
    (6, 'Traumatología',    850.00);

INSERT INTO clinica.medico_especialidad (id_medico, id_especialidad) VALUES
    (19, 1),            -- Salazar: Medicina General
    (20, 2), (20, 1),   -- Méndez: Pediatría y Medicina General
    (21, 3),            -- Ochoa: Cardiología
    (22, 4),            -- Ruiz: Ginecología
    (23, 5),            -- Villa: Dermatología
    (24, 6), (24, 1);   -- Quintero: Traumatología y Medicina General

-- dia_semana: 1 = lunes … 7 = domingo (ISODOW)
INSERT INTO clinica.horario (id_horario, id_medico, id_sede, dia_semana, hora_inicio, hora_fin) VALUES
    -- Salazar: Centro, lunes a viernes por la mañana
    ( 1, 19, 1, 1, '08:00', '14:00'),
    ( 2, 19, 1, 2, '08:00', '14:00'),
    ( 3, 19, 1, 3, '08:00', '14:00'),
    ( 4, 19, 1, 4, '08:00', '14:00'),
    ( 5, 19, 1, 5, '08:00', '14:00'),
    -- Méndez: Centro (lun, mié, vie) y Norte (mar, jue por la tarde)
    ( 6, 20, 1, 1, '09:00', '13:00'),
    ( 7, 20, 1, 3, '09:00', '13:00'),
    ( 8, 20, 1, 5, '09:00', '13:00'),
    ( 9, 20, 2, 2, '15:00', '19:00'),
    (10, 20, 2, 4, '15:00', '19:00'),
    -- Ochoa: Norte (lun, mié) y Sur (vie)
    (11, 21, 2, 1, '08:00', '12:00'),
    (12, 21, 2, 3, '08:00', '12:00'),
    (13, 21, 3, 5, '08:00', '12:00'),
    -- Ruiz: Centro (mar, jue) y Sur (lun por la tarde)
    (14, 22, 1, 2, '08:00', '13:00'),
    (15, 22, 1, 4, '08:00', '13:00'),
    (16, 22, 3, 1, '14:00', '18:00'),
    -- Villa: Norte (lun, mié, vie por la tarde)
    (17, 23, 2, 1, '14:00', '18:00'),
    (18, 23, 2, 3, '14:00', '18:00'),
    (19, 23, 2, 5, '14:00', '18:00'),
    -- Quintero: Sur (mar, jue y sábado)
    (20, 24, 3, 2, '09:00', '14:00'),
    (21, 24, 3, 4, '09:00', '14:00'),
    (22, 24, 3, 6, '09:00', '13:00');

-- ---------------------------------------------------------------------
--  Citas (creada_en = 6 días antes de la cita)
-- ---------------------------------------------------------------------
INSERT INTO clinica.cita
    (id_cita, id_paciente, id_medico, id_especialidad, id_sede, fecha_hora, estado, creada_en)
SELECT v.id, v.pac, v.med, v.esp, v.sede, v.fh::timestamptz, v.estado,
       v.fh::timestamptz - INTERVAL '6 days'
FROM (VALUES
    -- Pasadas
    ( 1,  1, 19, 1, 1, '2026-10-05 09:00-07', 'atendida'),
    ( 2,  2, 21, 3, 2, '2026-10-05 10:00-07', 'atendida'),
    ( 3, 16, 20, 2, 1, '2026-10-09 09:30-07', 'atendida'),
    ( 4,  4, 22, 4, 1, '2026-10-13 08:30-07', 'atendida'),
    ( 5,  5, 23, 5, 2, '2026-10-14 15:00-07', 'atendida'),
    ( 6,  6, 24, 6, 3, '2026-10-15 10:00-07', 'atendida'),
    ( 7,  7, 19, 1, 1, '2026-10-19 11:00-07', 'no_asistio'),
    ( 8,  8, 21, 3, 3, '2026-10-23 08:00-07', 'atendida'),
    ( 9,  3, 19, 1, 1, '2026-10-26 08:30-07', 'atendida'),
    (10,  9, 20, 1, 2, '2026-10-27 16:00-07', 'atendida'),
    (11, 10, 22, 4, 3, '2026-11-02 14:30-07', 'atendida'),
    (12, 11, 23, 5, 2, '2026-11-04 16:30-07', 'cancelada'),
    (13, 12, 24, 1, 3, '2026-11-07 10:00-07', 'atendida'),
    (14, 17, 20, 2, 1, '2026-11-09 10:00-07', 'atendida'),
    (15, 13, 21, 3, 2, '2026-11-11 09:00-07', 'atendida'),
    (16, 14, 19, 1, 1, '2026-11-12 12:00-07', 'atendida'),
    (17, 19, 21, 3, 3, '2026-11-13 11:00-07', 'atendida'),
    (18, 15, 24, 6, 3, '2026-11-17 09:30-07', 'atendida'),
    (19,  2, 21, 3, 2, '2026-11-18 10:30-07', 'atendida'),
    (20, 18, 20, 2, 1, '2026-11-20 09:00-07', 'atendida'),
    -- Futuras
    (21,  1, 19, 1, 1, '2026-11-23 09:00-07', 'confirmada'),
    (22,  6, 24, 6, 3, '2026-11-24 11:00-07', 'programada'),
    (23, 11, 23, 5, 2, '2026-11-25 16:30-07', 'programada'),  -- reagendada de la cita 12
    (24,  4, 22, 4, 1, '2026-11-26 08:00-07', 'programada'),
    (25,  7, 19, 1, 1, '2026-11-27 10:30-07', 'programada'),
    (26,  9, 22, 4, 3, '2026-11-30 15:00-07', 'confirmada'),
    (27, 13, 21, 3, 2, '2026-12-02 09:00-07', 'programada'),
    (28, 16, 20, 2, 1, '2026-12-04 10:00-07', 'programada')
) AS v(id, pac, med, esp, sede, fh, estado);

-- ---------------------------------------------------------------------
--  Consultas (solo para citas 'atendida'; registrada 25 min después)
-- ---------------------------------------------------------------------
INSERT INTO clinica.consulta
    (id_consulta, id_cita, motivo, presion_sistolica, presion_diastolica,
     frecuencia_cardiaca, temperatura_c, peso_kg, talla_cm, notas_clinicas, registrada_en)
SELECT v.id, v.cita, v.motivo, v.sis, v.dia, v.fc, v.temp, v.peso, v.talla, v.notas,
       c.fecha_hora + INTERVAL '25 minutes'
FROM (VALUES
    ( 1,  1, 'Dolor de garganta y fiebre de 2 días',                      118, 76,  88, 38.2, 64.50, 162.0, 'Amígdalas hiperémicas con exudado. Se indica antibiótico.'),
    ( 2,  2, 'Control de presión arterial',                               152, 94,  78, 36.6, 88.00, 170.0, 'Hipertensión no controlada. Se ajusta tratamiento y se solicita perfil de lípidos.'),
    ( 3,  3, 'Revisión de niño sano',                                     NULL, NULL,  90, 36.5, 32.40, 138.0, 'Crecimiento y desarrollo adecuados para la edad. Esquema de vacunación completo.'),
    ( 4,  4, 'Revisión ginecológica anual',                               112, 72,  72, 36.7, 61.20, 165.0, 'Exploración normal. Se toma citología.'),
    ( 5,  5, 'Brotes de acné en rostro y espalda',                        120, 78,  70, 36.5, 82.00, 178.0, 'Acné inflamatorio moderado.'),
    ( 6,  6, 'Dolor e inflamación en tobillo derecho tras jugar fútbol',  124, 80,  84, 36.8, 76.50, 175.0, 'Esguince grado I. Reposo, hielo y vendaje.'),
    ( 7,  8, 'Seguimiento de hipertensión y glucosa elevada',             148, 92,  80, 36.6, 91.30, 168.0, 'Glucosa en ayuno 168 mg/dL. Inicia metformina.'),
    ( 8,  9, 'Ardor estomacal después de comer',                          116, 74,  76, 36.7, 63.00, 160.0, 'Dolor epigástrico sin datos de alarma.'),
    ( 9, 10, 'Congestión nasal y estornudos',                             110, 70,  74, 37.1, 58.00, 163.0, 'Cuadro viral leve.'),
    (10, 11, 'Flujo vaginal anormal y comezón',                           114, 72,  78, 36.8, 66.00, 158.0, NULL),
    (11, 13, 'Dolor en la parte baja de la espalda',                      130, 84,  76, 36.6, 95.00, 172.0, 'Contractura paravertebral lumbar.'),
    (12, 14, 'Diarrea y vómito desde ayer',                               NULL, NULL, 110, 37.8, 22.10, 121.0, 'Deshidratación leve. Hidratación oral.'),
    (13, 15, 'Palpitaciones y cansancio',                                 138, 86, 112, 36.5, 70.00, 155.0, 'ECG con fibrilación auricular. Inicia anticoagulación.'),
    (14, 16, 'Dolor de cabeza frecuente',                                 122, 80,  72, 36.6, 80.00, 180.0, 'Cefalea tensional. Se recomienda higiene del sueño.'),
    (15, 17, 'Chequeo cardiológico de rutina',                            136, 88,  70, 36.5, 85.00, 176.0, 'Presión limítrofe. Cambios en el estilo de vida.'),
    (16, 18, 'Dolor lumbar al levantar peso',                             128, 82,  74, 36.7, 90.00, 174.0, NULL),
    (17, 19, 'Seguimiento de hipertensión',                               138, 86,  74, 36.6, 87.20, 170.0, 'Mejor control con el ajuste previo.'),
    (18, 20, 'Tos y silbido en el pecho',                                 108, 68,  96, 36.9, 48.00, 158.0, 'Sibilancias espiratorias. Crisis asmática leve.')
) AS v(id, cita, motivo, sis, dia, fc, temp, peso, talla, notas)
JOIN clinica.cita c ON c.id_cita = v.cita;

-- ---------------------------------------------------------------------
--  Diagnósticos (CIE-10) y diagnósticos por consulta
-- ---------------------------------------------------------------------
INSERT INTO clinica.diagnostico (id_diagnostico, codigo_cie10, descripcion) VALUES
    ( 1, 'J00',   'Rinofaringitis aguda (resfriado común)'),
    ( 2, 'J02.9', 'Faringitis aguda, no especificada'),
    ( 3, 'I10',   'Hipertensión esencial (primaria)'),
    ( 4, 'E11.9', 'Diabetes mellitus tipo 2 sin complicaciones'),
    ( 5, 'E78.5', 'Hiperlipidemia, no especificada'),
    ( 6, 'Z00.1', 'Control de salud de rutina del niño'),
    ( 7, 'Z01.4', 'Examen ginecológico (general) (de rutina)'),
    ( 8, 'L70.0', 'Acné vulgar'),
    ( 9, 'S93.4', 'Esguince y torcedura del tobillo'),
    (10, 'K29.7', 'Gastritis, no especificada'),
    (11, 'N76.0', 'Vaginitis aguda'),
    (12, 'M54.5', 'Lumbago no especificado'),
    (13, 'A09',   'Diarrea y gastroenteritis de presunto origen infeccioso'),
    (14, 'I48',   'Fibrilación y aleteo auricular'),
    (15, 'R51',   'Cefalea'),
    (16, 'J45.9', 'Asma, no especificada'),
    (17, 'L20.9', 'Dermatitis atópica, no especificada');

INSERT INTO clinica.consulta_diagnostico (id_consulta, id_diagnostico, es_principal, observaciones) VALUES
    ( 1,  2, true,  NULL),
    ( 2,  3, true,  'Cifras tensionales elevadas'),
    ( 2,  5, false, 'Pendiente confirmar con perfil de lípidos'),
    ( 3,  6, true,  NULL),
    ( 4,  7, true,  NULL),
    ( 5,  8, true,  NULL),
    ( 6,  9, true,  'Tobillo derecho'),
    ( 7,  3, true,  NULL),
    ( 7,  4, false, 'Diagnóstico de reciente inicio'),
    ( 8, 10, true,  NULL),
    ( 9,  1, true,  NULL),
    (10, 11, true,  NULL),
    (11, 12, true,  NULL),
    (12, 13, true,  NULL),
    (13, 14, true,  NULL),
    (14, 15, true,  NULL),
    (15,  3, true,  'Hipertensión etapa 1'),
    (16, 12, true,  NULL),
    (17,  3, true,  'Controlada'),
    (18, 16, true,  NULL);

-- ---------------------------------------------------------------------
--  Medicamentos, lotes y existencias
-- ---------------------------------------------------------------------
INSERT INTO clinica.medicamento (id_medicamento, nombre, presentacion, concentracion, precio_venta, activo) VALUES
    ( 1, 'Paracetamol',          'Tabletas (caja c/10)',      '500 mg',       35.00, true),
    ( 2, 'Ibuprofeno',           'Tabletas (caja c/10)',      '400 mg',       48.00, true),
    ( 3, 'Amoxicilina',          'Cápsulas (caja c/12)',      '500 mg',       95.00, true),
    ( 4, 'Losartán',             'Tabletas (caja c/30)',      '50 mg',       120.00, true),
    ( 5, 'Metformina',           'Tabletas (caja c/30)',      '850 mg',       65.00, true),
    ( 6, 'Omeprazol',            'Cápsulas (caja c/14)',      '20 mg',        70.00, true),
    ( 7, 'Atorvastatina',        'Tabletas (caja c/30)',      '20 mg',       180.00, true),
    ( 8, 'Salbutamol',           'Inhalador',                 '100 mcg/dosis',145.00, true),
    ( 9, 'Electrolitos orales',  'Sobre',                     '27.9 g',       18.00, true),
    (10, 'Metronidazol',         'Óvulos (caja c/10)',        '500 mg',      110.00, true),
    (11, 'Peróxido de benzoilo', 'Gel (tubo 60 g)',           '5%',          160.00, true),
    (12, 'Diclofenaco',          'Gel (tubo 50 g)',           '1%',           89.00, true),
    (13, 'Paracetamol',          'Suspensión (frasco 120 ml)','160 mg/5 ml',  55.00, true),
    (14, 'Apixabán',             'Tabletas (caja c/30)',      '5 mg',        650.00, true),
    (15, 'Loratadina',           'Tabletas (caja c/10)',      '10 mg',        40.00, true),
    (16, 'Ranitidina',           'Tabletas (caja c/20)',      '150 mg',       60.00, false);  -- descontinuado

INSERT INTO clinica.lote (id_lote, id_medicamento, numero_lote, fecha_vencimiento) VALUES
    ( 1,  1, 'PAR-2405A', '2027-06-30'),
    ( 2,  1, 'PAR-2511B', '2028-01-31'),
    ( 3,  2, 'IBU-2409',  '2027-09-30'),
    ( 4,  3, 'AMX-2502',  '2027-03-31'),
    ( 5,  4, 'LOS-2501',  '2027-12-31'),
    ( 6,  4, 'LOS-2508',  '2028-08-31'),
    ( 7,  5, 'MET-2412',  '2027-11-30'),
    ( 8,  6, 'OME-2503',  '2027-02-28'),
    ( 9,  7, 'ATO-2506',  '2028-05-31'),
    (10,  8, 'SAL-2410',  '2027-10-31'),
    (11,  9, 'SUE-2505',  '2027-04-30'),
    (12, 10, 'MTZ-2501',  '2026-12-15'),   -- próximo a vencer
    (13, 11, 'PBZ-2507',  '2027-07-31'),
    (14, 12, 'DIC-2504',  '2027-04-30'),
    (15, 13, 'PSU-2502',  '2026-10-31'),   -- vencido
    (16, 13, 'PSU-2509',  '2027-09-30'),
    (17, 14, 'APX-2508',  '2028-02-29'),
    (18, 15, 'LOR-2506',  '2028-06-30'),
    (19, 16, 'RAN-2311',  '2025-11-30');   -- vencido, medicamento descontinuado

INSERT INTO clinica.existencia (id_lote, id_sede, stock, fecha_ingreso) VALUES
    -- Sede Centro
    ( 1, 1,  40, '2026-06-10'),
    ( 2, 1, 100, '2026-11-02'),
    ( 3, 1,  60, '2026-06-10'),
    ( 4, 1,  23, '2026-06-10'),
    ( 5, 1,  30, '2026-06-10'),
    ( 8, 1,  19, '2026-06-10'),
    (11, 1,  76, '2026-07-01'),
    (16, 1,  24, '2026-10-05'),
    (15, 1,   3, '2026-03-01'),
    (10, 1,  12, '2026-08-20'),
    (18, 1,  50, '2026-08-20'),
    (19, 1,   0, '2024-01-15'),
    -- Sede Norte
    ( 1, 2,  35, '2026-06-12'),
    ( 3, 2,  45, '2026-06-12'),
    ( 5, 2,  27, '2026-06-12'),
    ( 6, 2,  40, '2026-11-02'),
    ( 9, 2,  14, '2026-07-15'),
    (13, 2,   9, '2026-07-15'),
    (17, 2,   8, '2026-09-01'),
    (18, 2,  30, '2026-08-22'),
    -- Sede Sur
    ( 1, 3,  30, '2026-06-15'),
    ( 3, 3,  39, '2026-06-15'),
    ( 5, 3,  18, '2026-06-15'),
    ( 7, 3,  28, '2026-06-15'),
    (12, 3,   4, '2026-02-10'),
    (14, 3,  15, '2026-07-20'),
    (10, 3,   6, '2026-08-25');

-- ---------------------------------------------------------------------
--  Recetas (emitidas al registrar la consulta)
-- ---------------------------------------------------------------------
INSERT INTO clinica.receta (id_receta, id_consulta, fecha_emision, estado, indicaciones)
SELECT v.id, v.consulta, co.registrada_en, v.estado, v.ind
FROM (VALUES
    ( 1,  1, 'dispensada', 'Completar el tratamiento antibiótico aunque desaparezcan los síntomas.'),
    ( 2,  2, 'dispensada', 'Dieta baja en sodio. Tomar la presión en casa y anotarla.'),
    ( 3,  5, 'dispensada', 'Aplicar por la noche sobre piel limpia y seca.'),
    ( 4,  6, 'dispensada', 'Reposo relativo 5 días. Hielo 20 min cada 4 horas.'),
    ( 5,  7, 'dispensada', 'Tomar metformina con los alimentos.'),
    ( 6,  8, 'dispensada', 'Evitar irritantes, café y alcohol.'),
    ( 7,  9, 'pendiente',  NULL),
    ( 8, 10, 'dispensada', 'Evitar relaciones sexuales durante el tratamiento.'),
    ( 9, 11, 'anulada',    'Anulada: se cambió por fisioterapia.'),
    (10, 12, 'dispensada', 'Dar suero a libre demanda en tomas pequeñas.'),
    (11, 13, 'dispensada', 'No suspender sin indicación médica. Vigilar sangrados.'),
    (12, 16, 'pendiente',  'Aplicar gel 3 veces al día.'),
    (13, 17, 'pendiente',  NULL),
    (14, 18, 'pendiente',  'Usar con espaciador. Acudir a urgencias si hay dificultad para respirar.')
) AS v(id, consulta, estado, ind)
JOIN clinica.consulta co ON co.id_consulta = v.consulta;

INSERT INTO clinica.receta_linea (id_receta, numero_linea, id_medicamento, dosis, frecuencia, cantidad) VALUES
    ( 1, 1,  1, '1 tableta',      'Cada 8 horas por 3 días',             1),
    ( 1, 2,  3, '1 cápsula',      'Cada 8 horas por 7 días',             2),
    ( 2, 1,  4, '1 tableta',      'Cada 24 horas',                       1),
    ( 2, 2,  7, '1 tableta',      'Cada 24 horas por la noche',          1),
    ( 3, 1, 11, 'Capa delgada',   'Cada 24 horas por 8 semanas',         1),
    ( 4, 1,  2, '1 tableta',      'Cada 8 horas por 5 días',             1),
    ( 4, 2, 12, 'Aplicación local','Cada 8 horas',                       1),
    ( 5, 1,  4, '1 tableta',      'Cada 24 horas',                       1),
    ( 5, 2,  5, '1 tableta',      'Cada 12 horas',                       2),
    ( 6, 1,  6, '1 cápsula',      'En ayunas por 14 días',               1),
    ( 7, 1,  1, '1 tableta',      'Cada 8 horas si hay fiebre',          1),
    ( 7, 2, 15, '1 tableta',      'Cada 24 horas por 5 días',            1),
    ( 8, 1, 10, '1 óvulo',        'Cada noche por 10 días',              1),
    ( 9, 1,  2, '1 tableta',      'Cada 8 horas por 5 días',             1),
    (10, 1,  9, '1 sobre en 1 L', 'A libre demanda',                     4),
    (10, 2, 13, '7.5 ml',         'Cada 6 horas si hay fiebre',          1),
    (11, 1, 14, '1 tableta',      'Cada 12 horas',                       2),
    (12, 1, 12, 'Aplicación local','Cada 8 horas',                       1),
    (12, 2,  2, '1 tableta',      'Cada 8 horas por 5 días',             1),
    (13, 1,  4, '1 tableta',      'Cada 24 horas',                       1),
    (14, 1,  8, '2 inhalaciones', 'Cada 6 horas por 5 días',             1);

-- ---------------------------------------------------------------------
--  Dispensaciones (en la farmacia de la sede de la cita,
--  15 min después de emitida la receta)
-- ---------------------------------------------------------------------
INSERT INTO clinica.dispensacion (id_dispensacion, id_receta, id_farmaceutico, id_sede, fecha)
SELECT v.id, v.receta, v.farm, v.sede, r.fecha_emision + INTERVAL '15 minutes'
FROM (VALUES
    (1,  1, 28, 1),
    (2,  2, 29, 2),
    (3,  3, 29, 2),
    (4,  4, 30, 3),
    (5,  5, 30, 3),
    (6,  6, 28, 1),
    (7,  8, 30, 3),
    (8, 10, 28, 1),
    (9, 11, 29, 2)
) AS v(id, receta, farm, sede)
JOIN clinica.receta r ON r.id_receta = v.receta;

INSERT INTO clinica.dispensacion_detalle (id_dispensacion, id_lote, cantidad) VALUES
    (1,  1, 1),   -- Paracetamol 500 mg
    (1,  4, 2),   -- Amoxicilina
    (2,  5, 1),   -- Losartán
    (2,  9, 1),   -- Atorvastatina
    (3, 13, 1),   -- Peróxido de benzoilo
    (4,  3, 1),   -- Ibuprofeno
    (4, 14, 1),   -- Diclofenaco gel
    (5,  5, 1),   -- Losartán
    (5,  7, 2),   -- Metformina
    (6,  8, 1),   -- Omeprazol
    (7, 12, 1),   -- Metronidazol
    (8, 11, 4),   -- Electrolitos orales
    (8, 16, 1),   -- Paracetamol suspensión (lote vigente, no el vencido)
    (9, 17, 2);   -- Apixabán

-- ---------------------------------------------------------------------
--  Facturas
--    1) Se crea el encabezado con la cobertura del paciente.
--    2) Se insertan las líneas (consulta + medicamentos dispensados).
--    3) Se calculan los totales a partir de las líneas.
--    4) Se registran los pagos.
--    5) Se calculan saldo y estado a partir de los pagos.
-- ---------------------------------------------------------------------
INSERT INTO clinica.factura
    (id_factura, id_consulta, id_aseguradora, fecha_emision, porcentaje_cobertura)
SELECT co.id_consulta, co.id_consulta, p.id_aseguradora,
       co.registrada_en + INTERVAL '30 minutes',
       COALESCE(p.porcentaje_cobertura, 0)
FROM clinica.consulta co
JOIN clinica.cita     ci ON ci.id_cita = co.id_cita
JOIN clinica.paciente p  ON p.id_persona = ci.id_paciente
ORDER BY co.id_consulta;

-- Línea 1 de cada factura: la consulta, al precio de la especialidad
INSERT INTO clinica.factura_linea (id_factura, numero_linea, concepto, id_medicamento, cantidad, precio_unitario)
SELECT f.id_factura, 1, 'consulta', NULL, 1, e.precio_consulta
FROM clinica.factura      f
JOIN clinica.consulta     co ON co.id_consulta = f.id_consulta
JOIN clinica.cita         ci ON ci.id_cita = co.id_cita
JOIN clinica.especialidad e  ON e.id_especialidad = ci.id_especialidad;

-- Medicamentos dispensados en la clínica
INSERT INTO clinica.factura_linea (id_factura, numero_linea, concepto, id_medicamento, cantidad, precio_unitario) VALUES
    ( 1, 2, 'medicamento',  1, 1,  35.00),
    ( 1, 3, 'medicamento',  3, 2,  95.00),
    ( 2, 2, 'medicamento',  4, 1, 120.00),
    ( 2, 3, 'medicamento',  7, 1, 180.00),
    ( 5, 2, 'medicamento', 11, 1, 160.00),
    ( 6, 2, 'medicamento',  2, 1,  48.00),
    ( 6, 3, 'medicamento', 12, 1,  89.00),
    ( 7, 2, 'medicamento',  4, 1, 120.00),
    ( 7, 3, 'medicamento',  5, 2,  65.00),
    ( 8, 2, 'medicamento',  6, 1,  70.00),
    (10, 2, 'medicamento', 10, 1, 110.00),
    (12, 2, 'medicamento',  9, 4,  18.00),
    (12, 3, 'medicamento', 13, 1,  55.00),
    (13, 2, 'medicamento', 14, 2, 650.00);

-- Totales: subtotal = suma de líneas; el seguro cubre su porcentaje
UPDATE clinica.factura f
SET subtotal       = t.total,
    monto_seguro   = ROUND(t.total * f.porcentaje_cobertura / 100, 2),
    monto_paciente = t.total - ROUND(t.total * f.porcentaje_cobertura / 100, 2),
    saldo          = t.total - ROUND(t.total * f.porcentaje_cobertura / 100, 2)
FROM (SELECT id_factura, SUM(importe) AS total
      FROM clinica.factura_linea
      GROUP BY id_factura) t
WHERE t.id_factura = f.id_factura;

-- Pagos que liquidan la parte del paciente en una sola exhibición
INSERT INTO clinica.pago (id_pago, id_factura, fecha, monto, metodo, referencia, id_recepcionista)
SELECT v.id, f.id_factura, f.fecha_emision + INTERVAL '5 minutes', f.monto_paciente,
       v.metodo, v.ref, v.recep
FROM (VALUES
    ( 1,  1, 'tarjeta',       'TJ-884120', 25),
    ( 2,  2, 'efectivo',      NULL,        26),
    ( 3,  3, 'efectivo',      NULL,        25),
    ( 4,  4, 'tarjeta',       'TJ-884377', 25),
    ( 5,  5, 'transferencia', 'SPEI-55102',26),
    ( 6,  6, 'efectivo',      NULL,        27),
    ( 7,  7, 'tarjeta',       'TJ-885010', 27),
    ( 8,  8, 'efectivo',      NULL,        25),
    ( 9, 10, 'tarjeta',       'TJ-886245', 27),
    (10, 11, 'efectivo',      NULL,        27),
    (11, 12, 'transferencia', 'SPEI-56877',25),
    (12, 14, 'tarjeta',       'TJ-887731', 25),
    (13, 15, 'efectivo',      NULL,        27),
    (14, 16, 'tarjeta',       'TJ-888102', 27)
) AS v(id, factura, metodo, ref, recep)
JOIN clinica.factura f ON f.id_factura = v.factura;

-- Pagos parciales / en varias exhibiciones
INSERT INTO clinica.pago (id_pago, id_factura, fecha, monto, metodo, referencia, id_recepcionista) VALUES
    -- Factura 9 (sin seguro, $500): se paga en dos partes el mismo día
    (15,  9, '2026-10-27 17:00-07', 200.00, 'efectivo',      NULL,         26),
    (16,  9, '2026-10-27 17:02-07', 300.00, 'tarjeta',       'TJ-885590',  26),
    -- Factura 13: abono parcial, queda saldo pendiente
    (17, 13, '2026-11-11 10:10-07', 300.00, 'efectivo',      NULL,         26),
    -- Factura 17: abono parcial, queda saldo pendiente
    (18, 17, '2026-11-18 11:40-07', 100.00, 'transferencia', 'SPEI-58014', 26);
    -- La factura 18 (consulta de hoy) aún no tiene pagos.

-- Saldo y estado según lo pagado
UPDATE clinica.factura f
SET saldo  = f.monto_paciente - t.pagado,
    estado = CASE WHEN f.monto_paciente - t.pagado = 0
                  THEN 'pagada' ELSE 'pendiente' END
FROM (SELECT fa.id_factura, COALESCE(SUM(pa.monto), 0) AS pagado
      FROM clinica.factura fa
      LEFT JOIN clinica.pago pa ON pa.id_factura = fa.id_factura
      GROUP BY fa.id_factura) t
WHERE t.id_factura = f.id_factura;

-- ---------------------------------------------------------------------
--  Reajustar las secuencias IDENTITY para que los siguientes INSERT
--  sin ID continúen después de los datos de ejemplo
-- ---------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('clinica.sede',         'id_sede'),         (SELECT MAX(id_sede)         FROM clinica.sede));
SELECT setval(pg_get_serial_sequence('clinica.persona',      'id_persona'),      (SELECT MAX(id_persona)      FROM clinica.persona));
SELECT setval(pg_get_serial_sequence('clinica.aseguradora',  'id_aseguradora'),  (SELECT MAX(id_aseguradora)  FROM clinica.aseguradora));
SELECT setval(pg_get_serial_sequence('clinica.especialidad', 'id_especialidad'), (SELECT MAX(id_especialidad) FROM clinica.especialidad));
SELECT setval(pg_get_serial_sequence('clinica.horario',      'id_horario'),      (SELECT MAX(id_horario)      FROM clinica.horario));
SELECT setval(pg_get_serial_sequence('clinica.cita',         'id_cita'),         (SELECT MAX(id_cita)         FROM clinica.cita));
SELECT setval(pg_get_serial_sequence('clinica.consulta',     'id_consulta'),     (SELECT MAX(id_consulta)     FROM clinica.consulta));
SELECT setval(pg_get_serial_sequence('clinica.diagnostico',  'id_diagnostico'),  (SELECT MAX(id_diagnostico)  FROM clinica.diagnostico));
SELECT setval(pg_get_serial_sequence('clinica.medicamento',  'id_medicamento'),  (SELECT MAX(id_medicamento)  FROM clinica.medicamento));
SELECT setval(pg_get_serial_sequence('clinica.lote',         'id_lote'),         (SELECT MAX(id_lote)         FROM clinica.lote));
SELECT setval(pg_get_serial_sequence('clinica.receta',       'id_receta'),       (SELECT MAX(id_receta)       FROM clinica.receta));
SELECT setval(pg_get_serial_sequence('clinica.dispensacion', 'id_dispensacion'), (SELECT MAX(id_dispensacion) FROM clinica.dispensacion));
SELECT setval(pg_get_serial_sequence('clinica.factura',      'id_factura'),      (SELECT MAX(id_factura)      FROM clinica.factura));
SELECT setval(pg_get_serial_sequence('clinica.pago',         'id_pago'),         (SELECT MAX(id_pago)         FROM clinica.pago));

COMMIT;
