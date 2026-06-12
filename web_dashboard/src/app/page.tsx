"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import dynamic from "next/dynamic";
import {
  AlertTriangle, Phone, CheckCircle, Clock, Activity, MapPin,
  User, FileText, Radio, Truck, Send, RefreshCw, ExternalLink,
  AlertCircle, Volume2, NotebookPen, ChevronUp, ChevronDown,
} from "lucide-react";
import type { Incident, IncidentStatus, IncidentPriority } from "../types";

const MapComponent = dynamic(() => import("../components/Map"), {
  ssr: false,
  loading: () => (
    <div className="w-full h-full flex items-center justify-center bg-gray-100 text-gray-400 text-sm tracking-wide">
      Initializing Map…
    </div>
  ),
});

// ─── Priority config ────────────────────────────────────────────────────────
const PRIORITY_META: Record<IncidentPriority, { label: string; bg: string; text: string; border: string; description: string }> = {
  P1: { label: "P1 CRITICAL", bg: "bg-red-600",    text: "text-white",      border: "border-red-700",   description: "Life-threatening — Immediate response" },
  P2: { label: "P2 URGENT",   bg: "bg-amber-500",  text: "text-white",      border: "border-amber-600", description: "Urgent — Respond within 8 minutes" },
  P3: { label: "P3 ROUTINE",  bg: "bg-blue-500",   text: "text-white",      border: "border-blue-600",  description: "Non-emergency — Respond within 30 minutes" },
};

// ─── Status config ──────────────────────────────────────────────────────────
const STATUS_FLOW: IncidentStatus[] = ["Received","Acknowledged","Dispatched","En Route","Resolved","Closed"];
const STATUS_META: Record<IncidentStatus, { bg: string; text: string; dot: string }> = {
  Received:     { bg: "bg-red-100",    text: "text-red-700",    dot: "bg-red-500" },
  Acknowledged: { bg: "bg-amber-100",  text: "text-amber-700",  dot: "bg-amber-500" },
  Dispatched:   { bg: "bg-blue-100",   text: "text-blue-700",   dot: "bg-blue-500" },
  "En Route":   { bg: "bg-indigo-100", text: "text-indigo-700", dot: "bg-indigo-500" },
  Resolved:     { bg: "bg-emerald-100",text: "text-emerald-700",dot: "bg-emerald-500" },
  Closed:       { bg: "bg-gray-100",   text: "text-gray-500",   dot: "bg-gray-400" },
};

// ─── Audio alert using Web Audio API (no external files) ───────────────────
function playAlertSound() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const playBeep = (freq: number, start: number, duration: number) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.type = "sine";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + start);
      gain.gain.setValueAtTime(0, ctx.currentTime + start);
      gain.gain.linearRampToValueAtTime(0.5, ctx.currentTime + start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + duration);
      osc.start(ctx.currentTime + start);
      osc.stop(ctx.currentTime + start + duration);
    };
    playBeep(880, 0,    0.18);
    playBeep(660, 0.22, 0.18);
    playBeep(880, 0.44, 0.18);
    playBeep(1100,0.66, 0.28);
  } catch {}
}

