import 'package:postgres/postgres.dart';

void main() async {
  final connection = await Connection.open(
    Endpoint(
      host: 'YOUR_NEON_HOST',
      database: 'neondb',
      username: 'YOUR_NEON_USER',
      password: 'YOUR_NEON_PASSWORD',
    ),
    settings: const ConnectionSettings(
      sslMode: SslMode.require,
    ),
  );

  print('Connected to Neon Postgres.');

  // Create users table
  await connection.execute('''
    CREATE TABLE IF NOT EXISTS users (
      phone VARCHAR(20) PRIMARY KEY,
      name VARCHAR(100),
      blood_group VARCHAR(10)
    )
  ''');
  print('Created users table.');

  // Create incidents table
  await connection.execute('''
    CREATE TABLE IF NOT EXISTS incidents (
      id UUID PRIMARY KEY,
      user_phone VARCHAR(20) REFERENCES users(phone),
      service_name VARCHAR(100),
      lat DOUBLE PRECISION,
      lng DOUBLE PRECISION,
      status VARCHAR(50),
      timestamp TIMESTAMP WITH TIME ZONE,
      photos TEXT -- Comma separated paths/URLs for hackathon simplicity
    )
  ''');
  print('Created incidents table.');

  await connection.close();
  print('Done.');
}
