import 'package:flutter/material.dart';

import 'datos.dart';
import 'pantallas.dart';
import 'chat.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoneyApp());
}

class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Money IA',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF2E7D32),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
      ),
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  Ajustes? _ajustes;
  Reporte? _ultimoReporte;
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    Ajustes.cargar().then((a) => setState(() {
          _ajustes = a;
          if (!a.configurado) _pestana = 3;
        }));
  }

  void _ajustesGuardados(Ajustes a) {
    setState(() {
      _ajustes = a;
      _pestana = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _ajustes;
    if (a == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final paginas = [
      SenalesPantalla(
        key: ValueKey('senales-${a.usuarioGithub}-${a.repo}'),
        ajustes: a,
        alCargar: (r) => _ultimoReporte = r,
      ),
      ChatPantalla(ajustes: a, contexto: () => _ultimoReporte?.jsonCrudo ?? ''),
      AciertosPantalla(key: ValueKey('aciertos-${a.usuarioGithub}-${a.repo}'), ajustes: a),
      AjustesPantalla(ajustes: a, alGuardar: _ajustesGuardados),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _pestana, children: paginas)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Señales'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Preguntar'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Aciertos'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
        ],
      ),
    );
  }
}
