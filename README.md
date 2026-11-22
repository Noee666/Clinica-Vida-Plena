# Clínica Vida Plena — Base de datos

Proyecto final de Bases de Datos. Diseño e implementación en **PostgreSQL** de una base de datos única, que hoy maneja citas, recetas, farmacia y cobros en hojas de cálculo separadas. El objetivo es eliminar las citas duplicadas, los medicamentos vencidos y las facturas sin cobrar, y dar servicio a todas sus sedes.

Todo el proyecto se reconstruye en una base vacía con un solo comando:

```bash
psql -U postgres -d clinica -f ejecutar_todo.sql
```

---

## Integrantes y reparto de trabajo

| # | Integrante | Responsabilidad | Archivos |
|---|---|---|---|
| 1 | _Torres Gonzalez Gael Andres_ | Modelado E-R, esquema relacional, normalización | `docs/normalizacion.md`, `sql/08_transacciones.sql` |
| 2 | _Montesinos Romero Maria Camila_ | Esquema y datos de prueba | `sql/01_esquema.sql`, `sql/02_datos.sql` |
| 3 | _Escobedo Ayala Andres Manuel_ | Consultas 7–15, vistas, índices y rendimiento | `sql/07_consultas.sql` (7–15), `sql/03_vistas_indices.sql` |
| 4 | _Cornejo Silva Martin Noe_ | Funciones, triggers, transacciones, concurrencia y repositorio en git | `sql/04_funciones_procedimientos.sql`, `sql/05_triggers.sql` |
| 5 | _Ibarra Lopez Danna Alejandra_ | Seguridad, respaldo, integración y README | `sql/06_seguridad.sql`, `respaldo/clinica.dump`, `ejecutar_todo.sql`, `sql/07_consultas.sql` (1–6) |

---

## Requisitos

- **PostgreSQL 14 o superior** (servidor y herramientas de cliente `psql`, `pg_dump`, `pg_restore`, `createdb`). El proyecto se probó completo en PostgreSQL 16.
- Extensión **`pg_trgm`** (incluida en PostgreSQL), usada por el índice de búsqueda de pacientes por nombre. Crearla requiere permisos de superusuario o de dueño de la base.
- Opcional: **DataGrip** u otro cliente gráfico para explorar la base.

---

## Instalación

Los comandos se ejecutan desde la **raíz del repositorio**, porque `ejecutar_todo.sql` invoca los scripts con rutas relativas (`\i sql/...`).

### 1. Clonar el repositorio

```bash
git clone <url-del-repositorio> proyecto-clinica
cd proyecto-clinica
```

### 2. Configurar la contraseña sin escribirla en el repositorio

Ninguna contraseña se guarda en este repositorio. Usa el archivo de contraseñas de PostgreSQL de tu maquina:

- **Windows:** `%APPDATA%\postgresql\pgpass.conf`
- **Linux / macOS:** `~/.pgpass` (con permisos `chmod 600 ~/.pgpass`)

Con una línea con este formato:

```
localhost:5432:*:postgres:TU_CONTRASEÑA
```

Si no lo configuras, `psql` te pedirá la contraseña al conectarse.

### 3. Crear la base vacía y reconstruir el proyecto

```bash
createdb -U postgres clinica
psql -U postgres -d clinica -f ejecutar_todo.sql
```

La carga incluye 50,000 citas; la reconstrucción completa tarda unos 10 segundos. Si cualquier script falla, la ejecución se detiene (`ON_ERROR_STOP`) y muestra el error.

### 4. Comprobar

```sql
SELECT count(*) FROM clinica.cita;      -- 50028
SELECT count(*) FROM clinica.paciente;  -- 505
SELECT count(*) FROM clinica.medico;    -- 20
```

---

## Estructura del repositorio

