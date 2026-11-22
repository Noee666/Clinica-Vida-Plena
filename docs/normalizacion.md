# Normalización — Clínica Vida Plena

**Responsable:** Torres Gonzalez Gael Andres
**Esquema analizado:** `sql/01_esquema.sql` (26 tablas en el esquema `clinica`)

## 1. Método

Para cada tabla se identificaron:

1. sus **dependencias funcionales** (DF) a partir de las reglas de negocio RN-01 a RN-19 y los supuestos S-01 a S-13 del README;
2. sus **claves candidatas** (la PK y los `UNIQUE`);
3. si cumple **1FN, 2FN, 3FN y FNBC**.

Recordatorio de las formas normales:

| Forma | Condición |
|---|---|
| 1FN | Atributos atómicos, sin grupos repetidos. |
| 2FN | 1FN y ningún atributo no clave depende de *parte* de una clave compuesta. |
| 3FN | 2FN y ningún atributo no clave depende de otro atributo no clave (sin dependencias transitivas). |
| FNBC | Para toda DF no trivial X → Y, X es superclave. |

**Resultado:** las 26 tablas están en 1FN y 2FN. **22 están en FNBC.** Las otras 4 tienen redundancias **intencionales y controladas**, que se explican en la sección 5: `factura` (totales calculados y cobertura copiada), `cita` (sede), `paciente` (cobertura de la póliza) y `auditoria` (JSON).

## 2. Primera forma normal

Se eliminaron los grupos repetidos que aparecen en las hojas de cálculo actuales de la clínica:

| En las hojas de cálculo | En el modelo |
|---|---|
| Un médico con "Pediatría, Medicina General" en una celda | Tabla `medico_especialidad` (N:M) |
| Una receta con columnas medicamento1, medicamento2, … | Entidad débil `receta_linea` |
| Una consulta con varios diagnósticos en una celda | Tabla `consulta_diagnostico` (N:M) |
| Una factura con sus conceptos en columnas | Entidad débil `factura_linea` |
| Stock por sede en columnas (Centro, Norte, Sur) | Tabla `existencia` (lote × sede) |
| Horario semanal como texto ("L–V 8 a 14") | Tabla `horario`, una fila por día y bloque |

El nombre se separa en `nombres`, `apellido_paterno` y `apellido_materno` porque se busca y se ordena por apellido.

Decisiones conscientes:

- `persona.direccion` se guarda como una sola cadena. La clínica no consulta por calle ni por colonia, así que separarla no aporta nada. Si un día se necesitara filtrar por colonia, se dividiría.
- `auditoria.datos_anteriores` y `datos_nuevos` son `JSONB`, es decir, **no atómicos**. Ver la sección 5.4.

## 3. Segunda forma normal

Solo las tablas con clave compuesta pueden violar la 2FN. En todas, cada atributo no clave depende de la clave **completa**:

| Tabla | Clave | Atributos no clave | ¿Dependen de toda la clave? |
|---|---|---|---|
| `medico_especialidad` | (id_medico, id_especialidad) | — | No hay atributos no clave |
| `consulta_diagnostico` | (id_consulta, id_diagnostico) | es_principal, observaciones | Sí: un diagnóstico es principal *en esa consulta* |
| `existencia` | (id_lote, id_sede) | stock, fecha_ingreso | Sí: el stock es del lote *en esa sede* |
| `receta_linea` | (id_receta, numero_linea) | id_medicamento, dosis, frecuencia, cantidad | Sí |
| `dispensacion_detalle` | (id_dispensacion, id_lote) | cantidad | Sí |
| `factura_linea` | (id_factura, numero_linea) | concepto, id_medicamento, cantidad, precio_unitario, importe | Sí (ver 5.1 sobre `precio_unitario`) |

`receta_linea` tiene una segunda clave candidata, (id_receta, id_medicamento) (`uq_receta_linea_medicamento`, S-12), y los atributos también dependen de ella completa.

Las tablas de subtipo `medico`, `recepcionista` y `farmaceutico` tienen la columna `tipo_empleado` con un valor fijo (`CHECK`). Depende de la PK de forma trivial y solo existe para la FK compuesta `(id_persona, tipo_empleado) → empleado`, que garantiza que la jerarquía sea **disjunta** (S-03): un empleado de tipo `medico` no puede tener fila en `recepcionista`.

## 4. Tercera forma normal y FNBC, tabla por tabla

