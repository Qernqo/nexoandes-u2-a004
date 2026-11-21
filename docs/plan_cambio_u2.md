# Plan de cambio U2 — Portal v1 → v2 en AWS (declarado ANTES de ejecutar)

> Commit de este plan: el commit de la rama `docs/plan-cambio-v2` que introduce este texto (ver `git log -- docs/plan_cambio_u2.md`) · fecha UTC: `2026-11-21T17:43:30Z` · autor: a004
> Este documento se versiona y se revisa en un PR **antes** del PR que cambia `app_version`.

## 1. Versiones y artefactos

| Elemento | v1 (origen / retorno) | v2 (objetivo) |
|---|---|---|
| Artefacto | `user_data_u2.sh.tpl` con `portal_version=v1` (perfil `basic`) | misma plantilla con `portal_version=v2` (perfil `extended`) |
| SHA-256 del artefacto instalado | `82f7e3a976f7ec7b46f739244e44e47b59a73aa840e0269870d3b0f42e1fd7fa` (E03) | distinto de v1; se registra en E05 |
| Launch Template | `na-u2-c50-a004-lt` versión `1` (lt-078862d5af9becb83) | versión `2` (se crea en el apply) |
| AMI | `ami-0a951420c495183dc` (Ubuntu 24.04, fijada, igual en ambas) | igual |
| build_ref | `e3f129c` | commit del PR `feat/portal-v2` (se registra en E05) |
| Dependencias | Python 3 de la imagen, systemd, IMDSv2 | iguales |
| Persistencia | ninguna (sin datos de negocio; instancias reemplazables) | igual |

## 2. Estrategias comparadas

| Criterio | Rolling (Instance Refresh) — **elegida** | Blue-green (2 ASG / 2 TG) | In-place (modificar EC2) |
|---|---|---|---|
| Inmutable | Sí (instancias nuevas) | Sí | **No** (descartada) |
| Capacidad extra | +2 temporal (max 200 %) | ×2 durante todo el cambio | 0 |
| Costo / cuota Learner Lab | Bajo (máx. 4 t3.micro) | Mayor (2 grupos completos) | Mínimo |
| Complejidad | Baja: un ASG, un TG, un controlador | Alta: conmutación de listener/TG | Baja pero manual |
| Recuperación | Nuevo refresh a la versión anterior de la plantilla | Volver el listener al TG azul (rápido) | Re-parcheo manual |
| Riesgo | Mezcla v1/v2 durante la transición (admitida) | Conmutación instantánea | Deriva de configuración |

Restricción que cambiaría la decisión: si se exigiera conmutación instantánea sin mezcla de versiones o
recuperación en segundos, se elegiría blue-green, asumiendo el doble de capacidad.

## 3. Parámetros del cambio

- **Controlador único:** Instance Refresh del ASG `na-u2-c50-a004-asg`, iniciado por Terraform desde el pipeline.
- **Capacidad base:** 2 destinos healthy. **Temporal:** hasta 2 adicionales (max 4).
- **Preferencias:** MinHealthy 100 %, MaxHealthy 200 %, warmup 120 s, auto_rollback desactivado.
- **Health check:** `GET /api/check` = 200 (comprobación funcional), intervalo 10 s, umbral 2.
- **Endpoint observado:** `http://na-u2-c50-a004-alb-101744380.us-east-1.elb.amazonaws.com/api/check` (el mismo durante toda la prueba).

## 4. Aceptación

1. Ventana completa: inicio − 60 s → estabilización + 120 s; peticiones cada 2 s, timeout 5 s, sin reintentos; separación ≤ 7 s.
2. Cero fallos funcionales (timeout, error, HTTP ≠ 200, `passed` ≠ true, identidad o versión incorrecta).
3. Capacidad: ≥ 2 destinos healthy en cada consulta al proveedor (cada ≤ 30 s).
4. Versión final: solo v2 después de estabilizar; todos los destinos en la nueva versión de plantilla.
5. Instance Refresh en estado `Successful` y plan posterior sin cambios.

**Estabilización** = refresh `Successful` + destinos healthy ≥ 2 + todos en la versión nueva + v2 comprobada por HTTP.

## 5. Señales de fallo y detención

| Señal | Acción |
|---|---|
| Destinos healthy < 2 en una consulta | Detener: `aws autoscaling cancel-instance-refresh` y evaluar retorno |
| Fallo funcional HTTP repetido (≥ 3 consecutivos) | Detener el refresh y registrar |
| Refresh `Failed` / `Cancelled` o timeout del pipeline (40 min) | No continuar; recuperación a v1 |
| Credenciales del laboratorio por expirar (< 45 min) | No iniciar el cambio |

## 6. Recuperación planificada (E07)

