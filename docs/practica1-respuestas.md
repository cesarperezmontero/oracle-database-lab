# Práctica 1 — Creación de índices (Actividad 3.2)

**Nombre:** César Pérez Montero
**Equipo:** César Pérez Montero (individual)
**Profesor:** Richard Aviles Lopez

---

## Datos de partida

| | cliente | pedido |
|---|---|---|
| Filas | 1.000.000 | 20.000.000 |
| Páginas | 25.000 | 400.000 |
| bfr | 40 | 50 |
| Umbral con correlación mala | 0,5 % (5.000 filas) | 0,4 % (80.000 filas) |
| Correlación buena | id_cliente | id_pedido, fecha_pedido |

Supuestos de cálculo:

- Todos los índices B+ tienen altura 3: una búsqueda única cuesta 3 lecturas de índice + 1 de tabla.
- Con correlación mala, cada fila que se recupera por RID es una lectura aleatoria de página.
- Con correlación buena, el índice lee unas k / bfr páginas de tabla.
- Una entrada de índice (clave + RID) ocupa unas diez veces menos que una fila: unas 500 entradas por hoja en un índice de una columna, unas 200-300 en un índice compuesto o cubriente.
- Recorrido completo: 25.000 páginas en cliente, 400.000 en pedido.
- Para Q2 y Q8 se toma como fecha actual el 24/10/2026.

---

## Ronda 1 — ¿Por qué no usa el índice?

### Q1 · Inicio de sesión

```sql
SELECT id_cliente, nombre FROM cliente
WHERE UPPER(email) = UPPER(:email_tecleado);
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas). |
| ¿Por qué? | `UPPER()` se aplica sobre la columna indexada: `ux_cli_email` está construido sobre `email`, no sobre `UPPER(email)`, y la columna ya no aparece desnuda. |
| Tu propuesta | Reescribir. El backend guarda el email siempre en minúsculas, así que basta con pasar a minúsculas el dato tecleado: `SELECT id_cliente, nombre FROM cliente WHERE email = LOWER(:email_tecleado);` |
| Justificación con números | Búsqueda única por `ux_cli_email`: 3 + 1 = 4 lecturas frente a 25.000. A 800 por segundo: 3.200 lecturas/s frente a 20.000.000 páginas/s. No hace falta un índice funcional sobre `UPPER(email)`: costaría espacio y una escritura más por alta, y no aporta nada si el dato ya está normalizado. |

### Q2 · Pedidos del último mes

```sql
SELECT id_pedido, importe FROM pedido
WHERE fecha_pedido + INTERVAL '30' DAY >= CURRENT_DATE;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de pedido (400.000 páginas). |
| ¿Por qué? | Aritmética sobre la columna: se suma un intervalo a `fecha_pedido`, así que `ix_ped_fecha` no se puede usar. |
| Tu propuesta | Reescribir pasando la aritmética al otro lado: `SELECT id_pedido, importe FROM pedido WHERE fecha_pedido >= CURRENT_DATE - INTERVAL '30' DAY;` |
| Justificación con números | 30 días ≈ 6,7 M × 30 / 365 ≈ 550.000 filas (2,75 %). Supera el umbral del 0,4 %, pero `fecha_pedido` tiene correlación buena: rango por `ix_ped_fecha` ≈ 550.000 / 50 = 11.000 páginas de tabla + unas 1.100 hojas de índice ≈ 12.100 lecturas frente a 400.000 (unas 33 veces menos). |

### Q3 · Envíos por código postal

