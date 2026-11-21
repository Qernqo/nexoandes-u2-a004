# Análisis de la ventana de observación U2

- Registro HTTP: `evidencias/20261121T183231Z_actualizacion_v2_http.csv` (448 muestras en total)
- Inicio (controlador): 2026-11-21T18:41:44.000Z | Estabilización: 2026-11-21T18:44:13.000Z
- Intervalo evaluado: 2026-11-21T18:40:44.000Z → 2026-11-21T18:46:13.000Z (329 s)
- Muestras dentro del intervalo: 164 | antes: 247 | después: 37 (se conservan y no se evalúan)
- Versión de origen: v1 | objetivo: v2 | identidad esperada: a004/c50/X=4

## Cobertura y cadencia
- Cadencia real de envío: media 2.00 s, mediana 2.00 s, máxima 2.02 s (programada: 2 s)
- Separación máxima en el intervalo (con bordes): 2.02 s entre 2026-11-21T18:43:53.305Z y 2026-11-21T18:43:55.320Z (tolerancia 7 s)
- Cobertura completa: SÍ

## Versiones observadas por fase
- antes: v1=30
- transicion: v1=24, v2=50
- despues: v2=60
- Instancias que respondieron con v1: i-05d02cc45da89f5a4, i-07a40b5345ffa6ec0
- Instancias que respondieron con v2: i-0554bb08f520eacb5, i-064b4796bae7c7f7c

## Fallos funcionales en el intervalo
- Ninguno (0 timeouts, 0 errores, 0 HTTP != 200, 0 identidades/versiones incorrectas).

## Capacidad y controlador (consultas al proveedor)
- Registro AWS: `evidencias/20261121T183232Z_actualizacion_v2_aws.csv` (17 consultas en el intervalo)
- Separación máxima entre consultas (con bordes): 20.0 s entre 2026-11-21T18:40:52.000Z y 2026-11-21T18:41:12.000Z (máximo 30 s)
- Destinos healthy en el intervalo: mínimo 2, máximo 4 (capacidad base declarada 2)
- Estados del controlador observados: Estable, Reemplazo
- Última consulta: 2026-11-21T18:46:12Z estado=Estable healthy=2 LT=3
- Capacidad comprobada: SÍ
- Las consultas acreditan los instantes observados; no prueban lo ocurrido entre ellas.

## Resultado
- Ventana completa: SÍ
- Cero fallos funcionales: SÍ
- Solo versión objetivo después de estabilizar: SÍ
- Capacidad base comprobada: SÍ

**ACEPTADO** según los criterios declarados. No se afirma disponibilidad absoluta; contrastar con las consultas al proveedor.