// ─── Response timer component ────────────────────────────────────────────────
function ResponseTimer({ timestamp, status }: { timestamp: string; status: string }) {
  const [elapsed, setElapsed] = useState("");
  const [isOverSLA, setIsOverSLA] = useState(false);
  const isActive = !["Resolved", "Closed"].includes(status);

  useEffect(() => {
    const update = () => {
      const diff = Math.floor((Date.now() - new Date(timestamp).getTime()) / 1000);
      const h = Math.floor(diff / 3600);
      const m = Math.floor((diff % 3600) / 60);
      const s = diff % 60;
      setElapsed(
        h > 0
          ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
          : `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
      );
      setIsOverSLA(diff > 8 * 60); // 8 minutes SLA
    };
    update();
    if (!isActive) return;
    const t = setInterval(update, 1000);
    return () => clearInterval(t);
  }, [timestamp, isActive]);

  if (!isActive) return <span className="text-xs text-gray-400 font-mono">—</span>;
  return (
    <span className={`text-sm font-bold font-mono ${isOverSLA ? "text-red-600 animate-pulse" : "text-gray-800"}`}>
      {elapsed}
      {isOverSLA && <span className="ml-1 text-[10px] font-bold text-red-500">⚠ SLA</span>}
    </span>
  );
}

// ─── Priority badge component ────────────────────────────────────────────────
function PriorityBadge({ priority }: { priority: string }) {
  const p = (priority as IncidentPriority) || "P2";
  const m = PRIORITY_META[p] ?? PRIORITY_META.P2;
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-[10px] font-black tracking-wider border ${m.bg} ${m.text} ${m.border}`}>
      {m.label}
    </span>
  );
}

// ─── Status badge ────────────────────────────────────────────────────────────
function StatusBadge({ status }: { status: string }) {
  const m = STATUS_META[status as IncidentStatus] ?? STATUS_META.Received;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold ${m.bg} ${m.text}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${m.dot}`} />
      {status}
    </span>
  );
}

function val(v: string | null | undefined, fallback = "—") {
  if (!v || !v.trim() || v.toLowerCase() === "unknown") return fallback;
  return v;
}

// ─── PDF export ──────────────────────────────────────────────────────────────
async function exportPDF(incident: Incident) {
  const { jsPDF } = await import("jspdf");
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const W = 210;
  const ts = new Date(incident.timestamp);
  const p = PRIORITY_META[incident.priority] ?? PRIORITY_META.P2;

  doc.setFillColor(220, 38, 38);
  doc.rect(0, 0, W, 30, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(16); doc.setFont("helvetica", "bold");
  doc.text("ROADSOS EMERGENCY — CAD INCIDENT REPORT", 14, 12);
  doc.setFontSize(9); doc.setFont("helvetica", "normal");
  doc.text("Computer-Aided Dispatch System — CONFIDENTIAL", 14, 19);
  doc.text(`Generated: ${new Date().toLocaleString("en-IN")}`, 14, 24);
  doc.setFontSize(11); doc.setFont("helvetica", "bold");
  doc.text(`${p.label}`, W - 45, 18);

  let y = 40;
  doc.setTextColor(17, 24, 39);

  const section = (title: string) => {
    doc.setFillColor(243, 244, 246);
    doc.rect(14, y, W - 28, 8, "F");
    doc.setFont("helvetica", "bold"); doc.setFontSize(9); doc.setTextColor(100, 116, 139);
    doc.text(title.toUpperCase(), 17, y + 5.5);
    y += 12; doc.setTextColor(17, 24, 39);
  };
  const row = (label: string, value: string) => {
    doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(107, 114, 128);
    doc.text(label, 17, y);
    doc.setFont("helvetica", "bold"); doc.setTextColor(17, 24, 39);
    doc.text(value, 72, y);
    y += 7;
  };

  section("Incident Information");
  row("Incident ID", incident.id);
  row("Priority", `${incident.priority} — ${p.description}`);
  row("Status", incident.status);
  row("Date / Time", ts.toLocaleString("en-IN"));
  row("Service Requested", incident.service_name);
  y += 4;

  section("Caller Information (ANI)");
  row("Full Name", val(incident.user_name));
  row("Phone Number", val(incident.user_phone));
  row("Blood Group", val(incident.blood_group));
  y += 4;

  section("Location (ALI — Auto Location Identification)");
  row("Latitude", incident.lat.toFixed(6));
  row("Longitude", incident.lng.toFixed(6));
  row("Maps", `https://maps.google.com?q=${incident.lat},${incident.lng}`);
  y += 4;

  section("Evidence & Notes");
  const photos = incident.photos?.split(",").filter(Boolean).length ?? 0;
  row("Photos Attached", `${photos} file(s) submitted by caller`);
  y += 4;
  if (incident.notes?.trim()) {
    doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(17, 24, 39);
    const lines = doc.splitTextToSize(`Dispatcher Notes:\n${incident.notes}`, W - 35);
    doc.text(lines, 17, y);
    y += lines.length * 6 + 4;
  }

  section("Dispatch Lines");
  doc.setDrawColor(200, 210, 220);
  for (let i = 0; i < 5; i++) { doc.line(17, y, W - 17, y); y += 8; }

  doc.setFontSize(7); doc.setTextColor(156, 163, 175); doc.setFont("helvetica", "normal");
  doc.text("CONFIDENTIAL — For authorized emergency response personnel only", 14, 285);
  doc.text(`ID: ${incident.id}`, W - 75, 285);

  doc.save(`ROADSOS_CAD_${incident.id.split("-")[0].toUpperCase()}.pdf`);
}

// ─── Main Dashboard ──────────────────────────────────────────────────────────
export default function Dashboard() {
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [selected, setSelected] = useState<Incident | null>(null);
  const [loading, setLoading] = useState(true);
  const [statusUpdating, setStatusUpdating] = useState(false);
  const [activeTab, setActiveTab] = useState<"details" | "dispatch" | "report">("details");
  const [mounted, setMounted] = useState(false);
  const [timeStr, setTimeStr] = useState("");
  const [filter, setFilter] = useState<"all" | "active" | "resolved">("all");
  const [notes, setNotes] = useState("");
  const [notesSaving, setNotesSaving] = useState(false);
  const prevCount = useRef(0);
  const notesTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Send Update to User form state
  const [updateMsg, setUpdateMsg] = useState("");
  const [responderName, setResponderName] = useState("");
  const [responderPhone, setResponderPhone] = useState("");
  const [responderLat, setResponderLat] = useState("");
  const [responderLng, setResponderLng] = useState("");
  const [sendingUpdate, setSendingUpdate] = useState(false);
  const [updateSent, setUpdateSent] = useState(false);

  useEffect(() => { setMounted(true); }, []);

  // Live clock
  useEffect(() => {
    const tick = () => setTimeStr(
      new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false })
    );
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  // Fetch incidents + audio alert on new
  const fetchIncidents = useCallback(async () => {
    try {
      const res = await fetch("/api/incidents");
      if (!res.ok) return;
      const data = await res.json();
      const list: Incident[] = data.incidents ?? [];
      
      // Audio alert if new incident appeared
      if (prevCount.current > 0 && list.length > prevCount.current) {
        playAlertSound();
      }
      prevCount.current = list.length;
      
      setIncidents(list);
      if (selected) {
        const updated = list.find((i) => i.id === selected.id);
        if (updated) {
          setSelected(updated);
          // Don't override notes if user is currently editing
          if (notesTimer.current === null) setNotes(updated.notes ?? "");
        }
      } else if (list.length > 0) {
        setSelected(list[0]);
        setNotes(list[0].notes ?? "");
      }
    } finally {
      setLoading(false);
    }
  }, [selected]);

  useEffect(() => {
    fetchIncidents();
    const t = setInterval(fetchIncidents, 3000);
    return () => clearInterval(t);
  }, [fetchIncidents]);

  // When selecting an incident, load its notes
  const selectIncident = (inc: Incident) => {
    setSelected(inc);
    setNotes(inc.notes ?? "");
    setActiveTab("details");
  };

  // Status update
  const updateStatus = async (status: IncidentStatus) => {
    if (!selected) return;
    setStatusUpdating(true);
    try {
      await fetch(`/api/incidents/${selected.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      const updated = { ...selected, status };
      setSelected(updated);
      setIncidents((p) => p.map((i) => (i.id === selected.id ? updated : i)));
    } finally { setStatusUpdating(false); }
  };

  // Send live update to user (writes to incident_updates table)
  const sendUpdateToUser = async (statusToSet?: IncidentStatus) => {
    if (!selected || !updateMsg.trim()) return;
    setSendingUpdate(true);
    try {
      // Optionally advance status first
      if (statusToSet) await updateStatus(statusToSet);

      await fetch(`/api/incidents/${selected.id}/updates`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: updateMsg.trim(),
          responder_name: responderName.trim() || null,
          responder_phone: responderPhone.trim() || null,
          responder_lat: responderLat ? parseFloat(responderLat) : null,
          responder_lng: responderLng ? parseFloat(responderLng) : null,
        }),
      });
      setUpdateMsg("");
      setResponderName("");
      setResponderPhone("");
      setResponderLat("");
      setResponderLng("");
      setUpdateSent(true);
      setTimeout(() => setUpdateSent(false), 3000);
    } finally {
      setSendingUpdate(false);
    }
  };

  // Priority update
  const updatePriority = async (priority: IncidentPriority) => {
    if (!selected) return;
    await fetch(`/api/incidents/${selected.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ priority }),
    });
    const updated = { ...selected, priority };
    setSelected(updated);
    setIncidents((p) => p.map((i) => (i.id === selected.id ? updated : i)));
  };

  // Notes debounced auto-save
  const handleNotesChange = (v: string) => {
    setNotes(v);
    if (notesTimer.current) clearTimeout(notesTimer.current);
    notesTimer.current = setTimeout(async () => {
      if (!selected) return;
      setNotesSaving(true);
      await fetch(`/api/incidents/${selected.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ notes: v }),
      });
      notesTimer.current = null;
      setNotesSaving(false);
    }, 1200);
  };

  const filteredIncidents = incidents.filter((i) => {
    if (filter === "active") return !["Resolved", "Closed"].includes(i.status);
    if (filter === "resolved") return ["Resolved", "Closed"].includes(i.status);
    return true;
  });

  const stats = {
    total: incidents.length,
    active: incidents.filter((i) => !["Resolved", "Closed"].includes(i.status)).length,
    dispatched: incidents.filter((i) => ["Dispatched", "En Route"].includes(i.status)).length,
    resolved: incidents.filter((i) => ["Resolved", "Closed"].includes(i.status)).length,
  };

  return (
    <div className="flex flex-col h-screen overflow-hidden" style={{ fontFamily: "'Inter', system-ui, sans-serif", background: "#f8f9fb" }}>

      {/* ── HEADER ─────────────────────────────────────── */}
      <header className="bg-white border-b border-gray-200 px-5 flex items-stretch shadow-sm flex-shrink-0 z-20" style={{ height: 52 }}>
        <div className="flex items-center gap-4 flex-1">
          <div className="flex items-center gap-2.5 pr-4 border-r border-gray-200 h-full">
            <div className="w-7 h-7 bg-red-600 rounded-md flex items-center justify-center">
              <Radio size={14} className="text-white" />
            </div>
            <div>
              <p className="text-sm font-bold text-gray-900 leading-none">RoadSoS CAD</p>
              <p className="text-[9px] text-gray-400 font-semibold tracking-widest uppercase leading-none mt-0.5">Dispatch Center</p>
            </div>
          </div>
          <div className="flex items-center gap-2.5">
            {[
              { l: "Total", v: stats.total, c: "text-gray-900" },
              { l: "Active", v: stats.active, c: "text-red-600" },
              { l: "Dispatched", v: stats.dispatched, c: "text-blue-600" },
              { l: "Resolved", v: stats.resolved, c: "text-emerald-600" },
            ].map((s) => (
              <div key={s.l} className="flex items-baseline gap-1 px-3 py-1 bg-gray-50 border border-gray-200 rounded-lg">
                <span className={`text-base font-bold leading-none ${s.c}`}>{s.v}</span>
                <span className="text-[10px] text-gray-400 font-medium">{s.l}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5 text-xs text-gray-400" suppressHydrationWarning>
            <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
            {mounted ? timeStr : "—"}
          </div>
          <div className="flex items-center gap-1 text-xs text-gray-400 border-l border-gray-200 pl-4">
            <Volume2 size={11} className="text-gray-400" />
            <span>Audio ON</span>
          </div>
          <button onClick={fetchIncidents} className="flex items-center gap-1.5 text-xs text-gray-500 hover:text-gray-800 px-3 py-1.5 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors font-medium">
            <RefreshCw size={11} />
            Sync
          </button>
        </div>
      </header>

      {/* ── MAIN ───────────────────────────────────────── */}
      <div className="flex flex-1 overflow-hidden">

        {/* LEFT — Queue */}
        <aside className="w-72 bg-white border-r border-gray-200 flex flex-col flex-shrink-0">
          <div className="px-4 pt-3.5 pb-2">
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-2">Incident Queue</p>
            <div className="flex gap-1">
              {(["all", "active", "resolved"] as const).map((f) => (
                <button key={f} onClick={() => setFilter(f)}
                  className={`flex-1 py-1.5 text-[10px] font-bold uppercase tracking-wide rounded-md transition-colors ${filter === f ? "bg-red-600 text-white" : "bg-gray-100 text-gray-500 hover:bg-gray-200"}`}>
                  {f}
                </button>
              ))}
            </div>
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-gray-100">
            {loading && <div className="p-6 text-center text-xs text-gray-400">Loading…</div>}
            {!loading && filteredIncidents.length === 0 && (
              <div className="p-8 text-center flex flex-col items-center gap-2 text-gray-300">
                <Activity size={28} />
                <p className="text-xs">No incidents</p>
              </div>
            )}
            {filteredIncidents.map((inc) => (
              <button key={inc.id} onClick={() => selectIncident(inc)}
                className={`w-full text-left px-4 py-3.5 hover:bg-gray-50 transition-colors border-l-2 ${selected?.id === inc.id ? "bg-red-50 border-l-red-500" : "border-l-transparent"}`}>
                <div className="flex items-center justify-between mb-1.5 gap-1">
                  <PriorityBadge priority={inc.priority} />
                  <StatusBadge status={inc.status} />
                </div>
                <p className="text-sm font-semibold text-gray-800 truncate leading-snug">{inc.service_name}</p>
                <div className="flex items-center justify-between mt-1">
                  <p className="text-[10px] text-gray-400 font-mono">
                    {new Date(inc.timestamp).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", hour12: false })}
                  </p>
                  <ResponseTimer timestamp={inc.timestamp} status={inc.status} />
                </div>
              </button>
            ))}
          </div>
        </aside>

        {/* CENTER — Map */}
        <div className="flex-1 relative overflow-hidden">
          {selected ? (
            <>
              <MapComponent lat={selected.lat} lng={selected.lng} />
              {/* Map overlay */}
              <div className="absolute top-4 left-4 z-[500] bg-white/95 backdrop-blur-sm border border-gray-200 rounded-xl shadow-xl p-4 w-72">
                <div className="flex items-center gap-2 mb-2 flex-wrap">
                  <PriorityBadge priority={selected.priority} />
                  <StatusBadge status={selected.status} />
                </div>
                <p className="font-semibold text-gray-900 text-sm leading-snug mb-2">{selected.service_name}</p>
                <div className="flex items-center justify-between border-t border-gray-100 pt-2">
                  <div>
                    <p className="text-[10px] text-gray-400">Response Time</p>
                    <ResponseTimer timestamp={selected.timestamp} status={selected.status} />
                  </div>
                  <a href={`https://maps.google.com?q=${selected.lat},${selected.lng}`} target="_blank"
                    className="text-xs text-blue-500 hover:text-blue-700 flex items-center gap-0.5 font-medium">
                    Maps <ExternalLink size={10} />
                  </a>
                </div>
              </div>
            </>
          ) : (
            <div className="w-full h-full flex items-center justify-center bg-gray-50 text-gray-300 flex-col gap-3">
              <MapPin size={40} />
              <p className="text-sm font-medium">Select an incident to view on map</p>
            </div>
          )}
        </div>

        {/* RIGHT — Panel */}
        {selected && (
          <aside className="w-[380px] bg-white border-l border-gray-200 flex flex-col overflow-hidden flex-shrink-0">
            <div className="grid grid-cols-3 border-b border-gray-200 flex-shrink-0">
              {(["details", "dispatch", "report"] as const).map((tab) => (
                <button key={tab} onClick={() => setActiveTab(tab)}
                  className={`py-3.5 text-[10px] font-bold uppercase tracking-widest transition-colors ${activeTab === tab ? "bg-red-50 text-red-600 border-b-2 border-red-500" : "text-gray-400 hover:text-gray-600 hover:bg-gray-50"}`}>
                  {tab}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto">

              {/* ─ DETAILS ─────────────────────────────── */}
              {activeTab === "details" && (
                <div className="p-5 space-y-4">
                  {/* Priority selector */}
                  <Card title="Priority Level" icon={AlertCircle}>
                    <div className="flex gap-2">
                      {(["P1","P2","P3"] as IncidentPriority[]).map((p) => {
                        const m = PRIORITY_META[p];
                        return (
                          <button key={p} onClick={() => updatePriority(p)}
                            className={`flex-1 py-2.5 text-xs font-black rounded-lg border transition-all ${selected.priority === p ? `${m.bg} ${m.text} ${m.border}` : "bg-white text-gray-500 border-gray-200 hover:bg-gray-50"}`}>
                            {p}
                          </button>
                        );
                      })}
                    </div>
                    <p className="text-[10px] text-gray-400 mt-1.5">{PRIORITY_META[selected.priority]?.description ?? ""}</p>
                  </Card>

                  {/* Response Timer card */}
                  <Card title="Response Timer" icon={Clock}>
                    <div className="flex items-center justify-between">
                      <div>
                        <ResponseTimer timestamp={selected.timestamp} status={selected.status} />
                        <p className="text-[10px] text-gray-400 mt-0.5">SLA: P1=4 min, P2=8 min, P3=30 min</p>
                      </div>
                      <div className="text-right text-[10px] text-gray-400 font-mono">
                        {new Date(selected.timestamp).toLocaleString("en-IN")}
                      </div>
                    </div>
                  </Card>

                  {/* Caller info */}
                  <Card title="Caller (ANI)" icon={User}>
                    <DR label="Name"  value={val(selected.user_name)} />
                    <DR label="Phone" value={val(selected.user_phone)} mono />
                    <DR label="Blood" value={val(selected.blood_group)}
                      valueClass={selected.blood_group ? "text-red-600 font-bold" : "text-gray-400"} />
                  </Card>

                  {/* Location */}
                  <Card title="Location (ALI)" icon={MapPin}>
                    <DR label="Lat" value={selected.lat.toFixed(6)} mono />
                    <DR label="Lng" value={selected.lng.toFixed(6)} mono />
                    <a href={`https://maps.google.com?q=${selected.lat},${selected.lng}`} target="_blank"
                      className="text-xs text-blue-500 hover:underline flex items-center gap-1 font-medium pt-1">
                      Open in Google Maps <ExternalLink size={10} />
                    </a>
                  </Card>

                  {/* Status */}
                  <Card title="Status" icon={Activity}
                    right={<StatusBadge status={selected.status} />}>
                    <div className="flex flex-wrap gap-1.5">
                      {STATUS_FLOW.map((s) => (
                        <button key={s} onClick={() => updateStatus(s)}
                          disabled={statusUpdating || selected.status === s}
                          className={`px-3 py-1.5 text-xs rounded-lg border font-medium transition-all disabled:cursor-not-allowed ${selected.status === s ? "bg-gray-900 text-white border-gray-900" : "bg-white text-gray-600 border-gray-300 hover:bg-gray-50 disabled:opacity-40"}`}>
                          {s}
                        </button>
                      ))}
                    </div>
                  </Card>

                  {/* Dispatcher Notes */}
                  <Card title="Dispatcher Notes" icon={NotebookPen}
                    right={<span className={`text-[10px] font-medium ${notesSaving ? "text-amber-500" : "text-gray-400"}`}>{notesSaving ? "Saving…" : "Auto-saved"}</span>}>
                    <textarea
                      value={notes}
                      onChange={(e) => handleNotesChange(e.target.value)}
                      placeholder="Add notes: unit assigned, ETA, field updates…"
                      rows={4}
                      className="w-full text-xs text-gray-700 bg-gray-50 border border-gray-200 rounded-lg p-3 resize-none focus:outline-none focus:ring-2 focus:ring-red-300 focus:border-red-400 placeholder-gray-400 font-mono leading-relaxed"
                    />
                  </Card>
                </div>
              )}

              {/* ─ DISPATCH ────────────────────────────── */}
              {activeTab === "dispatch" && (
                <div className="p-5 space-y-4">

                  {/* ★ SEND UPDATE TO USER — Zomato-style live update ★ */}
                  <Card title="Send Live Update to User" icon={Send}
                    right={updateSent ? <span className="text-[10px] font-bold text-emerald-600">✓ Sent!</span> : undefined}>
                    <p className="text-[10px] text-gray-400 leading-relaxed -mt-1">
                      This update is instantly visible to the user on their tracking screen.
                    </p>

                    {/* Quick message presets */}
                    <div className="flex flex-wrap gap-1.5">
                      {[
                        "Help is on the way!",
                        "Ambulance dispatched — ETA 8 min",
                        "Police en route to your location",
                        "Unit is 2 minutes away",
                        "Arrived at location",
                      ].map((preset) => (
                        <button key={preset} onClick={() => setUpdateMsg(preset)}
                          className="px-2.5 py-1 text-[10px] bg-gray-100 hover:bg-blue-50 hover:text-blue-700 border border-gray-200 hover:border-blue-300 rounded-full transition-colors font-medium">
                          {preset}
                        </button>
                      ))}
                    </div>

                    <textarea
                      value={updateMsg}
                      onChange={(e) => setUpdateMsg(e.target.value)}
                      placeholder="Type a message to the victim…"
                      rows={3}
                      className="w-full text-xs text-gray-700 bg-gray-50 border border-gray-200 rounded-lg p-3 resize-none focus:outline-none focus:ring-2 focus:ring-blue-300 focus:border-blue-400 placeholder-gray-400 leading-relaxed"
                    />

                    {/* Responder details */}
                    <div className="grid grid-cols-2 gap-2">
                      <div>
                        <label className="text-[10px] text-gray-400 font-semibold block mb-1">Responder Name</label>
                        <input value={responderName} onChange={(e) => setResponderName(e.target.value)}
                          placeholder="e.g. Dr. Rajan / Unit 4"
                          className="w-full text-xs border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-300" />
                      </div>
                      <div>
                        <label className="text-[10px] text-gray-400 font-semibold block mb-1">Responder Phone</label>
                        <input value={responderPhone} onChange={(e) => setResponderPhone(e.target.value)}
                          placeholder="+91 98765…"
                          className="w-full text-xs border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-300" />
                      </div>
                      <div>
                        <label className="text-[10px] text-gray-400 font-semibold block mb-1">Responder Lat</label>
                        <input value={responderLat} onChange={(e) => setResponderLat(e.target.value)}
                          placeholder="37.4219"
                          className="w-full text-xs border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 font-mono focus:outline-none focus:ring-2 focus:ring-blue-300" />
                      </div>
                      <div>
                        <label className="text-[10px] text-gray-400 font-semibold block mb-1">Responder Lng</label>
                        <input value={responderLng} onChange={(e) => setResponderLng(e.target.value)}
                          placeholder="-122.083"
                          className="w-full text-xs border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 font-mono focus:outline-none focus:ring-2 focus:ring-blue-300" />
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-2 pt-1">
                      <button onClick={() => sendUpdateToUser("Dispatched")}
                        disabled={!updateMsg.trim() || sendingUpdate}
                        className="py-3 text-xs font-bold bg-blue-600 hover:bg-blue-700 text-white rounded-lg disabled:opacity-40 transition-colors">
                        Send + Mark Dispatched
                      </button>
                      <button onClick={() => sendUpdateToUser("En Route")}
                        disabled={!updateMsg.trim() || sendingUpdate}
                        className="py-3 text-xs font-bold bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg disabled:opacity-40 transition-colors">
                        Send + Mark En Route
                      </button>
                    </div>
                    <button onClick={() => sendUpdateToUser()}
                      disabled={!updateMsg.trim() || sendingUpdate}
                      className="w-full py-2.5 text-xs font-bold bg-gray-800 hover:bg-gray-900 text-white rounded-lg disabled:opacity-40 transition-colors">
                      {sendingUpdate ? "Sending…" : "Send Message Only"}
                    </button>
                  </Card>

                  <Card title="Contact Caller" icon={Phone}>
                    {val(selected.user_phone) !== "—" ? (
                      <a href={`tel:${selected.user_phone}`}
                        className="flex items-center justify-center gap-2 py-3 w-full bg-emerald-600 hover:bg-emerald-700 text-white font-bold rounded-lg transition-colors text-sm">
                        <Phone size={15} />
                        Call {selected.user_phone}
                      </a>
                    ) : (
                      <p className="text-xs text-gray-400 text-center py-2">No phone on record</p>
                    )}
                  </Card>

                  <Card title="Notify Emergency Services" icon={Send}>
                    <div className="space-y-2">
                      {[
                        { emoji: "🚑", name: "Ambulance (EMRI)", num: "108" },
                        { emoji: "🚓", name: "Police Control Room", num: "100" },
                        { emoji: "🏥", name: "Trauma Center / Hospital", num: "112" },
                        { emoji: "🚒", name: "Fire Brigade", num: "101" },
                        { emoji: "🛡️", name: "National Emergency", num: "112" },
                      ].map((s) => (
                        <div key={s.name} className="flex items-center justify-between px-3 py-2.5 bg-gray-50 rounded-lg border border-gray-100">
                          <div className="flex items-center gap-2.5">
                            <span className="text-base">{s.emoji}</span>
                            <div>
                              <p className="text-xs font-semibold text-gray-700">{s.name}</p>
                              <p className="text-[10px] text-gray-400 font-mono">{s.num}</p>
                            </div>
                          </div>
                          <a href={`tel:${s.num}`}
                            className="flex items-center gap-1 px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-xs font-bold rounded-lg transition-colors">
                            <Phone size={10} /> Call
                          </a>
                        </div>
                      ))}
                    </div>
                  </Card>

                  <Card title="Quick Status" icon={Truck}>
                    <div className="grid grid-cols-2 gap-2">
                      {(["Acknowledged","Dispatched","En Route","Resolved"] as IncidentStatus[]).map((s) => (
                        <button key={s} onClick={() => updateStatus(s)}
                          disabled={statusUpdating || selected.status === s}
                          className={`py-3 text-xs rounded-lg border font-bold transition-all disabled:cursor-not-allowed ${selected.status === s ? "bg-gray-900 text-white border-gray-900" : "bg-white text-gray-700 border-gray-200 hover:bg-gray-50 disabled:opacity-40"}`}>
                          {s}
                        </button>
                      ))}
                    </div>
                  </Card>
                </div>
              )}

              {/* ─ REPORT ──────────────────────────────── */}
              {activeTab === "report" && (
                <div className="p-5 space-y-4">
                  <Card title="Incident Report Preview" icon={FileText}>
                    <div className="bg-gray-50 rounded-lg p-3 space-y-1.5 text-[10px] border border-gray-200">
                      {[
                        ["Incident ID", selected.id.split("-")[0].toUpperCase()],
                        ["Priority", `${selected.priority} — ${PRIORITY_META[selected.priority]?.label ?? ""}`],
                        ["Status", selected.status],
                        ["Date/Time", new Date(selected.timestamp).toLocaleString("en-IN")],
                        ["Service", selected.service_name],
                        ["Caller", val(selected.user_name)],
                        ["Phone", val(selected.user_phone)],
                        ["Blood", val(selected.blood_group)],
                        ["GPS", `${selected.lat.toFixed(4)}, ${selected.lng.toFixed(4)}`],
                        ["Photos", `${selected.photos?.split(",").filter(Boolean).length ?? 0}`],
                        ["Notes", notes.trim() || "—"],
                      ].map(([l, v]) => (
                        <div key={l} className="flex gap-3">
                          <span className="text-gray-400 w-16 flex-shrink-0">{l}</span>
                          <span className="text-gray-700 font-medium break-all">{v}</span>
                        </div>
                      ))}
                    </div>
                  </Card>

                  <button onClick={() => exportPDF(selected)}
                    className="w-full py-4 bg-red-600 hover:bg-red-700 text-white font-bold rounded-xl flex items-center justify-center gap-2 transition-colors text-sm shadow-sm">
                    <FileText size={16} />
                    Download Official CAD Report (PDF)
                  </button>

                  <p className="text-[10px] text-gray-400 text-center leading-relaxed">
                    CONFIDENTIAL — Authorized emergency personnel only.<br />
                    All activity is logged.
                  </p>
                </div>
              )}

            </div>
          </aside>
        )}
      </div>
    </div>
  );
}

// ─── Sub-components ─────────────────────────────────────────────────────────

function Card({ title, icon: Icon, children, right }: { title: string; icon: any; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="border border-gray-200 rounded-xl overflow-hidden">
      <div className="bg-gray-50 px-4 py-2.5 border-b border-gray-200 flex items-center gap-2">
        <Icon size={12} className="text-gray-400" />
        <span className="text-[10px] font-bold text-gray-500 uppercase tracking-widest flex-1">{title}</span>
        {right}
      </div>
      <div className="p-4 space-y-2">{children}</div>
    </div>
  );
}

function DR({ label, value, mono, valueClass }: { label: string; value: string; mono?: boolean; valueClass?: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-xs text-gray-400 flex-shrink-0">{label}</span>
      <span className={`text-xs text-right break-all leading-snug ${mono ? "font-mono" : "font-semibold"} ${valueClass ?? "text-gray-800"}`}>
        {value}
      </span>
    </div>
  );
}
