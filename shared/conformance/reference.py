#!/usr/bin/env python3
"""Implementación de referencia de las reglas de docs/WATCH_V1_SPEC.md.

Genera los vectores de shared/conformance/*.json. Los núcleos Swift y Kotlin
deben reproducir exactamente estos resultados. Para regenerar:

    python3 shared/conformance/reference.py

No editar los JSON a mano: cambiar la regla aquí y en la especificación.
"""
import json
import math
import os

R = 6_371_008.8
MAX_ACCURACY_M = 50.0
MIN_STEP_M = 10.0
MAX_SPEED_MPS = 4.0
POI_RADIUS_M = 300.0
POI_MIN_INTERVAL_S = 60.0

HERE = os.path.dirname(os.path.abspath(__file__))


def haversine(a, b):
    p1, p2 = math.radians(a["lat"]), math.radians(b["lat"])
    dp = p2 - p1
    dl = math.radians(b["lon"] - a["lon"])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(min(1.0, math.sqrt(h)))


def accumulate(fixes):
    """Devuelve (distancia, índice del lastFix o None)."""
    dist, last = 0.0, None
    for i, f in enumerate(fixes):
        if f["acc"] > MAX_ACCURACY_M:
            continue
        if last is None:
            last = i
            continue
        lf = fixes[last]
        d = haversine(lf, f)
        dt = f["t"] - lf["t"]
        if d < max(MIN_STEP_M, f["acc"]):
            continue
        if dt <= 0 or d / dt > MAX_SPEED_MPS:
            last = i
            continue
        dist += d
        last = i
    return dist, last


def poi_alert(pois, alerted, last_alert_at, now, pos):
    if pos["acc"] > MAX_ACCURACY_M:
        return None
    cands = [(haversine(pos, p["location"]), p["id"]) for p in pois if p["id"] not in alerted]
    cands = [c for c in cands if c[0] <= POI_RADIUS_M]
    if not cands:
        return None
    if last_alert_at is not None and now - last_alert_at < POI_MIN_INTERVAL_S:
        return None
    cands.sort(key=lambda c: (c[0], c[1]))
    return cands[0][1]


def backoff(attempt):
    return min(30 * 2 ** (attempt - 1), 1800)


def fmt_distance(m):
    m = max(0.0, m)
    r = math.floor(m / 10 + 0.5) * 10
    if r < 1000:
        return f"{r} m"
    tenths = math.floor(m / 100 + 0.5)
    if tenths < 100:
        return f"{tenths // 10},{tenths % 10} km"
    return f"{math.floor(m / 1000 + 0.5)} km"


def fmt_duration(s):
    s = max(0, int(s))
    if s < 3600:
        return f"{s // 60} min"
    return f"{s // 3600} h {(s % 3600) // 60:02d} min"


def fmt_steps(n):
    return f"{max(0, n):,}".replace(",", ".")


# ---------------------------------------------------------------- vectores

def pt(lat, lon):
    return {"lat": lat, "lon": lon}


def offset(p, north_m=0.0, east_m=0.0):
    """Desplaza un punto (aprox. local) para construir casos legibles."""
    dlat = north_m / R * 180 / math.pi
    dlon = east_m / (R * math.cos(math.radians(p["lat"]))) * 180 / math.pi
    return pt(round(p["lat"] + dlat, 7), round(p["lon"] + dlon, 7))


SARRIA = pt(42.7808, -7.4141)


def gen_haversine():
    pairs = [
        (SARRIA, SARRIA),
        (SARRIA, pt(42.8075, -7.6156)),
        (pt(42.8806, -8.5446), pt(42.9050, -8.3600)),
        (pt(0.0, 0.0), pt(0.0, 1.0)),
        (pt(0.0, 179.9), pt(0.0, -179.9)),
        (SARRIA, offset(SARRIA, north_m=100)),
    ]
    return {"tolerance_m": 0.01,
            "cases": [{"a": a, "b": b, "meters": round(haversine(a, b), 4)} for a, b in pairs]}


def fix(p, acc, t):
    return {"lat": p["lat"], "lon": p["lon"], "acc": acc, "t": t}


