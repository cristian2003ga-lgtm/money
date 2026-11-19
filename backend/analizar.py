#!/usr/bin/env python3
"""
Money IA - cerebro del sistema.

Qué hace cada vez que se ejecuta:
  1. Descarga precios y noticias recientes (Finnhub, plan gratis).
  2. Le pasa todo a la IA (Gemini, plan gratis) para que decida, por acción:
     COMPRAR / VENDER / MANTENER, con confianza y razones.
  3. Guarda el resultado en data/senales.json (lo lee la app del celular).
  4. Lleva un historial y mide si las señales pasadas acertaron (data/historial.json).
  5. Si hay una señal fuerte y nueva, envía una notificación al celular (ntfy).

Solo usa la librería estándar de Python: no hay que instalar nada.

Uso:
  python analizar.py           -> análisis real (necesita las claves)
  python analizar.py --demo    -> datos de ejemplo, sin internet ni claves (para probar la app)
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent
RAIZ = BASE.parent
DATA = RAIZ / "data"
ARCHIVO_SENALES = DATA / "senales.json"
ARCHIVO_HISTORIAL = DATA / "historial.json"

AVISO = ("Señales generadas por IA a partir de noticias y precios. No son asesoría "
         "financiera ni garantizan ganancias. Invierte solo lo que puedas perder.")

SENALES_VALIDAS = {"COMPRAR", "VENDER", "MANTENER"}


# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


def ahora_utc():
    return datetime.now(timezone.utc)


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def leer_iso(texto):
    return datetime.strptime(texto, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def cargar_env_local():
    """Permite correrlo en el PC con un archivo backend/.env (CLAVE=valor)."""
    ruta = BASE / ".env"
    if not ruta.exists():
        return
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        clave, valor = linea.split("=", 1)
        os.environ.setdefault(clave.strip(), valor.strip().strip('"').strip("'"))


def leer_json(ruta, defecto):
    try:
        return json.loads(Path(ruta).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return defecto


def guardar_json(ruta, datos):
    Path(ruta).parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(str(ruta) + ".tmp")
    tmp.write_text(json.dumps(datos, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(ruta)


def http(url, metodo="GET", cuerpo=None, cabeceras=None, timeout=30):
    datos = None
    cab = {"User-Agent": "MoneyIA/1.0"}
    if cabeceras:
        cab.update(cabeceras)
    if cuerpo is not None:
        datos = json.dumps(cuerpo).encode("utf-8")
        cab.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=datos, headers=cab, method=metodo)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        texto = r.read().decode("utf-8")
        return json.loads(texto) if texto else None


# ----------------------------------------------------------------------------
# Finnhub: precios y noticias
# ----------------------------------------------------------------------------

class Finnhub:
    URL = "https://finnhub.io/api/v1"

    def __init__(self, clave):
        self.clave = clave

    def _get(self, ruta, **params):
        params["token"] = self.clave
        url = f"{self.URL}/{ruta}?{urllib.parse.urlencode(params)}"
        for intento in range(3):
            try:
                return http(url)
            except urllib.error.HTTPError as e:
                if e.code == 429:  # límite gratis: 60 por minuto
                    log("Finnhub pidió esperar; reintentando en 20 s…")
                    time.sleep(20)
                    continue
                raise
        raise RuntimeError("Finnhub no respondió tras varios intentos")

    def precio(self, simbolo):
        q = self._get("quote", symbol=simbolo) or {}
        return {
            "precio": q.get("c"),
            "cambio_pct": q.get("dp"),
            "maximo_dia": q.get("h"),
            "minimo_dia": q.get("l"),
            "cierre_anterior": q.get("pc"),
        }

    def noticias_accion(self, simbolo, dias, limite):
        hoy = ahora_utc().date()
        desde = hoy - timedelta(days=dias)
        lista = self._get("company-news", symbol=simbolo,
                          **{"from": desde.isoformat(), "to": hoy.isoformat()}) or []
        return [self._limpiar(n) for n in lista[:limite]]

    def noticias_generales(self, limite):
        lista = self._get("news", category="general") or []
        return [self._limpiar(n) for n in lista[:limite]]

    @staticmethod
    def _limpiar(n):
        fecha = n.get("datetime")
        return {
            "titulo": (n.get("headline") or "").strip(),
            "resumen": (n.get("summary") or "").strip()[:400],
            "fuente": n.get("source") or "",
            "url": n.get("url") or "",
            "fecha": iso(datetime.fromtimestamp(fecha, timezone.utc)) if fecha else "",
        }


# ----------------------------------------------------------------------------
# Gemini: la IA que analiza
# ----------------------------------------------------------------------------

INSTRUCCIONES_IA = """Eres un analista bursátil prudente que ayuda a un inversionista
principiante en Colombia (invierte con montos pequeños desde la app trii).
Recibes precios del día y noticias recientes de varias acciones, más noticias
generales del mundo (economía, política, guerras, tasas de interés, petróleo).

