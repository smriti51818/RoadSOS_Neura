export type IncidentStatus = 'Received' | 'Acknowledged' | 'Dispatched' | 'En Route' | 'Resolved' | 'Closed';
export type IncidentPriority = 'P1' | 'P2' | 'P3';

export interface Incident {
  id: string;
  user_phone: string | null;
  service_name: string;
  lat: number;
  lng: number;
  status: IncidentStatus;
  timestamp: string;
  photos: string | null;
  user_name: string | null;
  blood_group: string | null;
  priority: IncidentPriority;
  notes: string | null;
}
