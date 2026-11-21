# Análisis de la ventana de observación U2

- Registro HTTP: `evidencias/20261121T190045Z_recuperacion_v1_http.csv` (312 muestras en total)
- Inicio (controlador): 2026-11-21T19:05:35.000Z | Estabilización: 2026-11-21T19:08:01.000Z
- Intervalo evaluado: 2026-11-21T19:04:35.000Z → 2026-11-21T19:10:01.000Z (326 s)
- Muestras dentro del intervalo: 163 | antes: 115 | después: 34 (se conservan y no se evalúan)
- Versión de origen: v2 | objetivo: v1 | identidad esperada: a004/c50/X=4

## Cobertura y cadencia
- Cadencia real de envío: media 2.00 s, mediana 2.00 s, máxima 2.02 s (programada: 2 s)
- Separación máxima en el intervalo (con bordes): 2.02 s entre 2026-11-21T19:06:47.149Z y 2026-11-21T19:06:49.166Z (tolerancia 7 s)
- Cobertura completa: SÍ

## Versiones observadas por fase
- antes: v2=30
- transicion: v1=50, v2=23
- despues: v1=60
- Instancias que respondieron con v1: i-03ec8843710b8c884, i-07f61c97296adf415
- Instancias que respondieron con v2: i-0554bb08f520eacb5, i-064b4796bae7c7f7c

## Fallos funcionales en el intervalo
- Ninguno (0 timeouts, 0 errores, 0 HTTP != 200, 0 identidades/versiones incorrectas).

## Capacidad y controlador (consultas al proveedor)
- Registro AWS: `evidencias/20261121T190046Z_recuperacion_v1_aws.csv` (16 consultas en el intervalo)
- Separación máxima entre consultas (con bordes): 20.0 s entre 2026-11-21T19:04:46.000Z y 2026-11-21T19:05:06.000Z (máximo 30 s)
- Destinos healthy en el intervalo: mínimo 2, máximo 2 (capacidad base declarada 2)
- Estados del controlador observados: Estable, Reemplazo
- Última consulta: 2026-11-21T19:09:46Z estado=Estable healthy=2 LT=4
- Capacidad comprobada: SÍ
- Las consultas acreditan los instantes observados; no prueban lo ocurrido entre ellas.

## Resultado
- Ventana completa: SÍ
- Cero fallos funcionales: SÍ
- Solo versión objetivo después de estabilizar: SÍ
- Capacidad base comprobada: SÍ

**ACEPTADO** según los criterios declarados. No se afirma disponibilidad absoluta; contrastar con las consultas al proveedor.
