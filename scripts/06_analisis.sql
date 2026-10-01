-- =====================================================================
--  CDD-IN | Tarea 6: Análisis sobre el Data Warehouse
--  Ejecutar en DBeaver sobre la base cddin.
--  PRIMERO: ejecutar entero con Alt+X (crea las vistas y la función).
--  DESPUÉS: ejecutar cada SELECT de la sección "CONSULTAS" con Ctrl+Enter.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) VISTAS DE REPORTES (reemplazan las planillas Excel armadas a mano)
-- ---------------------------------------------------------------------

-- A1. Ventas (unidades e ingresos) por producto, empleado, sucursal y mes
CREATE OR REPLACE VIEW dw.v_ventas_prod_emp_suc_mes AS
SELECT t.anio, t.mes_id, t.mes_nombre, e.region, e.sucursal, e.empleado,
       p.categoria, p.subcategoria, p.producto,
       SUM(f.cantidad) AS unidades, SUM(f.ingresos) AS ingresos
FROM dw.fact_ventas f
JOIN dw.dim_tiempo   t USING (fecha_key)
JOIN dw.dim_empleado e USING (empleado_key)
JOIN dw.dim_producto p USING (producto_key)
GROUP BY t.anio, t.mes_id, t.mes_nombre, e.region, e.sucursal, e.empleado,
         p.categoria, p.subcategoria, p.producto;

-- A2. Costos por empleado, región y sucursal (con ingresos y margen para comparar)
CREATE OR REPLACE VIEW dw.v_costos_emp_reg_suc AS
SELECT e.region, e.sucursal, e.empleado,
       SUM(f.costo) AS costo, SUM(f.ingresos) AS ingresos, SUM(f.margen) AS margen,
       round(100 * SUM(f.margen) / NULLIF(SUM(f.ingresos), 0), 2) AS margen_pct
FROM dw.fact_ventas f JOIN dw.dim_empleado e USING (empleado_key)
GROUP BY e.region, e.sucursal, e.empleado;

-- A3. Producto más vendido por categoría y tramo de edad
CREATE OR REPLACE VIEW dw.v_top_producto_categoria_tramo AS
SELECT tramo, categoria, producto, unidades
FROM (
  SELECT te.tramo, p.categoria, p.producto, SUM(f.cantidad) AS unidades,
         RANK() OVER (PARTITION BY te.tramo, p.categoria ORDER BY SUM(f.cantidad) DESC) AS puesto
  FROM dw.fact_ventas f
  JOIN dw.dim_producto   p  USING (producto_key)
  JOIN dw.dim_tramo_edad te USING (tramo_key)
  WHERE te.tramo_key BETWEEN 1 AND 4          -- solo los tramos pedidos
  GROUP BY te.tramo, p.categoria, p.producto
) x WHERE puesto = 1;

-- ---------------------------------------------------------------------
-- B) ASOCIACIÓN DE PRODUCTOS: algoritmo APRIORI (reglas de asociación)
--    Canasta = ticket (pedido_id). Medidas:
--      soporte(A)      = % de tickets que contienen A
--      soporte(A,B)    = % de tickets que contienen A y B juntos
--      confianza(A->B) = soporte(A,B) / soporte(A)  -> "si compra A, prob. de que compre B"
--      lift(A->B)      = confianza(A->B) / soporte(B) -> >1 = se compran juntos más que por azar
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dw.reglas_asociacion;
CREATE TABLE dw.reglas_asociacion AS
WITH canastas AS (                          -- cada ticket con sus productos (sin repetir)
  SELECT DISTINCT pedido_id, producto_key FROM dw.fact_ventas
),
total AS (SELECT COUNT(DISTINCT pedido_id)::NUMERIC AS n FROM canastas),
-- Paso 1 de Apriori: itemsets de 1 producto que superan el soporte mínimo
items_frecuentes AS (
  SELECT producto_key, COUNT(*) AS tickets
  FROM canastas GROUP BY producto_key
  HAVING COUNT(*) >= 20                     -- soporte mínimo: 20 tickets
),
-- Paso 2 de Apriori: pares formados SOLO con productos frecuentes (poda)
pares AS (
  SELECT a.producto_key AS prod_a, b.producto_key AS prod_b, COUNT(*) AS tickets_juntos
  FROM canastas a
  JOIN canastas b ON a.pedido_id = b.pedido_id AND a.producto_key <> b.producto_key
  WHERE a.producto_key IN (SELECT producto_key FROM items_frecuentes)
    AND b.producto_key IN (SELECT producto_key FROM items_frecuentes)
  GROUP BY a.producto_key, b.producto_key
  HAVING COUNT(*) >= 20                     -- el par también debe ser frecuente
)
-- Paso 3: generar las reglas A -> B con sus medidas
SELECT pa.producto_id AS producto_a, pa.producto AS nombre_a,
       pb.producto_id AS producto_b, pb.producto AS nombre_b,
       pr.tickets_juntos,
       round(100 * pr.tickets_juntos / t.n, 3)                            AS soporte_pct,
       round(100.0 * pr.tickets_juntos / ia.tickets, 2)                   AS confianza_pct,
       round((pr.tickets_juntos::NUMERIC / ia.tickets) / (ib.tickets / t.n), 2) AS lift
