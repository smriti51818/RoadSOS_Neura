import { neon } from '@neondatabase/serverless';
import { NextResponse } from 'next/server';

const DB_URL = 'postgresql://neondb_owner:npg_Jp8auMDi9LQo@ep-proud-hall-aomwr005-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const sql = neon(DB_URL);
    const updates = await sql`
      SELECT id, incident_id, message, responder_name, responder_phone,
             responder_lat, responder_lng, created_at
      FROM incident_updates
      WHERE incident_id = ${id}
      ORDER BY created_at ASC
    `;
    
    // Also fetch current incident status
    const incident = await sql`
      SELECT status, priority FROM incidents WHERE id = ${id}
    `;

    return NextResponse.json({ 
      updates,
      incident_status: incident[0]?.status ?? 'Received',
      incident_priority: incident[0]?.priority ?? 'P2',
    });
  } catch (error) {
    console.error('Error fetching updates:', error);
    return NextResponse.json({ error: 'Failed to fetch updates' }, { status: 500 });
  }
}

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { message, responder_name, responder_phone, responder_lat, responder_lng } = body;

    if (!message) {
      return NextResponse.json({ error: 'Message is required' }, { status: 400 });
    }

    const sql = neon(DB_URL);
    await sql`
      INSERT INTO incident_updates (incident_id, message, responder_name, responder_phone, responder_lat, responder_lng)
      VALUES (
        ${id},
        ${message},
        ${responder_name || null},
        ${responder_phone || null},
        ${responder_lat || null},
        ${responder_lng || null}
      )
    `;

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error posting update:', error);
    return NextResponse.json({ error: 'Failed to post update' }, { status: 500 });
  }
}
