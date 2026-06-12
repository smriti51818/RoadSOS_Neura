import { neon } from '@neondatabase/serverless';
import { NextResponse } from 'next/server';

const DB_URL = 'postgresql://neondb_owner:npg_Jp8auMDi9LQo@ep-proud-hall-aomwr005-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { status, notes, priority } = body;

    const sql = neon(DB_URL);

    if (status !== undefined) {
      await sql`UPDATE incidents SET status = ${status} WHERE id = ${id}`;
    }
    if (notes !== undefined) {
      await sql`UPDATE incidents SET notes = ${notes} WHERE id = ${id}`;
    }
    if (priority !== undefined) {
      await sql`UPDATE incidents SET priority = ${priority} WHERE id = ${id}`;
    }

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('Error updating incident:', error);
    return NextResponse.json({ error: 'Failed to update incident' }, { status: 500 });
  }
}