FROM pares pr
CROSS JOIN total t
JOIN items_frecuentes ia ON ia.producto_key = pr.prod_a
JOIN items_frecuentes ib ON ib.producto_key = pr.prod_b
JOIN dw.dim_producto pa ON pa.producto_key = pr.prod_a
JOIN dw.dim_producto pb ON pb.producto_key = pr.prod_b;

-- Función: "dado un producto, ¿con cuál se compra más frecuentemente?"
CREATE OR REPLACE FUNCTION dw.producto_asociado(p_producto_id INTEGER, p_cantidad INTEGER DEFAULT 5)
RETURNS TABLE (producto_b INTEGER, nombre_b VARCHAR, tickets_juntos BIGINT,
               confianza_pct NUMERIC, lift NUMERIC)
LANGUAGE sql AS $$
  SELECT producto_b, nombre_b, tickets_juntos, confianza_pct, lift
  FROM dw.reglas_asociacion
  WHERE producto_a = p_producto_id
  ORDER BY tickets_juntos DESC, lift DESC
  LIMIT p_cantidad
$$;

-- =====================================================================
--  CONSULTAS (ejecutar de a una con Ctrl+Enter)
-- =====================================================================

-- 1. Ingresos por sucursal y mes (evolución)
SELECT anio, mes_id, sucursal, SUM(unidades) AS unidades, SUM(ingresos) AS ingresos
FROM dw.v_ventas_prod_emp_suc_mes
GROUP BY anio, mes_id, sucursal ORDER BY mes_id, ingresos DESC;

-- 2. Top 10 productos por ingresos
SELECT producto, categoria, SUM(unidades) AS unidades, SUM(ingresos) AS ingresos
FROM dw.v_ventas_prod_emp_suc_mes
GROUP BY producto, categoria ORDER BY ingresos DESC LIMIT 10;

-- 3. Top 10 empleados por ingresos
SELECT empleado, sucursal, region, SUM(unidades) AS unidades, SUM(ingresos) AS ingresos
FROM dw.v_ventas_prod_emp_suc_mes
GROUP BY empleado, sucursal, region ORDER BY ingresos DESC LIMIT 10;

-- 4. Costos por región
SELECT region, SUM(costo) AS costo, SUM(ingresos) AS ingresos,
       round(100 * SUM(margen) / SUM(ingresos), 2) AS margen_pct
FROM dw.v_costos_emp_reg_suc GROUP BY region ORDER BY costo DESC;

-- 5. Costos por sucursal y empleado
SELECT * FROM dw.v_costos_emp_reg_suc ORDER BY region, sucursal, costo DESC;

-- 6. Producto más vendido por categoría y tramo de edad
SELECT * FROM dw.v_top_producto_categoria_tramo ORDER BY tramo, categoria;

-- 7. Reglas de asociación más fuertes (las que más se repiten)
SELECT * FROM dw.reglas_asociacion ORDER BY tickets_juntos DESC, lift DESC LIMIT 20;

-- 8. Dado un producto, ¿con cuál se compra más? (cambiar el 233 por cualquier producto)
SELECT * FROM dw.producto_asociado(233);
