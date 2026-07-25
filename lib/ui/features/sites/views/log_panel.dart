import 'package:flutter/material.dart';

/// A monospace, auto-scrolling log pane for a site's server output.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.lines});

  final List<String> lines;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant LogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: widget.lines.isEmpty
          ? const Center(
              child: Text(
                'No output yet. Start the site to see logs.',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
              ),
            )
          : ListView.builder(
              controller: _controller,
              itemCount: widget.lines.length,
              itemBuilder: (context, i) => Text(
                widget.lines[i],
                style: const TextStyle(
                  color: Color(0xFFD1D1D6),
                  fontFamily: 'Menlo',
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
    );
  }
}
