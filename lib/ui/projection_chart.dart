import 'dart:math' as math;

import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_ui/material_ui.dart';

import '../domain/money.dart';

class ChartSeries {
  final String name;
  final Color color;
  final List<(DateTime, Cents)> points;
  const ChartSeries(this.name, this.color, this.points);
}

String _compact(Cents c) {
  final v = c / 100;
  final abs = v.abs();
  final sign = v < 0 ? '-' : '';
  if (abs >= 1000000) return '$sign\$${(abs / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) return '$sign\$${(abs / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
  return '$sign\$${abs.toStringAsFixed(0)}';
}

/// Gráfica de saldo proyectado por día (líneas escalonadas: el saldo solo
/// cambia cuando ocurre un evento). Toca o pasa el cursor para ver el detalle.
class ProjectionChart extends StatefulWidget {
  final List<ChartSeries> series;
  final double height;
  const ProjectionChart({super.key, required this.series, this.height = 220});

  @override
  State<ProjectionChart> createState() => _ProjectionChartState();
}

class _ProjectionChartState extends State<ProjectionChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.series;
    if (s.isEmpty || s.first.points.isEmpty) return const SizedBox.shrink();
    final n = s.first.points.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            for (final x in s)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 3, decoration: BoxDecoration(color: x.color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text(x.name, style: theme.textTheme.bodySmall),
              ]),
          ]),
        ),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          const left = 44.0, right = 8.0;
          int indexAt(double dx) => (((dx - left) / (c.maxWidth - left - right)) * (n - 1)).round().clamp(0, n - 1);
          return MouseRegion(
            onHover: (e) => setState(() => _hover = indexAt(e.localPosition.dx)),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapDown: (e) => setState(() => _hover = indexAt(e.localPosition.dx)),
              onHorizontalDragUpdate: (e) => setState(() => _hover = indexAt(e.localPosition.dx)),
              onHorizontalDragEnd: (_) {},
              child: Stack(clipBehavior: Clip.none, children: [
                CustomPaint(
                  size: Size(c.maxWidth, widget.height),
                  painter: _ChartPainter(
                    series: s,
                    hover: _hover,
                    grid: theme.colorScheme.outlineVariant,
                    axis: theme.colorScheme.onSurfaceVariant,
                    surface: theme.colorScheme.surface,
                    labelStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    left: left,
                    right: right,
                  ),
                ),
                if (_hover != null) _tooltip(context, c.maxWidth, left, right),
              ]),
            ),
          );
        }),
      ),
    ]);
  }

  Widget _tooltip(BuildContext context, double width, double left, double right) {
    final theme = Theme.of(context);
    final i = _hover!;
    final n = widget.series.first.points.length;
    final x = left + (width - left - right) * (n == 1 ? 0 : i / (n - 1));
    const w = 190.0;
    final dx = (x + 10 + w > width) ? x - 10 - w : x + 10;
    return Positioned(
      left: dx.clamp(0, math.max(0, width - w)),
      top: 0,
      child: IgnorePointer(
        child: Container(
          width: w,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x22000000))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(DateFormat("EEE d MMM", 'es_MX').format(widget.series.first.points[i].$1), style: theme.textTheme.labelMedium),
            for (final s in widget.series)
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(s.name, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                Text(formatMoney(s.points[i].$2), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final int? hover;
  final Color grid, axis, surface;
  final TextStyle labelStyle;
  final double left, right;

  _ChartPainter({
    required this.series,
    required this.hover,
    required this.grid,
    required this.axis,
    required this.surface,
    required this.labelStyle,
    required this.left,
    required this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0, bottom = 22.0;
    final n = series.first.points.length;
    var lo = 0, hi = 0;
    for (final s in series) {
      for (final p in s.points) {
        lo = math.min(lo, p.$2);
        hi = math.max(hi, p.$2);
      }
    }
    if (hi == lo) hi = lo + 10000;
    // Escala «redonda»: 4 divisiones.
    final rawStep = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final step = ([1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((v) => v >= rawStep, orElse: () => 10 * mag)).toDouble();
    final yMin = (lo / step).floor() * step;
    final yMax = (hi / step).ceil() * step;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double xOf(int i) => left + (n == 1 ? 0 : w * i / (n - 1));
    double yOf(num v) => top + h * (1 - (v - yMin) / (yMax - yMin));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = yMin; v <= yMax + 1; v += step) {
      final y = yOf(v);
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), gridPaint);
      final tp = TextPainter(text: TextSpan(text: _compact(v.round()), style: labelStyle), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(left - tp.width - 6, y - tp.height / 2));
    }
    // Línea de cero más marcada: debajo de ella el saldo sería negativo.
    if (yMin < 0) {
      canvas.drawLine(Offset(left, yOf(0)), Offset(size.width - right, yOf(0)), Paint()
        ..color = axis
        ..strokeWidth = 1);
    }
    final fmt = DateFormat('d MMM', 'es_MX');
    for (final i in {0, n ~/ 2, n - 1}) {
      final tp = TextPainter(text: TextSpan(text: fmt.format(series.first.points[i].$1), style: labelStyle), textDirection: TextDirection.ltr)
        ..layout();
      final x = (xOf(i) - tp.width / 2).clamp(left, size.width - right - tp.width);
      tp.paint(canvas, Offset(x, size.height - bottom + 6));
    }

    for (final s in series) {
      final path = Path()..moveTo(xOf(0), yOf(s.points.first.$2));
      for (var i = 1; i < n; i++) {
        path.lineTo(xOf(i), yOf(s.points[i - 1].$2));
        path.lineTo(xOf(i), yOf(s.points[i].$2));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    if (hover != null) {
      final x = xOf(hover!);
      canvas.drawLine(Offset(x, top), Offset(x, top + h), Paint()
        ..color = axis.withValues(alpha: 0.6)
        ..strokeWidth = 1);
      for (final s in series) {
        final c = Offset(x, yOf(s.points[hover!].$2));
        canvas.drawCircle(c, 6, Paint()..color = surface);
        canvas.drawCircle(c, 4, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.series != series || old.hover != hover || old.grid != grid;
}
