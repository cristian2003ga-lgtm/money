import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'datos.dart';

Color colorSenal(String s) {
  switch (s) {
    case 'COMPRAR':
      return const Color(0xFF2E7D32);
    case 'VENDER':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF616161);
  }
}

IconData iconoSenal(String s) {
  switch (s) {
    case 'COMPRAR':
      return Icons.trending_up;
    case 'VENDER':
      return Icons.trending_down;
    default:
      return Icons.trending_flat;
  }
}

Widget mensajeError(String texto, VoidCallback reintentar) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off, size: 56),
        const SizedBox(height: 16),
        Text(texto, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: reintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );

// ---------------------------------------------------------------------------
// Pantalla principal: lista de señales
// ---------------------------------------------------------------------------

class SenalesPantalla extends StatefulWidget {
  final Ajustes ajustes;
  final void Function(Reporte) alCargar;
  const SenalesPantalla({super.key, required this.ajustes, required this.alCargar});

  @override
  State<SenalesPantalla> createState() => _SenalesPantallaState();
}

class _SenalesPantallaState extends State<SenalesPantalla> {
  Reporte? _reporte;
  String? _error;
  bool _cargando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!widget.ajustes.configurado) {
      setState(() => _error = 'Ve a Ajustes y escribe tu usuario de GitHub.');
      return;
    }
    setState(() => _cargando = true);
    try {
      final r = await Servicio.senales(widget.ajustes);
      widget.alCargar(r);
      if (mounted) setState(() {
        _reporte = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reporte;
    Widget cuerpo;
    if (r == null && _error != null) {
      cuerpo = mensajeError(_error!, _cargar);
    } else if (r == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      cuerpo = ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (r.demo)
            const Card(
              color: Color(0xFF8D6E00),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('MODO DEMO: datos inventados para probar la app. '
                    'Las señales reales aparecen cuando configures las claves en GitHub.'),
              ),
            ),
          if (r.resumen.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ánimo del mercado',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(r.resumen),
                  ],
                ),
              ),
            ),
          ...r.acciones.map((s) => _TarjetaSenal(senal: s)),
          const SizedBox(height: 12),
          Text(r.aviso,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return Column(
      children: [
        ListTile(
          title: const Text('Money IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          subtitle: Text(r == null
              ? 'Cargando…'
              : 'Actualizado ${fechaCorta(r.actualizado)} (${hace(r.actualizado)})'),
          trailing: _cargando
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ),
        if (_error != null && r != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('No se pudo actualizar: $_error',
                style: const TextStyle(color: Colors.orangeAccent)),
          ),
        Expanded(child: RefreshIndicator(onRefresh: _cargar, child: cuerpo)),
      ],
    );
  }
}

class _TarjetaSenal extends StatelessWidget {
  final Senal senal;
  const _TarjetaSenal({required this.senal});

