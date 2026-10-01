-- =====================================================================
--  CDD-IN | Tarea 5: Data Warehouse (modelo estrella)
--  Ejecutar DESPUÉS de 04_etl.sql, en la base cddin (DBeaver: Alt+X, o psql \i)
-- ---------------------------------------------------------------------
--  Data marts con dimensiones conformadas (arquitectura de bus):
--    * Data mart VENTAS -> dw.fact_ventas  (grano: 1 producto en 1 ticket)
--    * Data mart STOCK  -> dw.fact_stock   (grano: 1 producto en 1 mes)
--  Comparten dim_producto y el tiempo (dim_tiempo / dim_mes).
--  Las dimensiones están DESNORMALIZADAS (estrella, no copo de nieve).
-- =====================================================================
DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;

-- ---------------- DIMENSIONES ----------------

-- Tiempo (día). Jerarquía: día -> mes -> trimestre -> año
CREATE TABLE dw.dim_tiempo (
    fecha_key   INTEGER PRIMARY KEY,           -- AAAAMMDD
    fecha       DATE NOT NULL UNIQUE,
    dia         SMALLINT, dia_semana VARCHAR(10),
    mes_id      INTEGER,  mes_nombre VARCHAR(20),
    trimestre   SMALLINT, anio SMALLINT);
