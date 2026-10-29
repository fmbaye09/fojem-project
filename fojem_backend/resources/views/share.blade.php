<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>Suivi de trajet · FOJËM</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
  <style>
    :root { --jade:#00A58C; --azur:#008ACE; --mango:#FC8731; --ink:#07232F; --muted:#5C737C; --bg:#E7F3F3; --card:#F1F8F9; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; background:var(--bg); color:var(--ink); }
    header { background:linear-gradient(135deg,var(--jade),var(--azur)); color:#fff; padding:20px 16px 56px; border-radius:0 0 28px 28px; }
    header .brand { font-weight:800; letter-spacing:.5px; opacity:.9; font-size:14px; }
    header h1 { margin:6px 0 4px; font-size:22px; }
    header p { margin:0; opacity:.9; font-size:14px; }
    main { max-width:640px; margin:-40px auto 24px; padding:0 16px; display:flex; flex-direction:column; gap:14px; }
    .card { background:var(--card); border-radius:20px; padding:16px; box-shadow:0 8px 24px rgba(87,119,130,.18); }
    #map { height:280px; border-radius:20px; overflow:hidden; padding:0; }
    .row { display:flex; justify-content:space-between; gap:12px; padding:8px 0; border-bottom:1px solid #D3E1E3; }
    .row:last-child { border-bottom:0; }
    .label { color:var(--muted); font-size:13px; }
    .value { font-weight:600; text-align:right; }
    .plate { display:inline-block; background:#fff; border:2px solid var(--ink); border-radius:8px; padding:2px 10px; font-weight:800; letter-spacing:1px; }
    .pill { display:inline-block; padding:4px 10px; border-radius:999px; font-size:13px; font-weight:700; }
    .pill.live { background:#E0F4E7; color:#2E8B4E; }
    .pill.wait { background:#FFF0D9; color:#B26B00; }
    .pill.off { background:#E7EEF0; color:var(--muted); }
    .muted { color:var(--muted); font-size:13px; }
    .error { text-align:center; padding:40px 16px; }
  </style>
</head>
<body>
  <header>
    <div class="brand">FOJËM</div>
    <h1 id="title">Suivi de trajet</h1>
    <p id="subtitle">Chargement…</p>
  </header>
  <main id="content">
    <div id="map" class="card"></div>
    <div class="card">
      <div class="row"><span class="label">Statut</span><span class="value" id="status">—</span></div>
      <div class="row"><span class="label">Prise en charge</span><span class="value" id="boarding">—</span></div>
      <div class="row"><span class="label">Arrivée</span><span class="value" id="alighting">—</span></div>
      <div class="row"><span class="label">Chauffeur</span><span class="value" id="driver">—</span></div>
      <div class="row"><span class="label">Véhicule</span><span class="value" id="vehicle">—</span></div>
    </div>
    <p class="muted" id="updated" style="text-align:center"></p>
  </main>

  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    const token = @json($token);
    const endpoint = `/api/public/share/${token}`;
    const byId = (id) => document.getElementById(id);
    const time = (iso) => iso ? new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : null;
    const setText = (id, value) => { byId(id).textContent = value; };

    const map = L.map('map', { zoomControl: false }).setView([14.69, -17.44], 11);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap' }).addTo(map);
    const dot = (color, size) => L.divIcon({
      className: '', iconSize: [size, size], iconAnchor: [size / 2, size / 2],
      html: `<div style="width:${size}px;height:${size}px;border-radius:50%;background:${color};border:3px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
    });
    let route, boardingMarker, alightingMarker, carMarker, fitted = false, timer;

    function stopLine(stop) {
      if (!stop) return '—';
      const at = time(stop.eta) || time(stop.scheduled_at);
      return at ? `${stop.name} · ${stop.eta ? 'vers ' : ''}${at}` : stop.name;
    }

    function expired() {
      clearInterval(timer);
      setText('title', 'Lien expiré');
      setText('subtitle', 'Ce trajet est terminé ou le lien n’est plus valide.');
      byId('content').innerHTML = '<div class="card error">Ce lien de suivi n’est plus actif.<br><span class="muted">Demandez un nouveau lien à la personne qui vous l’a envoyé.</span></div>';
    }

    async function refresh() {
      let data;
      try {
        const res = await fetch(endpoint, { headers: { Accept: 'application/json' } });
        if (res.status === 404) return expired();
        if (!res.ok) throw new Error(String(res.status));
        data = await res.json();
      } catch (e) {
        setText('updated', 'Connexion impossible, nouvel essai dans un instant…');
        return;
      }

      setText('title', data.passenger_first_name ? `Trajet de ${data.passenger_first_name}` : 'Suivi de trajet');
      setText('subtitle', `${data.boarding?.name ?? 'Départ'} → ${data.alighting?.name ?? 'Arrivée'}`);

      const pill = document.createElement('span');
      if (data.status === 'in_progress') {
        pill.className = 'pill live';
        pill.textContent = data.boarded ? 'En route' : 'Le chauffeur arrive';
      } else if (data.status === 'completed') {
        pill.className = 'pill off';
        pill.textContent = 'Arrivé';
      } else {
        pill.className = 'pill wait';
        pill.textContent = 'Départ à venir';
      }
      byId('status').replaceChildren(pill);
      setText('boarding', stopLine(data.boarding));
      setText('alighting', stopLine(data.alighting));
      setText('driver', data.driver_first_name ?? '—');

      if (data.vehicle) {
        const plate = document.createElement('span');
        plate.className = 'plate';
        plate.textContent = data.vehicle.plate_number;
        byId('vehicle').replaceChildren(`${data.vehicle.label} `, plate);
      } else {
        setText('vehicle', '—');
      }

      if (data.route && data.route.length > 1) {
        if (route) route.setLatLngs(data.route);
        else route = L.polyline(data.route, { color: '#00A58C', weight: 5, opacity: 0.8 }).addTo(map);
      }
      if (data.boarding && !boardingMarker) {
        boardingMarker = L.marker([data.boarding.lat, data.boarding.lng], { icon: dot('#00A58C', 18) }).addTo(map).bindPopup('Prise en charge');
      }
      if (data.alighting && !alightingMarker) {
        alightingMarker = L.marker([data.alighting.lat, data.alighting.lng], { icon: dot('#07232F', 18) }).addTo(map).bindPopup('Arrivée');
      }
      if (data.vehicle_position) {
        const p = [data.vehicle_position.lat, data.vehicle_position.lng];
        if (carMarker) carMarker.setLatLng(p);
        else carMarker = L.marker(p, { icon: dot('#FC8731', 22) }).addTo(map).bindPopup('Véhicule');
        setText('updated', `Position du véhicule mise à jour à ${time(data.vehicle_position.updated_at)}`);
      } else {
        if (carMarker) { map.removeLayer(carMarker); carMarker = null; }
        setText('updated', data.status === 'in_progress'
          ? 'Position du véhicule momentanément indisponible.'
          : 'La position du véhicule s’affichera au départ.');
      }
      if (!fitted) {
        const layers = [route, boardingMarker, alightingMarker, carMarker].filter(Boolean);
        if (layers.length) {
          map.fitBounds(L.featureGroup(layers).getBounds().pad(0.2));
          fitted = true;
        }
      }
    }

    timer = setInterval(refresh, 15000);
    refresh();
  </script>
</body>
</html>