```sql
SELECT id_pedido, estado FROM pedido
WHERE codigo_postal = 30001;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de pedido (400.000 páginas). |
| ¿Por qué? | Dos motivos: no hay índice sobre `codigo_postal`, y además se compara un `VARCHAR(5)` con un número. El motor convierte la columna (`TO_NUMBER(codigo_postal) = 30001`), lo que rompería cualquier índice sobre ella. |
| Tu propuesta | Reescribir con literal de texto, `WHERE codigo_postal = '30001'`, y crear un índice cubriente: `CREATE INDEX ix_ped_cp ON pedido (codigo_postal) INCLUDE (id_pedido, estado);` En Oracle, que no tiene `INCLUDE`, las columnas van como clave: `(codigo_postal, id_pedido, estado)`. |
| Justificación con números | 20 M / 11.000 ≈ 1.800 pedidos por código postal (0,009 %, muy por debajo de 80.000). Con índice simple: 3 + 1.800 lecturas aleatorias ≈ 1.800. Con el cubriente: 3 + unas 6 hojas ≈ 10 lecturas, sin tocar la tabla. A 50 por segundo: 500 lecturas/s frente a 90.000 (índice simple) o 20.000.000 (hoy). Coste: 300 INSERT/s y 150 UPDATE de estado/s mantienen el índice, unas 3 páginas cada uno (≈ 1.350 páginas/s), muy por debajo de lo que se ahorra. |

### Q4 · Buscador de atención al cliente

```sql
-- a) Apellidos que terminan en «ez»
SELECT * FROM cliente WHERE apellidos LIKE '%ez';
-- b) Apellidos que empiezan por «Gonz»
SELECT * FROM cliente WHERE apellidos LIKE 'Gonz%';
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas) en las dos. |
| ¿Por qué? | No hay índice sobre `apellidos`. Aunque lo hubiera: en (a) el comodín a la izquierda impide usar un B+, y en (b) el prefijo sí es sargable pero devuelve demasiadas filas. |
| Tu propuesta | No hacer nada en ninguna de las dos. |
| Justificación con números | (b) «Gonz…» = 2 % = 20.000 filas, cuatro veces el umbral de 5.000. Con correlación mala, un índice costaría 3 + 20.000 lecturas aleatorias (equivalentes a 100.000 secuenciales) frente a 25.000 del recorrido completo: el optimizador no lo usaría. (a) Los apellidos en «-ez» (González, Pérez, Martínez, Sánchez…) son una fracción todavía mayor. Un índice de trigramas o un índice funcional sobre `REVERSE(apellidos)` haría la consulta sargable, pero devolvería igual cientos de miles de filas. Además `SELECT *` impide un índice cubriente. A 20 por minuto, 25.000 páginas por búsqueda es asumible. |

### Q5 · Identificar a quien llama

```sql
SELECT * FROM cliente
WHERE email = :dato OR telefono = :dato;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas). |
| ¿Por qué? | El `OR` incluye una columna sin índice (`telefono`). Para resolver esa rama hay que leer toda la tabla, así que de nada sirve `ux_cli_email` en la otra. |
| Tu propuesta | Crear `CREATE INDEX ix_cli_telefono ON cliente (telefono);` (no único: un teléfono puede ser compartido) y reescribir en dos ramas: `SELECT * FROM cliente WHERE email = :dato UNION ALL SELECT * FROM cliente WHERE telefono = :dato;` Ninguna fila puede cumplir las dos condiciones (un email lleva «@» y un teléfono no), así que `UNION ALL` no duplica resultados y evita la ordenación de `UNION`. |
| Justificación con números | Rama email: 3 + 1 = 4 lecturas. Rama teléfono: 3 + 1 (o pocas más) = 4. Total ≈ 8 lecturas frente a 25.000. A 10 por segundo: 80 lecturas/s frente a 250.000. La tabla cliente casi no recibe escrituras (altas de cliente), así que el índice nuevo apenas cuesta. |

---

## Ronda 2 — Compuestos, cubrientes y ORDER BY

### Q6 · Clientes de una ciudad

```sql
SELECT id_cliente, nombre, apellidos FROM cliente
WHERE ciudad = 'Lorca';
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas). |
| ¿Por qué? | El índice `ix_cli_pais_ciudad` empieza por `pais`. Por la regla del prefijo izquierdo no sirve para buscar solo por `ciudad`. |
| Tu propuesta | Reescribir añadiendo el país, que la campaña de marketing conoce: `SELECT id_cliente, nombre, apellidos FROM cliente WHERE pais = 'ES' AND ciudad = 'Lorca';` |
| Justificación con números | 1.000 filas = 0,1 %, por debajo del umbral de 5.000. Rango por `ix_cli_pais_ciudad`: 3 + 1.000 lecturas aleatorias ≈ 1.003 frente a 25.000 (25 veces menos), sin crear ningún índice. Con 30 consultas por hora no compensa un índice nuevo sobre `ciudad` sola. |