INSERT INTO dw.dim_tiempo
SELECT to_char(dia_id,'YYYYMMDD')::INT, dia_id, extract(day FROM dia_id),
       (ARRAY['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'])[extract(dow FROM dia_id)+1],
       mes_id,
       (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[extract(month FROM dia_id)],
       extract(quarter FROM dia_id), anio_id
FROM lu_fecha;

-- Mes: versión "reducida" y conformada de dim_tiempo (la usa el mart de stock)
CREATE TABLE dw.dim_mes (
    mes_id INTEGER PRIMARY KEY, mes_desc VARCHAR(50), trimestre SMALLINT, anio SMALLINT);
INSERT INTO dw.dim_mes
SELECT mes_id, mes_desc, ((mes_id % 100) - 1) / 3 + 1, anio_id FROM lu_mes;

-- Producto. Jerarquía: producto -> subcategoría -> categoría (+ proveedor)
CREATE TABLE dw.dim_producto (
    producto_key  SERIAL PRIMARY KEY,
    producto_id   INTEGER UNIQUE NOT NULL,     -- clave natural del sistema origen
    producto      VARCHAR(255), subcategoria VARCHAR(50), categoria VARCHAR(50),
    proveedor     VARCHAR(50),
    precio_unitario NUMERIC(12,4), costo_unitario NUMERIC(12,4));
INSERT INTO dw.dim_producto (producto_id, producto, subcategoria, categoria, proveedor, precio_unitario, costo_unitario)
SELECT p.producto_id, p.producto_desc, s.subcategoria_desc, c.categoria_desc, pr.proveedor_desc,
       p.mnt_precio_unitario, p.mnt_costo_unitario
FROM lu_producto p
JOIN lu_subcategoria s USING (subcategoria_id)
JOIN lu_categoria   c USING (categoria_id)
JOIN lu_proveedor  pr USING (proveedor_id);

-- Empleado. Jerarquía: empleado -> sucursal -> región
CREATE TABLE dw.dim_empleado (
    empleado_key SERIAL PRIMARY KEY,
    empleado_id  SMALLINT UNIQUE NOT NULL,
    empleado     VARCHAR(50), sucursal VARCHAR(50), region VARCHAR(50));
INSERT INTO dw.dim_empleado (empleado_id, empleado, sucursal, region)
SELECT e.empleado_id, e.empleado_desc, s.sucursal_desc, coalesce(r.region_desc, 'Sin región')
FROM lu_empleado e
JOIN lu_sucursal s USING (sucursal_id)
LEFT JOIN lu_region r ON r.region_id = s.region_id;

-- Cliente (todas sus características en una sola tabla)
CREATE TABLE dw.dim_cliente (
    cliente_key SERIAL PRIMARY KEY,
    cliente_id  INTEGER UNIQUE NOT NULL,
    cliente VARCHAR(255), genero VARCHAR(50), fecha_nacimiento DATE, codigo_postal VARCHAR(10),
    educacion VARCHAR(50), estado_civil VARCHAR(50), rango_ingresos VARCHAR(50),
    tipo_alojamiento VARCHAR(50), tamanio_familia VARCHAR(50));
INSERT INTO dw.dim_cliente (cliente_id, cliente, genero, fecha_nacimiento, codigo_postal, educacion,
                            estado_civil, rango_ingresos, tipo_alojamiento, tamanio_familia)
SELECT c.cliente_id, c.cliente_nombre, g.genero_desc, c.fecha_nacimiento, c.codigo_postal, ed.educacion_desc,
       ec.estado_civil_desc, ri.rango_ingresos_desc, ta.tipo_alojamiento_desc, tf.tamanio_familia_desc
FROM lu_cliente c
LEFT JOIN lu_genero g             USING (genero_id)
LEFT JOIN lu_educacion ed         USING (educacion_id)
LEFT JOIN lu_estado_civil ec      USING (estado_civil_id)
LEFT JOIN lu_rango_ingresos ri    USING (rango_ingresos_id)
LEFT JOIN lu_tipo_alojamiento ta  USING (tipo_alojamiento_id)
LEFT JOIN lu_tamanio_familia tf   USING (tamanio_familia_id);

-- Tramo de edad (segmentación pedida). Se asigna según la edad
-- del cliente EN LA FECHA DE LA COMPRA, no según una edad fija.
CREATE TABLE dw.dim_tramo_edad (
    tramo_key SMALLINT PRIMARY KEY, tramo VARCHAR(40), edad_desde SMALLINT, edad_hasta SMALLINT);
INSERT INTO dw.dim_tramo_edad VALUES
    (0, 'Menor de 18 (fuera de segmento)', 0, 17),
    (1, '18 a 30', 18, 30), (2, '31 a 45', 31, 45),
    (3, '46 a 60', 46, 60), (4, '61 a 75', 61, 75),
    (9, 'Mayor de 75 (fuera de segmento)', 76, 150);

-- Promoción. Jerarquía: promoción -> tipo de promoción
CREATE TABLE dw.dim_promocion (
    promocion_key SERIAL PRIMARY KEY, promocion_id SMALLINT UNIQUE NOT NULL,
    promocion VARCHAR(50), tipo_promocion VARCHAR(50));
INSERT INTO dw.dim_promocion (promocion_id, promocion, tipo_promocion)
SELECT p.promocion_id, p.promocion_desc, t.promo_tipo_desc
FROM lu_promocion p JOIN lu_promo_tipo t USING (promo_tipo_id)
UNION ALL SELECT -1, 'No informada', 'No informada';

-- Forma de pago: las del sistema + las nuevas que aparecieron en las planillas
CREATE TABLE dw.dim_tipo_pago (
    tipo_pago_key SERIAL PRIMARY KEY, tipo_pago VARCHAR(50) UNIQUE NOT NULL);
INSERT INTO dw.dim_tipo_pago (tipo_pago)
SELECT tipo_pago_desc FROM lu_tipo_pago
UNION SELECT DISTINCT tipo_pago FROM stg.ventas_integradas;

-- Origen del dato (trazabilidad: de qué fuente vino cada venta)
CREATE TABLE dw.dim_fuente (fuente_key SERIAL PRIMARY KEY, fuente VARCHAR(20) UNIQUE NOT NULL);
INSERT INTO dw.dim_fuente (fuente) SELECT DISTINCT fuente FROM stg.ventas_integradas ORDER BY 1;

-- ---------------- HECHOS ----------------

CREATE TABLE dw.fact_ventas (
    fecha_key     INTEGER  NOT NULL REFERENCES dw.dim_tiempo,
    producto_key  INTEGER  NOT NULL REFERENCES dw.dim_producto,
    empleado_key  INTEGER  NOT NULL REFERENCES dw.dim_empleado,
    cliente_key   INTEGER  NOT NULL REFERENCES dw.dim_cliente,
    tramo_key     SMALLINT NOT NULL REFERENCES dw.dim_tramo_edad,
    promocion_key INTEGER  NOT NULL REFERENCES dw.dim_promocion,
    tipo_pago_key INTEGER  NOT NULL REFERENCES dw.dim_tipo_pago,
    fuente_key    INTEGER  NOT NULL REFERENCES dw.dim_fuente,
    pedido_id     INTEGER  NOT NULL,           -- dimensión degenerada (nro de ticket)
    cantidad      INTEGER       NOT NULL,
    ingresos      NUMERIC(12,4) NOT NULL,
    costo         NUMERIC(12,4) NOT NULL,
    descuento     NUMERIC(12,4) NOT NULL,
    margen        NUMERIC(12,4) GENERATED ALWAYS AS (ingresos - costo) STORED,
    PRIMARY KEY (pedido_id, producto_key));

INSERT INTO dw.fact_ventas (fecha_key, producto_key, empleado_key, cliente_key, tramo_key, promocion_key,
                            tipo_pago_key, fuente_key, pedido_id, cantidad, ingresos, costo, descuento)
SELECT t.fecha_key, p.producto_key, e.empleado_key, c.cliente_key,
       te.tramo_key, pr.promocion_key, tp.tipo_pago_key, f.fuente_key,
       v.pedido_id, v.cnt_unidades_vendidas, v.mnt_ingresos, v.mnt_costo, v.mnt_descuento
FROM stg.ventas_integradas v
JOIN dw.dim_tiempo    t  ON t.fecha        = v.fecha_pedido
JOIN dw.dim_producto  p  ON p.producto_id  = v.producto_id
JOIN dw.dim_empleado  e  ON e.empleado_id  = v.empleado_id
JOIN dw.dim_cliente   c  ON c.cliente_id   = v.cliente_id
JOIN dw.dim_tramo_edad te ON extract(year FROM age(v.fecha_pedido, c.fecha_nacimiento))
                             BETWEEN te.edad_desde AND te.edad_hasta
JOIN dw.dim_promocion pr ON pr.promocion_id = v.promocion_id
JOIN dw.dim_tipo_pago tp ON tp.tipo_pago    = v.tipo_pago
JOIN dw.dim_fuente    f  ON f.fuente        = v.fuente;

CREATE TABLE dw.fact_stock (
    mes_id       INTEGER NOT NULL REFERENCES dw.dim_mes,
    producto_key INTEGER NOT NULL REFERENCES dw.dim_producto,
    unidades_recibidas INTEGER NOT NULL,
    PRIMARY KEY (mes_id, producto_key));
INSERT INTO dw.fact_stock
SELECT s.mes_id, p.producto_key, s.cant_unidades_recibidas
FROM fact_ingresos_stock s JOIN dw.dim_producto p USING (producto_id);

CREATE INDEX ix_fv_fecha    ON dw.fact_ventas (fecha_key);
CREATE INDEX ix_fv_producto ON dw.fact_ventas (producto_key);
CREATE INDEX ix_fv_empleado ON dw.fact_ventas (empleado_key);
CREATE INDEX ix_fv_tramo    ON dw.fact_ventas (tramo_key);

-- Control de carga: lo que entró al DW tiene que coincidir con el staging
SELECT 'stg.ventas_integradas' AS tabla, COUNT(*) AS filas, SUM(mnt_ingresos) AS ingresos FROM stg.ventas_integradas
UNION ALL SELECT 'dw.fact_ventas', COUNT(*), SUM(ingresos) FROM dw.fact_ventas
UNION ALL SELECT 'dw.fact_stock',  COUNT(*), SUM(unidades_recibidas) FROM dw.fact_stock;