| Tabla | Claves candidatas | DF relevantes | Forma |
|---|---|---|---|
| `sede` | {id_sede}, {nombre} | id_sede → nombre, dirección, teléfono | FNBC |
| `persona` | {id_persona}, {documento}, {email}* | id_persona → todos | FNBC |
| `aseguradora` | {id_aseguradora}, {nombre} | id → nombre, teléfono | FNBC |
| `paciente` | {id_persona} | id_persona → responsable, aseguradora, póliza, cobertura, registro | 3FN con una reserva, ver **5.3** |
| `empleado` | {id_persona}, {numero_empleado} | id_persona → número, tipo, contratación, activo | FNBC |
| `medico` | {id_persona}, {cedula_profesional} | id_persona → cédula | FNBC |
| `recepcionista` | {id_persona} | id_persona → id_sede (S-04) | FNBC |
| `farmaceutico` | {id_persona}, {licencia_sanitaria} | id_persona → sede, licencia | FNBC |
| `especialidad` | {id_especialidad}, {nombre} | id → nombre, precio_consulta (S-07) | FNBC |
| `medico_especialidad` | {id_medico, id_especialidad} | — | FNBC |
| `horario` | {id_horario} | id_horario → médico, sede, día, horas | FNBC |
| `cita` | {id_cita} | id_cita → todos | 3FN con una reserva, ver **5.2** |
| `consulta` | {id_consulta}, {id_cita} | id_consulta → cita, motivo, signos, notas | FNBC |
| `diagnostico` | {id_diagnostico}, {codigo_cie10} | id → código, descripción | FNBC |
| `consulta_diagnostico` | {id_consulta, id_diagnostico} | → es_principal, observaciones | FNBC |
| `medicamento` | {id_medicamento}, {nombre, presentacion, concentracion} | id → todos | FNBC |
| `lote` | {id_lote}, {id_medicamento, numero_lote} | id_lote → medicamento, número, vencimiento | FNBC |
| `existencia` | {id_lote, id_sede} | → stock, fecha_ingreso | FNBC |
| `receta` | {id_receta}, {id_consulta} | id_receta → consulta, emisión, estado, indicaciones | FNBC |
| `receta_linea` | {id_receta, numero_linea}, {id_receta, id_medicamento} | → medicamento, dosis, frecuencia, cantidad | FNBC |
| `dispensacion` | {id_dispensacion}, {id_receta} | id → receta, farmacéutico, sede, fecha | FNBC |
| `dispensacion_detalle` | {id_dispensacion, id_lote} | → cantidad | FNBC |
| `factura` | {id_factura}, {id_consulta} | ver **5.1** | **No** FNBC (intencional) |
| `factura_linea` | {id_factura, numero_linea} | ver **5.1** | 3FN (importe es una columna generada) |
| `pago` | {id_pago} | id_pago → factura, fecha, monto, método, referencia, recepcionista | FNBC |
| `auditoria` | {id_auditoria} | id → todos | 1FN discutible, ver **5.4** |

\* `email` es único cuando no es nulo.

Dos casos que **parecen** dependencias transitivas pero no lo son:

- `dispensacion.id_sede`: no se deduce de la receta ni de la cita, porque una receta se puede surtir en cualquier sede (S-11). Es un dato propio del evento.
- `lote.fecha_vencimiento`: depende del lote (id_lote, o medicamento + número de lote), no solo del medicamento. Dos lotes del mismo medicamento vencen en fechas distintas.

## 5. Desnormalización controlada

Cada redundancia tiene un motivo de negocio y un mecanismo que la mantiene correcta. Ninguna depende de que "el programador se acuerde".

### 5.1 Facturación (RN-15, RN-16, RN-17)

