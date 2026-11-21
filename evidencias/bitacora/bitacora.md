# Bitácora U2 · NexoAndes · a004 · c50 · X=4 · prefijo na-u2-c50-a004

Cuenta AWS ****9245 (AWS Academy Learner Lab, rol voclabs) · us-east-1 · state `s3://na-u2-c50-a004-tfstate-66e7c6/nexoandes/u2/aws/terraform.tfstate`

| Hora UTC | Evento | Evidencia / referencia |
|---|---|---|
| 2026-11-21 16:46Z | Push estructura base a `main` (run 44926356937 falla: aún no existe `terraform/`, esperado) | commit 34535e5 |
| 16:52Z | Bucket del state creado (versionado, AES256, bloqueo público, tags) y 4 secrets cargados | C02, C04 |
| 16:55Z | AMI fijada `ami-0a951420c495183dc` (ubuntu-noble-24.04-amd64-server-20261120). **Adaptación:** el owner de Canonical que trae la guía (099720692166) no devuelve imágenes; el owner real es `099720109477` | Fase 3.2 |
| 16:58Z | PR #1 «Infraestructura AWS U2 (Portal v1)»: Controles y Plan en verde, **Plan: 19 to add** (la guía estimaba ~21; vale el plan real) | C07 |
| 17:19Z | Merge PR #1 → run 44929101576, aprobado en `produccion` | — |
| 17:22Z | **Incidente (intento 1):** `terraform apply` falla al crear el ASG: *Access denied when attempting to assume role …/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling* (primer ASG de la cuenta; el rol vinculado aún no estaba disponible). AWS reintentó y lanzó 2 instancias healthy, pero el ASG quedó *tainted* en el state. El step terminó en verde porque `terraform apply \| tee` corría sin `pipefail` | `bitacora/intento1_apply_fallido_run44929101576/` |
| 17:25Z | Decisión: no hacer untaint manual; corregir el pipeline y redesplegar limpio por pipeline. PR #2 `fix(ci)`: `defaults.run.shell: bash` (bash -eo pipefail) | PR #2 |
| 17:28–17:30Z | Destroy por pipeline (run 44930081866, aprobado): 19 destroyed, verify_cleanup sin recursos | `bitacora/intento1_destroy_run44930081866/` |
| 17:32Z | Merge PR #2 → run 44930539421 (commit ea4a753, build_ref e3f129c), aprobado | C08, C09 |
| 17:36:49Z | **Apply complete! Resources: 19 added**; ESTABLE 17:36:54Z (2/2 healthy, LT v1); verify_portal 15 muestras v1, 0 fallos | C10, C11, `E03_registros_pipeline/` |
| 17:38Z | Consulta independiente `capture_state.sh` y curl /api/info, /api/check. **Corrección de script:** `capture_state.sh` mezclaba `-w HTTP` con el JSON y jq imprimía «(sin respuesta JSON)» falso; ahora registra código HTTP y JSON por separado | `*_E03_v1_inicial_estado.txt` |
| 17:40Z | Plan posterior (run 44931248948): **No changes** | C18 |
| 17:45Z | PR #5 plan de cambio v1→v2 fusionado (antes del PR de v2) | C19 |
| 18:03:42Z | Inicio de observadores `actualizacion_v2` (HTTP 2 s, AWS 20 s) | — |
| 18:12Z | PR #6 `feat/portal-v2`: plan 0 add / 2 change / 0 destroy (build_ref a717a65) | C20 |
| 18:19:47Z | Merge PR #6 → run 44933633166 aprobado; LT versión 2 creada | — |
| 18:19:58Z | **Incidente (intento v2):** apply falla: `AccessDenied … autoscaling:StartInstanceRefresh … explicit deny in a service control policy`. El ASG quedó apuntando a LT 2 pero sin reemplazar instancias; servicio sin impacto: 525 respuestas HTTP 200 v1, 0 fallos, 2/2 healthy | `bitacora/intento_v2_refresh_denegado_run44933633166/` |
| 18:21Z | Observadores detenidos. Decisión (Anexo B, adaptación documentada): sustituir Instance Refresh por **reemplazo inmutable del ASG** (create_before_destroy, nombre `-asg-ltN`, mismo TG); adaptar scripts que suponían nombre fijo de ASG y refresh | Adenda §9 de `docs/plan_cambio_u2.md` |

## Tabla de sesión E03 (v1)

| Dato | Valor |
|---|---|
| Endpoint | http://na-u2-c50-a004-alb-101744380.us-east-1.elb.amazonaws.com |
| Instancias | i-07a40b5345ffa6ec0 (us-east-1a, 10.4.10.39) · i-05d02cc45da89f5a4 (us-east-1b, 10.4.20.186) |
| Launch Template | lt-078862d5af9becb83 versión 1 |
| build_ref | e3f129c |
| SHA-256 v1 | 82f7e3a976f7ec7b46f739244e44e47b59a73aa840e0269870d3b0f42e1fd7fa |
| VPC / subredes | vpc-00dff4d6803b806d1 10.4.0.0/16 · 10.4.10.0/24 (1a) · 10.4.20.0/24 (1b) |
