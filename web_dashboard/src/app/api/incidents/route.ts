import { neon } from '@neondatabase/serverless';
import { NextResponse } from 'next/server';

const DB_URL = 'postgresql://neondb_owner:npg_Jp8auMDi9LQo@ep-proud-hall-aomwr005-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require';

export async function GET() {
  try {
    const sql = neon(DB_URL);
    const incidents = await sql`
      SELECT 
        i.id, 
        i.user_phone, 
        i.service_name, 
        i.lat, 
        i.lng, 
        i.status, 
        i.timestamp, 
        i.photos,
        i.priority,
        i.notes,
        u.name   AS user_name,
        u.blood_group
      FROM incidents i
      LEFT JOIN users u ON i.user_phone = u.phone
      ORDER BY i.timestamp DESC
    `;
    return NextResponse.json({ incidents });
  } catch (error) {
    console.error('Error fetching incidents:', error);
    return NextResponse.json({ error: 'Failed to fetch incidents' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { id, user_phone, service_name, lat, lng, status, timestamp, photos, priority } = body;

    if (!id || !service_name || lat == null || lng == null) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    const sql = neon(DB_URL);

    if (user_phone) {
      await sql`
        INSERT INTO users (phone, name, blood_group)
        VALUES (${user_phone}, 'Unknown', 'Unknown')
        ON CONFLICT DO NOTHING
      `;
    }

    await sql`
      INSERT INTO incidents (id, user_phone, service_name, lat, lng, status, timestamp, photos, priority, notes)
      VALUES (
        ${id},
        ${user_phone || null},
        ${service_name},
        ${lat},
        ${lng},
        ${status},
        ${timestamp},
        ${photos || ''},
        ${priority || 'P2'},
        ${''}
      )
    `;

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error inserting incident:', error);
    return NextResponse.json({ error: 'Failed to insert incident' }, { status: 500 });
  }
}
