# Money IA — señales de bolsa con IA (versión gratis)

App para Android que lee noticias y precios cada 30 minutos, le pide a una IA
(Gemini, plan gratuito) que decida **COMPRAR / VENDER / MANTENER** para cada
acción, te avisa al celular cuando hay una señal fuerte y te deja hacerle
preguntas en un chat. Además lleva un **registro de aciertos** para que veas con
números reales si la IA sirve o no.

> ⚠️ Las señales las genera una IA y pueden estar equivocadas. No son asesoría
> financiera. La compra o venta siempre la haces tú en trii. Antes de meter plata,
> deja la app funcionando varias semanas y mira la pestaña **Aciertos**:
> si no supera claramente el 50 %, no le está ganando a tirar una moneda.

## Cómo funciona

```
 GitHub Actions (gratis, cada 30 min)          Tu celular
 ┌──────────────────────────────────┐          ┌────────────────────────┐
 │ backend/analizar.py              │          │ App Money IA (APK)     │
 │  1. Finnhub → precios y noticias │  JSON    │  • Señales             │
 │  2. Gemini  → decide señales     │ ───────▶ │  • Detalle + noticias  │
 │  3. Guarda data/senales.json     │          │  • Chat con la IA      │
 │  4. Mide aciertos (historial)    │          │  • Aciertos            │
 │  5. Aviso por ntfy ──────────────┼────────▶ │ App ntfy (avisos)      │
 └──────────────────────────────────┘          └────────────────────────┘
```

Costo: **$0**. Todo usa planes gratuitos.

---

## Paso 1 — Sacar las 3 claves gratis

| Clave | Dónde | Notas |
|---|---|---|
| **Finnhub** | finnhub.io → *Get free API key* | Regístrate con tu correo; la clave aparece en el Dashboard |
| **Gemini** | aistudio.google.com → *Get API key* → *Create API key* | Entra con tu cuenta de Google. No pide tarjeta |
| **Tema de ntfy** | Lo inventas tú | Un nombre difícil de adivinar, ej. `money-cristian-7k2q9`. Quien conozca el nombre puede leer los avisos |

Guarda las claves en un lugar seguro. **No las pegues en ningún chat ni archivo que subas a GitHub.**

## Paso 2 — Subir el proyecto a GitHub

1. Crea una cuenta en github.com (si no tienes).
2. Arriba a la derecha: **+ → New repository**. Nombre: `money`. Marca **Public**. Clic en **Create repository**.
   (Público = cualquiera puede ver el código y las señales, pero **no** tus claves. Los repositorios públicos tienen GitHub Actions gratis e ilimitado.)
3. En la página del repositorio vacío, clic en **uploading an existing file**.
4. Abre la carpeta `Documentos\money` en tu PC, selecciona **todo su contenido** y arrástralo al navegador. Clic en **Commit changes**.
5. Crea las dos automatizaciones. Por seguridad no pude escribirlas directamente en la carpeta oculta `.github` de tu PC, así que están en `flujos-github`. Hazlo así, una vez por archivo:
   - **Add file → Create new file**.
   - En el nombre escribe exactamente `.github/workflows/analizar.yml` (al escribir las `/` GitHub crea las carpetas).
   - Abre `flujos-github\analizar.yml` en tu PC con el Bloc de notas, copia todo y pégalo. **Commit changes**.
   - Repite con el nombre `.github/workflows/construir-apk.yml` y el archivo `flujos-github\construir-apk.yml`.

## Paso 3 — Guardar las claves como "secretos"

En el repositorio: **Settings → Secrets and variables → Actions → New repository secret**. Crea estos tres:

| Name | Secret |
|---|---|
| `FINNHUB_KEY` | tu clave de Finnhub |
| `GEMINI_API_KEY` | tu clave de Gemini |
| `NTFY_TOPIC` | el tema que inventaste |

## Paso 4 — Probar el análisis