| Columna | Se podría calcular como… | Por qué se guarda | Cómo se mantiene correcta |
|---|---|---|---|
| `factura_linea.precio_unitario` | `especialidad.precio_consulta` o `medicamento.precio_venta` | **RN-15:** la factura conserva el precio **vigente al momento de la venta**. Si mañana sube el precio, las facturas de ayer no deben cambiar. No es una DF en el tiempo: el precio del catálogo cambia y el de la línea no. | Trigger `trg_factura_linea_validar` copia el precio al insertar |
| `factura_linea.importe` | cantidad × precio_unitario | Comodidad y rendimiento al sumar | `GENERATED ALWAYS AS … STORED`: PostgreSQL lo calcula, nadie lo puede escribir |
| `factura.id_aseguradora`, `porcentaje_cobertura` | Los del paciente | Igual que el precio: si el paciente cambia de aseguradora, la factura vieja debe seguir con la cobertura con la que se emitió (S-09) | Trigger `trg_factura_copiar_cobertura` |
| `factura.subtotal` | Σ importe de sus líneas | Se consulta en cada reporte de facturación (pregunta 10) | Trigger `trg_factura_linea_recalcular` → `fn_recalcular_factura` |
| `factura.monto_seguro`, `monto_paciente` | subtotal × porcentaje / 100 y el resto | Igual | Misma función + `CHECK (monto_seguro + monto_paciente = subtotal)` |
| `factura.saldo` | monto_paciente − Σ pagos | Es lo que pregunta la caja en cada cobro | Trigger `trg_pago_actualizar_factura` + `CHECK (saldo BETWEEN 0 AND monto_paciente)` |
| `factura.estado` | 'pagada' si saldo = 0 | Filtrar pendientes sin sumar pagos | Mismo trigger + `CHECK (estado <> 'pagada' OR saldo = 0)` |

Formalmente, en `factura` existe la DF {subtotal, porcentaje_cobertura} → monto_seguro, cuyo lado izquierdo no es superclave, así que `factura` **no está en FNBC**. La alternativa normalizada sería una vista que calcule todo en cada consulta, pero con 35,000 pagos cada cobro tendría que recalcular sumas. La redundancia es segura porque **solo** los triggers modifican esas columnas y los `CHECK` rechazan cualquier combinación inconsistente.

### 5.2 `cita.id_sede`

Como un médico no puede tener dos bloques de horario encimados el mismo día (`EXCLUDE` en `horario`), en el horario **actual** se cumple {id_medico, fecha_hora} → id_sede. Aun así, se guarda la sede en la cita porque:

- el horario cambia con el tiempo, y la cita debe recordar **dónde ocurrió**, no dónde atendería hoy el médico;
- sin esa columna, cada consulta por sede (preguntas 1 y 7, agenda, facturación por sede) tendría que reconstruirla cruzando con el horario por día de la semana y hora.

La coherencia en el momento de agendar la garantiza el trigger `trg_cita_validar_horario` (RN-09): la cita debe caber en un horario del médico **en esa sede**.

### 5.3 Cobertura de la póliza en `paciente`

Si se asume que la póliza determina la cobertura, entonces {id_aseguradora, numero_poliza} → porcentaje_cobertura es una dependencia transitiva. En los datos se ve en los menores, que repiten la póliza y la cobertura de su responsable.

Se decidió **no** crear una tabla `poliza` por dos razones:

1. En la práctica, una misma póliza familiar puede dar coberturas distintas a cada beneficiario, así que la DF no está garantizada por el negocio.
2. S-09 define la cobertura como dato **del paciente**, y RN-16 solo pide validarla entre 0 y 100.

Si la clínica necesitara administrar pólizas (vigencia, titular, beneficiarios), el diseño normalizado sería:

```
poliza (id_poliza PK, id_aseguradora FK, numero_poliza, titular FK → paciente, vigencia)   UNIQUE (id_aseguradora, numero_poliza)
paciente_poliza (id_paciente FK, id_poliza FK, porcentaje_cobertura)                        PK (id_paciente, id_poliza)
```

### 5.4 `auditoria` (RN-18)

`datos_anteriores` y `datos_nuevos` guardan la fila completa en `JSONB`, así que estrictamente no son atómicos. Es una decisión deliberada:

- una sola tabla registra cambios de 10 tablas con columnas distintas;
- la auditoría se **lee**, nunca se actualiza ni se une con otras tablas, y no hay riesgo de anomalías de actualización;
- si cambia una tabla auditada, la auditoría no necesita cambiar.

## 6. Mapeo de las jerarquías

| Jerarquía | Tipo | Cómo se mapeó |
|---|---|---|
| `persona` → `paciente`, `empleado` | **Solapada** (un empleado puede ser paciente) | Una tabla por subtipo con la misma PK (`id_persona`) que es FK a `persona` |
| `empleado` → `medico`, `recepcionista`, `farmaceutico` | **Disjunta y total** (S-03) | Una tabla por subtipo + discriminador `tipo_empleado` + FK compuesta `(id_persona, tipo_empleado)` |

Se descartó "una sola tabla con todo" porque habría llenado de `NULL` las columnas de cada subtipo (cédula, licencia, sede, póliza…) y no permitiría FK específicas, como `dispensacion.id_farmaceutico → farmaceutico`, que garantiza que solo un farmacéutico pueda surtir.