### Q7 · Historial del cliente en la app

```sql
SELECT id_pedido, fecha_pedido, importe, estado
FROM   pedido
WHERE  id_cliente = :c
  AND  fecha_pedido >= CURRENT_DATE - INTERVAL '1' YEAR
ORDER  BY fecha_pedido DESC;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Rango por `ix_ped_cliente` + acceso a la tabla por RID, filtro de fecha sobre las filas leídas y ordenación. |
| ¿Por qué? | El índice solo tiene `id_cliente`: hay que ir a la tabla por los 20 pedidos del cliente para descartar los 13 de más de un año y luego ordenar los 7 restantes. |
| Tu propuesta | (a) Índice compuesto, igualdad primero y luego rango/orden: `CREATE INDEX ix_ped_cli_fec ON pedido (id_cliente, fecha_pedido);` Se lee hacia atrás y sale ya ordenado, sin `SORT`. (b) Versión cubriente, la que propongo: `CREATE INDEX ix_ped_cli_fec ON pedido (id_cliente, fecha_pedido) INCLUDE (id_pedido, importe, estado);` (en Oracle, todas como columnas de clave). En los dos casos se elimina `ix_ped_cliente`, que queda redundante por el prefijo izquierdo. |
| Justificación con números | Hoy: 3 + 20 = 23 lecturas por consulta → 46.000 lecturas/s a 2.000 por segundo, más 2.000 ordenaciones/s. (a) 3 + 7 = 10 lecturas → 20.000/s, sin ordenación. (b) Las 7 entradas caben en una hoja: unas 3-4 lecturas → 6.000-8.000/s, sin tocar la tabla. El precio de (b) es que los 150 UPDATE de estado/s modifican el índice (≈ 3 páginas cada uno, 450/s), muy por debajo de las ≈ 14.000 lecturas/s que ahorra frente a (a). Como sustituye a `ix_ped_cliente`, el número de índices que mantiene cada INSERT no cambia. |

### Q8 · Contador del panel de dirección

```sql
SELECT COUNT(*) FROM pedido
WHERE fecha_pedido >= DATE '2026-01-01';
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Rango solo índice sobre `ix_ped_fecha` (no se toca la tabla). |
| ¿Por qué? | `COUNT(*)` no necesita ninguna columna de la tabla y el único filtro está en el índice: basta con contar las entradas del rango. |
| Tu propuesta | No hacer nada: la consulta ya es óptima. |
| Justificación con números | Del 1/1 al 24/10 de 2026 hay unos 5,45 M pedidos (27 %). El índice tiene unas 20 M / 500 = 40.000 hojas, así que el rango lee ≈ 3 + 11.000 hojas frente a 400.000 páginas del recorrido completo de tabla. Una vez por minuto, 11.000 lecturas es asumible. |

### Q9 · Últimos 20 pedidos

```sql
SELECT * FROM pedido
ORDER BY fecha_pedido DESC
FETCH FIRST 20 ROWS ONLY;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido de `ix_ped_fecha` hacia atrás desde el final, parando en la fila 20, + acceso por RID. |
| ¿Por qué? | El índice ya entrega las filas en el orden del `ORDER BY` y `fecha_pedido` es `NOT NULL`, así que no falta ninguna fila. Con `FETCH FIRST` el motor se detiene tras 20 entradas. |
| Tu propuesta | No hacer nada. |
| Justificación con números | 3 lecturas de índice + 20 filas que, por la correlación buena, están en 1 o 2 páginas de tabla ≈ 5 lecturas. Sin índice serían 400.000 páginas + ordenar 20 M filas, cada 10 segundos. |

---

## Ronda 3 — ¿Merece la pena el índice?

### Q10 · Clientes de España

```sql
SELECT * FROM cliente WHERE pais = 'ES';
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas), aunque exista `ix_cli_pais_ciudad`. |
| ¿Por qué? | «ES» es el 60 % de los clientes, 120 veces el umbral del 0,5 %. El optimizador descarta el índice. |
| Tu propuesta | No hacer nada. |
| Justificación con números | Por índice: 3 + 600.000 lecturas aleatorias (equivalentes a 3.000.000 secuenciales) frente a 25.000 secuenciales del recorrido completo. Es un informe semanal: el recorrido completo es lo correcto. |

