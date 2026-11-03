-- =====================================================================
--  CDD-IN  |  Base de Datos II - AE2  |  Tarea inicial: Sistema transaccional
--  Motor: PostgreSQL
--  Origen: bdestudio.accdb (BD aportada por la cátedra), migrada y corregida
-- ---------------------------------------------------------------------
--  Correcciones respecto del modelo original en Access:
--   1. Tipos de datos unificados: todas las claves son INTEGER/SMALLINT
--      (en Access PRODUCTO_ID era DOUBLE en LU_PRODUCTO, INTEGER en
--      FACT_VENTAS y SMALLINT en FACT_INGRESOS_STOCK; lo mismo con
--      CLIENTE_ID, EMPLEADO_ID, etc.).
--   2. Montos en NUMERIC (no DOUBLE) para evitar errores de redondeo.
--   3. Fechas como DATE (el horario siempre era 00:00:00).
--   4. Se definen claves primarias y foráneas (Access no las tenía).
--   5. Se elimina LU_CLIENTE.EDAD: es un dato derivado de
--      FECHA_NACIMIENTO que queda desactualizado con el tiempo.
--   6. Se agrega 'Sucursal 3', referenciada por empleados pero
--      inexistente en LU_SUCURSAL (error de integridad del origen).
-- =====================================================================

-- ---------- Tiempo ----------
CREATE TABLE lu_mes (
    mes_id      INTEGER     PRIMARY KEY,          -- formato AAAAMM
    anio_id     SMALLINT    NOT NULL,
    mes_desc    VARCHAR(50) NOT NULL
);

CREATE TABLE lu_fecha (
    dia_id      DATE        PRIMARY KEY,
    mes_id      INTEGER     NOT NULL REFERENCES lu_mes(mes_id),
    anio_id     SMALLINT    NOT NULL
);

