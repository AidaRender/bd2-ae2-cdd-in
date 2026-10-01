# AE2 Base de Datos II — Caso CDD-IN

Sistema transaccional, ETL, Data Warehouse (modelo estrella) y algoritmo Apriori en PostgreSQL.

## Orden de ejecución
1. `01_crear_esquema_cddin.sql` — estructura del sistema transaccional (DBeaver)
2. `02_cargar_datos.sql` — datos migrados (psql: `\i 02_cargar_datos.sql`)
3. `03_pruebas.sql` — pruebas de integridad y transacción ACID
4. `04_etl.sql` — ETL de las planillas (psql, desde la carpeta etl)
5. `05_data_warehouse.sql` — modelo estrella y carga del DW
6. `06_analisis.sql` — reportes, segmentación y reglas de asociación (Apriori)

Memoria completa: `Memoria_AE2_BaseDeDatosII_CDD-IN.docx`
