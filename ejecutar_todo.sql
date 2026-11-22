-- =====================================================================
--  Clínica Vida Plena — Reconstrucción completa del proyecto
--  Autora: Ibarra Lopez Danna Alejandra
--
--  Uso (desde la raíz del repositorio, sobre una base VACÍA):
--      createdb -U postgres clinica
--      psql -U postgres -d clinica -f ejecutar_todo.sql
--
--  Las rutas de \i son relativas a la carpeta desde donde se ejecuta
--  psql: por eso hay que correrlo desde la raíz del repositorio.
--  ON_ERROR_STOP detiene todo en el primer error y lo muestra.
-- =====================================================================

\set ON_ERROR_STOP on
\timing off

\echo '=== 01 Esquema ==='
\i sql/01_esquema.sql
\echo '=== 02 Datos ==='
\i sql/02_datos.sql
\echo '=== 03 Vistas e índices ==='
\i sql/03_vistas_indices.sql
\echo '=== 04 Funciones y procedimientos ==='
\i sql/04_funciones_procedimientos.sql
\echo '=== 05 Triggers ==='
\i sql/05_triggers.sql
\echo '=== 06 Seguridad ==='
\i sql/06_seguridad.sql
\echo '=== 07 Consultas ==='
\i sql/07_consultas.sql
\echo '=== 08 Transacciones ==='
\i sql/08_transacciones.sql
\echo '=== Proyecto reconstruido ==='