-- ---------- Geografía / Empleados ----------
CREATE TABLE lu_region (
    region_id   SMALLINT    PRIMARY KEY,
    region_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_sucursal (
    sucursal_id   SMALLINT    PRIMARY KEY,
    sucursal_desc VARCHAR(50) NOT NULL,
    region_id     SMALLINT    REFERENCES lu_region(region_id)   -- NULL = región desconocida
);

CREATE TABLE lu_empleado (
    empleado_id   SMALLINT    PRIMARY KEY,
    empleado_desc VARCHAR(50) NOT NULL,
    sucursal_id   SMALLINT    NOT NULL REFERENCES lu_sucursal(sucursal_id)
);

-- ---------- Productos ----------
CREATE TABLE lu_categoria (
    categoria_id   SMALLINT    PRIMARY KEY,
    categoria_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_subcategoria (
    subcategoria_id   SMALLINT    PRIMARY KEY,
    categoria_id      SMALLINT    NOT NULL REFERENCES lu_categoria(categoria_id),
    subcategoria_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_proveedor (
    proveedor_id   SMALLINT    PRIMARY KEY,
    proveedor_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_producto (
    producto_id          INTEGER       PRIMARY KEY,
    producto_desc        VARCHAR(255)  NOT NULL,
    mnt_precio_unitario  NUMERIC(12,4) NOT NULL,
    mnt_costo_unitario   NUMERIC(12,4) NOT NULL,
    subcategoria_id      SMALLINT      NOT NULL REFERENCES lu_subcategoria(subcategoria_id),
    proveedor_id         SMALLINT      NOT NULL REFERENCES lu_proveedor(proveedor_id)
);

-- ---------- Clientes ----------
CREATE TABLE lu_genero           (genero_id           SMALLINT PRIMARY KEY, genero_desc           VARCHAR(50) NOT NULL);
CREATE TABLE lu_educacion        (educacion_id        SMALLINT PRIMARY KEY, educacion_desc        VARCHAR(50) NOT NULL);
CREATE TABLE lu_estado_civil     (estado_civil_id     SMALLINT PRIMARY KEY, estado_civil_desc     VARCHAR(50) NOT NULL);
CREATE TABLE lu_rango_ingresos   (rango_ingresos_id   SMALLINT PRIMARY KEY, rango_ingresos_desc   VARCHAR(50) NOT NULL);
CREATE TABLE lu_tipo_alojamiento (tipo_alojamiento_id SMALLINT PRIMARY KEY, tipo_alojamiento_desc VARCHAR(50) NOT NULL);
CREATE TABLE lu_tamanio_familia  (tamanio_familia_id  SMALLINT PRIMARY KEY, tamanio_familia_desc  VARCHAR(50) NOT NULL);

CREATE TABLE lu_cliente (
    cliente_id          INTEGER      PRIMARY KEY,
    cliente_nombre      VARCHAR(255) NOT NULL,
    fecha_nacimiento    DATE         NOT NULL,
    codigo_postal       VARCHAR(10),
    genero_id           SMALLINT REFERENCES lu_genero(genero_id),
    rango_ingresos_id   SMALLINT REFERENCES lu_rango_ingresos(rango_ingresos_id),
    estado_civil_id     SMALLINT REFERENCES lu_estado_civil(estado_civil_id),
    educacion_id        SMALLINT REFERENCES lu_educacion(educacion_id),
    tipo_alojamiento_id SMALLINT REFERENCES lu_tipo_alojamiento(tipo_alojamiento_id),
    tamanio_familia_id  SMALLINT REFERENCES lu_tamanio_familia(tamanio_familia_id)
);

-- ---------- Ventas: promociones y pagos ----------
CREATE TABLE lu_promo_tipo (
    promo_tipo_id   SMALLINT    PRIMARY KEY,
    promo_tipo_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_promocion (
    promocion_id   SMALLINT    PRIMARY KEY,
    promo_tipo_id  SMALLINT    NOT NULL REFERENCES lu_promo_tipo(promo_tipo_id),
    promocion_desc VARCHAR(50) NOT NULL
);

CREATE TABLE lu_tipo_pago (
    tipo_pago_id   SMALLINT    PRIMARY KEY,
    tipo_pago_desc VARCHAR(50) NOT NULL
);

-- ---------- Hechos ----------
CREATE TABLE fact_ventas (
    pedido_id             INTEGER       NOT NULL,
    producto_id           INTEGER       NOT NULL REFERENCES lu_producto(producto_id),
    fecha_pedido          DATE          NOT NULL REFERENCES lu_fecha(dia_id),
    empleado_id           SMALLINT      NOT NULL REFERENCES lu_empleado(empleado_id),
    promocion_id          SMALLINT      NOT NULL REFERENCES lu_promocion(promocion_id),
    cliente_id            INTEGER       NOT NULL REFERENCES lu_cliente(cliente_id),
    tipo_pago_id          SMALLINT      NOT NULL REFERENCES lu_tipo_pago(tipo_pago_id),
    cnt_unidades_vendidas INTEGER       NOT NULL CHECK (cnt_unidades_vendidas > 0),
    mnt_ingresos          NUMERIC(12,4) NOT NULL,
    mnt_costo             NUMERIC(12,4) NOT NULL,
    mnt_descuento         NUMERIC(12,4) NOT NULL DEFAULT 0,
    PRIMARY KEY (pedido_id, producto_id)          -- una línea por producto en cada ticket
);

CREATE TABLE fact_ingresos_stock (
    mes_id                  INTEGER NOT NULL REFERENCES lu_mes(mes_id),
    producto_id             INTEGER NOT NULL REFERENCES lu_producto(producto_id),
    cant_unidades_recibidas INTEGER NOT NULL CHECK (cant_unidades_recibidas >= 0),
    PRIMARY KEY (mes_id, producto_id)
);

-- Índices para las consultas más frecuentes
CREATE INDEX ix_ventas_fecha    ON fact_ventas (fecha_pedido);
CREATE INDEX ix_ventas_empleado ON fact_ventas (empleado_id);
CREATE INDEX ix_ventas_cliente  ON fact_ventas (cliente_id);
CREATE INDEX ix_ventas_producto ON fact_ventas (producto_id);
