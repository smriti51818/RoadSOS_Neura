"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import dynamic from "next/dynamic";
import {
  AlertTriangle, Phone, CheckCircle, Clock, Activity, MapPin,
  User, FileText, Radio, Truck, Send, RefreshCw, ExternalLink,
  AlertCircle, Volume2, NotebookPen, Shield, Zap,
} from "lucide-react";
import type { Incident, IncidentStatus, IncidentPriority } from "../types";

const MapComponent = dynamic(() => import("../components/Map"), {
  ssr: false,
  loading: () => (
    <div className="w-full h-full flex items-center justify-center bg-[#F1F5F9] text-[#94A3B8] text-xs tracking-wide">
      Initializing Map…
    </div>
  ),
});

// ─── Priority config ─────────────────────────────────────────────────────────
const PRIORITY_META: Record<IncidentPriority, { label: string; bg: string; text: string; dot: string; ring: string; description: string }> = {
  P1: { label: "P1 CRITICAL", bg: "bg-red-50", text: "text-red-700", dot: "bg-red-600", ring: "border border-red-400", description: "Life-threatening — Immediate response" },
  P2: { label: "P2 URGENT",   bg: "bg-amber-50", text: "text-amber-700", dot: "bg-amber-600", ring: "border border-amber-400", description: "Urgent — Respond within 8 minutes" },
  P3: { label: "P3 ROUTINE",  bg: "bg-blue-50", text: "text-blue-700", dot: "bg-blue-600", ring: "border border-blue-400", description: "Non-emergency — Respond within 30 minutes" },
};

const STATUS_FLOW: IncidentStatus[] = ["Received","Acknowledged","Dispatched","En Route","Resolved","Closed"];
const STATUS_META: Record<IncidentStatus, { bg: string; text: string; dot: string }> = {
  Received:     { bg: "bg-red-50",  text: "text-red-700",  dot: "bg-red-600" },
  Acknowledged: { bg: "bg-amber-50",  text: "text-amber-700",  dot: "bg-amber-600" },
  Dispatched:   { bg: "bg-blue-50",  text: "text-blue-700",  dot: "bg-blue-600" },
  "En Route":   { bg: "bg-indigo-50",  text: "text-indigo-700",  dot: "bg-indigo-600" },
  Resolved:     { bg: "bg-emerald-50",  text: "text-emerald-700",  dot: "bg-emerald-600" },
  Closed:       { bg: "bg-zinc-50",  text: "text-zinc-600",  dot: "bg-zinc-500" },
};

// ─── Audio alert ──────────────────────────────────────────────────────────────
function playAlertSound() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const beep = (freq: number, start: number, dur: number) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain); gain.connect(ctx.destination);
      osc.type = "sine"; osc.frequency.setValueAtTime(freq, ctx.currentTime + start);
      gain.gain.setValueAtTime(0, ctx.currentTime + start);
      gain.gain.linearRampToValueAtTime(0.45, ctx.currentTime + start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + dur);
      osc.start(ctx.currentTime + start); osc.stop(ctx.currentTime + start + dur);
    };
    beep(880, 0, 0.18); beep(660, 0.22, 0.18); beep(880, 0.44, 0.18); beep(1100, 0.66, 0.28);
  } catch {}
}

// ─── Pulsing dot ──────────────────────────────────────────────────────────────
function PulsingDot({ color = "bg-[#10B981]", size = "w-2 h-2" }: { color?: string; size?: string }) {
  return (
    <span className="relative flex shrink-0" style={{ width: 8, height: 8 }}>
      <span className={`animate-ping absolute inline-flex h-full w-full rounded-full opacity-60 ${color}`} />
      <span className={`relative inline-flex rounded-full ${size} ${color}`} />
    </span>
  );
}

// ─── Response timer ───────────────────────────────────────────────────────────
function ResponseTimer({ timestamp, status }: { timestamp: string; status: string }) {
  const [elapsed, setElapsed] = useState("");
  const [isOverSLA, setIsOverSLA] = useState(false);
  const isActive = !["Resolved", "Closed"].includes(status);

  useEffect(() => {
    const update = () => {
      const diff = Math.floor((Date.now() - new Date(timestamp).getTime()) / 1000);
      const h = Math.floor(diff / 3600), m = Math.floor((diff % 3600) / 60), s = diff % 60;
      setElapsed(h > 0 ? `${h}:${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}` : `${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}`);
      setIsOverSLA(diff > 8 * 60);
    };
    update();
    if (!isActive) return;
    const t = setInterval(update, 1000);
    return () => clearInterval(t);
  }, [timestamp, isActive]);

  if (!isActive) return <span className="text-xs text-[#94A3B8] font-mono">—</span>;
  return (
    <span className={`text-xs font-bold font-mono ${isOverSLA ? "text-[#E11D48] animate-pulse" : "text-[#0F172A]"}`}>
      {elapsed}{isOverSLA && <span className="ml-1 text-[9px] text-[#E11D48] font-bold">⚠ SLA</span>}
    </span>
  );
}