```
proyecto-clinica/
├── README.md                        este archivo
├── ejecutar_todo.sql                invoca los scripts en orden con \i
├── .gitignore
├── docs/
│   ├── modelo_er.pdf                diagrama entidad-relación
│   ├── esquema_relacional.pdf       tablas, claves y decisiones de mapeo
│   ├── normalizacion.md             dependencias funcionales, 3FN, FNBC, desnormalización
│   ├── rendimiento.md               planes y tiempos antes y después de los índices
│   ├── permisos.md                  matriz de roles
│   └── evidencias/
│       ├── concurrencia/            transcripciones de dos sesiones simultáneas, con tiempos
│       ├── permisos/                pruebas con SET ROLE (script y su salida)
│       └── respaldo/                pg_dump, pg_restore y comparación de conteos
├── sql/
│   ├── 01_esquema.sql               esquema clinica: 26 tablas, PK, FK, CHECK, UNIQUE
│   ├── 02_datos.sql                 datos de ejemplo + carga masiva (generate_series)
│   ├── 03_vistas_indices.sql        4 vistas e índices de rendimiento
│   ├── 04_funciones_procedimientos.sql
│   ├── 05_triggers.sql
│   ├── 06_seguridad.sql             roles y GRANT
│   ├── 07_consultas.sql             las 15 preguntas de negocio
│   └── 08_transacciones.sql         demostraciones de transacciones y concurrencia
└── respaldo/
    └── clinica.dump                 respaldo en formato personalizado
```

### Orden de ejecución

`ejecutar_todo.sql`:

```sql
\set ON_ERROR_STOP on
\echo '== 01 Esquema ==='
\i sql/01_esquema.sql
\echo '== 02 Datos ==='
\i sql/02_datos.sql
\echo '== 03 Vistas e índices ==='
\i sql/03_vistas_indices.sql
\echo '== 04 Funciones y procedimientos ==='
\i sql/04_funciones_procedimientos.sql
\echo '== 05 Triggers ==='
\i sql/05_triggers.sql
\echo '== 06 Seguridad ==='
\i sql/06_seguridad.sql
\echo '== 07 Consultas ==='
\i sql/07_consultas.sql
\echo '== 08 Transacciones ==='
\i sql/08_transacciones.sql
\echo '== Proyecto reconstruido ==='
```

Por qué este orden:

- Las **tablas** van primero porque todo lo demás depende de ellas.
- Los **datos** se cargan antes de los índices de rendimiento, porque crear índices después de una carga masiva es más rápido.
- Los **triggers** se crean después de los datos, así que `02_datos.sql` debe dejar los datos ya coherentes por sí mismo (citas atendidas con su consulta, facturas con totales correctos).
- **`08_transacciones.sql`** corre en una sola sesión: las demostraciones de dos sesiones están como comentarios con instrucciones, y los errores provocados a propósito se capturan para no detener el script.

---

## Modelo de datos

El modelo tiene **26 tablas** en el esquema `clinica`, organizadas en cinco áreas:

| Área | Tablas |
|---|---|
| Personas y personal | `persona`, `paciente`, `empleado`, `medico`, `recepcionista`, `farmaceutico`, `aseguradora` |
| Agenda | `sede`, `especialidad`, `medico_especialidad`, `horario`, `cita` |
| Atención clínica | `consulta`, `diagnostico`, `consulta_diagnostico`, `receta`, `receta_linea` |
| Farmacia | `medicamento`, `lote`, `existencia`, `dispensacion`, `dispensacion_detalle` |
| Facturación | `factura`, `factura_linea`, `pago`, `auditoria` |

Requisitos de modelado cubiertos:

- **Jerarquías de especialización:** `persona` → `paciente`, `empleado` (solapada: un empleado puede ser paciente) y `empleado` → `medico`, `recepcionista`, `farmaceutico` (disjunta, garantizada con un discriminador y una FK compuesta).
- **Relaciones N:M:** `medico_especialidad`, `horario` (médico–sede), `consulta_diagnostico` y `existencia` (lote–sede).
- **Entidades débiles:** `receta_linea`, `factura_linea`, `dispensacion_detalle`.
- **Relación recursiva:** paciente menor → paciente responsable.
- **Desnormalización controlada (RN-15):** `factura_linea.precio_unitario` conserva el precio vigente al momento de la venta. Ver `docs/normalizacion.md`.

---

## Supuestos

Decisiones tomadas donde las reglas del caso eran ambiguas:

