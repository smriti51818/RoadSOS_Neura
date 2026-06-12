import { useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Circle, ZoomControl, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

const redIcon = L.divIcon({
  className: '',
  html: `
    <svg width="40" height="48" viewBox="0 0 40 48" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M20 0C8.954 0 0 8.954 0 20c0 11.046 20 28 20 28s20-16.954 20-28C40 8.954 31.046 0 20 0z" fill="#dc2626"/>
      <circle cx="20" cy="20" r="8" fill="white"/>
      <circle cx="20" cy="20" r="5" fill="#dc2626"/>
    </svg>
  `,
  iconSize: [40, 48],
  iconAnchor: [20, 48],
});

function Recenter({ lat, lng }: { lat: number; lng: number }) {
  const map = useMap();
  useEffect(() => {
    map.flyTo([lat, lng], 16, { duration: 1.2 });
  }, [lat, lng, map]);
  return null;
}

export default function Map({ lat, lng }: { lat: number; lng: number }) {
  const position: [number, number] = [lat, lng];

  return (
    <MapContainer
      key={`${lat}-${lng}`}
      center={position}
      zoom={16}
      style={{ height: '100%', width: '100%' }}
      zoomControl={false}
      attributionControl={false}
    >
      {/* CartoDB Voyager — closest free alternative to Google Maps style */}
      <TileLayer
        url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
        subdomains="abcd"
        maxZoom={20}
      />
      <ZoomControl position="bottomright" />
      
      {/* Soft pulsing radius */}
      <Circle
        center={position}
        radius={150}
        pathOptions={{ color: '#dc2626', fillColor: '#fca5a5', fillOpacity: 0.2, weight: 1.5, dashArray: '6 4' }}
      />

      <Marker position={position} icon={redIcon} />
      <Recenter lat={lat} lng={lng} />
    </MapContainer>
  );
}
