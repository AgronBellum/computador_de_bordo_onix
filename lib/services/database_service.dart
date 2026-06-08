import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/trip_model.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._init();

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('car_fuel.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        litersAdded REAL NOT NULL,
        consumptionPerKm REAL NOT NULL,
        initialOdometer REAL NOT NULL,
        currentOdometer REAL NOT NULL,
        distanceTraveled REAL NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        endedAt TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        remainingFuel REAL NOT NULL DEFAULT 0,
        estimatedRange REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE gps_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        odometer REAL NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<TripModel> createTrip(TripModel trip) async {
    final db = await database;

    // Garante que só exista uma viagem ativa por vez.
    await db.update(
      'trips',
      {
        'isActive': 0,
        'endedAt': DateTime.now().toIso8601String(),
      },
      where: 'isActive = ?',
      whereArgs: [1],
    );

    final id = await db.insert(
      'trips',
      trip.toMap()..remove('id'),
    );

    return trip.copyWith(id: id);
  }

  Future<List<TripModel>> getAllTrips() async {
    final db = await database;

    final maps = await db.query(
      'trips',
      orderBy: 'createdAt DESC',
    );

    return maps.map((e) => TripModel.fromMap(e)).toList();
  }

  Future<TripModel?> getActiveTrip() async {
    final db = await database;

    final maps = await db.query(
      'trips',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return TripModel.fromMap(maps.first);
  }

  Future<int> updateTrip(TripModel trip) async {
    if (trip.id == null) return 0;

    final db = await database;

    return db.update(
      'trips',
      trip.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  Future<int> endTrip(int tripId) async {
    final db = await database;

    return db.update(
      'trips',
      {
        'isActive': 0,
        'endedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [tripId],
    );
  }

  Future<int> deleteTrip(int id) async {
    final db = await database;

    return db.delete(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addGpsPoint(int tripId, GpsPoint point) async {
    final db = await database;

    await db.insert(
      'gps_points',
      {
        ...point.toMap(),
        'tripId': tripId,
      },
    );
  }

  Future<List<GpsPoint>> getGpsPoints(int tripId) async {
    final db = await database;

    final maps = await db.query(
      'gps_points',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((e) => GpsPoint.fromMap(e)).toList();
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

extension TripModelCopy on TripModel {
  TripModel copyWith({
    int? id,
    double? litersAdded,
    double? consumptionPerKm,
    double? initialOdometer,
    double? currentOdometer,
    double? distanceTraveled,
    DateTime? createdAt,
    DateTime? endedAt,
    bool? isActive,
    double? remainingFuel,
    double? estimatedRange,
    List<GpsPoint>? gpsPoints,
  }) {
    return TripModel(
      id: id ?? this.id,
      litersAdded: litersAdded ?? this.litersAdded,
      consumptionPerKm: consumptionPerKm ?? this.consumptionPerKm,
      initialOdometer: initialOdometer ?? this.initialOdometer,
      currentOdometer: currentOdometer ?? this.currentOdometer,
      distanceTraveled: distanceTraveled ?? this.distanceTraveled,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      isActive: isActive ?? this.isActive,
      remainingFuel: remainingFuel ?? this.remainingFuel,
      estimatedRange: estimatedRange ?? this.estimatedRange,
      gpsPoints: gpsPoints ?? this.gpsPoints,
    );
  }
}