// ─── Priority badge ───────────────────────────────────────────────────────────
function PriorityBadge({ priority }: { priority: string }) {
  const p = (priority as IncidentPriority) || "P2";
  const m = PRIORITY_META[p] ?? PRIORITY_META.P2;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-lg border text-[9px] font-black tracking-wider ${m.bg} ${m.text} ${m.ring}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${m.dot}`} />
      {m.label}
    </span>
  );
}

// ─── Status badge ─────────────────────────────────────────────────────────────
function StatusBadge({ status }: { status: string }) {
  const m = STATUS_META[status as IncidentStatus] ?? STATUS_META.Received;
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[9px] font-bold ${m.bg} ${m.text}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${m.dot}`} />
      {status}
    </span>
  );
}

function val(v: string | null | undefined, fallback = "—") {
  if (!v || !v.trim() || v.toLowerCase() === "unknown") return fallback;
  return v;
}

// ─── PDF export ───────────────────────────────────────────────────────────────
async function exportPDF(incident: Incident) {
  const { jsPDF } = await import("jspdf");
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const W = 210; const ts = new Date(incident.timestamp);
  const p = PRIORITY_META[incident.priority] ?? PRIORITY_META.P2;

  doc.setFillColor(225, 29, 72); doc.rect(0, 0, W, 30, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(16); doc.setFont("helvetica", "bold");
  doc.text("ROADSOS EMERGENCY — CAD INCIDENT REPORT", 14, 12);
  doc.setFontSize(9); doc.setFont("helvetica", "normal");
  doc.text("Computer-Aided Dispatch System — CONFIDENTIAL", 14, 19);
  doc.text(`Generated: ${new Date().toLocaleString("en-IN")}`, 14, 24);
  doc.setFontSize(11); doc.setFont("helvetica", "bold"); doc.text(p.label, W - 45, 18);

  let y = 40; doc.setTextColor(15, 23, 42);

  const section = (title: string) => {
    doc.setFillColor(248, 250, 252); doc.rect(14, y, W - 28, 8, "F");
    doc.setFont("helvetica", "bold"); doc.setFontSize(9); doc.setTextColor(100, 116, 139);
    doc.text(title.toUpperCase(), 17, y + 5.5);
    y += 12; doc.setTextColor(15, 23, 42);
  };
  const row = (label: string, value: string) => {
    doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(107, 114, 128);
    doc.text(label, 17, y);
    doc.setFont("helvetica", "bold"); doc.setTextColor(15, 23, 42);
    doc.text(value, 72, y); y += 7;
  };

  section("Incident Information");
  row("Incident ID", incident.id); row("Priority", `${incident.priority} — ${p.description}`);
  row("Status", incident.status); row("Date / Time", ts.toLocaleString("en-IN"));
  row("Service Requested", incident.service_name); y += 4;

  section("Caller Information (ANI)");
  row("Full Name", val(incident.user_name)); row("Phone Number", val(incident.user_phone));
  row("Blood Group", val(incident.blood_group)); y += 4;

  section("Location (ALI)");
  row("Latitude", incident.lat.toFixed(6)); row("Longitude", incident.lng.toFixed(6));
  row("Maps", `https://maps.google.com?q=${incident.lat},${incident.lng}`); y += 4;

  section("Evidence & Notes");
  const photos = incident.photos?.split(",").filter(Boolean).length ?? 0;
  row("Photos Attached", `${photos} file(s)`); y += 4;
  if (incident.notes?.trim()) {
    doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(15, 23, 42);
    const lines = doc.splitTextToSize(`Dispatcher Notes:\n${incident.notes}`, W - 35);
    doc.text(lines, 17, y); y += lines.length * 6 + 4;
  }

  section("Dispatch Lines");
  doc.setDrawColor(226, 232, 240);
  for (let i = 0; i < 5; i++) { doc.line(17, y, W - 17, y); y += 8; }

  doc.setFontSize(7); doc.setTextColor(148, 163, 184); doc.setFont("helvetica", "normal");
  doc.text("CONFIDENTIAL — Authorized emergency response personnel only", 14, 285);
  doc.text(`ID: ${incident.id}`, W - 75, 285);
  doc.save(`ROADSOS_CAD_${incident.id.split("-")[0].toUpperCase()}.pdf`);
}

// ─── Main Dashboard ───────────────────────────────────────────────────────────
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
  const selectedRef = useRef<Incident | null>(null);
  const [updateMsg, setUpdateMsg] = useState("");
  const [responderName, setResponderName] = useState("");
  const [responderPhone, setResponderPhone] = useState("");
  const [responderLat, setResponderLat] = useState("");
  const [responderLng, setResponderLng] = useState("");
  const [sendingUpdate, setSendingUpdate] = useState(false);
  const [updateSent, setUpdateSent] = useState(false);

  useEffect(() => { setMounted(true); }, []);

  useEffect(() => {
    const tick = () => setTimeStr(new Date().toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }));
    tick(); const id = setInterval(tick, 1000); return () => clearInterval(id);
  }, []);

  const fetchIncidents = useCallback(async () => {
    try {
      const res = await fetch("/api/incidents");
      if (!res.ok) return;
      const data = await res.json();
      const list: Incident[] = data.incidents ?? [];
      if (prevCount.current > 0 && list.length > prevCount.current) playAlertSound();
      prevCount.current = list.length;
      setIncidents(list);
      // Use ref so this callback is never recreated when selection changes
      const cur = selectedRef.current;
      if (cur) {
        const updated = list.find((i) => i.id === cur.id);
        if (updated) {
          selectedRef.current = updated;
          setSelected(updated);
          if (notesTimer.current === null) setNotes(updated.notes ?? "");
        }
      } else if (list.length > 0) {
        selectedRef.current = list[0];
        setSelected(list[0]);
        setNotes(list[0].notes ?? "");
      }
    } finally { setLoading(false); }
  }, []); // stable — never recreated

  useEffect(() => { fetchIncidents(); const t = setInterval(fetchIncidents, 3000); return () => clearInterval(t); }, [fetchIncidents]);

  const selectIncident = (inc: Incident) => {
    selectedRef.current = inc;
    setSelected(inc);
    setNotes(inc.notes ?? "");
    setActiveTab("details");
  };

  const updateStatus = async (status: IncidentStatus) => {
    if (!selected) return; setStatusUpdating(true);
    try {
      await fetch(`/api/incidents/${selected.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ status }) });
      const updated = { ...selected, status };
      selectedRef.current = updated;
      setSelected(updated); setIncidents((p) => p.map((i) => (i.id === selected.id ? updated : i)));
    } finally { setStatusUpdating(false); }
  };

  const sendUpdateToUser = async (statusToSet?: IncidentStatus) => {
    if (!selected || !updateMsg.trim()) return; setSendingUpdate(true);
    try {
      if (statusToSet) await updateStatus(statusToSet);
      await fetch(`/api/incidents/${selected.id}/updates`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: updateMsg.trim(), responder_name: responderName.trim() || null, responder_phone: responderPhone.trim() || null, responder_lat: responderLat ? parseFloat(responderLat) : null, responder_lng: responderLng ? parseFloat(responderLng) : null }),
      });
      setUpdateMsg(""); setResponderName(""); setResponderPhone(""); setResponderLat(""); setResponderLng("");
      setUpdateSent(true); setTimeout(() => setUpdateSent(false), 3000);
    } finally { setSendingUpdate(false); }
  };

  const updatePriority = async (priority: IncidentPriority) => {
    if (!selected) return;
    await fetch(`/api/incidents/${selected.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ priority }) });
    const updated = { ...selected, priority };
    selectedRef.current = updated;
    setSelected(updated); setIncidents((p) => p.map((i) => (i.id === selected.id ? updated : i)));
  };

  const handleNotesChange = (v: string) => {
    setNotes(v);
    if (notesTimer.current) clearTimeout(notesTimer.current);
    notesTimer.current = setTimeout(async () => {
      if (!selected) return; setNotesSaving(true);
      await fetch(`/api/incidents/${selected.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ notes: v }) });
      notesTimer.current = null; setNotesSaving(false);
    }, 1200);
  };

  const filteredIncidents = incidents.filter((i) => {
    if (filter === "active") return !["Resolved","Closed"].includes(i.status);
    if (filter === "resolved") return ["Resolved","Closed"].includes(i.status);
    return true;
  });

  const stats = {
    total: incidents.length,
    active: incidents.filter((i) => !["Resolved","Closed"].includes(i.status)).length,
    dispatched: incidents.filter((i) => ["Dispatched","En Route"].includes(i.status)).length,
    resolved: incidents.filter((i) => ["Resolved","Closed"].includes(i.status)).length,
  };

  // Priority left-border color
  const priorityBorder: Record<IncidentPriority, string> = { P1: "#E11D48", P2: "#F59E0B", P3: "#2563EB" };

  return (
    <div className="flex flex-col h-screen overflow-hidden" style={{ fontFamily: "var(--font-body)", background: "#F8FAFC" }}>

      {/* ── HEADER ─────────────────────────────────────────────────────────── */}
      <header className="bg-white border-b border-[#F1F5F9] px-5 flex items-stretch flex-shrink-0 z-20" style={{ height: 56 }}>
        {/* Brand */}
        <div className="flex items-center gap-3 pr-5 border-r border-[#F1F5F9]">
          <div className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: "rgba(225,29,72,0.08)" }}>
            <Radio size={15} style={{ color: "#E11D48" }} />
          </div>
          <div>
            <p className="text-sm font-extrabold text-[#0F172A] leading-none tracking-tight">RoadSoS CAD</p>
            <p className="section-label mt-0.5">Dispatch Center</p>
          </div>
        </div>

        {/* Stats */}
        <div className="flex items-center gap-2 px-5 flex-1">
          {[
            { l: "Total",      v: stats.total,      color: "#0F172A" },
            { l: "Active",     v: stats.active,      color: "#E11D48" },
            { l: "Dispatched", v: stats.dispatched,  color: "#2563EB" },
            { l: "Resolved",   v: stats.resolved,    color: "#10B981" },
          ].map((s) => (
            <div key={s.l} className="flex items-baseline gap-1.5 px-3 py-1.5 rounded-xl border border-[#F1F5F9] bg-[#F8FAFC]">
              <span className="text-base font-black leading-none" style={{ color: s.color }}>{s.v}</span>
              <span className="section-label">{s.l}</span>
            </div>
          ))}
        </div>

        {/* Controls */}
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2" suppressHydrationWarning>
            <PulsingDot />
            <span className="text-xs font-bold text-[#0F172A] font-mono">{mounted ? timeStr : "—"}</span>
          </div>
          <div className="flex items-center gap-1.5 text-xs text-[#64748B] border-l border-[#F1F5F9] pl-4">
            <Volume2 size={12} />
            <span className="font-semibold">Audio ON</span>
          </div>
          <button onClick={fetchIncidents}
            className="flex items-center gap-1.5 text-xs font-bold text-[#64748B] hover:text-[#0F172A] px-3 py-2 rounded-xl border border-[#F1F5F9] hover:bg-[#F8FAFC] transition-colors">
            <RefreshCw size={11} />Sync
          </button>
        </div>
      </header>

      {/* ── MAIN ───────────────────────────────────────────────────────────── */}
      <div className="flex flex-1 overflow-hidden">

        {/* ── LEFT QUEUE ──────────────────────────────────────────────────── */}
        <aside className="w-72 bg-white border-r border-[#F1F5F9] flex flex-col flex-shrink-0">
          <div className="px-4 pt-4 pb-3">
            <p className="section-label mb-3">Incident Queue</p>
            <div className="flex gap-1 p-1 bg-[#F8FAFC] rounded-xl border border-[#F1F5F9]">
              {(["all","active","resolved"] as const).map((f) => (
                <button key={f} onClick={() => setFilter(f)}
                  className={`flex-1 py-1.5 text-[9px] font-black uppercase tracking-wider rounded-lg transition-all ${filter === f ? "bg-white text-[#0F172A] shadow-sm border border-[#F1F5F9]" : "text-[#94A3B8] hover:text-[#64748B]"}`}>
                  {f}
                </button>
              ))}
            </div>
          </div>

          <div className="flex-1 overflow-y-auto">
            {loading && <div className="p-6 text-center text-xs text-[#94A3B8]">Loading…</div>}
            {!loading && filteredIncidents.length === 0 && (
              <div className="p-8 text-center flex flex-col items-center gap-2 text-[#CBD5E1]">
                <Activity size={28} /><p className="text-xs font-medium">No incidents</p>
              </div>
            )}
            {filteredIncidents.map((inc) => {
              const isSelected = selected?.id === inc.id;
              const borderColor = priorityBorder[(inc.priority as IncidentPriority)] ?? "#94A3B8";
              return (
                <button key={inc.id} onClick={() => selectIncident(inc)}
                  className={`w-full text-left px-4 py-3.5 transition-colors border-b border-[#F1F5F9] ${isSelected ? "bg-[#FEF2F2]" : "hover:bg-[#F8FAFC]"}`}
                  style={{ borderLeft: `3px solid ${isSelected ? borderColor : "transparent"}` }}>
                  <div className="flex items-center gap-1.5 mb-2 flex-wrap">
                    <PriorityBadge priority={inc.priority} />
                    <StatusBadge status={inc.status} />
                  </div>
                  <p className="text-sm font-bold text-[#0F172A] truncate leading-snug mb-1.5">{inc.service_name}</p>
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] text-[#94A3B8] font-mono">
                      {new Date(inc.timestamp).toLocaleTimeString("en-IN",{ hour:"2-digit", minute:"2-digit", hour12:false })}
                    </span>
                    <ResponseTimer timestamp={inc.timestamp} status={inc.status} />
                  </div>
                </button>
              );
            })}
          </div>
        </aside>

        {/* ── MAP CENTER ──────────────────────────────────────────────────── */}
        <div className="flex-1 relative overflow-hidden">
          {selected ? (
            <>
              <MapComponent lat={selected.lat} lng={selected.lng} />
              <div className="absolute top-4 left-4 z-[500] bg-white/95 backdrop-blur rounded-2xl border border-[#F1F5F9] shadow-lg p-4 w-64">
                <div className="flex items-center gap-1.5 mb-2.5 flex-wrap">
                  <PriorityBadge priority={selected.priority} />
                  <StatusBadge status={selected.status} />
                </div>
                <p className="font-bold text-[#0F172A] text-sm leading-snug mb-3">{selected.service_name}</p>
                <div className="flex items-center justify-between border-t border-[#F1F5F9] pt-2.5">
                  <div>
                    <p className="section-label mb-0.5">Response Time</p>
                    <ResponseTimer timestamp={selected.timestamp} status={selected.status} />
                  </div>
                  <a href={`https://maps.google.com?q=${selected.lat},${selected.lng}`} target="_blank"
                    className="text-xs text-[#2563EB] hover:text-[#1D4ED8] flex items-center gap-0.5 font-semibold">
                    Maps <ExternalLink size={10} />
                  </a>
                </div>
              </div>
            </>
          ) : (
            <div className="w-full h-full flex items-center justify-center bg-[#F8FAFC] flex-col gap-3 text-[#CBD5E1]">
              <MapPin size={36} /><p className="text-sm font-medium text-[#94A3B8]">Select an incident to view on map</p>
            </div>
          )}
        </div>

        {/* ── RIGHT PANEL ─────────────────────────────────────────────────── */}
        {selected && (
          <aside className="w-[380px] bg-white border-l border-[#F1F5F9] flex flex-col overflow-hidden flex-shrink-0">

            {/* Tabs */}
            <div className="flex border-b border-[#F1F5F9] flex-shrink-0 bg-white">
              {(["details","dispatch","report"] as const).map((tab) => (
                <button key={tab} onClick={() => setActiveTab(tab)}
                  className={`flex-1 py-3.5 text-[9px] font-black uppercase tracking-widest transition-all ${activeTab === tab ? "text-[#E11D48] border-b-2 border-[#E11D48]" : "text-[#94A3B8] hover:text-[#64748B]"}`}>
                  {tab}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-3">

              {/* ─ DETAILS TAB ───────────────────────────────────────────── */}
              {activeTab === "details" && (
                <>
                  {/* Priority */}
                  <Panel title="Priority Level" icon={AlertCircle}>
                    <div className="flex gap-2 mb-2">
                      {(["P1","P2","P3"] as IncidentPriority[]).map((p) => {
                        const m = PRIORITY_META[p];
                        return (
                          <button key={p} onClick={() => updatePriority(p)}
                            className={`flex-1 py-2.5 text-xs font-black rounded-xl border transition-all ${selected.priority === p ? `${m.bg} ${m.text} ${m.ring}` : "bg-white text-[#94A3B8] border-[#F1F5F9] hover:border-[#E2E8F0]"}`}>
                            {p}
                          </button>
                        );
                      })}
                    </div>
                    <p className="text-[10px] text-[#94A3B8]">{PRIORITY_META[selected.priority]?.description}</p>
                  </Panel>

                  {/* Timer */}
                  <Panel title="Response Timer" icon={Clock}>
                    <div className="flex items-center justify-between">
                      <div>
                        <ResponseTimer timestamp={selected.timestamp} status={selected.status} />
                        <p className="text-[10px] text-[#94A3B8] mt-0.5">SLA: P1=4 min · P2=8 min · P3=30 min</p>
                      </div>
                      <span className="text-[10px] text-[#94A3B8] font-mono">{new Date(selected.timestamp).toLocaleString("en-IN")}</span>
                    </div>
                  </Panel>

                  {/* Caller */}
                  <Panel title="Caller (ANI)" icon={User}>
                    <DR label="Name"  value={val(selected.user_name)} />
                    <DR label="Phone" value={val(selected.user_phone)} mono />
                    <DR label="Blood" value={val(selected.blood_group)} valueClass={selected.blood_group ? "text-[#E11D48] font-bold" : "text-[#94A3B8]"} />
                  </Panel>

                  {/* Location */}
                  <Panel title="Location (ALI)" icon={MapPin}>
                    <DR label="Lat" value={selected.lat.toFixed(6)} mono />
                    <DR label="Lng" value={selected.lng.toFixed(6)} mono />
                    <a href={`https://maps.google.com?q=${selected.lat},${selected.lng}`} target="_blank"
                      className="text-xs text-[#2563EB] hover:underline flex items-center gap-1 font-semibold pt-1">
                      Open in Google Maps <ExternalLink size={10} />
                    </a>
                  </Panel>

                  {/* Status */}
                  <Panel title="Status" icon={Activity} right={<StatusBadge status={selected.status} />}>
                    <div className="flex flex-wrap gap-1.5">
                      {STATUS_FLOW.map((s) => (
                        <button key={s} onClick={() => updateStatus(s)}
                          disabled={statusUpdating || selected.status === s}
                          className={`px-3 py-1.5 text-xs rounded-xl border font-semibold transition-all disabled:cursor-not-allowed ${selected.status === s ? "bg-[#0F172A] text-white border-[#0F172A]" : "bg-white text-[#64748B] border-[#F1F5F9] hover:border-[#E2E8F0] hover:text-[#0F172A] disabled:opacity-40"}`}>
                          {s}
                        </button>
                      ))}
                    </div>
                  </Panel>

                  {/* Notes */}
                  <Panel title="Dispatcher Notes" icon={NotebookPen}
                    right={<span className={`text-[9px] font-bold ${notesSaving ? "text-[#F59E0B]" : "text-[#94A3B8]"}`}>{notesSaving ? "Saving…" : "Auto-saved"}</span>}>
                    <textarea value={notes} onChange={(e) => handleNotesChange(e.target.value)}
                      placeholder="Unit assigned, ETA, field updates…" rows={4}
                      className="w-full text-xs text-[#334155] bg-[#F8FAFC] border border-[#F1F5F9] rounded-xl p-3 resize-none focus:outline-none focus:ring-2 focus:ring-[#E11D48]/20 focus:border-[#E11D48]/40 placeholder-[#CBD5E1] font-mono leading-relaxed" />
                  </Panel>
                </>
              )}

              {/* ─ DISPATCH TAB ──────────────────────────────────────────── */}
              {activeTab === "dispatch" && (
                <>
                  {/* Send update */}
                  <Panel title="Send Live Update to User" icon={Send}
                    right={updateSent ? <span className="text-[9px] font-black text-[#10B981] flex items-center gap-1"><CheckCircle size={10} />Sent</span> : undefined}>
                    <p className="text-[10px] text-[#94A3B8] leading-relaxed -mt-1 mb-2">Update appears instantly on the user's tracking screen.</p>
                    <div className="flex flex-wrap gap-1.5 mb-3">
                      {["Help is on the way!","Ambulance dispatched — ETA 8 min","Police en route","Unit is 2 minutes away","Arrived at location"].map((preset) => (
                        <button key={preset} onClick={() => setUpdateMsg(preset)}
                          className="px-2.5 py-1 text-[10px] bg-[#F8FAFC] hover:bg-[#EFF6FF] hover:text-[#2563EB] border border-[#F1F5F9] hover:border-[#BFDBFE] rounded-full transition-colors font-semibold text-[#64748B]">
                          {preset}
                        </button>
                      ))}
                    </div>
                    <textarea value={updateMsg} onChange={(e) => setUpdateMsg(e.target.value)}
                      placeholder="Type a message to the victim…" rows={3}
                      className="w-full text-xs text-[#334155] bg-[#F8FAFC] border border-[#F1F5F9] rounded-xl p-3 resize-none focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20 focus:border-[#2563EB]/40 placeholder-[#CBD5E1] leading-relaxed mb-3" />
                    <div className="grid grid-cols-2 gap-2 mb-2">
                      <div>
                        <label className="section-label block mb-1">Responder Name</label>
                        <input value={responderName} onChange={(e) => setResponderName(e.target.value)} placeholder="Dr. Rajan / Unit 4"
                          className="w-full text-xs border border-[#F1F5F9] rounded-xl px-3 py-2 bg-[#F8FAFC] focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20 text-[#334155] placeholder-[#CBD5E1]" />
                      </div>
                      <div>
                        <label className="section-label block mb-1">Responder Phone</label>
                        <input value={responderPhone} onChange={(e) => setResponderPhone(e.target.value)} placeholder="+91 98765…"
                          className="w-full text-xs border border-[#F1F5F9] rounded-xl px-3 py-2 bg-[#F8FAFC] focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20 text-[#334155] placeholder-[#CBD5E1]" />
                      </div>
                      <div>
                        <label className="section-label block mb-1">Responder Lat</label>
                        <input value={responderLat} onChange={(e) => setResponderLat(e.target.value)} placeholder="19.076"
                          className="w-full text-xs border border-[#F1F5F9] rounded-xl px-3 py-2 bg-[#F8FAFC] font-mono focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20 text-[#334155] placeholder-[#CBD5E1]" />
                      </div>
                      <div>
                        <label className="section-label block mb-1">Responder Lng</label>
                        <input value={responderLng} onChange={(e) => setResponderLng(e.target.value)} placeholder="72.877"
                          className="w-full text-xs border border-[#F1F5F9] rounded-xl px-3 py-2 bg-[#F8FAFC] font-mono focus:outline-none focus:ring-2 focus:ring-[#2563EB]/20 text-[#334155] placeholder-[#CBD5E1]" />
                      </div>
                    </div>
                    <div className="grid grid-cols-2 gap-2 mb-2">
                      <button onClick={() => sendUpdateToUser("Dispatched")} disabled={!updateMsg.trim() || sendingUpdate}
                        className="py-2.5 text-xs font-bold bg-[#2563EB] hover:bg-[#1D4ED8] text-white rounded-xl disabled:opacity-40 transition-colors">
                        Send + Dispatched
                      </button>
                      <button onClick={() => sendUpdateToUser("En Route")} disabled={!updateMsg.trim() || sendingUpdate}
                        className="py-2.5 text-xs font-bold bg-[#4338CA] hover:bg-[#3730A3] text-white rounded-xl disabled:opacity-40 transition-colors">
                        Send + En Route
                      </button>
                    </div>
                    <button onClick={() => sendUpdateToUser()} disabled={!updateMsg.trim() || sendingUpdate}
                      className="w-full py-2.5 text-xs font-bold bg-[#0F172A] hover:bg-[#1E293B] text-white rounded-xl disabled:opacity-40 transition-colors">
                      {sendingUpdate ? "Sending…" : "Send Message Only"}
                    </button>
                  </Panel>

                  {/* Call caller */}
                  <Panel title="Contact Caller" icon={Phone}>
                    {val(selected.user_phone) !== "—" ? (
                      <a href={`tel:${selected.user_phone}`}
                        className="flex items-center justify-center gap-2 py-3 w-full bg-[#ECFDF5] hover:bg-[#D1FAE5] text-[#059669] font-bold rounded-xl transition-colors text-sm border border-[#A7F3D0]">
                        <Phone size={14} /> Call {selected.user_phone}
                      </a>
                    ) : <p className="text-xs text-[#94A3B8] text-center py-2">No phone on record</p>}
                  </Panel>

                  {/* Emergency services */}
                  <Panel title="Notify Emergency Services" icon={AlertTriangle}>
                    <div className="space-y-2">
                      {[
                        { icon: Shield,    name: "Unified Emergency",      num: "112", color: "#E11D48", bg: "#FEF2F2" },
                        { icon: Activity,  name: "Ambulance (EMRI)",        num: "108", color: "#2563EB", bg: "#EFF6FF" },
                        { icon: Zap,       name: "Police Control Room",     num: "100", color: "#1D4ED8", bg: "#EEF2FF" },
                        { icon: AlertTriangle, name: "Fire Brigade",        num: "101", color: "#EA580C", bg: "#FFF7ED" },
                        { icon: MapPin,    name: "NHAI Road Helpline",       num: "1033",color: "#16A34A", bg: "#F0FDF4" },
                      ].map((s) => (
                        <div key={s.name} className="flex items-center justify-between px-3 py-2.5 rounded-xl border border-[#F1F5F9] bg-[#F8FAFC]">
                          <div className="flex items-center gap-2.5">
                            <div className="w-8 h-8 rounded-xl flex items-center justify-center" style={{ background: s.bg }}>
                              <s.icon size={14} style={{ color: s.color }} />
                            </div>
                            <div>
                              <p className="text-xs font-bold text-[#0F172A]">{s.name}</p>
                              <p className="text-[10px] text-[#94A3B8] font-mono">{s.num}</p>
                            </div>
                          </div>
                          <a href={`tel:${s.num}`}
                            className="flex items-center gap-1 px-3 py-1.5 rounded-xl text-xs font-bold transition-colors text-white"
                            style={{ background: s.color }}>
                            <Phone size={10} /> Call
                          </a>
                        </div>
                      ))}
                    </div>
                  </Panel>

                  {/* Quick status */}
                  <Panel title="Quick Status Update" icon={Truck}>
                    <div className="grid grid-cols-2 gap-2">
                      {(["Acknowledged","Dispatched","En Route","Resolved"] as IncidentStatus[]).map((s) => (
                        <button key={s} onClick={() => updateStatus(s)}
                          disabled={statusUpdating || selected.status === s}
                          className={`py-2.5 text-xs rounded-xl border font-bold transition-all disabled:cursor-not-allowed ${selected.status === s ? "bg-[#0F172A] text-white border-[#0F172A]" : "bg-white text-[#64748B] border-[#F1F5F9] hover:border-[#E2E8F0] hover:text-[#0F172A] disabled:opacity-40"}`}>
                          {s}
                        </button>
                      ))}
                    </div>
                  </Panel>
                </>
              )}

              {/* ─ REPORT TAB ────────────────────────────────────────────── */}
              {activeTab === "report" && (
                <>
                  <Panel title="Incident Report Preview" icon={FileText}>
                    <div className="bg-[#F8FAFC] rounded-xl p-3 space-y-1.5 border border-[#F1F5F9]">
                      {[
                        ["Incident ID", selected.id.split("-")[0].toUpperCase()],
                        ["Priority", `${selected.priority} — ${PRIORITY_META[selected.priority]?.label}`],
                        ["Status", selected.status],
                        ["Date / Time", new Date(selected.timestamp).toLocaleString("en-IN")],
                        ["Service", selected.service_name],
                        ["Caller", val(selected.user_name)],
                        ["Phone", val(selected.user_phone)],
                        ["Blood Group", val(selected.blood_group)],
                        ["GPS", `${selected.lat.toFixed(4)}, ${selected.lng.toFixed(4)}`],
                        ["Photos", `${selected.photos?.split(",").filter(Boolean).length ?? 0}`],
                        ["Notes", notes.trim() || "—"],
                      ].map(([l, v]) => (
                        <div key={l} className="flex gap-3">
                          <span className="text-[10px] text-[#94A3B8] w-20 flex-shrink-0 font-medium">{l}</span>
                          <span className="text-[10px] text-[#334155] font-bold break-all">{v}</span>
                        </div>
                      ))}
                    </div>
                  </Panel>

                  <button onClick={() => exportPDF(selected)}
                    className="w-full py-4 text-white font-bold rounded-2xl flex items-center justify-center gap-2 transition-all text-sm shadow-sm hover:shadow-md"
                    style={{ background: "#E11D48" }}>
                    <FileText size={15} /> Download Official CAD Report (PDF)
                  </button>

                  <p className="text-[10px] text-[#CBD5E1] text-center leading-relaxed pb-2">
                    CONFIDENTIAL — Authorized emergency personnel only.<br />All activity is logged.
                  </p>
                </>
              )}
            </div>
          </aside>
        )}
      </div>
    </div>
  );
}

// ─── Shared sub-components ────────────────────────────────────────────────────

function Panel({ title, icon: Icon, children, right }: { title: string; icon: any; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-[#F1F5F9] overflow-hidden shadow-[0_4px_12px_rgba(15,23,42,0.03)]">
      <div className="bg-[#F8FAFC] px-4 py-2.5 border-b border-[#F1F5F9] flex items-center gap-2">
        <div className="w-5 h-5 rounded-lg bg-white border border-[#F1F5F9] flex items-center justify-center">
          <Icon size={10} className="text-[#64748B]" />
        </div>
        <span className="section-label flex-1">{title}</span>
        {right}
      </div>
      <div className="p-4 space-y-2.5">{children}</div>
    </div>
  );
}

function DR({ label, value, mono, valueClass }: { label: string; value: string; mono?: boolean; valueClass?: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-[10px] text-[#94A3B8] font-medium flex-shrink-0">{label}</span>
      <span className={`text-xs text-right break-all leading-snug ${mono ? "font-mono text-[#334155]" : "font-bold"} ${valueClass ?? "text-[#0F172A]"}`}>
        {value}
      </span>
    </div>
  );
}
