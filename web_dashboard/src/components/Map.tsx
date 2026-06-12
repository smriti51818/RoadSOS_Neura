import { useEffect, useRef } from 'react';
import { MapContainer, TileLayer, Marker, Circle, ZoomControl, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

const emergencyIcon = L.divIcon({
  className: '',
  html: `
    <div style="display: flex; align-items: center; justify-content: center; width: 36px; height: 36px;">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#E11D48" width="36" height="36" style="filter: drop-shadow(0px 2px 4px rgba(0,0,0,0.3));">
        <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z" />
      </svg>
    </div>
  `,
  iconSize: [36, 36],
  iconAnchor: [18, 36],
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
    // No key prop — MapContainer must never be remounted; Recenter handles panning smoothly.
    <MapContainer
      center={position}
      zoom={16}
      style={{ height: '100%', width: '100%' }}
      zoomControl={false}
      attributionControl={false}
    >
      <TileLayer
        url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
        subdomains="abcd"
        maxZoom={20}
      />
      <ZoomControl position="bottomright" />
      <Marker position={position} icon={emergencyIcon} />
      <Recenter lat={lat} lng={lng} />
    </MapContainer>
  );
}