| # | Regla | Supuesto |
|---|---|---|
| S-01 | RN-02 | Menor de edad = menos de 18 años a la fecha actual. Se valida con trigger porque la edad cambia con el tiempo. |
| S-02 | RN-02 | El responsable de un menor es otro paciente, distinto de él mismo y mayor de edad. |
| S-03 | RN-03 | Un empleado tiene un solo tipo: médico, recepcionista o farmacéutico. |
| S-04 | RN-03 | Recepcionistas y farmacéuticos trabajan en una sede fija; los médicos se asignan a sedes por su horario. |
| S-05 | RN-06 | Las citas empiezan en el minuto 0 o 30 y duran siempre 30 minutos. |
| S-06 | RN-08 | Una cita "activa" es cualquiera cuyo estado no sea `cancelada`. |
| S-07 | RN-15 | El precio de la consulta depende de la especialidad. |
| S-08 | RN-15 | Una consulta genera como máximo una factura. |
| S-09 | RN-16 | El porcentaje de cobertura pertenece a la póliza del paciente y se aplica al total de la factura. |
| S-10 | RN-17 | Los pagos del paciente cubren solo su parte; el cobro a la aseguradora queda fuera del alcance. |
| S-11 | RN-14 | Cada receta se dispensa una sola vez y en una sola sede. |
| S-12 | RN-12 | Una receta no repite el mismo medicamento en dos líneas. |
| S-13 | RN-18 | "Quién" hizo un cambio es el usuario de base de datos de la sesión (`session_user`). |

---

## Reglas de negocio y dónde se implementan

| Regla | Descripción | Implementación |
|---|---|---|
| RN-01 | Sedes con nombre, dirección y teléfono | Tabla `sede`, `UNIQUE (nombre)` |
| RN-02 | Personas, empleados que son pacientes, menores con responsable | Jerarquía `persona`; FK recursiva en `paciente`; trigger de edad |
| RN-03 | Tipos de empleado | Subtipos con discriminador y FK compuesta |
| RN-04 | Médico con varias especialidades | Tabla `medico_especialidad` |
| RN-05 | Horario semanal por sede | Tabla `horario`, `CHECK (hora_fin > hora_inicio)` |
| RN-06 | Cita en bloques de 30 minutos | `CHECK` sobre los minutos de `fecha_hora` |
| RN-07 | Transiciones de estado de la cita | `CHECK` de valores + trigger de transiciones |
| RN-08 | Sin dos citas activas a la misma hora | Índices únicos parciales `WHERE estado <> 'cancelada'` |
| RN-09 | Cita dentro del horario y de una especialidad del médico | FK compuesta a `medico_especialidad` + trigger de horario |
| RN-10 | Una consulta por cita atendida | `UNIQUE (id_cita)` + trigger de estado |
| RN-11 | Exactamente un diagnóstico principal | Índice único parcial + trigger diferido |
| RN-12 | Receta y sus líneas | Entidad débil `receta_linea`, `ON DELETE CASCADE` |
| RN-13 | Inventario por lote y sede, stock no negativo | Tabla `existencia`, `CHECK (stock >= 0)` |
| RN-14 | Lote que vence antes primero; todo o nada | Procedimiento de dispensación con `FOR UPDATE` en una transacción |
| RN-15 | Precio vigente al momento de la venta | `factura_linea.precio_unitario` (desnormalización controlada) |
| RN-16 | Cobertura entre 0 y 100 | `CHECK` en `paciente` y cálculo de la parte del seguro y del paciente en `factura` |
| RN-17 | Pagos que no superan el saldo; factura pagada automáticamente | `CHECK` sobre `saldo` + trigger tras cada pago |
| RN-18 | Auditoría de cambios | Tabla `auditoria` llenada por triggers |
| RN-19 | Recepción no ve datos clínicos | Roles con `GRANT` mínimos y vista `v_agenda` sin datos clínicos |

---

## Datos de prueba

`02_datos.sql` corre en una sola transacción y tiene dos partes:

- **Parte 1, escrita a mano** (personas 1–30, citas 1–28, facturas 1–18). Son los casos que citan los comentarios de `07_consultas.sql` y que usan las demostraciones de `08_transacciones.sql` (receta 7, factura 18, Dr. Salazar…), por eso tienen IDs y fechas fijas (octubre–diciembre de 2026).
- **Parte 2, carga masiva** con `generate_series`. Las fechas son relativas a `current_date`, así que las consultas de "este mes", "hoy" o "próximos 90 días" siempre devuelven resultados. Es **reproducible**: en lugar de `random()` usa un hash md5, así que todos los integrantes obtienen exactamente la misma base.

