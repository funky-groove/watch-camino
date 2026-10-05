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
    # Si el reloj ha ido hacia atrás (now < last_alert_at) no se bloquea: el intervalo no es fiable.
    if last_alert_at is not None and 0 <= now - last_alert_at < POI_MIN_INTERVAL_S:
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
        ("reloj_hacia_atras_no_bloquea", pois, [], 2000, 1000, pos(s)),
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


# ------------------------------------------------------------- V1.1: trayecto

MIN_MOVING_SPEED_MPS = 0.5
MAX_VERTICAL_ACCURACY_M = 15.0
ALT_HYSTERESIS_M = 3.0
PROFILE_SPACING_M = 50.0
PROFILE_GAP_M = 200.0


def trip_metrics(events, profile_cap=500):
    """§4.2 pausa, §5.2 tiempo en movimiento, §5.3 altitud y desnivel, §5.4 perfil."""
    st = dict(distance=0.0, moving=0.0, paused=False, pausedAt=None, pausedSeconds=0.0,
              ascent=0.0, descent=0.0, altRef=None, altitude=None, altitudeAt=None)
    last = None  # último fix ancla (dict)
    profile = []
    spacing = PROFILE_SPACING_M
    ignored = []
    for i, e in enumerate(events):
        kind = e["type"]
        if kind == "pause":
            if st["paused"]:
                ignored.append(i)
                continue
            st["paused"], st["pausedAt"] = True, e["t"]
            last = None
            st["altRef"] = None  # el desnivel recorrido en pausa no se cuenta al reanudar
            continue
        if kind == "resume":
            if not st["paused"]:
                ignored.append(i)
                continue
            st["pausedSeconds"] += max(0.0, e["t"] - st["pausedAt"])
            st["paused"], st["pausedAt"] = False, None
            continue
        # fix
        if st["paused"] or e["acc"] > MAX_ACCURACY_M:
            continue
        # distancia y tiempo en movimiento (§5 + §5.2)
        if last is None:
            last = e
        else:
            d = haversine(last, e)
            dt = e["t"] - last["t"]
            if d >= max(MIN_STEP_M, e["acc"]):
                if dt <= 0 or d / dt > MAX_SPEED_MPS:
                    last = e
                else:
                    st["distance"] += d
                    if d / dt >= MIN_MOVING_SPEED_MPS:
                        st["moving"] += dt
                    last = e
        # altitud (§5.3)
        alt, vacc = e.get("alt"), e.get("vacc")
        if alt is None or vacc is None or vacc < 0 or vacc > MAX_VERTICAL_ACCURACY_M:
            continue
        st["altitude"], st["altitudeAt"] = alt, e["t"]
        if st["altRef"] is None:
            st["altRef"] = alt
        else:
            diff = alt - st["altRef"]
            if diff >= ALT_HYSTERESIS_M:
                st["ascent"] += diff
                st["altRef"] = alt
            elif diff <= -ALT_HYSTERESIS_M:
                st["descent"] += -diff
                st["altRef"] = alt
        # perfil (§5.4)
        dist = st["distance"]
        if not profile or dist - profile[-1]["d"] >= spacing:
            # El umbral de hueco crece con el espaciado: tras recortar, 2 muestras seguidas
            # pueden estar a `spacing` de distancia sin que falten datos.
            gap = bool(profile) and dist - profile[-1]["d"] > max(PROFILE_GAP_M, 2 * spacing)
            profile.append({"d": round(dist, 4), "alt": alt, "gapBefore": gap})
            if len(profile) > profile_cap:
                kept = []
                pending_gap = False
                for j, smp in enumerate(profile):
                    if j % 2 == 0:
                        smp = dict(smp)
                        smp["gapBefore"] = smp["gapBefore"] or pending_gap
                        pending_gap = False
                        kept.append(smp)
                    else:
                        pending_gap = pending_gap or smp["gapBefore"]
                profile = kept
                spacing *= 2
    return {
        "distance_m": round(st["distance"], 4),
        "moving_s": round(st["moving"], 4),
        "paused": st["paused"],
        "paused_s": round(st["pausedSeconds"], 4),
        "ascent_m": round(st["ascent"], 4),
        "descent_m": round(st["descent"], 4),
        "altitude_m": st["altitude"],
        "altitude_t": st["altitudeAt"],
        "profile": profile,
        "ignored_events": ignored,
    }


