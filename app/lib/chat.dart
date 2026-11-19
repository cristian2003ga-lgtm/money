import 'package:flutter/material.dart';

import 'datos.dart';

class ChatPantalla extends StatefulWidget {
  final Ajustes ajustes;
  final String Function() contexto;
  const ChatPantalla({super.key, required this.ajustes, required this.contexto});

  @override
  State<ChatPantalla> createState() => _ChatPantallaState();
}

class _ChatPantallaState extends State<ChatPantalla> {
  final _mensajes = <MensajeChat>[];
  final _entrada = TextEditingController();
  final _scroll = ScrollController();
  bool _pensando = false;

  static const _sugerencias = [
    '¿Cuál es la mejor oportunidad hoy?',
    '¿Qué pasa con Ecopetrol?',
    'Explícame la señal de Nvidia',
    '¿Qué noticias están moviendo el mercado?',
  ];

  @override
  void dispose() {
    _entrada.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar([String? texto]) async {
    final pregunta = (texto ?? _entrada.text).trim();
    if (pregunta.isEmpty || _pensando) return;
    if (!widget.ajustes.chatListo) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Primero pon tu clave de Gemini en Ajustes.')));
      return;
    }
    _entrada.clear();
    setState(() {
      _mensajes.add(MensajeChat(true, pregunta));
      _pensando = true;
    });
    _bajar();
    try {
      final ctx = widget.contexto();
      final respuesta = await ChatIA.preguntar(
        widget.ajustes,
        // se envían los últimos 12 mensajes para no gastar de más
        _mensajes.length > 12 ? _mensajes.sublist(_mensajes.length - 12) : _mensajes,
        ctx.isEmpty ? '(Aún no se han cargado señales; abre la pestaña Señales.)' : ctx,
      );
      setState(() => _mensajes.add(MensajeChat(false, respuesta)));
    } catch (e) {
      setState(() => _mensajes.add(
          MensajeChat(false, '⚠️ ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      setState(() => _pensando = false);
      _bajar();
    }
  }

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      children: [
        const ListTile(
          title: Text('Pregúntale a la IA',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          subtitle: Text('Responde con las señales y noticias más recientes'),
        ),
        Expanded(
          child: _mensajes.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Prueba con:'),
                    const SizedBox(height: 8),
                    ..._sugerencias.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ActionChip(label: Text(s), onPressed: () => _enviar(s)),
                        )),
                  ],
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _mensajes.length + (_pensando ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _mensajes.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Pensando…'),
                      );
                    }
                    final m = _mensajes[i];
                    return Align(
                      alignment: m.esUsuario ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.82),
                        decoration: BoxDecoration(
                          color: m.esUsuario
                              ? esquema.primaryContainer
                              : esquema.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(m.texto),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _entrada,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(),
                  decoration: const InputDecoration(
                    hintText: 'Escribe tu pregunta…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _pensando ? null : _enviar,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
