import 'package:flutter/material.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key, required this.onStart, required this.onModels});
  final VoidCallback onStart, onModels;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: '軍師、平静',
                  image: true,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/gunshi/face_composed.png',
                      height: 192,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) => const SizedBox(
                        height: 192,
                        child: Center(child: Text('軍師、平静')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '自称・天才軍師との一局',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                const Text('煽って冷静を崩す、褒めて慢心させる。感情が動くと指し手も変わります'),
                const SizedBox(height: 16),
                const Text('感情を動かせるのは1手3回まで。効き方は局面で変わります'),
                const SizedBox(height: 24),
                FilledButton(onPressed: onStart, child: const Text('対局を始める')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onModels,
                  child: const Text('軍師の言葉について'),
                ),
                const SizedBox(height: 8),
                const Text('モデルの導入は任意です。未導入でも定型文で遊べます。'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