def tfix(p, t, acc=5, alt=None, vacc=None):
    e = {"type": "fix", "lat": p["lat"], "lon": p["lon"], "acc": acc, "t": t}
    if alt is not None:
        e["alt"] = alt
    if vacc is not None:
        e["vacc"] = vacc
    return e


def walk(start_north, count, step_m, dt, t0=0, alt=None, alt_step=0.0, vacc=5):
    out = []
    for k in range(count):
        a = None if alt is None else round(alt + alt_step * k, 4)
        out.append(tfix(offset(SARRIA, start_north + step_m * k), t0 + dt * k, alt=a,
                        vacc=None if alt is None else vacc))
    return out


def gen_trip():
    cases = {
        "caminar_recto": walk(0, 11, 14, 10),
        "deriva_lenta_suma_distancia_no_movimiento": [tfix(offset(SARRIA, 0), 0), tfix(offset(SARRIA, 12), 60),
                                                       tfix(offset(SARRIA, 24), 120)],
        "pausa_y_reanudar_sin_contar_hueco": walk(0, 4, 14, 10) + [{"type": "pause", "t": 40}]
            + walk(100, 3, 14, 10, t0=50) + [{"type": "resume", "t": 400}] + walk(400, 4, 14, 10, t0=410),
        "doble_pausa_y_reanudar_sin_pausa": [{"type": "resume", "t": 0}] + walk(0, 3, 14, 10)
            + [{"type": "pause", "t": 30}, {"type": "pause", "t": 35}, {"type": "resume", "t": 60}]
            + walk(200, 2, 14, 10, t0=70),
        "ruido_de_altitud_no_suma_desnivel": [tfix(offset(SARRIA, 14 * k), 10 * k, alt=[500, 502, 499, 501.5, 498.5, 500][k % 6], vacc=4)
                                             for k in range(12)],
        "subida_continua": walk(0, 31, 14, 10, alt=400, alt_step=1.0),
        "subida_y_bajada": walk(0, 11, 14, 10, alt=400, alt_step=2.0) + walk(154, 11, 14, 10, t0=110, alt=420, alt_step=-2.0),
        "altitud_imprecisa_o_ausente_ignorada": [tfix(offset(SARRIA, 0), 0, alt=400, vacc=5), tfix(offset(SARRIA, 14), 10, alt=450, vacc=20),
                                                 tfix(offset(SARRIA, 28), 20), tfix(offset(SARRIA, 42), 30, alt=401, vacc=-1),
                                                 tfix(offset(SARRIA, 56), 40, alt=404, vacc=10)],
        "perfil_con_hueco": walk(0, 8, 14, 10, alt=300, alt_step=0.5) + walk(112, 25, 14, 10, t0=80)
            + walk(462, 8, 14, 10, t0=330, alt=310, alt_step=0.5),
    }
    out = []
    for name, events in cases.items():
        out.append({"name": name, "profileCap": 500, "events": events, "expected": trip_metrics(events)})
    climb_in_pause = walk(0, 4, 14, 10, alt=300, vacc=5) + [{"type": "pause", "t": 40}] \
        + walk(60, 3, 14, 10, t0=50, alt=350, vacc=5) + [{"type": "resume", "t": 400}] \
        + walk(400, 4, 14, 10, t0=410, alt=700, alt_step=1.0, vacc=5)
    out.append({"name": "subida_en_pausa_no_cuenta", "profileCap": 500, "events": climb_in_pause,
                "expected": trip_metrics(climb_in_pause)})
    long_walk = walk(0, 400, 50, 40, alt=500, alt_step=0.0)
    out.append({"name": "perfil_largo_recortado_sin_huecos_falsos", "profileCap": 8, "events": long_walk,
                "expected": trip_metrics(long_walk, profile_cap=8)})
    capped = walk(0, 60, 14, 10, alt=200, alt_step=0.2)
    out.append({"name": "perfil_recortado_a_8", "profileCap": 8, "events": capped,
                "expected": trip_metrics(capped, profile_cap=8)})
    return {"constants": {"minMovingSpeedMps": MIN_MOVING_SPEED_MPS, "maxVerticalAccuracyM": MAX_VERTICAL_ACCURACY_M,
                          "altitudeHysteresisM": ALT_HYSTERESIS_M, "profileSpacingM": PROFILE_SPACING_M,
                          "profileGapM": PROFILE_GAP_M},
            "tolerance": 0.01, "cases": out}