1. Pestaña **Actions** del repositorio. Si pide habilitar los workflows, acepta.
2. Clic en **Analizar mercado → Run workflow → Run workflow**.
3. En 1–2 minutos debe quedar en verde ✅. Abre `data/senales.json` en el repositorio: ahí están las señales reales.
   Si sale en rojo ❌, abre la ejecución y lee el error (normalmente es una clave mal copiada).

Desde ahí corre solo, de lunes a viernes, cada 30 min entre las 8:00 a. m. y las 4:00 p. m. (hora Colombia).

## Paso 5 — Crear el APK (sin instalar nada en tu PC)

1. En **Actions → Construir APK → Run workflow**. Tarda unos 5–8 minutos.
2. Cuando termine en verde, ve a la página principal del repositorio → **Releases** (columna derecha) → descarga `MoneyIA.apk`.
   Lo más fácil: abre esa página desde el celular y descárgalo ahí mismo.
3. Al instalar, Android pedirá permitir "instalar apps de origen desconocido" para el navegador. Acéptalo solo para esto.

Cada vez que cambies algo dentro de `app/`, el APK se vuelve a construir solo.

## Paso 6 — Configurar la app

En la pestaña **Ajustes** de la app:
- **Usuario de GitHub**: tu usuario (ej. `cristiangaravino`).
- **Repositorio**: `money`.
- **Clave de Gemini**: la misma clave (se guarda solo en tu celular; es para el chat).
- **Modelo**: déjalo en `gemini-flash-latest`.

Guarda y ve a **Señales**.

## Paso 7 — Notificaciones

Instala **ntfy** desde Play Store → botón **+** → escribe tu tema (ej. `money-cristian-7k2q9`) → *Subscribe*.
Te llega un aviso cuando la IA da una señal de COMPRAR o VENDER con confianza ≥ 70 % que sea nueva.

---

## Personalizar

Todo en `backend/config.json`:
- `acciones`: agrega o quita símbolos (los de la bolsa de EE. UU. que también puedes comprar en trii).
  Ecopetrol y Bancolombia están como sus ADR en Nueva York (`EC`, `CIB`), porque esos datos son gratis.
- `confianza_minima_notificacion`: sube a 75–80 si te llegan demasiados avisos.
- `horas_para_evaluar_acierto`: cada cuánto se califica una señal (24 h por defecto).

Para cambiar la frecuencia, edita la línea `cron` en `.github/workflows/analizar.yml`.

## Correrlo en tu PC (opcional)

Necesitas Python 3.10+ (no hay que instalar librerías):

```
cd Documentos\money\backend
copy claves-ejemplo.txt .env   (y edita .env con tus claves)
python analizar.py          (análisis real)
python analizar.py --demo   (datos de ejemplo, sin internet)
```

## Problemas comunes

| Síntoma | Solución |
|---|---|
| La app dice "Todavía no hay datos en GitHub" | Revisa usuario/repositorio en Ajustes y que *Analizar mercado* haya corrido en verde |
| Aparece "MODO DEMO" | Faltan los secretos `FINNHUB_KEY` / `GEMINI_API_KEY` en GitHub |
| Error 404 de Gemini | El nombre del modelo cambió: en AI Studio copia el nombre exacto de un modelo *Flash* gratuito y ponlo en `config.json` y en Ajustes |
| Error 429 | Llegaste al límite gratis del momento; espera unos minutos |
| El análisis automático dejó de correr | GitHub pausa los horarios si el repositorio pasa 60 días sin actividad: en *Actions* vuelve a habilitarlo |
| Las señales se ven con unos minutos de atraso | Normal: GitHub puede retrasar las tareas programadas y la app guarda copia unos minutos |

## Mejoras posibles después

- Cambiar Gemini por Claude (mejor análisis, pago por uso) — solo cambia la clase `Gemini` en `analizar.py`.
- Agregar indicadores técnicos (RSI, medias móviles) además de las noticias.
- Agregar acciones colombianas de la BVC con otra fuente de datos.
