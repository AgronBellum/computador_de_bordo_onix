import 'dart:math' as math;
import 'package:flutter/material.dart';

class FuelGauge extends StatelessWidget {
  final double percentage;
  final double remainingLiters;
  final double estimatedKm;

  const FuelGauge({
    super.key,
    required this.percentage,
    required this.remainingLiters,
    required this.estimatedKm,
  });

  static const Color _blue = Color(0xFF1677FF);

  @override
  Widget build(BuildContext context) {
    final safePercentage = percentage.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 345),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF071527),
            Color(0xFF0A1D34),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: SizedBox(
          width: 330,
          height: 245,
          child: CustomPaint(
            painter: _FuelArcPainter(percentage: safePercentage),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_gas_station,
                    color: Colors.white,
                    size: 34,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'GASOLINA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '${(safePercentage * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 70,
                      fontWeight: FontWeight.bold,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'E',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildFuelBlocks(),
                      const SizedBox(width: 10),
                      const Text(
                        'F',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nível de combustível',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFuelBlocks() {
    const colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.orange,
      Colors.amber,
      Colors.yellow,
      Colors.limeAccent,
      Colors.lightGreenAccent,
      Colors.green,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(colors.length, (index) {
        return Container(
          width: 19,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: colors[index],
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: colors[index].withOpacity(0.35),
                blurRadius: 8,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _FuelArcPainter extends CustomPainter {
  final double percentage;

  _FuelArcPainter({required this.percentage});

  @override
  void paint(Canvas canvas, Size size) {
    final safePercentage = percentage.clamp(0.0, 1.0);

    final rect = Rect.fromLTWH(
      22,
      20,
      size.width - 44,
      size.height + 70,
    );

    const startAngle = math.pi * 0.82;
    const sweepAngle = math.pi * 1.36;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: const [
        Colors.red,
        Colors.orange,
        Colors.yellow,
        Colors.lightGreenAccent,
        Colors.green,
      ],
    );

    final fuelPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * safePercentage,
      false,
      fuelPaint,
    );

    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..strokeWidth = 1.4;

    for (int i = 0; i <= 12; i++) {
      final angle = startAngle + (sweepAngle / 12) * i;
      final center = rect.center;

      final outerRadius = rect.width / 2 - 8;
      final innerRadius = rect.width / 2 - 20;

      final p1 = Offset(
        center.dx + math.cos(angle) * outerRadius,
        center.dy + math.sin(angle) * outerRadius,
      );

      final p2 = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );

      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FuelArcPainter oldDelegate) {
    return oldDelegate.percentage != percentage;
  }
}