### Q11 · Ventas de 2025

```sql
SELECT SUM(importe) FROM pedido
WHERE EXTRACT(YEAR FROM fecha_pedido) = 2025;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de pedido (400.000 páginas). |
| ¿Por qué? | Función sobre la columna (`EXTRACT`): `ix_ped_fecha` no se puede usar. |
| Tu propuesta | Reescribir como rango semiabierto, sin índice nuevo: `SELECT SUM(importe) FROM pedido WHERE fecha_pedido >= TIMESTAMP '2025-01-01 00:00:00' AND fecha_pedido < TIMESTAMP '2026-01-01 00:00:00';` El `<` final incluye todo el 31 de diciembre aunque `fecha_pedido` lleve hora. |
| Justificación con números | 2025 ≈ 6,7 M filas (33 %), muy por encima del 0,4 %, pero `fecha_pedido` tiene correlación buena: ≈ 6,7 M / 50 = 134.000 páginas de tabla + 13.400 hojas ≈ 147.000 lecturas, casi todas secuenciales, frente a 400.000 (2,7 veces menos). La reescritura es gratis. Un índice funcional sobre `EXTRACT(YEAR …)` o un cubriente `(fecha_pedido, importe)` no compensan para un informe mensual: costarían mantenimiento en los 300 INSERT/s. |

### Q12 · Panel del almacén: pedidos pendientes

```sql
SELECT id_pedido, id_cliente, fecha_pedido
FROM pedido
WHERE estado = 'P'
ORDER BY fecha_pedido;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de pedido (400.000 páginas) + ordenación de 400.000 filas. |
| ¿Por qué? | No hay índice sobre `estado`. Y un B+ normal sobre `estado` tampoco serviría: 400.000 filas son 5 veces el umbral de 80.000 y la correlación es mala. |
| Tu propuesta | Índice parcial y cubriente, solo con los pendientes y ordenado por fecha: `CREATE INDEX ix_ped_pendientes ON pedido (fecha_pedido) INCLUDE (id_pedido, id_cliente) WHERE estado = 'P';` En Oracle se emula con un índice funcional que deja fuera las filas que no interesan (las claves `NULL` no se indexan): `CREATE INDEX ix_ped_pendientes ON pedido (CASE WHEN estado = 'P' THEN fecha_pedido END);` |
| Justificación con números | El índice tiene solo 400.000 entradas (≈ 1.600 hojas), no 20 M. Lectura cada 30 s: ≈ 1.600 hojas en orden, sin ir a la tabla y sin ordenar, frente a 400.000 páginas + `SORT`. Escritura: cada INSERT nace en 'P' y añade una entrada, y solo los UPDATE que sacan un pedido de 'P' borran una. Un índice completo sobre `estado` movería una entrada en cada uno de los 150 UPDATE/s y guardaría 19,6 M entradas inútiles de 'E', 'C' y 'D'. |

### Q13 · Verificación de identidad

```sql
SELECT id_cliente, nombre, apellidos FROM cliente
WHERE dni = :dni;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de cliente (25.000 páginas). |
| ¿Por qué? | No existe índice sobre `dni`. |
| Tu propuesta | Crear un índice único: `CREATE UNIQUE INDEX ux_cli_dni ON cliente (dni);` |
| Justificación con números | Búsqueda única: 3 + 1 = 4 lecturas frente a 25.000. A 500 por segundo: 2.000 lecturas/s frente a 12.500.000 páginas/s. Además la base de datos garantiza la unicidad que hoy controla la aplicación: dos altas simultáneas con el mismo DNI pueden pasar el control de la aplicación, pero no el índice único. No lo hago cubriente: solo ahorraría 1 lectura de 4. |

---

## Ronda 4 — Bitmap, hash y auditoría

### Q14 · Analistas: ventas por combinación de filtros

```sql
SELECT SUM(importe) FROM venta_hecho
WHERE region = 'Sur' AND canal = 'W'
  AND categoria = 'Hogar' AND anio = 2025;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Recorrido completo de `venta_hecho` (500 M filas). No tiene índices. |
