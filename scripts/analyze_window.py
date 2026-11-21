#!/usr/bin/env python3
"""Analizador de la ventana de observación U2 (apoyo; contrastar con el proveedor).

Evalúa, sobre el registro íntegro, el intervalo [inicio - 60 s, estabilización + 120 s]:
  * cobertura HTTP: separación máxima entre muestras <= 7 s (incluye los bordes),
  * fallos funcionales: timeout/error, HTTP != 200, passed != true, identidad incorrecta,
    versión fuera de lo admitido (antes del inicio: origen; transición: origen u objetivo;
    después de estabilizar: solo objetivo),
  * cadencia real de envío,
  * capacidad (opcional, registro AWS): destinos healthy >= capacidad base y separación
    entre consultas al proveedor <= 30 s, con muestras próximas a ambos límites.

Uso:
  python3 scripts/analyze_window.py --http evidencias/..._http.csv --aws evidencias/..._aws.csv \
      --start 2026-11-21T14:03:10Z --stable 2026-11-21T14:12:40Z \
      --from-version v1 --target v2 --student a004 --course c50 --x 4 --base 2 \
      --out evidencias/analisis_actualizacion_v2.md
"""
import argparse
import csv
import statistics
import sys
from datetime import datetime, timedelta, timezone


def ts(value):
    value = value.strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def fmt(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def max_gap(times, lo, hi):
    """Separación máxima considerando los bordes lo/hi."""
    pts = sorted(t for t in times if lo <= t <= hi)
    if not pts:
        return (hi - lo).total_seconds(), None
    edges = [lo] + pts + [hi]
    gaps = [(edges[i + 1] - edges[i]).total_seconds() for i in range(len(edges) - 1)]
    worst = max(range(len(gaps)), key=lambda i: gaps[i])
    return gaps[worst], (edges[worst], edges[worst + 1])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--http", required=True)
    ap.add_argument("--aws")
    ap.add_argument("--start", required=True, help="Inicio del controlador (StartTime del Instance Refresh), UTC")
    ap.add_argument("--stable", required=True, help="Estabilización comprobada, UTC")
    ap.add_argument("--from-version", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--student", required=True)
    ap.add_argument("--course", required=True)
    ap.add_argument("--x", required=True)
    ap.add_argument("--base", type=int, default=2)
    ap.add_argument("--pre", type=int, default=60)
    ap.add_argument("--post", type=int, default=120)
    ap.add_argument("--max-gap", type=float, default=7.0)
    ap.add_argument("--max-aws-gap", type=float, default=30.0)
    ap.add_argument("--out")
    a = ap.parse_args()

    start, stable = ts(a.start), ts(a.stable)
    if stable < start:
        sys.exit("La estabilización no puede ser anterior al inicio")
    w_lo, w_hi = start - timedelta(seconds=a.pre), stable + timedelta(seconds=a.post)

    with open(a.http, newline="", encoding="utf-8") as fh:
        rows = sorted(csv.DictReader(fh), key=lambda r: int(r["seq"]))
    for r in rows:
        r["_t"] = ts(r["enviada_utc"])

    all_times = [r["_t"] for r in rows]
    inside = [r for r in rows if w_lo <= r["_t"] <= w_hi]
    before = [r for r in rows if r["_t"] < w_lo]
    after = [r for r in rows if r["_t"] > w_hi]

    gap, gap_at = max_gap(all_times, w_lo, w_hi)
    coverage_ok = gap <= a.max_gap and bool(rows) and min(all_times) <= w_lo + timedelta(seconds=a.max_gap) \
        and max(all_times) >= w_hi - timedelta(seconds=a.max_gap)

    sent = [r["_t"] for r in rows]
    deltas = [(sent[i + 1] - sent[i]).total_seconds() for i in range(len(sent) - 1)]
    sent_sorted = sorted(sent)
    deltas_sorted = [(sent_sorted[i + 1] - sent_sorted[i]).total_seconds() for i in range(len(sent_sorted) - 1)]

    failures = []
    phase_counts = {"antes": {}, "transicion": {}, "despues": {}}
    resources = {}
    for r in inside:
        t = r["_t"]
        phase = "antes" if t < start else ("transicion" if t <= stable else "despues")
        allowed = {a.from_version} if phase == "antes" else (
            {a.from_version, a.target} if phase == "transicion" else {a.target})
        ver = r["version"] or "-"
        phase_counts[phase][ver] = phase_counts[phase].get(ver, 0) + 1
        if r["resource_id"]:
            resources.setdefault(ver, set()).add(r["resource_id"])
        reasons = []
        if r["curl_exit"] != "0":
            reasons.append(f"curl_exit={r['curl_exit']} {r['error'].strip()}")
        if r["http_code"] != "200":
            reasons.append(f"HTTP {r['http_code']}")
        if r["passed"] != "true":
            reasons.append("passed!=true")
        if (r["alumno"], r["curso"], r["x"], r["proveedor"]) != (a.student, a.course, str(a.x), "aws"):
            reasons.append("identidad incorrecta")
        if ver not in allowed:
            reasons.append(f"versión {ver} no admitida en fase {phase}")
        if reasons:
            failures.append((r["seq"], fmt(t), phase, ", ".join(reasons)))

    out = []
    p = out.append
    p("# Análisis de la ventana de observación U2\n")
    p(f"- Registro HTTP: `{a.http}` ({len(rows)} muestras en total)")
    p(f"- Inicio (controlador): {fmt(start)} | Estabilización: {fmt(stable)}")
    p(f"- Intervalo evaluado: {fmt(w_lo)} → {fmt(w_hi)} ({(w_hi - w_lo).total_seconds():.0f} s)")
    p(f"- Muestras dentro del intervalo: {len(inside)} | antes: {len(before)} | después: {len(after)} (se conservan y no se evalúan)")
    p(f"- Versión de origen: {a.from_version} | objetivo: {a.target} | identidad esperada: {a.student}/{a.course}/X={a.x}\n")

    p("## Cobertura y cadencia")
    if deltas:
        p(f"- Cadencia real de envío: media {statistics.mean(deltas_sorted):.2f} s, mediana "
          f"{statistics.median(deltas_sorted):.2f} s, máxima {max(deltas_sorted):.2f} s (programada: 2 s)")
    where = f" entre {fmt(gap_at[0])} y {fmt(gap_at[1])}" if gap_at else ""
    p(f"- Separación máxima en el intervalo (con bordes): {gap:.2f} s{where} (tolerancia {a.max_gap:.0f} s)")
    p(f"- Cobertura completa: {'SÍ' if coverage_ok else 'NO'}\n")

    p("## Versiones observadas por fase")
    for ph in ("antes", "transicion", "despues"):
        p(f"- {ph}: " + (", ".join(f"{k}={v}" for k, v in sorted(phase_counts[ph].items())) or "sin muestras"))
    for ver, ids in sorted(resources.items()):
        p(f"- Instancias que respondieron con {ver}: {', '.join(sorted(ids))}")
    p("")

    p("## Fallos funcionales en el intervalo")
    if failures:
        p("| seq | UTC | fase | motivo |\n|---|---|---|---|")
        for f in failures:
            p(f"| {f[0]} | {f[1]} | {f[2]} | {f[3]} |")
    else:
        p("- Ninguno (0 timeouts, 0 errores, 0 HTTP != 200, 0 identidades/versiones incorrectas).")
    p("")

    capacity_ok = None
    if a.aws:
        with open(a.aws, newline="", encoding="utf-8") as fh:
            arows = list(csv.DictReader(fh))
        for r in arows:
            r["_t"] = ts(r["utc"])
        a_in = [r for r in arows if w_lo <= r["_t"] <= w_hi]
        agap, agap_at = max_gap([r["_t"] for r in arows], w_lo, w_hi)
        low = [r for r in a_in if int(r["destinos_healthy"] or 0) < a.base]
        capacity_ok = agap <= a.max_aws_gap and not low and bool(a_in)
        p("## Capacidad y controlador (consultas al proveedor)")
        p(f"- Registro AWS: `{a.aws}` ({len(a_in)} consultas en el intervalo)")
        where = f" entre {fmt(agap_at[0])} y {fmt(agap_at[1])}" if agap_at else ""
        p(f"- Separación máxima entre consultas (con bordes): {agap:.1f} s{where} (máximo {a.max_aws_gap:.0f} s)")
        if a_in:
            p(f"- Destinos healthy en el intervalo: mínimo {min(int(r['destinos_healthy'] or 0) for r in a_in)}, "
              f"máximo {max(int(r['destinos_healthy'] or 0) for r in a_in)} (capacidad base declarada {a.base})")
            states = sorted({r["refresh_estado"] for r in a_in})
            p(f"- Estados del controlador observados: {', '.join(states)}")
            p(f"- Última consulta: {r_last(a_in)}")
        for r in low:
            p(f"  - {r['utc']}: healthy={r['destinos_healthy']} < base {a.base}")
        p(f"- Capacidad comprobada: {'SÍ' if capacity_ok else 'NO'}")
        p("- Las consultas acreditan los instantes observados; no prueban lo ocurrido entre ellas.\n")

    final_version_ok = phase_counts["despues"] and set(phase_counts["despues"]) == {a.target}
    accepted = coverage_ok and not failures and bool(final_version_ok) and capacity_ok is not False
    p("## Resultado")
    p(f"- Ventana completa: {'SÍ' if coverage_ok else 'NO'}")
    p(f"- Cero fallos funcionales: {'SÍ' if not failures else 'NO (' + str(len(failures)) + ')'}")
    p(f"- Solo versión objetivo después de estabilizar: {'SÍ' if final_version_ok else 'NO'}")
    if capacity_ok is not None:
        p(f"- Capacidad base comprobada: {'SÍ' if capacity_ok else 'NO'}")
    p(f"\n**{'ACEPTADO' if accepted else 'NO ACEPTADO'}** según los criterios declarados. "
      "No se afirma disponibilidad absoluta; contrastar con las consultas al proveedor.")

    text = "\n".join(out)
    print(text)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    return 0 if accepted else 1


def r_last(rows):
    r = max(rows, key=lambda x: x["_t"])
    return f"{r['utc']} estado={r['refresh_estado']} healthy={r['destinos_healthy']} LT={r['asg_lt_version']}"


if __name__ == "__main__":
    sys.exit(main())
