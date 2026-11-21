# Plan de cambio U2 — Portal v1 → v2 en AWS (declarado ANTES de ejecutar)

> Commit de este plan: `<sha>` · fecha UTC: `<AAAA-MM-DDTHH:MM:SSZ>` · autor: a004
> Este documento se versiona y se revisa en un PR **antes** del PR que cambia `app_version`.

## 1. Versiones y artefactos

| Elemento | v1 (origen / retorno) | v2 (objetivo) |
|---|---|---|
| Artefacto | `user_data_u2.sh.tpl` con `portal_version=v1` (perfil `basic`) | misma plantilla con `portal_version=v2` (perfil `extended`) |
| SHA-256 del artefacto instalado | `<observado en E03>` | `<observado en E05>` |
| Launch Template | `na-u2-c50-a004-lt` versión `<n>` | versión `<n+1>` (se crea en el apply) |
| AMI | `<ami-...>` (fijada, igual en ambas) | igual |
| build_ref | `<commit v1>` | `<commit v2>` |
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
- **Endpoint observado:** `http://<DNS del ALB>/api/check` (el mismo durante toda la prueba).

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