| Entidad | Mínimo pedido | Cargado |
|---|--:|--:|
| Sedes | 3 | 3 |
| Médicos | 20 | 20 (uno inactivo y sin citas) |
| Pacientes | 500 | 505 (≈55 menores con responsable, ≈35 % sin aseguradora) |
| Citas | 50,000 | 50,028 (≈15 meses hacia atrás y 2 meses hacia adelante) |
| Consultas / facturas | — | 36,699 / 36,699 |
| Recetas / dispensaciones | — | 27,079 / 23,141 |
| Pagos | — | 35,514 (≈3,000 facturas con saldo pendiente) |

Como los triggers se crean después de los datos, la carga masiva respeta a mano todo lo que ellos validarían: citas dentro del horario del médico y sin choques, consulta solo para citas atendidas, un diagnóstico principal, Pediatría solo con menores y Ginecología solo con mujeres, dispensación solo de lotes no vencidos, y totales, saldos y estados de factura que cuadran. Se verificó con 16 comprobaciones (todas con 0 errores).

Los datos incluyen a propósito los casos que buscan las consultas: pacientes sin aseguradora, menores con responsable, cinco empleados que también son pacientes, medicamentos nunca recetados (Ranitidina, Ciprofloxacino, Cetirizina, Naproxeno) y lotes que vencen en los próximos 90 días.

---|---|
| Sedes | 3 |
| Médicos | 20 |
| Pacientes | 500 |
| Citas | 50,000 |

Las fechas son relativas a `current_date`, así que las consultas de "este mes", "hoy" o "próximos 90 días" devuelven resultados sin importar cuándo se ejecute el proyecto. Los datos incluyen a propósito los casos que buscan las consultas: pacientes sin aseguradora, menores con responsable, empleados que también son pacientes, medicamentos nunca recetados y lotes próximos a vencer.

---

## Consultas

`sql/07_consultas.sql` responde las 15 preguntas de negocio. Cada una lleva un comentario que explica la solución y una muestra de su resultado.

| # | Pregunta | Técnica principal |
|---|---|---|
| 1 | Citas de una sede en un rango de fechas | `WHERE`, `BETWEEN`, `ORDER BY` |
| 2 | Pacientes sin aseguradora ("Particular") | `LEFT JOIN`, `IS NULL`, `COALESCE` |
| 3 | Búsqueda por nombre parcial, paginada | `ILIKE`, funciones de texto, `LIMIT`, `OFFSET` |
| 4 | Especialidades con más de 20 citas por mes | Funciones de fecha, `GROUP BY`, `HAVING` |
| 5 | Agenda del día | `JOIN` múltiple |
| 6 | Citas por médico este mes, incluidos los que no tienen | `LEFT JOIN`, `COUNT` |
| 7 | Citas por sede y especialidad, incluidas las de cero | `CROSS JOIN`, `LEFT JOIN` |
| 8 | Pacientes menores y su responsable | Self join |
| 9 | Medicamentos nunca recetados | `NOT EXISTS` |
| 10 | Médicos que facturan más que el promedio de su especialidad | Subconsulta correlacionada |
| 11 | Personas que son empleados y pacientes | `INTERSECT` |
| 12 | Lotes que vencen en 90 días | Funciones de fecha, `JOIN`, `WHERE` |
| 13 | Citas por especialidad: este mes contra el anterior | CTE, `FULL OUTER JOIN` |
| 14 | Ranking de médicos por citas atendidas | `DENSE_RANK`, `PARTITION BY` |
| 15 | Última consulta de cada paciente | `ROW_NUMBER` |

---

## Transacciones y concurrencia

`sql/08_transacciones.sql` contiene cinco demostraciones. En `docs/evidencias/concurrencia/` están las transcripciones de esas demostraciones ejecutadas con **dos sesiones reales al mismo tiempo**, con la hora de cada paso: se ve a la sesión B esperando y el momento en que se libera.

| Demostración | Qué se comprueba |
|---|---|
| Reservar cita | Dos sesiones intentan el mismo bloque y solo una lo consigue. |
| Dispensar receta | Si falta stock en una línea, se revierte toda la operación (RN-14). |
| Registrar pago | Un fallo a mitad del proceso no deja pagos ni estados inconsistentes. |
| Bloqueos | `SELECT ... FOR UPDATE` sobre un lote hace esperar a la segunda sesión. |
| Aislamiento | Diferencia entre `READ COMMITTED` y `REPEATABLE READ`. |

