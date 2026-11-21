# NexoAndes U2 — Portal Operacional con infraestructura inmutable (AWS)

Evaluación Sumativa U2 · Automatización de Infraestructura con IaC (IC106TICL).
Identidad de laboratorio: **X=4 · alumno a004 · curso c50** · prefijo `na-u2-c50-a004`
(reemplazar por los valores asignados en `terraform/terraform.tfvars`).

## 1. Qué contiene

| Ruta | Contenido |
|---|---|
| `terraform/` | Orquestación root: `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars`, `.terraform.lock.hcl` |
| `terraform/modules/aws_network` | VPC 10.X.0.0/16, subred A 10.X.10.0/24 y B 10.X.20.0/24 en zonas distintas, IGW y rutas |
| `terraform/modules/aws_portal` | SG-ALB / SG-EC2, ALB + listener HTTP 80, Target Group (`/api/check`), Launch Template versionada (IMDSv2), ASG con Instance Refresh |
| `terraform/templates/user_data_u2.sh.tpl` | Artefacto docente del Portal (sin modificar), renderizado con `templatefile()` |
| `.github/workflows/infra-u2.yml` | Pipeline: controles → plan → aprobación (`produccion`) → apply → espera del controlador → verificación |
| `scripts/` | Observación (`observe_http.sh`, `observe_aws.sh`), análisis (`analyze_window.py`), consultas independientes (`capture_state.sh`, `refresh_times.sh`, `verify_cleanup.sh`), espera/verificación del pipeline, higiene y ZIP |
| `docs/` | Diagrama (`arquitectura_u2_aws.png/.dot`), plan de cambio (`plan_cambio_u2.md`), README docente |
| `evidencias/` | Registros de observación y consultas (revisados, sin secretos) |

## 2. Arquitectura

![Arquitectura U2 AWS](docs/arquitectura_u2_aws.png)

```mermaid
flowchart LR
  subgraph Gestion["Gestión (API)"]
    PC[PC estudiante] -- PR --> GH[GitHub repo]
    GH --> GA[GitHub Actions<br/>controles→plan→aprobación→apply]
    GA <-- lock/state --> S3[(S3 state<br/>use_lockfile)]
  end
  GA -. API AWS .-> LT[Launch Template<br/>v1/v2 versionada]
  GA -. API AWS .-> ASG[ASG base 2 / máx 4<br/>Instance Refresh]
  LT -.-> ASG
  subgraph VPC["VPC 10.4.0.0/16"]
    IGW[IGW] --> ALB[ALB :80] --> TG[Target Group<br/>/api/check]
    TG --> A[EC2 · subred A 10.4.10.0/24]
    TG --> B[EC2 · subred B 10.4.20.0/24]
  end
  ASG -. lanza/reemplaza .-> A & B
  C[Cliente curl] -->|HTTP 80| IGW
```

Gestión (líneas discontinuas) y tráfico (continuas) están separados: el pipeline nunca sirve el Portal;
el endpoint de servicio es el **DNS del ALB**, no la IP de una EC2.

**Azure:** el encargo contempla un Portal v1 en VM Linux. En esta entrega quedó **fuera del alcance
práctico** (restricción registrada en la bitácora de la Ficha). No existe conectividad, peering ni failover
entre nubes.

## 3. Decisiones principales

- **Estrategia:** rolling con *Instance Refresh* (min healthy 100 %, max healthy 200 %): se lanzan instancias
  nuevas antes de retirar las anteriores; capacidad base 2, temporal hasta +2.
- **Controlador único:** el Instance Refresh del ASG. Terraform lo inicia al cambiar la versión de la
  Launch Template; `scripts/wait_refresh.sh` espera su resultado real (el éxito de `apply` no basta).
- **Inmutabilidad:** cada versión del Portal es una versión nueva de la Launch Template (AMI fijada +
  bootstrap + `portal_version` + `build_ref`). No hay cambios manuales en instancias ni acceso SSH.
- **Persistencia:** el Portal no guarda datos de negocio; las instancias son reemplazables.
- **build_ref:** último commit que modificó `terraform/` (`git log -1 --format=%h -- terraform/`):
  cambios solo de documentación no reemplazan instancias.
- **State:** S3 remoto, cifrado, versionado y con bloqueo nativo (`use_lockfile`); fuera de Git.
- **Credenciales:** temporales del Learner Lab, como *secrets* del repositorio; nunca en el código.

## 4. Uso rápido

```bash
# Local (validación)
cd terraform
cp backend.hcl.example backend.hcl            # completar bucket real (no se versiona)
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive && terraform validate
terraform plan -var "build_ref=$(git log -1 --format=%h -- .)"

# Observación de un cambio (desde la raíz del repo)
bash scripts/observe_http.sh "http://<DNS-ALB>" actualizacion_v2
bash scripts/observe_aws.sh  na-u2-c50-a004     actualizacion_v2
bash scripts/refresh_times.sh na-u2-c50-a004
python3 scripts/analyze_window.py --http evidencias/<...>_http.csv --aws evidencias/<...>_aws.csv \
  --start <InicioUTC> --stable <EstableUTC> --from-version v1 --target v2 \
  --student a004 --course c50 --x 4 --base 2 --out evidencias/analisis_v2.md
```

Los despliegues evaluados se ejecutan **solo por el pipeline** (merge a `main` o `workflow_dispatch`).

## 5. Referencias

- AWS — Instance refresh: https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html
- AWS — User data e IMDSv2: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html
- Terraform — `aws_autoscaling_group`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group
- Terraform — Backend S3 (`use_lockfile`): https://developer.hashicorp.com/terraform/language/backend/s3
- GitHub — Environments: https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment

## 6. Declaración de uso de IA

Se utilizó Claude (Anthropic) para generar la guía de trabajo, el código base de Terraform, el pipeline,
los scripts de observación y la plantilla de la Ficha. El código fue revisado, ejecutado y ajustado por el
estudiante; las ejecuciones, registros y capturas son propios. *(Ajustar este texto a su uso real.)*