def gen_accumulator():
    s = SARRIA
    cases = {
        "vacio": [],
        "primer_fix_no_suma": [fix(s, 5, 0)],
        "dos_fixes_validos": [fix(s, 5, 0), fix(offset(s, 50), 5, 30)],
        "descarta_baja_precision": [fix(s, 5, 0), fix(offset(s, 50), 80, 30), fix(offset(s, 100), 5, 60)],
        "ruido_no_mueve_lastfix": [fix(s, 5, 0), fix(offset(s, 6), 5, 10), fix(offset(s, 12), 5, 20)],
        "ruido_relativo_a_precision": [fix(s, 5, 0), fix(offset(s, 30), 40, 30)],
        "salto_vehiculo_reancla": [fix(s, 5, 0), fix(offset(s, 2000), 5, 60), fix(offset(s, 2050), 5, 90)],
        "dt_cero_reancla": [fix(s, 5, 0), fix(offset(s, 40), 5, 0), fix(offset(s, 80), 5, 30)],
        "paseo_en_l": [fix(s, 5, 0), fix(offset(s, 100), 5, 70), fix(offset(s, 100, 100), 5, 140),
                       fix(offset(s, 100, 200), 8, 210)],
        "primer_fix_malo_ignorado": [fix(s, 90, 0), fix(offset(s, 50), 5, 30), fix(offset(s, 100), 5, 60)],
    }
    out = []
    for name, fixes in cases.items():
        d, last = accumulate(fixes)
        out.append({"name": name, "fixes": fixes, "distance_m": round(d, 4), "last_fix_index": last})
    return {"tolerance_m": 0.01, "cases": out}


def poi(pid, p, cat="water"):
    return {"id": pid, "stageId": "s", "name": pid, "category": cat, "location": p}


def gen_poi():
    s = SARRIA
    pois = [poi("a", offset(s, 200)), poi("b", offset(s, -250)), poi("c", offset(s, 1000)),
            poi("d", offset(s, 0, 200))]
    def pos(p, acc=5):
        return {"lat": p["lat"], "lon": p["lon"], "acc": acc}
    cases = [
        ("sin_candidatos", pois, [], None, 1000, pos(offset(s, 600))),
        ("mas_cercano", pois, [], None, 1000, pos(s)),
        ("empate_por_id", [poi("z", offset(s, 100)), poi("y", offset(s, 100))], [], None, 1000, pos(s)),
        ("ya_avisados_saltados", pois, ["a", "d"], None, 1000, pos(s)),
        ("ritmo_bloquea", pois, [], 970, 1000, pos(s)),
        ("ritmo_cumplido_60s", pois, [], 940, 1000, pos(s)),
        ("limite_radio_300_incluido", [poi("e", offset(s, 299.9))], [], None, 1000, pos(s)),
        ("fuera_de_radio", [poi("e", offset(s, 301))], [], None, 1000, pos(s)),
        ("baja_precision_ignorada", pois, [], None, 1000, pos(s, acc=51)),
        ("todos_avisados", pois, ["a", "b", "c", "d"], None, 1000, pos(s)),
    ]
    out = []
    for name, ps, alerted, last, now, p in cases:
        out.append({"name": name, "pois": ps, "alreadyAlerted": alerted, "lastAlertAt": last,
                    "now": now, "position": p, "expected": poi_alert(ps, set(alerted), last, now, p)})
    return {"radius_m": POI_RADIUS_M, "min_interval_s": POI_MIN_INTERVAL_S, "cases": out}


def gen_backoff():
    return {"jitter": 0, "cases": [{"attempt": a, "seconds": backoff(a)} for a in range(1, 10)]}


def gen_formatting():
    dist = [0, -5, 4, 5, 340, 994.9, 995, 999, 1000, 1049, 1050, 1234, 9940, 9949.9, 9950, 9999,
            10000, 10499, 10500, 22200, 123456]
    dur = [0, 59, 60, 2700, 3599, 3600, 3900, 7199, 36000, -3]
    steps = [0, -1, 999, 1000, 1234, 25000, 1234567]
    return {
        "distance": [{"meters": m, "text": fmt_distance(m)} for m in dist],
        "duration": [{"seconds": s, "text": fmt_duration(s)} for s in dur],
        "steps": [{"steps": n, "text": fmt_steps(n)} for n in steps],
    }


