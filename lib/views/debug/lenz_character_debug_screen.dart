import 'package:flutter/material.dart';

import '../../widgets/lenz/lenz.dart';

/// Debug-only gallery of every Lenz mood x view. Not wired into routes.
class LenzCharacterDebugScreen extends StatefulWidget {
  const LenzCharacterDebugScreen({super.key});

  @override
  State<LenzCharacterDebugScreen> createState() => _LenzCharacterDebugScreenState();
}

class _LenzCharacterDebugScreenState extends State<LenzCharacterDebugScreen> {
  LenzMood _mood = LenzMood.idle;
  LenzView _view = LenzView.full;
  bool _fx = true;
  bool _shadow = true;
  bool _reduce = false;
  final LenzController _controller = LenzController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(title: const Text('Lenz character debug')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300),
                      child: LenzCharacter(
                        mood: _mood,
                        view: _view,
                        fx: _fx,
                        shadow: _shadow,
                        reduceMotion: _reduce,
                        controller: _controller,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${_mood.name} / ${_view.name}', style: Theme.of(context).textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(label: const Text('FX'), selected: _fx, onSelected: (v) => setState(() => _fx = v)),
                      FilterChip(label: const Text('Shadow'), selected: _shadow, onSelected: (v) => setState(() => _shadow = v)),
                      FilterChip(
                        label: const Text('Reduce motion'),
                        selected: _reduce,
                        onSelected: (v) => setState(() => _reduce = v),
                      ),
                      TextButton(onPressed: _controller.hop, child: const Text('Hop')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          for (final view in LenzView.values) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(view.name.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: LenzMood.values.length,
                  (context, i) {
                    final mood = LenzMood.values[i];
                    final selected = mood == _mood && view == _view;
                    return Material(
                      color: selected ? const Color(0xFFD6E8DE) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() {
                          _mood = mood;
                          _view = view;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: LenzCharacter(
                                    mood: mood,
                                    view: view,
                                    fx: _fx,
                                    reduceMotion: _reduce,
                                    interactive: false,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(mood.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