Para CADA acción decide una señal para un horizonte de 1 a 5 días:
- "COMPRAR": las noticias y el precio sugieren con claridad que puede subir.
- "VENDER": sugieren con claridad que puede bajar (para quien ya la tiene).
- "MANTENER": no hay evidencia clara, las noticias son mixtas o ya están
  reflejadas en el precio. Ante la duda, MANTENER.

Reglas:
- Sé honesto con la incertidumbre: la confianza (0-100) rara vez debe pasar de 80.
- Si una acción no tiene noticias relevantes, MANTENER con confianza baja.
- Considera si la noticia ya movió el precio (cambio_pct del día).
- Escribe todo en español sencillo, frases cortas.
- No inventes noticias: usa solo las que te doy.

Responde SOLO con JSON con esta forma exacta:
{
  "resumen_mercado": "2-3 frases sobre el ánimo general del mercado hoy",
  "acciones": [
    {
      "simbolo": "AAPL",
      "senal": "COMPRAR | VENDER | MANTENER",
      "confianza": 0,
      "razones": ["razón 1", "razón 2"],
      "riesgos": ["riesgo principal"],
      "noticias_clave": [0, 2]
    }
  ]
}
"noticias_clave" son los índices (empezando en 0) de las noticias de esa acción
que más pesaron en tu decisión."""


class Gemini:
    URL = "https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent"

    def __init__(self, clave, modelos):
        self.clave = clave
        self.modelos = modelos

    def generar_json(self, instrucciones, texto):
        cuerpo = {
            "systemInstruction": {"parts": [{"text": instrucciones}]},
            "contents": [{"role": "user", "parts": [{"text": texto}]}],
            "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"},
        }
        ultimo_error = None
        for modelo in self.modelos:
            for intento in range(3):
                try:
                    r = http(self.URL.format(modelo=modelo), "POST", cuerpo,
                             {"x-goog-api-key": self.clave}, timeout=120)
                    partes = r["candidates"][0]["content"]["parts"]
                    salida = "".join(p.get("text", "") for p in partes)
                    log(f"Respuesta recibida de {modelo}")
                    return json.loads(extraer_json(salida))
                except urllib.error.HTTPError as e:
                    detalle = e.read().decode("utf-8", "ignore")[:300]
                    ultimo_error = f"{modelo}: HTTP {e.code} {detalle}"
                    log(f"Gemini error {ultimo_error}")
                    if e.code in (429, 500, 503):
                        time.sleep(15 * (intento + 1))
                        continue
                    break  # 400/404: probar el siguiente modelo
                except (KeyError, IndexError, json.JSONDecodeError) as e:
                    ultimo_error = f"{modelo}: respuesta inválida ({e})"
                    log(ultimo_error)
                    time.sleep(5)
        raise RuntimeError(f"La IA no respondió. Último error: {ultimo_error}")


def extraer_json(texto):
    texto = texto.strip()
    if texto.startswith("```"):
        texto = texto.strip("`")
        if texto.lower().startswith("json"):
            texto = texto[4:]
    inicio, fin = texto.find("{"), texto.rfind("}")
    return texto[inicio:fin + 1] if inicio != -1 else texto


# ----------------------------------------------------------------------------
# Historial y aciertos
# ----------------------------------------------------------------------------

def evaluar_historial(historial, precios, horas):
    """Marca como acierto/fallo las señales que ya cumplieron su plazo."""
    limite = ahora_utc() - timedelta(hours=horas)
    for r in historial["registros"]:
        if r.get("resultado") or leer_iso(r["fecha"]) > limite:
            continue
        actual = (precios.get(r["simbolo"]) or {}).get("precio")
        if not actual or not r.get("precio"):
            continue
        cambio = (actual - r["precio"]) / r["precio"] * 100
        r["precio_final"] = round(actual, 4)
        r["cambio_pct"] = round(cambio, 2)
        r["fecha_evaluacion"] = iso(ahora_utc())
        if r["senal"] == "COMPRAR":
            r["resultado"] = "acierto" if cambio > 0 else "fallo"
        elif r["senal"] == "VENDER":
            r["resultado"] = "acierto" if cambio < 0 else "fallo"
        else:  # MANTENER acierta si el precio no se movió mucho
            r["resultado"] = "acierto" if abs(cambio) < 1.5 else "fallo"


def registrar_senales(historial, acciones):
    ultima = {}
    for r in historial["registros"]:
        ultima[r["simbolo"]] = r
    for a in acciones:
        previa = ultima.get(a["simbolo"])
        misma = previa and previa["senal"] == a["senal"] and not previa.get("resultado")
        if misma or not a.get("precio"):
            continue  # no duplicar la misma señal mientras sigue abierta
        historial["registros"].append({
            "simbolo": a["simbolo"],
            "senal": a["senal"],
            "confianza": a["confianza"],
            "precio": a["precio"],
            "fecha": iso(ahora_utc()),
        })
    historial["registros"] = historial["registros"][-600:]


def calcular_estadisticas(historial):
    est = {"total": 0, "aciertos": 0, "porcentaje": None, "pendientes": 0, "por_senal": {}}
    for r in historial["registros"]:
        res = r.get("resultado")
        if not res:
            est["pendientes"] += 1
            continue
        s = est["por_senal"].setdefault(r["senal"], {"total": 0, "aciertos": 0})
        s["total"] += 1
        est["total"] += 1
        if res == "acierto":
            s["aciertos"] += 1
            est["aciertos"] += 1
    if est["total"]:
        est["porcentaje"] = round(est["aciertos"] / est["total"] * 100, 1)
    for s in est["por_senal"].values():
        s["porcentaje"] = round(s["aciertos"] / s["total"] * 100, 1) if s["total"] else None
    historial["estadisticas"] = est


# ----------------------------------------------------------------------------
# Notificaciones (ntfy)
# ----------------------------------------------------------------------------

def notificar(tema, acciones, anteriores, confianza_min):
    if not tema:
        return
    previas = {a["simbolo"]: a.get("senal") for a in anteriores.get("acciones", [])}
    for a in acciones:
        if a["senal"] == "MANTENER" or a["confianza"] < confianza_min:
            continue
        if previas.get(a["simbolo"]) == a["senal"]:
            continue  # ya se avisó antes
        icono = "chart_with_upwards_trend" if a["senal"] == "COMPRAR" else "chart_with_downwards_trend"
        mensaje = {
            "topic": tema,
            "title": f"{a['senal']} {a['simbolo']} ({a['confianza']}%)",
            "message": (a["razones"][0] if a["razones"] else "Nueva señal")
                       + f"\nPrecio: {a.get('precio')} USD",
            "priority": 4,
            "tags": [icono],
        }
        try:
            http("https://ntfy.sh/", "POST", mensaje)
            log(f"Notificación enviada: {mensaje['title']}")
        except Exception as e:  # una notificación fallida no debe tumbar todo
            log(f"No se pudo notificar: {e}")


# ----------------------------------------------------------------------------
# Armado del análisis
# ----------------------------------------------------------------------------

def normalizar(respuesta_ia, cfg, precios, noticias):
    por_simbolo = {a.get("simbolo", "").upper(): a for a in respuesta_ia.get("acciones", [])}
    acciones = []
    for acc in cfg["acciones"]:
        sim = acc["simbolo"]
        ia = por_simbolo.get(sim, {})
        senal = str(ia.get("senal", "MANTENER")).upper().strip()
        if senal not in SENALES_VALIDAS:
            senal = "MANTENER"
        try:
            confianza = max(0, min(100, int(ia.get("confianza", 0))))
        except (TypeError, ValueError):
            confianza = 0
        lista = noticias.get(sim, [])
        clave = [lista[i] for i in ia.get("noticias_clave", [])
                 if isinstance(i, int) and 0 <= i < len(lista)]
        p = precios.get(sim, {})
        acciones.append({
            "simbolo": sim,
            "nombre": acc["nombre"],
            "precio": p.get("precio"),
            "cambio_pct": round(p["cambio_pct"], 2) if p.get("cambio_pct") is not None else None,
            "senal": senal,
            "confianza": confianza,
            "razones": [str(x) for x in ia.get("razones", [])][:4] or ["Sin análisis disponible"],
            "riesgos": [str(x) for x in ia.get("riesgos", [])][:3],
            "noticias": [{k: n[k] for k in ("titulo", "fuente", "url", "fecha")}
                         for n in (clave or lista[:3])],
        })
    orden = {"COMPRAR": 0, "VENDER": 1, "MANTENER": 2}
    acciones.sort(key=lambda a: (orden[a["senal"]], -a["confianza"]))
    return acciones


def recolectar(cfg, finnhub):
    precios, noticias = {}, {}
    for acc in cfg["acciones"]:
        sim = acc["simbolo"]
        try:
            precios[sim] = finnhub.precio(sim)
            noticias[sim] = finnhub.noticias_accion(sim, cfg["dias_noticias"], cfg["noticias_por_accion"])
            log(f"{sim}: precio {precios[sim]['precio']} | {len(noticias[sim])} noticias")
        except Exception as e:
            log(f"{sim}: error al descargar datos ({e})")
            precios.setdefault(sim, {})
            noticias.setdefault(sim, [])
        time.sleep(1.1)  # respetar el límite gratis de Finnhub
    generales = finnhub.noticias_generales(cfg["noticias_generales"])
    return precios, noticias, generales


def armar_texto(cfg, precios, noticias, generales):
    bloques = [f"Fecha y hora (UTC): {iso(ahora_utc())}", "", "NOTICIAS GENERALES DEL MUNDO:"]
    for n in generales:
        bloques.append(f"- {n['titulo']} ({n['fuente']}): {n['resumen'][:200]}")
    for acc in cfg["acciones"]:
        sim = acc["simbolo"]
        p = precios.get(sim, {})
        bloques += ["", f"=== {sim} - {acc['nombre']} ===",
                    f"Contexto: {acc['nota']}" if acc.get("nota") else "",
                    f"Precio: {p.get('precio')} USD | cambio hoy: {p.get('cambio_pct')}% | "
                    f"cierre anterior: {p.get('cierre_anterior')}",
                    "Noticias:"]
        lista = noticias.get(sim, [])
        if not lista:
            bloques.append("  (sin noticias recientes)")
        for i, n in enumerate(lista):
            bloques.append(f"  [{i}] {n['fecha']} {n['titulo']} ({n['fuente']}): {n['resumen']}")
    return "\n".join(b for b in bloques if b is not None)


def datos_demo(cfg):
    """Datos inventados para probar la app sin claves ni internet."""
    import random
    random.seed(int(time.time()) // 3600)
    precios, noticias, ia = {}, {}, {"resumen_mercado": "MODO DEMO: datos de ejemplo, no reales.", "acciones": []}
    for acc in cfg["acciones"]:
        sim = acc["simbolo"]
        precio = round(random.uniform(10, 500), 2)
        precios[sim] = {"precio": precio, "cambio_pct": round(random.uniform(-3, 3), 2)}
        noticias[sim] = [{"titulo": f"Noticia de ejemplo sobre {acc['nombre']}", "resumen": "",
                          "fuente": "Demo", "url": "https://finnhub.io", "fecha": iso(ahora_utc())}]
        senal = random.choice(["COMPRAR", "VENDER", "MANTENER", "MANTENER"])
        ia["acciones"].append({"simbolo": sim, "senal": senal, "confianza": random.randint(40, 80),
                               "razones": ["Ejemplo de razón generada en modo demo"],
                               "riesgos": ["Esto no es un análisis real"], "noticias_clave": [0]})
    return precios, noticias, ia


# ----------------------------------------------------------------------------
# Programa principal
# ----------------------------------------------------------------------------

def main():
    cargar_env_local()
    demo = "--demo" in sys.argv
    cfg = leer_json(BASE / "config.json", None)
    if not cfg:
        sys.exit("No encontré backend/config.json")

    anteriores = leer_json(ARCHIVO_SENALES, {})
    historial = leer_json(ARCHIVO_HISTORIAL, {"registros": []})
    historial.setdefault("registros", [])

    if demo:
        log("Modo DEMO (sin internet)")
        precios, noticias, respuesta = datos_demo(cfg)
    else:
        fh_key = os.environ.get("FINNHUB_KEY")
        gm_key = os.environ.get("GEMINI_API_KEY")
        if not fh_key or not gm_key:
            sys.exit("Faltan las claves FINNHUB_KEY y/o GEMINI_API_KEY")
        precios, noticias, generales = recolectar(cfg, Finnhub(fh_key))
        modelo = os.environ.get("GEMINI_MODEL") or cfg.get("modelo_gemini", "gemini-flash-latest")
        modelos = [modelo] + [m for m in ("gemini-flash-latest", "gemini-flash-lite-latest") if m != modelo]
        log("Enviando noticias a la IA…")
        respuesta = Gemini(gm_key, modelos).generar_json(
            INSTRUCCIONES_IA, armar_texto(cfg, precios, noticias, generales))

    acciones = normalizar(respuesta, cfg, precios, noticias)

    evaluar_historial(historial, precios, cfg["horas_para_evaluar_acierto"])
    registrar_senales(historial, acciones)
    calcular_estadisticas(historial)

    salida = {
        "actualizado": iso(ahora_utc()),
        "demo": demo,
        "resumen_mercado": str(respuesta.get("resumen_mercado", "")),
        "aviso": AVISO,
        "acciones": acciones,
    }
    guardar_json(ARCHIVO_SENALES, salida)
    guardar_json(ARCHIVO_HISTORIAL, historial)

    if not demo:
        notificar(os.environ.get("NTFY_TOPIC"), acciones, anteriores, cfg["confianza_minima_notificacion"])

    for a in acciones:
        log(f"{a['simbolo']:6} {a['senal']:9} {a['confianza']:3}%  {a['razones'][0][:70]}")
    est = historial["estadisticas"]
    log(f"Historial: {est['aciertos']}/{est['total']} aciertos ({est['porcentaje']}%), {est['pendientes']} pendientes")


if __name__ == "__main__":
    main()