def gen_sessions():
    """Secuencias de comandos sobre la máquina de estados (§4)."""
    st = "cf-sarria-portomarin"
    return {"knownStageIds": ["cf-sarria-portomarin", "cf-portomarin-palas"], "cases": [
        {"name": "ciclo_completo", "steps": [
            {"op": "start", "stageId": st, "sessionId": "S1", "t": 1000,
             "expect": {"state": "active", "error": None, "steps": 0, "history": 0, "queued": ["stage_started"]}},
            {"op": "updateSteps", "n": 120,
             "expect": {"state": "active", "error": None, "steps": 120, "history": 0, "queued": ["stage_started"]}},
            {"op": "updateSteps", "n": 80,
             "expect": {"state": "active", "error": None, "steps": 120, "history": 0, "queued": ["stage_started"]}},
            {"op": "finish", "t": 4661.9,
             "expect": {"state": "idle", "error": None, "history": 1, "activeSeconds": 3661, "summarySteps": 120,
                        "queued": ["stage_started", "stage_finished"]}},
        ]},
        {"name": "doble_start", "steps": [
            {"op": "start", "stageId": st, "sessionId": "S1", "t": 0,
             "expect": {"state": "active", "error": None, "steps": 0, "history": 0, "queued": ["stage_started"]}},
            {"op": "start", "stageId": st, "sessionId": "S2", "t": 5,
             "expect": {"state": "active", "error": "alreadyActive", "steps": 0, "history": 0, "queued": ["stage_started"]}},
        ]},
        {"name": "etapa_desconocida", "steps": [
            {"op": "start", "stageId": "nope", "sessionId": "S1", "t": 0,
             "expect": {"state": "idle", "error": "unknownStage", "history": 0, "queued": []}},
        ]},
        {"name": "finish_sin_activa", "steps": [
            {"op": "finish", "t": 0,
             "expect": {"state": "idle", "error": "notActive", "history": 0, "queued": []}},
        ]},
        {"name": "reloj_hacia_atras", "steps": [
            {"op": "start", "stageId": st, "sessionId": "S1", "t": 500,
             "expect": {"state": "active", "error": None, "steps": 0, "history": 0, "queued": ["stage_started"]}},
            {"op": "finish", "t": 400,
             "expect": {"state": "idle", "error": None, "history": 1, "activeSeconds": 0, "summarySteps": 0,
                        "queued": ["stage_started", "stage_finished"]}},
        ]},
        {"name": "dos_etapas_seguidas", "steps": [
            {"op": "start", "stageId": st, "sessionId": "S1", "t": 0,
             "expect": {"state": "active", "error": None, "steps": 0, "history": 0, "queued": ["stage_started"]}},
            {"op": "finish", "t": 100,
             "expect": {"state": "idle", "error": None, "history": 1, "activeSeconds": 100, "summarySteps": 0,
                        "queued": ["stage_started", "stage_finished"]}},
            {"op": "start", "stageId": "cf-portomarin-palas", "sessionId": "S2", "t": 200,
             "expect": {"state": "active", "error": None, "steps": 0, "history": 1,
                        "queued": ["stage_started", "stage_finished", "stage_started"]}},
        ]},
    ]}


def sync_run(queue, responses, now, manual, backoff_state):
    """Simula syncNow (§7). responses se consumen en orden, uno por envío."""
    attempt, next_at = backoff_state["attempt"], backoff_state["nextAttemptAt"]
    if next_at is not None and now < next_at and not manual:
        return {"status": "pending" if queue else "synced", "sent": [], "remaining": queue, "deadLetters": [],
                "attempt": attempt, "nextAttemptAt": next_at}
    remaining, dead, sent = list(queue), [], []
    status = None
    resp = list(responses)
    while remaining:
        ev = remaining[0]
        r = resp.pop(0)
        sent.append(ev)
        if r == "accepted":
            remaining.pop(0); attempt = 0; next_at = None
        elif r == "permanent":
            dead.append(remaining.pop(0))
        elif r == "retryable":
            attempt += 1; next_at = now + backoff(attempt); status = "pending"; break
        elif r == "unauthorized":
            status = "needsLink"; break
        elif r == "blocked":
            status = "blocked"; break
    if status is None:
        status = "synced" if not remaining else "pending"
    return {"status": status, "sent": sent, "remaining": remaining, "deadLetters": dead,
            "attempt": attempt, "nextAttemptAt": next_at}


def gen_sync():
    nb = {"attempt": 0, "nextAttemptAt": None}
    cases = [
        ("cola_vacia", [], [], 1000, False, nb),
        ("todo_aceptado", ["e1", "e2"], ["accepted", "accepted"], 1000, False, nb),
        ("reintentable_para", ["e1", "e2", "e3"], ["accepted", "retryable"], 1000, False, nb),
        ("segundo_reintento", ["e2"], ["retryable"], 2000, False, {"attempt": 1, "nextAttemptAt": 1030}),
        ("backoff_respetado", ["e2"], [], 1010, False, {"attempt": 1, "nextAttemptAt": 1030}),
        ("manual_ignora_backoff", ["e2"], ["accepted"], 1010, True, {"attempt": 1, "nextAttemptAt": 1030}),
        ("permanente_a_dead_letter", ["e1", "e2"], ["permanent", "accepted"], 1000, False, nb),
        ("no_autorizado_para", ["e1", "e2"], ["unauthorized"], 1000, False, nb),
        ("bloqueado_no_pierde", ["e1", "e2"], ["blocked"], 1000, False, nb),
        ("backoff_tope", ["e1"], ["retryable"], 0, False, {"attempt": 7, "nextAttemptAt": None}),
    ]
    return {"cases": [{"name": n, "queue": q, "responses": r, "now": now, "manual": m, "backoff": b,
                       "expected": sync_run(q, r, now, m, b)} for n, q, r, now, m, b in cases]}


def main():
    files = {
        "haversine.json": gen_haversine(),
        "distance_accumulator.json": gen_accumulator(),
        "poi_alerts.json": gen_poi(),
        "backoff.json": gen_backoff(),
        "formatting.json": gen_formatting(),
        "session_transitions.json": gen_sessions(),
        "sync_engine.json": gen_sync(),
    }
    for name, data in files.items():
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("escrito", name)


if __name__ == "__main__":
    main()
