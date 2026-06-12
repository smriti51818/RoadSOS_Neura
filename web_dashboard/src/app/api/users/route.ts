import { neon } from '@neondatabase/serverless';
import { NextResponse } from 'next/server';

const DB_URL = 'postgresql://neondb_owner:npg_Jp8auMDi9LQo@ep-proud-hall-aomwr005-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require';

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { phone, name, blood_group } = body;

    if (!phone) {
      return NextResponse.json({ error: 'Phone is required' }, { status: 400 });
    }

    const sql = neon(DB_URL);
    await sql`
      INSERT INTO users (phone, name, blood_group)
      VALUES (${phone}, ${name || ''}, ${blood_group || ''})
      ON CONFLICT (phone) DO UPDATE 
      SET name = EXCLUDED.name, blood_group = EXCLUDED.blood_group
    `;

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error upserting user:', error);
    return NextResponse.json({ error: 'Failed to upsert user' }, { status: 500 });
  }
}