  @override
  Widget build(BuildContext context) {
    final s = senal;
    final color = colorSenal(s.senal);
    final cambio = s.cambioPct;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => DetallePantalla(senal: s))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 92,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Icon(iconoSenal(s.senal), color: Colors.white),
                    Text(s.senal,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('${s.confianza}%',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(s.simbolo,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        if (s.precio != null)
                          Text('\$${s.precio!.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                            child: Text(s.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall)),
                        if (cambio != null)
                          Text('${cambio >= 0 ? '+' : ''}${cambio.toStringAsFixed(2)}%',
                              style: TextStyle(
                                  color: cambio >= 0 ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(s.razones.isNotEmpty ? s.razones.first : '',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detalle de una acción
// ---------------------------------------------------------------------------

class DetallePantalla extends StatelessWidget {
  final Senal senal;
  const DetallePantalla({super.key, required this.senal});

  @override
  Widget build(BuildContext context) {
    final s = senal;
    final color = colorSenal(s.senal);
    final titulo = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: Text('${s.simbolo} · ${s.nombre}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(iconoSenal(s.senal), color: Colors.white, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.senal,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('Confianza de la IA: ${s.confianza}%',
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                if (s.precio != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('\$${s.precio!.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 18)),
                      if (s.cambioPct != null)
                        Text('${s.cambioPct! >= 0 ? '+' : ''}${s.cambioPct!.toStringAsFixed(2)}% hoy',
                            style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('¿Por qué?', style: titulo),
          ...s.razones.map((t) => ListTile(
              dense: true, leading: const Icon(Icons.check_circle_outline), title: Text(t))),
          if (s.riesgos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Riesgos', style: titulo),
            ...s.riesgos.map((t) => ListTile(
                dense: true, leading: const Icon(Icons.warning_amber), title: Text(t))),
          ],
          if (s.noticias.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Noticias que pesaron', style: titulo),
            ...s.noticias.map((n) => Card(
                  child: ListTile(
                    title: Text(n.titulo),
                    subtitle: Text(
                        '${n.fuente} · ${fechaCorta(DateTime.tryParse(n.fecha)?.toLocal())}'),
                    trailing: n.url.isEmpty ? null : const Icon(Icons.open_in_new),
                    onTap: n.url.isEmpty
                        ? null
                        : () => launchUrl(Uri.parse(n.url),
                            mode: LaunchMode.externalApplication),
                  ),
                )),
          ],
          const SizedBox(height: 16),
          const Text(
            'Recuerda: la compra o venta la haces tú en trii. La IA puede equivocarse; '
            'mira el porcentaje de aciertos antes de confiar en ella.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Registro de aciertos
// ---------------------------------------------------------------------------

class AciertosPantalla extends StatefulWidget {
  final Ajustes ajustes;
  const AciertosPantalla({super.key, required this.ajustes});

  @override
  State<AciertosPantalla> createState() => _AciertosPantallaState();
}

class _AciertosPantallaState extends State<AciertosPantalla> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!widget.ajustes.configurado) return;
    try {
      final d = await Servicio.historial(widget.ajustes);
      if (mounted) setState(() {
        _datos = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    if (d == null) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: _error != null
            ? mensajeError(_error!, _cargar)
            : ListView(children: const [
                SizedBox(height: 200),
                Center(child: CircularProgressIndicator()),
              ]),
      );
    }
    final est = (d['estadisticas'] as Map<String, dynamic>?) ?? {};
    final porSenal = (est['por_senal'] as Map<String, dynamic>?) ?? {};
    final registros = ((d['registros'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList()
        .reversed
        .toList();
    final pct = est['porcentaje'];
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('¿Qué tan bien le va a la IA?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(pct == null ? '—' : '$pct%',
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
                  Text('${est['aciertos'] ?? 0} aciertos de ${est['total'] ?? 0} señales evaluadas'),
                  Text('${est['pendientes'] ?? 0} señales esperando resultado (se evalúan a las 24 h)',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          ...porSenal.entries.map((e) {
            final v = e.value as Map<String, dynamic>;
            return ListTile(
              leading: Icon(iconoSenal(e.key), color: colorSenal(e.key)),
              title: Text(e.key),
              trailing: Text('${v['porcentaje'] ?? '—'}%  (${v['aciertos']}/${v['total']})'),
            );
          }),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Guía: tirar una moneda acierta 50%. Mientras la IA no supere con claridad '
              'ese número durante varias semanas, úsala solo para aprender, no para apostar.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          ...registros.take(100).map((r) {
            final res = r['resultado'];
            final fecha = DateTime.tryParse((r['fecha'] ?? '').toString())?.toLocal();
            return ListTile(
              dense: true,
              leading: Icon(iconoSenal('${r['senal']}'), color: colorSenal('${r['senal']}')),
              title: Text('${r['senal']} ${r['simbolo']} a \$${r['precio']}'),
              subtitle: Text(fechaCorta(fecha) +
                  (r['cambio_pct'] != null ? ' · después: ${r['cambio_pct']}%' : '')),
              trailing: res == null
                  ? const Text('pendiente')
                  : Icon(res == 'acierto' ? Icons.check_circle : Icons.cancel,
                      color: res == 'acierto' ? Colors.greenAccent : Colors.redAccent),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ajustes
// ---------------------------------------------------------------------------

class AjustesPantalla extends StatefulWidget {
  final Ajustes ajustes;
  final void Function(Ajustes) alGuardar;
  const AjustesPantalla({super.key, required this.ajustes, required this.alGuardar});

  @override
  State<AjustesPantalla> createState() => _AjustesPantallaState();
}

class _AjustesPantallaState extends State<AjustesPantalla> {
  late final TextEditingController _usuario, _repo, _clave, _modelo;
  bool _verClave = false;

  @override
  void initState() {
    super.initState();
    final a = widget.ajustes;
    _usuario = TextEditingController(text: a.usuarioGithub);
    _repo = TextEditingController(text: a.repo);
    _clave = TextEditingController(text: a.claveGemini);
    _modelo = TextEditingController(text: a.modelo);
  }

  @override
  void dispose() {
    for (final c in [_usuario, _repo, _clave, _modelo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final a = Ajustes(
      usuarioGithub: _usuario.text,
      repo: _repo.text.isEmpty ? 'money' : _repo.text,
      claveGemini: _clave.text,
      modelo: _modelo.text.isEmpty ? 'gemini-flash-latest' : _modelo.text,
    );
    await a.guardar();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
    widget.alGuardar(a);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ajustes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        const Text('Dónde están tus señales (tu repositorio de GitHub):'),
        const SizedBox(height: 8),
        TextField(
          controller: _usuario,
          decoration: const InputDecoration(
              labelText: 'Usuario de GitHub', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _repo,
          decoration: const InputDecoration(
              labelText: 'Nombre del repositorio', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        const Text('Para el chat "Preguntar" (clave gratis de Google AI Studio). '
            'Se guarda solo en este celular:'),
        const SizedBox(height: 8),
        TextField(
          controller: _clave,
          obscureText: !_verClave,
          decoration: InputDecoration(
            labelText: 'Clave de Gemini',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _verClave = !_verClave),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelo,
          decoration: const InputDecoration(
              labelText: 'Modelo de Gemini', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _guardar,
          icon: const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Notificaciones: instala la app "ntfy" desde Play Store y suscríbete al mismo '
          'tema que pusiste en GitHub (NTFY_TOPIC). Ahí te llegan los avisos de compra/venta.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