| Evidencia | Demostración |
|---|---|
| `01_reserva_misma_cita_commit.txt`, `02_..._rollback.txt` | Reservar cita (A confirma / A revierte) |
| `03_for_update_espera.txt` | B espera en `FOR UPDATE`; una tercera sesión muestra `pg_blocking_pids` |
| `04_nowait_lock_timeout.txt` | `NOWAIT` y `lock_timeout` |
| `05_deadlock.txt` | Interbloqueo detectado por PostgreSQL |
| `06_aislamiento.txt` | Lectura no repetible y error de serialización |

Para reproducir las demostraciones de dos sesiones, abre dos ventanas de `psql` (o dos consolas en DataGrip) conectadas a `clinica` y sigue los pasos marcados como **Sesión A** y **Sesión B** en los comentarios del script.

---

## Seguridad

`sql/06_seguridad.sql` crea cuatro roles de grupo, sin contraseña ni `LOGIN`, con los permisos mínimos que necesita cada uno. La matriz completa está en `docs/permisos.md`.

| Rol | Acceso principal |
|---|---|
| `rol_recepcion` | Pacientes, agenda (`v_agenda`) y citas, facturas y pagos. **Sin acceso** a motivo, notas clínicas, signos vitales, diagnósticos ni recetas (RN-19). |
| `rol_medico` | Citas, consultas, diagnósticos y recetas. Único rol que registra datos clínicos. |
| `rol_farmacia` | Recetas, medicamentos, lotes, existencias y dispensación. |
| `rol_auditor` | Lectura de la tabla de auditoría. |

Recepción y farmacia solo pueden leer `id_consulta`, `id_cita` y `registrada_en` de `consulta`, gracias a los permisos por columna. Prueba de un acceso denegado:

```sql
SET ROLE rol_recepcion;
SELECT notas_clinicas FROM clinica.consulta;   -- ERROR: permission denied for table consulta
RESET ROLE;
```

`docs/evidencias/permisos/pruebas_permisos.sql` recorre con `SET ROLE` el flujo completo de una cita (recepción agenda → médico atiende y receta → farmacia surte → recepción cobra → auditor revisa) y comprueba 21 accesos denegados. Su salida está en `pruebas_permisos_salida.txt`.

### Vistas (`03_vistas_indices.sql`)

| Vista | Uso |
|---|---|
| `v_agenda` | Agenda sin datos clínicos (RN-19), para recepción |
| `v_inventario_vigente` | Stock surtible por sede: solo lotes no vencidos y con existencia |
| `v_lote_por_vencer` | Lotes con stock vencidos o que vencen en 90 días |
| `v_cuentas_por_cobrar` | Facturas pendientes con saldo del paciente |

---

## Respaldo y restauración

```bash
# 1. Respaldo en formato personalizado
pg_dump -U postgres -Fc -d clinica -f respaldo/clinica.dump

# 2. Restaurar en una base nueva
createdb -U postgres clinica_restaurada
pg_restore -U postgres -d clinica_restaurada respaldo/clinica.dump
```

`respaldo/clinica.dump` se generó con `pg_dump` 16. `pg_restore` no lee respaldos hechos con una versión más nueva que la suya: si tu PostgreSQL es 14 o 15, reconstruye la base con `ejecutar_todo.sql` y genera tu propio respaldo con el comando 1.

Los roles son globales del servidor y `pg_dump` no los incluye. Al restaurar en el mismo servidor ya existen; en otro servidor, primero hay que ejecutar `sql/06_seguridad.sql`.

Para comprobar la restauración, ejecuta esta consulta en las dos bases y compara los resultados:

```sql
SELECT table_name AS tabla,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name),
                           false, true, '')))[1]::text::bigint AS filas
FROM information_schema.tables
WHERE table_schema = 'clinica' AND table_type = 'BASE TABLE'
ORDER BY tabla;
```

La comparación está en `docs/evidencias/respaldo/respaldo_restauracion.txt`: las 26 tablas coinciden fila por fila.

---