| ¿Por qué? | No hay índices, y cada filtro por separado es poco selectivo: `canal` deja pasar 1/3 de las filas, `region` 1/6, `anio` 1/5 y `categoria` 1/25. |
| Tu propuesta | Un índice bitmap por columna de filtro: `CREATE BITMAP INDEX bx_vh_region ON venta_hecho (region);` `CREATE BITMAP INDEX bx_vh_canal ON venta_hecho (canal);` `CREATE BITMAP INDEX bx_vh_categoria ON venta_hecho (categoria);` `CREATE BITMAP INDEX bx_vh_anio ON venta_hecho (anio);` En la carga nocturna se desactivan y se reconstruyen al terminar. |
| Justificación con números | Combinados: 1/6 × 1/3 × 1/25 × 1/5 = 1/2.250 → ≈ 222.000 filas (0,044 %). El motor cruza los mapas de bits con AND en memoria y solo va a la tabla por esas filas. Un compuesto B+ no sirve porque cada analista combina filtros distintos: con 4 columnas hay 15 combinaciones y un único orden de columnas solo atiende las que respetan el prefijo. Los bitmap son pequeños con tan pocos valores distintos (39 en total, un mapa de 500 M bits ≈ 62,5 MB sin comprimir por valor, mucho menos comprimido). Su punto débil, la escritura concurrente, no existe aquí: durante el día la tabla es de solo lectura. Suponiendo bfr ≈ 50, el recorrido completo son 10 M páginas frente a como mucho 222.000. |

### Q15 · Validar una sesión

```sql
SELECT id_cliente FROM sesion_web WHERE token = :t;
-- Y cada minuto, limpieza:
DELETE FROM sesion_web WHERE caduca < CURRENT_TIMESTAMP;
```

| Casilla | Respuesta |
|---|---|
| Ruta de acceso hoy | Validación: búsqueda única por el B+ de la clave primaria (`token`). Limpieza: recorrido completo de la tabla (no hay índice sobre `caduca`). |
| ¿Por qué? | La PK crea un B+ por defecto. El `DELETE` filtra por rango sobre `caduca`, que no está indexada. |
| Tu propuesta | Validación: sustituir el B+ de la PK por un índice hash sobre `token` (por ejemplo, en una tabla en memoria de SQL Server: `token CHAR(64) NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 262144)`). Limpieza: no hacer nada. |
| Justificación con números | Validación: el token es aleatorio y solo se busca por igualdad exacta, nunca por rango ni orden, que es justo lo que ofrece el hash. Acceso ≈ 1 cubeta + 1 fila frente a 3 + 1 del B+: a 40.000 por segundo, ≈ 80.000 accesos/s frente a 160.000. Limpieza: una vez por minuto recorrer 200.000 filas en memoria (≈ 3.300 filas/s de media) es mínimo frente a 40.000 validaciones/s. Un índice sobre `caduca` solo lo usaría esa sentencia y habría que mantenerlo en cada alta de sesión, y el hash no serviría porque `<` es un rango. |

### Q16 · Auditoría de los índices de pedido

