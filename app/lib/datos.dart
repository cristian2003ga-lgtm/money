import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Ajustes guardados en el celular (nunca dentro del APK)
// ---------------------------------------------------------------------------

class Ajustes {
  String usuarioGithub;
  String repo;
  String claveGemini;
  String modelo;

  Ajustes({
    this.usuarioGithub = '',
    this.repo = 'money',
    this.claveGemini = '',
    this.modelo = 'gemini-flash-latest',
  });

  bool get configurado => usuarioGithub.trim().isNotEmpty;
  bool get chatListo => claveGemini.trim().isNotEmpty;

  String urlDatos(String archivo) =>
      'https://raw.githubusercontent.com/${usuarioGithub.trim()}/${repo.trim()}/main/data/$archivo';

  static Future<Ajustes> cargar() async {
    final p = await SharedPreferences.getInstance();
    return Ajustes(
      usuarioGithub: p.getString('usuarioGithub') ?? '',
      repo: p.getString('repo') ?? 'money',
      claveGemini: p.getString('claveGemini') ?? '',
      modelo: p.getString('modelo') ?? 'gemini-flash-latest',
    );
  }

  Future<void> guardar() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('usuarioGithub', usuarioGithub.trim());
    await p.setString('repo', repo.trim());
    await p.setString('claveGemini', claveGemini.trim());
    await p.setString('modelo', modelo.trim());
  }
}

// ---------------------------------------------------------------------------
// Modelos de datos
// ---------------------------------------------------------------------------

