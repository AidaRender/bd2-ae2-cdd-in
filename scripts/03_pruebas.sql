-- =====================================================================
--  CDD-IN | Pruebas del sistema transaccional (ejecutar en DBeaver)
-- =====================================================================

-- 1) ¿Se cargó todo? Cantidad de filas por tabla principal
SELECT 'fact_ventas' AS tabla, COUNT(*) FROM fact_ventas
UNION ALL SELECT 'fact_ingresos_stock', COUNT(*) FROM fact_ingresos_stock
UNION ALL SELECT 'lu_cliente',  COUNT(*) FROM lu_cliente
UNION ALL SELECT 'lu_producto', COUNT(*) FROM lu_producto
UNION ALL SELECT 'lu_empleado', COUNT(*) FROM lu_empleado;

-- 2) Integridad: ventas por sucursal y región (usa las FK nuevas)
SELECT r.region_desc, s.sucursal_desc,
       SUM(v.cnt_unidades_vendidas) AS unidades,
       SUM(v.mnt_ingresos)          AS ingresos
FROM fact_ventas v
JOIN lu_empleado e ON e.empleado_id = v.empleado_id
JOIN lu_sucursal s ON s.sucursal_id = e.sucursal_id
LEFT JOIN lu_region r ON r.region_id = s.region_id
GROUP BY r.region_desc, s.sucursal_desc
ORDER BY ingresos DESC;

-- 3) La base rechaza datos inválidos (debería dar ERROR de clave foránea)
-- INSERT INTO fact_ventas VALUES (1, 99999, '2016-01-01', 1, 0, 143, 1, 1, 10, 8, 0);

-- 4) Transacción ACID: registrar una venta nueva de 2 productos.
--    O se guardan las dos líneas, o ninguna (atomicidad).
BEGIN;
  INSERT INTO fact_ventas VALUES (900001, 1, '2016-12-31', 1, 0, 143, 1, 1, 46, 32.8640, 0);
  INSERT INTO fact_ventas VALUES (900001, 2, '2016-12-31', 1, 0, 143, 1, 1, 11,  8.2160, 0);
  SELECT * FROM fact_ventas WHERE pedido_id = 900001;
ROLLBACK;   -- deshacemos la prueba; con COMMIT quedaría guardada

-- Comprobación: después del ROLLBACK no quedó nada
SELECT COUNT(*) AS debe_ser_cero FROM fact_ventas WHERE pedido_id = 900001;