| Índice | Decisión | Motivo en una línea |
|---|---|---|
| Clave primaria (`id_pedido`) | Mantener | Identidad y unicidad del pedido, búsquedas por id. |
| `ix_ped_cliente` | Eliminar | Redundante: `ix_ped_cli_fec` (Q7) empieza por `id_cliente` y cubre las mismas búsquedas por prefijo izquierdo. |
| `ix_ped_fecha` | Mantener | Lo usan Q2, Q8, Q9 y Q11, con correlación buena. |
| `ix_ped_importe` | Eliminar | 0 lecturas en 6 meses y se mantiene en 300 INSERT/s. |
| `ix_ped_estado` | Rechazar | 4 valores (C = 90 %, P = 2 % = 400.000 > 80.000): no se usaría, y se movería en los 150 UPDATE/s. Lo sustituye el parcial de Q12. |
| `ix_ped_canal` | Rechazar | 3 valores (≈ 33 % cada uno), muy por encima del 0,4 %, y ninguna consulta filtra por canal. |
| `ix_ped_cli_fec` | Crear (en versión cubriente) | Q7, la consulta más frecuente (2.000/s): `(id_cliente, fecha_pedido) INCLUDE (id_pedido, importe, estado)`. |
| `ix_ped_fec_cli` | Rechazar | Ninguna consulta filtra por igualdad de fecha y luego por cliente. Por prefijo, lo que hace ya lo cubre `ix_ped_fecha`. |
| `ix_ped_cp` | Crear (en versión cubriente) | Q3 (50/s) tras reescribir el literal: `(codigo_postal) INCLUDE (id_pedido, estado)`. |
| Otros: `ix_ped_pendientes` (Q12) | Crear | Parcial `WHERE estado = 'P'` sobre `fecha_pedido`: panel del almacén sin recorrido completo ni ordenación. |

**Páginas que toca un INSERT.** Modelo: 1 página del montículo + 3 por cada índice B+ (raíz, nodo interno y hoja).

| Escenario | Índices en pedido | Páginas por INSERT | A 300 INSERT/s |
|---|---|---|---|
| Hoy | PK, cliente, fecha, importe (4) | 1 + 4 × 3 = **13** | 3.900 páginas/s |
| Con la propuesta del compañero | Los 4 de hoy + estado, canal, cli_fec, fec_cli, cp (9) | 1 + 9 × 3 = **28** | 8.400 páginas/s |
| Con mi propuesta | PK, fecha, cli_fec, cp, pendientes (5) | 1 + 5 × 3 = **16** | 4.800 páginas/s |

Todo pedido nace en 'P', así que cada INSERT entra también en el índice parcial. Este es pequeño (≈ 1.600 hojas) y probablemente tenga altura 2, lo que dejaría el total en 15.

Los UPDATE de estado también cuentan. Hoy no tocan ningún índice. Con mi propuesta modifican los dos cubrientes (≈ 3 + 3 páginas) y, si el pedido sale de 'P', el parcial (≈ 3), unas 1.500 páginas/s a 150 UPDATE/s. Con la del compañero, `ix_ped_estado` mueve la entrada (borrar + insertar ≈ 6 páginas), unas 1.050 páginas/s.

En total, mi propuesta cuesta unas 6.300 páginas/s de escritura (hoy, unas 4.050; la del compañero, unas 9.450) y a cambio elimina la mayor parte de la lectura: Q3 pasa de 20 M páginas/s a 500, Q7 de 46.000 lecturas/s a unas 7.000 y Q12 de 400.000 páginas cada 30 s a 1.600. Los índices del compañero añaden casi el doble de escritura y solo `ix_ped_cli_fec` y `ix_ped_cp` resuelven alguna consulta.

---

## Cierre: tres ideas para llevarse

1. **Escribir predicados sargables antes de crear nada.** La columna indexada va desnuda: sin funciones, sin aritmética y sin conversiones de tipo. Reescribir es gratis y en Q1, Q2, Q3, Q6 y Q11 bastó para usar un índice que ya existía.
2. **Decidir con números, no por intuición.** Selectividad frente al punto de equilibrio (0,5 % en cliente, 0,4 % en pedido) y correlación física. Un índice sobre una columna poco selectiva no se usa (Q4b, Q10, `ix_ped_estado`), y la correlación buena hace rentable un rango grande (Q2, Q11).
3. **Cada índice se paga en cada escritura.** Antes de crear uno hay que mirar redundancias por prefijo y, después, auditar su uso: `ix_ped_importe` llevaba 6 meses sin una lectura y `ix_ped_cliente` sobraba. Menos índices, bien elegidos (compuestos, cubrientes, parciales), rinden más que muchos simples.