# ------------------------------------------------------------- V1.1: unidades

M_PER_MI = 1609.344
FT_PER_M = 3.28084


def sep(lang):
    return (",", ".") if lang == "es" else (".", ",")


def fmt_distance_u(m, units, lang):
    dec, _ = sep(lang)
    m = max(0.0, m)
    if units == "metric":
        return fmt_distance(m).replace(",", dec)
    mi = m / M_PER_MI
    if mi < 0.1:
        return f"{math.floor(m * FT_PER_M / 10 + 0.5) * 10} ft"
    tenths = math.floor(mi * 10 + 0.5)
    if tenths < 100:
        return f"{tenths // 10}{dec}{tenths % 10} mi"
    return f"{math.floor(mi + 0.5)} mi"


def fmt_elevation(m, units):
    v = m if units == "metric" else m * FT_PER_M
    n = math.floor(v + 0.5) if v >= 0 else -math.floor(-v + 0.5)
    return f"{n} {'m' if units == 'metric' else 'ft'}"


def fmt_steps_l(n, lang):
    _, th = sep(lang)
    return f"{max(0, n):,}".replace(",", th)


def pace_text(distance_m, moving_s, units):
    if distance_m < 100 or moving_s < 60:
        return None
    unit_m = 1000.0 if units == "metric" else M_PER_MI
    total = math.floor(moving_s / (distance_m / unit_m) + 0.5)
    if total > 99 * 60 + 59:
        return None
    return f"{total // 60}:{total % 60:02d} /{'km' if units == 'metric' else 'mi'}"


def speed_text(distance_m, moving_s, units, lang):
    if distance_m < 100 or moving_s < 60:
        return None
    dec, _ = sep(lang)
    v = distance_m / moving_s * (3.6 if units == "metric" else 2.2369362920544)
    tenths = math.floor(v * 10 + 0.5)
    return f"{tenths // 10}{dec}{tenths % 10} {'km/h' if units == 'metric' else 'mph'}"


def gen_units():
    out = {"distance": [], "elevation": [], "steps": [], "pace": [], "speed": []}
    for lang in ("es", "en"):
        for units in ("metric", "imperial"):
            for m in [0, 15, 160, 161, 1234, 1609.344, 9999, 16093.44, 22200, 123456]:
                out["distance"].append({"meters": m, "units": units, "lang": lang, "text": fmt_distance_u(m, units, lang)})
            for n in [0, 1234, 1234567]:
                pass
        for n in [0, 999, 1234, 1234567]:
            out["steps"].append({"steps": n, "lang": lang, "text": fmt_steps_l(n, lang)})
    for units in ("metric", "imperial"):
        for m in [0, 0.4, 0.5, 12.6, -3.5, 812.3]:
            out["elevation"].append({"meters": m, "units": units, "text": fmt_elevation(m, units)})
        for d, s in [(0, 0), (99, 600), (1000, 59), (1000, 600), (4200, 3000), (22200, 18000), (150, 59000)]:
            out["pace"].append({"distanceM": d, "movingS": s, "units": units, "text": pace_text(d, s, units)})
            for lang in ("es", "en"):
                out["speed"].append({"distanceM": d, "movingS": s, "units": units, "lang": lang,
                                     "text": speed_text(d, s, units, lang)})
    return out


def main():
    files = {
        "haversine.json": gen_haversine(),
        "distance_accumulator.json": gen_accumulator(),
        "poi_alerts.json": gen_poi(),
        "backoff.json": gen_backoff(),
        "formatting.json": gen_formatting(),
        "session_transitions.json": gen_sessions(),
        "sync_engine.json": gen_sync(),
        "trip_metrics.json": gen_trip(),
        "units_formatting.json": gen_units(),
    }
    for name, data in files.items():
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print("escrito", name)


if __name__ == "__main__":
    main()
