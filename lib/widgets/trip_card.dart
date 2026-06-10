import 'package:flutter/material.dart';
import '../models/trip_model.dart';

class TripCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback? onTap;

  const TripCard({
    super.key,
    required this.trip,
    this.onTap,
  });

  static const Color _panel = Color(0xFF071527);
  static const Color _panel2 = Color(0xFF0A1D34);
  static const Color _blue = Color(0xFF39D8B6);
  static const Color _green = Color(0xFF31E981);

  @override
  Widget build(BuildContext context) {
    final fuelPercent = trip.litersAdded > 0
        ? (trip.remainingFuel / trip.litersAdded).clamp(0.0, 1.0)
        : 0.0;

    final statusColor = trip.isActive ? Colors.orange.shade400 : _green;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_panel, _panel2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: trip.isActive
              ? Colors.orange.withOpacity(0.35)
              : _blue.withOpacity(0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(statusColor),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfo(
                      'No tanque',
                      '${trip.remainingFuel.toStringAsFixed(1)} L',
                      Icons.local_gas_station,
                    ),
                    _buildInfo(
                      'Consumo',
                      '${trip.consumptionPerKm.toStringAsFixed(1)} km/L',
                      Icons.speed,
                    ),
                    _buildInfo(
                      'Percorrido',
                      '${trip.distanceTraveled.toStringAsFixed(1)} km',
                      Icons.route,
                    ),
                    _buildInfo(
                      'Autonomia',
                      '${trip.estimatedRange.toStringAsFixed(0)} km',
                      Icons.map,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fuelPercent,
                    minHeight: 7,
                    backgroundColor: const Color(0xFF050A14),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      fuelPercent > 0.5
                          ? _green
                          : fuelPercent > 0.2
                              ? Colors.orange.shade400
                              : Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color statusColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              trip.isActive ? Icons.local_gas_station : Icons.check_circle,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              trip.isActive ? 'VIAGEM ATIVA' : 'VIAGEM FINALIZADA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: statusColor,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        Text(
          _formatDate(trip.createdAt),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildInfo(String label, String value, IconData icon) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: _blue, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white38,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }
}
