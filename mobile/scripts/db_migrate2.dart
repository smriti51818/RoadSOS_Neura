import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(
    Endpoint(
      host: 'YOUR_NEON_HOST',
      database: 'neondb',
      username: 'YOUR_NEON_USER',
      password: 'YOUR_NEON_PASSWORD',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );

  print('Connected.');
  
  await conn.execute('''
    CREATE TABLE IF NOT EXISTS incident_updates (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      incident_id UUID NOT NULL,
      message TEXT NOT NULL,
      responder_name VARCHAR(100),
      responder_phone VARCHAR(20),
      responder_lat DOUBLE PRECISION,
      responder_lng DOUBLE PRECISION,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )
  ''');
  print('Created incident_updates table.');

  await conn.close();
  print('Done.');
}