double? _num(dynamic v) => v is num ? v.toDouble() : null;
List<String> _textos(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

class Noticia {
  final String titulo, fuente, url, fecha;
  Noticia(this.titulo, this.fuente, this.url, this.fecha);

  factory Noticia.fromJson(Map<String, dynamic> j) => Noticia(
        (j['titulo'] ?? '').toString(),
        (j['fuente'] ?? '').toString(),
        (j['url'] ?? '').toString(),
        (j['fecha'] ?? '').toString(),
      );
}

class Senal {
  final String simbolo, nombre, senal;
  final double? precio, cambioPct;
  final int confianza;
  final List<String> razones, riesgos;
  final List<Noticia> noticias;

  Senal({
    required this.simbolo,
    required this.nombre,
    required this.senal,
    required this.precio,
    required this.cambioPct,
    required this.confianza,
    required this.razones,
    required this.riesgos,
    required this.noticias,
  });

  factory Senal.fromJson(Map<String, dynamic> j) => Senal(
        simbolo: (j['simbolo'] ?? '').toString(),
        nombre: (j['nombre'] ?? '').toString(),
        senal: (j['senal'] ?? 'MANTENER').toString(),
        precio: _num(j['precio']),
        cambioPct: _num(j['cambio_pct']),
        confianza: (j['confianza'] is num) ? (j['confianza'] as num).round() : 0,
        razones: _textos(j['razones']),
        riesgos: _textos(j['riesgos']),
        noticias: (j['noticias'] is List)
            ? (j['noticias'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Noticia.fromJson)
                .toList()
            : <Noticia>[],
      );
}

class Reporte {
  final DateTime? actualizado;
  final bool demo;
  final String resumen, aviso;
  final List<Senal> acciones;
  final String jsonCrudo;

  Reporte(this.actualizado, this.demo, this.resumen, this.aviso, this.acciones,
      this.jsonCrudo);

  factory Reporte.fromJson(Map<String, dynamic> j, String crudo) => Reporte(
        DateTime.tryParse((j['actualizado'] ?? '').toString())?.toLocal(),
        j['demo'] == true,
        (j['resumen_mercado'] ?? '').toString(),
        (j['aviso'] ?? '').toString(),
        (j['acciones'] is List)
            ? (j['acciones'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Senal.fromJson)
                .toList()
            : <Senal>[],
        crudo,
      );
}

// ---------------------------------------------------------------------------
// Lectura de datos publicados por el servidor (GitHub)
// ---------------------------------------------------------------------------

class Servicio {
  static Future<String> _bajar(Ajustes a, String archivo) async {
    final url = '${a.urlDatos(archivo)}?t=${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) {
      throw Exception('Todavía no hay datos en GitHub. Revisa en Ajustes tu usuario y '
          'repositorio, y que el análisis automático se haya ejecutado al menos una vez.');
    }
    if (r.statusCode != 200) {
      throw Exception('Error ${r.statusCode} al leer los datos.');
    }
    return utf8.decode(r.bodyBytes);
  }

  static Future<Reporte> senales(Ajustes a) async {
    final texto = await _bajar(a, 'senales.json');
    return Reporte.fromJson(jsonDecode(texto) as Map<String, dynamic>, texto);
  }

  static Future<Map<String, dynamic>> historial(Ajustes a) async {
    final texto = await _bajar(a, 'historial.json');
    return jsonDecode(texto) as Map<String, dynamic>;
  }
}

// ---------------------------------------------------------------------------
// Chat con la IA (Gemini)
// ---------------------------------------------------------------------------

class MensajeChat {
  final bool esUsuario;
  final String texto;
  MensajeChat(this.esUsuario, this.texto);
}

class ChatIA {
  static Future<String> preguntar(
      Ajustes a, List<MensajeChat> conversacion, String contexto) async {
    final instrucciones = '''
Eres el asistente de la app "Money IA". Ayudas a un inversionista principiante
en Colombia que compra acciones con montos pequeños en la app trii.
Responde en español sencillo y breve. Basa tus respuestas en el análisis más
reciente que te paso abajo (precios, señales y noticias). Si te preguntan algo
que no está en esos datos, dilo con honestidad y responde con conocimiento
general, aclarando que no es información en tiempo real.
Nunca prometas ganancias. Recuerda, cuando aplique, que no eres asesor
financiero y que conviene diversificar y no invertir dinero que se necesite.

ANÁLISIS MÁS RECIENTE (JSON):
$contexto
''';
    final cuerpo = {
      'systemInstruction': {
        'parts': [
          {'text': instrucciones}
        ]
      },
      'contents': conversacion
          .map((m) => {
                'role': m.esUsuario ? 'user' : 'model',
                'parts': [
                  {'text': m.texto}
                ]
              })
          .toList(),
      'generationConfig': {'temperature': 0.4},
    };
    // Si Google está saturado (503) o se corta la conexión, reintenta y,
    // si sigue fallando, prueba con un modelo más liviano.
    final modelos = <String>{a.modelo.trim(), 'gemini-flash-lite-latest'}.toList();
    http.Response? r;
    Object? ultimoError;
    int? ultimoCodigo;
    for (final modelo in modelos) {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$modelo:generateContent');
      for (var intento = 0; intento < 3; intento++) {
        final cliente = http.Client();
        try {
          final resp = await cliente
              .post(uri,
                  headers: {
                    'Content-Type': 'application/json',
                    'Connection': 'close',
                    'x-goog-api-key': a.claveGemini.trim(),
                  },
                  body: jsonEncode(cuerpo))
              .timeout(const Duration(seconds: 90));
          ultimoCodigo = resp.statusCode;
          if (resp.statusCode == 200) {
            r = resp;
            break;
          }
          if (resp.statusCode == 400 || resp.statusCode == 403) {
            throw Exception('Gemini rechazó la clave (error ${resp.statusCode}). '
                'Revisa la clave en Ajustes.');
          }
          if (resp.statusCode == 404) break; // modelo no existe: probar el siguiente
        } on Exception catch (e) {
          if (e.toString().contains('rechazó la clave')) rethrow;
          ultimoError = e;
        } finally {
          cliente.close();
        }
        await Future.delayed(Duration(seconds: 2 * (intento + 1)));
      }
      if (r != null) break;
    }
    if (r == null) {
      if (ultimoCodigo == 503 || ultimoCodigo == 500) {
        throw Exception('Los servidores de Google están saturados en este momento. '
            'Intenta de nuevo en uno o dos minutos.');
      }
      if (ultimoCodigo == 429) {
        throw Exception('Llegaste al límite gratis de Gemini por ahora. Espera un minuto.');
      }
      if (ultimoCodigo == 404) {
        throw Exception('El modelo de Gemini no existe. Revisa el nombre en Ajustes.');
      }
      throw Exception('No se pudo conectar con la IA. Revisa tu internet y vuelve a '
          'preguntar. (Detalle: ${ultimoError ?? 'código $ultimoCodigo'})');
    }
    final texto = utf8.decode(r.bodyBytes);
    final j = jsonDecode(texto) as Map<String, dynamic>;
    final candidatos = j['candidates'];
    if (candidatos is! List || candidatos.isEmpty) {
      return 'La IA no devolvió respuesta. Intenta preguntar de otra forma.';
    }
    final partes = (candidatos.first['content']?['parts'] as List?) ?? [];
    return partes.map((p) => (p['text'] ?? '').toString()).join().trim();
  }
}

// ---------------------------------------------------------------------------
// Formato
// ---------------------------------------------------------------------------

String dosDigitos(int n) => n.toString().padLeft(2, '0');

String fechaCorta(DateTime? d) {
  if (d == null) return '—';
  return '${dosDigitos(d.day)}/${dosDigitos(d.month)} ${dosDigitos(d.hour)}:${dosDigitos(d.minute)}';
}

String hace(DateTime? d) {
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'hace un momento';
  if (m < 60) return 'hace $m min';
  final h = m ~/ 60;
  if (h < 48) return 'hace $h h';
  return 'hace ${h ~/ 24} días';
}