- **Disparador:** ensayo planificado de reversión tras estabilizar v2 (decisión registrada en la bitácora).
- **Acción:** PR que restablece `app_version = "v1"` → pipeline → nueva versión de plantilla con el artefacto v1 → Instance Refresh.
- **Requisitos:** AMI y plantilla v1 reproducibles; mismo endpoint; misma capacidad base.
- **Verificación:** perfil `basic`, SHA-256 igual al de v1 en E03, IDs nuevos, refresh `Successful`, plan posterior sin cambios.

## 7. Herramientas y evidencias

`observe_http.sh` (PC) · `observe_aws.sh` (PC, cada 20 s) · `refresh_times.sh` · `analyze_window.py` ·
`capture_state.sh` · registros del job `apply` (wait_refresh.log, verify_portal.log) · consola AWS.

## 8. Estado de partida (E03, antes del cambio)

| Dato | Valor |
|---|---|
| Instancias v1 | i-07a40b5345ffa6ec0 (us-east-1a, 10.4.10.39) · i-05d02cc45da89f5a4 (us-east-1b, 10.4.20.186) |
| Target Group | na-u2-c50-a004-tg · 2 healthy · health check /api/check |
| Plan posterior | `No changes` (run 44931248948) |
| Registro | `evidencias/*_E04_antes_del_cambio_estado.txt` |

---

## 9. ADENDA (declarada 2026-11-21T18:27:07Z, ANTES de reintentar el cambio) — controlador adaptado

**Hecho que la motiva.** El 2026-11-21 a las 18:19:58Z el apply del PR #6 (run 44933633166) falló:
`AccessDenied … not authorized to perform: autoscaling:StartInstanceRefresh … with an explicit deny in a service control policy`.
La cuenta del Learner Lab prohíbe Instance Refresh por SCP (restricción del proveedor, no del código).
Efecto real: se creó la versión 2 de la Launch Template y el ASG quedó apuntando a ella, pero **no se reemplazó ninguna instancia**;
las 2 instancias v1 siguieron atendiendo (525 respuestas HTTP 200 v1, 0 fallos, ≥ 2 healthy en todo el registro).
Evidencia: `evidencias/bitacora/intento_v2_refresh_denegado_run44933633166/`.

**Estrategia adaptada: reemplazo inmutable del ASG sobre el mismo Target Group.**

| Criterio | Reemplazo de ASG (create_before_destroy) — **elegida por restricción** | Rolling Instance Refresh (plan original) |
|---|---|---|
| Disponible en el Learner Lab | Sí (Create/DeleteAutoScalingGroup ya usados en el despliegue y destroy) | **No** (denegado por SCP) |
| Inmutable | Sí: ASG e instancias nuevas; nunca se modifica una instancia | Sí |
| Controlador único | Terraform desde el pipeline (crea `na-u2-c50-a004-asg-ltN`, espera, elimina el anterior) | Instance Refresh de AWS |
| Capacidad | Base 2 healthy; temporal +2 (máx. 4 t3.micro: 2 del ASG anterior + 2 del nuevo) | Igual (+2) |
| Mezcla v1/v2 | Sí, durante la superposición (admitida) | Sí |
| Detención | **Automática**: si el ASG nuevo no alcanza 2 destinos healthy en el ALB en 15 min (`min_elb_capacity`), el apply falla y el ASG anterior **no se elimina** | Cancelar el refresh |
| Recuperación | Nueva versión de plantilla con v1 → otro ASG nuevo (mismo procedimiento) | Nuevo refresh |

**Parámetros que cambian respecto de §3:**
- Controlador: reemplazo de ASG; el nombre del ASG incluye la versión de plantilla (`na-u2-c50-a004-asg-lt2` para v2, `-lt3` para el retorno a v1).
- Se elimina el bloque `instance_refresh`; se agrega `lifecycle { create_before_destroy = true }`.
- Plan esperado del cambio: `1 to add, 0 to change, 1 to destroy` (solo el ASG; ALB, TG, VPC y SG sin cambios; mismo endpoint).
  La Launch Template versión 2 ya existe (creada en el intento denegado) y no cambia.
- Inicio del intervalo = primer «Launching» del ASG nuevo; estabilización = la más tardía entre la última «Terminating» del ASG
  anterior y la línea ESTABLE (`refresh_times.sh` adaptado); el resto de la ventana (−60 s / +120 s, 2 s, timeout 5 s) no cambia.

**Aceptación (sustituye el punto 5 de §4):** apply terminado sin error, un único ASG vigente (`-lt2`) con 2 destinos healthy en LT 2,
ASG anterior eliminado, solo v2 tras estabilizar, 0 fallos funcionales, ≥ 2 healthy en cada consulta y plan posterior `No changes`.

**Detención adicional:** ≥ 3 fallos HTTP consecutivos o healthy < 2 → cancelar la ejecución del pipeline solo si el ASG anterior
aún existe (Terraform no lo habrá eliminado), registrar y evaluar.

**Restricción que cambiaría la decisión:** si el docente habilita Instance Refresh en la cuenta, se vuelve al plan original (§3).
