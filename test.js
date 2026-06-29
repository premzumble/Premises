
    let map;
    let autocomplete;
    let activeMode = "0";
    let isDrawing = false;
    let hoverLine = null;
    let isPolygonCustomized = false;

    // Circle config state
    let centerMarker;
    let mapCircle;
    let circleCenter = { lat: 0, lng: 0 };
    let circleRadius = 0;

    // Polygon config state
    let mapPolygon;
    let polygonVertices = [];
    let isUpdatingPath = false;
    let onPathChangedGlobal = null;

    function updatePolygonPath(vertices) {
      if (!mapPolygon) return;
      const path = mapPolygon.getPath();
      if (!path) return;
      isUpdatingPath = true;
      path.clear();
      for (const v of vertices) {
        path.push(new google.maps.LatLng(v.lat, v.lng));
      }
      isUpdatingPath = false;
      if (onPathChangedGlobal) onPathChangedGlobal();
    }

    // History state stacks for Undo/Redo
    let undoStack = [];
    let redoStack = [];

    // Parse initial coordinates
    try {
      const initVerts = JSON.parse("0");
      if (initVerts && initVerts.length > 0) {
        polygonVertices = initVerts.map(v => ({ lat: v.latitude, lng: v.longitude }));
        isPolygonCustomized = true;
      }
    } catch (e) {
      console.error("Error parsing initial vertices", e);
    }

    // Toggle Sidebar collapse
    function toggleSidebar() {
      const sidebar = document.getElementById('sidebar');
      const workspace = document.getElementById('workspace');
      const expandBtn = document.getElementById('expand-btn');
      
      sidebar.classList.toggle('collapsed');
      workspace.classList.toggle('full-width');
      
      if (sidebar.classList.contains('collapsed')) {
        expandBtn.style.display = 'block';
      } else {
        expandBtn.style.display = 'none';
      }
      // Re-layout map
      setTimeout(() => {
        if (map) google.maps.event.trigger(map, 'resize');
      }, 300);
    }

    function initMap() {
      // Create modern Google Map with hybrid map type Horizontal bar, Pegman streetview, scale/zoom controls
      const initialCenter = activeMode === 'polygon' && polygonVertices.length > 0 
        ? calculateCentroid(polygonVertices)
        : circleCenter;

      map = new google.maps.Map(document.getElementById('map'), {
        center: initialCenter,
        zoom: 15,
        mapTypeId: 'roadmap',
        disableDoubleClickZoom: true,
        mapTypeControl: true,
        mapTypeControlOptions: {
          style: google.maps.MapTypeControlStyle.HORIZONTAL_BAR,
          position: google.maps.ControlPosition.TOP_RIGHT
        },
        zoomControl: true,
        zoomControlOptions: {
          position: google.maps.ControlPosition.RIGHT_CENTER
        },
        fullscreenControl: true,
        streetViewControl: true,
        streetViewControlOptions: {
          position: google.maps.ControlPosition.RIGHT_CENTER
        },
        scaleControl: true,
        styles: [
          { elementType: "geometry", stylers: [{ color: "#1e293b" }] },
          { elementType: "labels.text.stroke", stylers: [{ color: "#0f172a" }] },
          { elementType: "labels.text.fill", stylers: [{ color: "#94a3b8" }] },
          { featureType: "administrative", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "poi", elementType: "labels.text.fill", stylers: [{ color: "#64748b" }] },
          { featureType: "road", elementType: "geometry", stylers: [{ color: "#334155" }] },
          { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#1e293b" }] },
          { featureType: "water", elementType: "geometry", stylers: [{ color: "#0f172a" }] }
        ]
      });

      // Autocomplete Search Box
      const searchBox = document.getElementById('search');
      autocomplete = new google.maps.places.Autocomplete(searchBox);
      autocomplete.bindTo('bounds', map);
      autocomplete.addListener('place_changed', onPlaceSelected);

      // Listen to search typing to toggle clear icon
      searchBox.addEventListener('input', function() {
        document.getElementById('clear-search-btn').style.display = this.value ? 'block' : 'none';
      });

      // Init shape instances
      setupCircleElements();
      setupPolygonElements();

      // Click to draw custom polygon
      map.addListener('click', function(e) {
        if (activeMode === 'polygon' && isDrawing) {
          saveHistoryState();
          const clickedLoc = e.latLng.toJSON();
          
          // Check if close to first vertex to close path (within 15 meters)
          if (polygonVertices.length >= 3 && google.maps.geometry) {
            const first = polygonVertices[0];
            const dist = google.maps.geometry.spherical.computeDistanceBetween(
              e.latLng, 
              new google.maps.LatLng(first.lat, first.lng)
            );
            if (dist < 15) {
              completeDrawing();
              return;
            }
          }
          
          polygonVertices.push(clickedLoc);
          drawActivePolygon();
          updateUI();
        }
      });

      // Mousemove for hoverPreview polygon segment lines
      map.addListener('mousemove', function(e) {
        if (activeMode === 'polygon' && isDrawing && polygonVertices.length > 0) {
          const lastPoint = polygonVertices[polygonVertices.length - 1];
          const mouseLoc = e.latLng;
          if (!hoverLine) {
            hoverLine = new google.maps.Polyline({
              strokeColor: '#10b981',
              strokeOpacity: 0.6,
              strokeWeight: 2,
              map: map,
              clickable: false
            });
          }
          hoverLine.setPath([lastPoint, mouseLoc]);
        }
      });

      // Double click listener to complete drawing or relocate/translate active shape
      map.addListener('dblclick', function(e) {
        if (activeMode === 'polygon' && isDrawing) {
          if (polygonVertices.length >= 3) {
            completeDrawing();
          }
          return;
        }

        saveHistoryState();
        const clickedLoc = e.latLng.toJSON();
        if (activeMode === 'circle') {
          circleCenter = clickedLoc;
          centerMarker.setPosition(circleCenter);
          mapCircle.setCenter(circleCenter);
          
          // Re-center polygon vertices around the new center
          if (polygonVertices.length > 0) {
            const centroid = calculateCentroid(polygonVertices);
            const dLat = circleCenter.lat - centroid.lat;
            const dLng = circleCenter.lng - centroid.lng;
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          } else {
            const offset = 0.001;
            polygonVertices = [
              { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
              { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
              { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
              { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset }
            ];
            updatePolygonPath(polygonVertices);
          }
        } else {
          // Translate polygon vertices around the double-clicked centroid
          if (polygonVertices.length > 0) {
            const centroid = calculateCentroid(polygonVertices);
            const dLat = clickedLoc.lat - centroid.lat;
            const dLng = clickedLoc.lng - centroid.lng;
            polygonVertices = polygonVertices.map(v => ({
              lat: v.lat + dLat,
              lng: v.lng + dLng
            }));
            updatePolygonPath(polygonVertices);
          }
        }
        updateUI();
        notifyChanged();
      });

      // Listen to postMessage location updates from parent Flutter widget
      window.addEventListener('message', function(event) {
        try {
          const payload = JSON.parse(event.data);
          if (payload && payload.type === 'SET_LOCATION') {
            const lat = payload.latitude;
            const lng = payload.longitude;
            const rad = payload.radius;
            const loc = { lat: lat, lng: lng };

            map.setCenter(loc);
            map.setZoom(16);

            saveHistoryState();

             if (activeMode === 'circle') {
              circleCenter = loc;
              circleRadius = rad;
              centerMarker.setPosition(circleCenter);
              mapCircle.setCenter(circleCenter);
              mapCircle.setRadius(circleRadius);

              // Translate polygon vertices around the new center
              if (polygonVertices.length > 0) {
                const centroid = calculateCentroid(polygonVertices);
                const dLat = circleCenter.lat - centroid.lat;
                const dLng = circleCenter.lng - centroid.lng;
                polygonVertices = polygonVertices.map(v => ({
                  lat: v.lat + dLat,
                  lng: v.lng + dLng
                }));
                updatePolygonPath(polygonVertices);
              } else {
                const offset = 0.001;
                polygonVertices = [
                  { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
                  { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
                  { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
                  { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset }
                ];
                updatePolygonPath(polygonVertices);
              }
            } else {
              // Place default polygon bounds around searched coordinate
              const offset = 0.001;
              polygonVertices = [
                { lat: loc.lat - offset, lng: loc.lng - offset },
                { lat: loc.lat + offset, lng: loc.lng - offset },
                { lat: loc.lat + offset, lng: loc.lng + offset },
                { lat: loc.lat - offset, lng: loc.lng - offset }
              ];
              isDrawing = false;
              mapPolygon.setOptions({
                clickable: true,
                editable: true,
                draggable: true
              });
              updatePolygonPath(polygonVertices);
              mapPolygon.setMap(map);
              isPolygonCustomized = true;

              // Also sync circle
              circleCenter = loc;
              centerMarker.setPosition(circleCenter);
              mapCircle.setCenter(circleCenter);
            }
            updateUI();
            notifyChanged();
          }
        } catch (err) {
          // Ignore non-json messages
        }
      });

      // Check onboarding state
      if (0 === 18.403817 && 0 === 76.560943 && polygonVertices.length === 0) {
        document.getElementById('onboarding-overlay').style.display = 'flex';
      }

      setMode(activeMode);
    }

    function dismissOnboarding() {
      document.getElementById('onboarding-overlay').style.display = 'none';
      document.getElementById('step-1').classList.add('active');
    }

    function setupCircleElements() {
      centerMarker = new google.maps.Marker({
        position: circleCenter,
        map: null,
        draggable: true,
        title: "Relocate Geofence center"
      });

      mapCircle = new google.maps.Circle({
        map: null,
        center: circleCenter,
        radius: circleRadius,
        editable: true,
        draggable: true,
        fillColor: '#4f46e5',
        fillOpacity: 0.12,
        strokeColor: '#4f46e5',
        strokeWeight: 2
      });

      // Drag center events
      centerMarker.addListener('dragend', () => {
        saveHistoryState();
        circleCenter = centerMarker.getPosition().toJSON();
        mapCircle.setCenter(circleCenter);
        
        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          polygonVertices = polygonVertices.map(v => ({
            lat: v.lat + dLat,
            lng: v.lng + dLng
          }));
          updatePolygonPath(polygonVertices);
        } else {
          const offset = 0.001;
          polygonVertices = [
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset }
          ];
          updatePolygonPath(polygonVertices);
        }
        
        updateUI();
        notifyChanged();
      });

      mapCircle.addListener('center_changed', () => {
        circleCenter = mapCircle.getCenter().toJSON();
        centerMarker.setPosition(circleCenter);
        
        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          polygonVertices = polygonVertices.map(v => ({
            lat: v.lat + dLat,
            lng: v.lng + dLng
          }));
          updatePolygonPath(polygonVertices);
        } else {
          const offset = 0.001;
          polygonVertices = [
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng - offset },
            { lat: circleCenter.lat + offset, lng: circleCenter.lng + offset },
            { lat: circleCenter.lat - offset, lng: circleCenter.lng - offset }
          ];
          updatePolygonPath(polygonVertices);
        }
        
        updateUI();
        notifyChanged();
      });

      mapCircle.addListener('radius_changed', () => {
        circleRadius = mapCircle.getRadius();
        updateUI();
        notifyChanged();
      });
    }

    function setupPolygonElements() {
      const initialPath = new google.maps.MVCArray();
      if (polygonVertices && polygonVertices.length > 0) {
        for (const v of polygonVertices) {
          initialPath.push(new google.maps.LatLng(v.lat, v.lng));
        }
      }

      mapPolygon = new google.maps.Polygon({
        paths: initialPath,
        map: null,
        editable: !isDrawing,
        draggable: !isDrawing,
        clickable: !isDrawing,
        fillColor: '#10b981',
        fillOpacity: 0.12,
        strokeColor: '#10b981',
        strokeWeight: 2
      });

      // Edit handlers
      const path = mapPolygon.getPath();
      const onPathChanged = () => {
        if (isUpdatingPath) return;
        let rawVertices = [];
        for (let i = 0; i < path.getLength(); i++) {
          const pt = path.getAt(i);
          rawVertices.push({
            lat: typeof pt.lat === 'function' ? pt.lat() : pt.lat,
            lng: typeof pt.lng === 'function' ? pt.lng() : pt.lng
          });
        }
        const cleaned = removeDuplicateVertices(rawVertices);
        
        if (cleaned.length !== rawVertices.length) {
          // Found and removed duplicates, update map path asynchronously
          setTimeout(() => updatePolygonPath(cleaned), 0);
          return;
        }
        
        saveHistoryState();
        polygonVertices = cleaned;
        isPolygonCustomized = true;
        
        // Sync circle center to polygon centroid
        if (polygonVertices.length > 0) {
          circleCenter = calculateCentroid(polygonVertices);
          centerMarker.setPosition(circleCenter);
          mapCircle.setCenter(circleCenter);
        }
        
        updateUI();
        notifyChanged();
      };
      onPathChangedGlobal = onPathChanged;

      path.addListener('insert_at', onPathChanged);
      path.addListener('remove_at', onPathChanged);
      path.addListener('set_at', onPathChanged);
      
      mapPolygon.addListener('dragend', () => {
        onPathChanged();
      });

      // Right-click polygon vertex to delete
      mapPolygon.addListener('rightclick', function(mev) {
        if (mev.vertex !== undefined) {
          saveHistoryState();
          mapPolygon.getPath().removeAt(mev.vertex);
        }
      });
    }

    function drawActivePolygon() {
      if (polygonVertices.length < 3) {
        // Render polyline
        if (mapPolygon) mapPolygon.setMap(null);
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      } else {
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      }
    }

    function removeDuplicateVertices(verts) {
      const clean = [];
      for (const v of verts) {
        if (clean.length === 0) {
          clean.push(v);
        } else {
          const last = clean[clean.length - 1];
          if (Math.abs(last.lat - v.lat) > 1e-7 || Math.abs(last.lng - v.lng) > 1e-7) {
            clean.push(v);
          }
        }
      }
      if (clean.length > 1) {
        const first = clean[0];
        const last = clean[clean.length - 1];
        if (Math.abs(first.lat - last.lat) < 1e-7 && Math.abs(first.lng - last.lng) < 1e-7) {
          clean.pop();
        }
      }
      return clean;
    }

    function completeDrawing() {
      isDrawing = false;
      if (hoverLine) {
        hoverLine.setMap(null);
        hoverLine = null;
      }
      polygonVertices = removeDuplicateVertices(polygonVertices);
      mapPolygon.setOptions({
        clickable: true,
        editable: true,
        draggable: true
      });
      updatePolygonPath(polygonVertices);
      mapPolygon.setMap(map);
      isPolygonCustomized = true;
      updateUI();
    }

    function onPlaceSelected() {
      const place = autocomplete.getPlace();
      if (!place.geometry || !place.geometry.location) {
        return;
      }
      
      const loc = place.geometry.location;
      map.setCenter(loc);
      map.setZoom(16);

      saveHistoryState();

      if (activeMode === 'circle') {
        circleCenter = loc.toJSON();
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);

        // Translate polygon vertices around the new center
        if (polygonVertices.length > 0) {
          const centroid = calculateCentroid(polygonVertices);
          const dLat = circleCenter.lat - centroid.lat;
          const dLng = circleCenter.lng - centroid.lng;
          polygonVertices = polygonVertices.map(v => ({
            lat: v.lat + dLat,
            lng: v.lng + dLng
          }));
          updatePolygonPath(polygonVertices);
        } else {
          const offset = 0.001;
          const newC = loc.toJSON();
          polygonVertices = [
            { lat: newC.lat - offset, lng: newC.lng - offset },
            { lat: newC.lat + offset, lng: newC.lng - offset },
            { lat: newC.lat + offset, lng: newC.lng + offset },
            { lat: newC.lat - offset, lng: newC.lng + offset }
          ];
          updatePolygonPath(polygonVertices);
        }
      } else {
        // Place default polygon bounds around searched coordinate
        const offset = 0.001;
        const newC = loc.toJSON();
        polygonVertices = [
          { lat: newC.lat - offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng - offset },
          { lat: newC.lat + offset, lng: newC.lng + offset },
          { lat: newC.lat - offset, lng: newC.lng + offset }
        ];
        isDrawing = false;
        mapPolygon.setOptions({
          clickable: true,
          editable: true,
          draggable: true
        });
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
        isPolygonCustomized = true;

        // Sync circle too
        circleCenter = newC;
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);
      }
      
      updateUI();
      notifyChanged();
      
      // Update step progress
      document.getElementById('step-1').className = 'step completed';
      document.getElementById('step-2').classList.add('active');
    }

    function clearSearch() {
      document.getElementById('search').value = '';
      document.getElementById('clear-search-btn').style.display = 'none';
    }

    function setMode(mode) {
      activeMode = mode;
      saveHistoryState();

      document.getElementById('mode-btn-circle').className = mode === 'circle' ? 'mode-btn active' : 'mode-btn';
      document.getElementById('mode-btn-polygon').className = mode === 'polygon' ? 'mode-btn active' : 'mode-btn';
      
      document.getElementById('stat-mode').innerText = mode === 'circle' ? 'Circle' : 'Custom Polygon';
      
      if (mode === 'circle') {
        document.getElementById('stat-row-radius').style.display = 'flex';
        document.getElementById('stat-row-perimeter').style.display = 'none';
        document.getElementById('stat-row-vertices').style.display = 'none';
        document.getElementById('help-tip').innerText = 'Step 3 Help: Resize the circle geofence by dragging its outer bounding handles. Drag the center node to relocate.';

        centerMarker.setMap(map);
        mapCircle.setMap(map);
        mapPolygon.setMap(null);
        if (hoverLine) {
          hoverLine.setMap(null);
          hoverLine = null;
        }
      } else {
        document.getElementById('stat-row-radius').style.display = 'none';
        document.getElementById('stat-row-perimeter').style.display = 'flex';
        document.getElementById('stat-row-vertices').style.display = 'flex';
        document.getElementById('help-tip').innerText = 'Step 3 Help: Click locations on the map to add boundary corners. Drag vertices to adjust segments. Right-click points to delete. Double-click to complete.';

        centerMarker.setMap(null);
        mapCircle.setMap(null);
        
        if (polygonVertices.length === 0) {
          isDrawing = true;
          mapPolygon.setOptions({
            clickable: false,
            editable: false,
            draggable: false
          });
        } else {
          isDrawing = false;
          mapPolygon.setOptions({
            clickable: true,
            editable: true,
            draggable: true
          });
          updatePolygonPath(polygonVertices);
          mapPolygon.setMap(map);
        }
      }

      updateUI();
      notifyChanged();
      
      document.getElementById('step-2').className = 'step completed';
      document.getElementById('step-3').classList.add('active');
    }

    // Centroid calculation
    function calculateCentroid(points) {
      if (points.length === 0) return circleCenter;
      let latSum = 0;
      let lngSum = 0;
      for (const p of points) {
        latSum += p.lat;
        lngSum += p.lng;
      }
      return { lat: latSum / points.length, lng: lngSum / points.length };
    }

    // Geometry statistics
    function updateUI() {
      const alertBox = document.getElementById('alert-box');
      const saveBtn = document.getElementById('btn-save');
      
      alertBox.style.display = 'none';
      saveBtn.disabled = false;

      // Update Toolbar buttons states
      document.getElementById('tb-undo').disabled = undoStack.length === 0;
      document.getElementById('tb-redo').disabled = redoStack.length === 0;

      if (activeMode === 'circle') {
        const centerStr = circleCenter.lat.toFixed(5) + ", " + circleCenter.lng.toFixed(5);
        document.getElementById('stat-center').innerText = centerStr;
        document.getElementById('stat-radius').innerText = Math.round(circleRadius) + " m";
        
        const area = Math.PI * Math.pow(circleRadius, 2);
        document.getElementById('stat-area').innerText = formatArea(area);

        // Validation
        if (circleRadius < 10 || circleRadius > 10000) {
          alertBox.innerText = "Validation Warning: Circle radius must be between 10m and 10km.";
          alertBox.style.display = 'block';
          saveBtn.disabled = true;
        }
      } else {
        document.getElementById('stat-vertices').innerText = polygonVertices.length;
        
        const centroid = calculateCentroid(polygonVertices);
        document.getElementById('stat-center').innerText = centroid.lat.toFixed(5) + ", " + centroid.lng.toFixed(5);

        // Calculate exact area and perimeter using Maps spherical geometry library
        if (polygonVertices.length >= 3 && google.maps.geometry) {
          const path = polygonVertices.map(v => new google.maps.LatLng(v.lat, v.lng));
          const area = google.maps.geometry.spherical.computeArea(path);
          const perimeter = google.maps.geometry.spherical.computeLength(path);

          document.getElementById('stat-area').innerText = formatArea(area);
          document.getElementById('stat-perimeter').innerText = Math.round(perimeter) + " m";

          // Check consecutive duplicates & degenerate
          let hasDuplicates = false;
          for (let i = 0; i < polygonVertices.length; i++) {
            let p1 = polygonVertices[i];
            let p2 = polygonVertices[(i + 1) % polygonVertices.length];
            if (Math.abs(p1.lat - p2.lat) < 1e-9 && Math.abs(p1.lng - p2.lng) < 1e-9) {
              hasDuplicates = true;
              break;
            }
          }
          let uniquePoints = [];
          for (let p of polygonVertices) {
            if (!uniquePoints.some(up => Math.abs(up.lat - p.lat) < 1e-9 && Math.abs(up.lng - p.lng) < 1e-9)) {
              uniquePoints.push(p);
            }
          }

          if (uniquePoints.length < 3) {
            alertBox.innerText = "Invalid Boundary: Polygon must have at least 3 unique vertices.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (hasDuplicates) {
            alertBox.innerText = "Invalid Boundary: Duplicate consecutive vertices detected.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (isSelfIntersecting(polygonVertices)) {
            alertBox.innerText = "Invalid Boundary: Self-intersecting edges detected. Adjust vertices to resolve crossings.";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (area < 100) {
            alertBox.innerText = "Validation Warning: Boundary area is too small (" + Math.round(area) + " m²). Must be at least 100 m².";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          } else if (area > 100000000) {
            alertBox.innerText = "Validation Warning: Boundary area is too large. Must be under 100 km².";
            alertBox.style.display = 'block';
            saveBtn.disabled = true;
          }
        } else {
          document.getElementById('stat-area').innerText = "0 m²";
          document.getElementById('stat-perimeter').innerText = "0 m";
        }
      }

      // Update guided workflow progress indicator
      if (!saveBtn.disabled && (activeMode === 'circle' || polygonVertices.length >= 3)) {
        document.getElementById('step-3').className = 'step completed';
        document.getElementById('step-4').className = 'step active';
      }
    }

    function formatArea(area) {
      if (area >= 1000000) {
        return (area / 1000000).toFixed(2) + " km²";
      }
      return Math.round(area).toLocaleString() + " m²";
    }

    // Geometry Helpers
    function checkOrientation(p, q, r) {
      const val = (q.lng - p.lng) * (r.lat - q.lat) - (q.lat - p.lat) * (r.lng - q.lng);
      if (Math.abs(val) < 1e-9) return 0;
      return val > 0 ? 1 : 2;
    }

    function onSegment(p, q, r) {
      if (q.lat <= Math.max(p.lat, r.lat) && q.lat >= Math.min(p.lat, r.lat) &&
          q.lng <= Math.max(p.lng, r.lng) && q.lng >= Math.min(p.lng, r.lng)) {
        return true;
      }
      return false;
    }

    function doSegmentsIntersect(p1, q1, p2, q2) {
      const o1 = checkOrientation(p1, q1, p2);
      const o2 = checkOrientation(p1, q1, q2);
      const o3 = checkOrientation(p2, q2, p1);
      const o4 = checkOrientation(p2, q2, q1);

      if (o1 !== o2 && o3 !== o4) return true;

      if (o1 === 0 && onSegment(p1, p2, q1)) return true;
      if (o2 === 0 && onSegment(p1, q2, q1)) return true;
      if (o3 === 0 && onSegment(p2, p1, q2)) return true;
      if (o4 === 0 && onSegment(p2, q1, q2)) return true;

      return false;
    }

    function isSelfIntersecting(points) {
      const n = points.length;
      if (n < 4) return false;
      const edges = [];
      for (let i = 0; i < n; i++) {
        edges.push({ p1: points[i], p2: points[(i + 1) % n] });
      }
      for (let i = 0; i < n; i++) {
        for (let j = i + 2; j < n; j++) {
          if (i === 0 && j === n - 1) continue;
          if (doSegmentsIntersect(edges[i].p1, edges[i].p2, edges[j].p1, edges[j].p2)) {
            return true;
          }
        }
      }
      return false;
    }

    // Save history state for Undo/Redo
    function saveHistoryState() {
      const state = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      
      undoStack.push(JSON.stringify(state));
      // Cap undo stack to 20 states
      if (undoStack.length > 20) {
        undoStack.shift();
      }
      redoStack = []; // Clear redo stack on new action
    }

    function undo() {
      if (undoStack.length === 0) return;
      
      const currentState = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      redoStack.push(JSON.stringify(currentState));

      const prevState = JSON.parse(undoStack.pop());
      restoreState(prevState);
    }

    function redo() {
      if (redoStack.length === 0) return;

      const currentState = {
        mode: activeMode,
        circleCenter: { ...circleCenter },
        circleRadius: circleRadius,
        polygonVertices: [ ...polygonVertices ]
      };
      undoStack.push(JSON.stringify(currentState));

      const nextState = JSON.parse(redoStack.pop());
      restoreState(nextState);
    }

    function restoreState(state) {
      activeMode = state.mode;
      circleCenter = state.circleCenter;
      circleRadius = state.circleRadius;
      polygonVertices = state.polygonVertices;

      document.getElementById('mode-btn-circle').className = activeMode === 'circle' ? 'mode-btn active' : 'mode-btn';
      document.getElementById('mode-btn-polygon').className = activeMode === 'polygon' ? 'mode-btn active' : 'mode-btn';

      if (activeMode === 'circle') {
        centerMarker.setPosition(circleCenter);
        mapCircle.setCenter(circleCenter);
        mapCircle.setRadius(circleRadius);
        
        centerMarker.setMap(map);
        mapCircle.setMap(map);
        mapPolygon.setMap(null);
      } else {
        centerMarker.setMap(null);
        mapCircle.setMap(null);
        
        isDrawing = (polygonVertices.length === 0);
        updatePolygonPath(polygonVertices);
        mapPolygon.setMap(map);
      }
      
      updateUI();
      notifyChanged();
    }

    // Geolocation My Location tool
    function centerMap() {
      if (activeMode === 'circle') {
        map.setCenter(circleCenter);
      } else if (polygonVertices.length > 0) {
        const centroid = calculateCentroid(polygonVertices);
        map.setCenter(centroid);
      }
      map.setZoom(16);
    }

    function fitBoundary() {
      if (activeMode === 'circle') {
        map.fitBounds(mapCircle.getBounds());
      } else if (polygonVertices.length > 0) {
        const bounds = new google.maps.LatLngBounds();
        for (const p of polygonVertices) {
          bounds.extend(new google.maps.LatLng(p.lat, p.lng));
        }
        map.fitBounds(bounds);
      }
    }

    function clearShape() {
      saveHistoryState();
      if (activeMode === 'circle') {
        circleRadius = 100;
        mapCircle.setRadius(circleRadius);
      } else {
        polygonVertices = [];
        isDrawing = true;
        updatePolygonPath([]);
        if (hoverLine) {
          hoverLine.setMap(null);
          hoverLine = null;
        }
      }
      updateUI();
      notifyChanged();
    }

    function resetMap() {
      if (confirm("Are you sure you want to discard your edits and revert to the saved boundary settings?")) {
        window.location.reload();
      }
    }

    function cancelChanges() {
      if (confirm("Discard all unsaved boundary modifications?")) {
        window.location.reload();
      }
    }

    function saveGeofence() {
      document.getElementById('step-4').className = 'step completed';
      document.getElementById('step-5').className = 'step active';

      const data = {
        geofence_type: activeMode,
        name: 'Campus Boundary',
        is_active: true
      };

      if (activeMode === 'circle') {
        data.latitude = circleCenter.lat;
        data.longitude = circleCenter.lng;
        data.radius_meters = circleRadius;
        data.vertices = null;
      } else {
        data.latitude = null;
        data.longitude = null;
        data.radius_meters = null;
        data.vertices = polygonVertices.map(v => ({
          latitude: v.lat,
          longitude: v.lng
        }));
      }

      // Submit changes
      window.parent.postMessage(JSON.stringify({
        type: 'SAVE_GEOFENCE',
        data: data
      }), '*');
    }

    // Notify Flutter parent widget of dirty changes status
    function notifyChanged() {
      const centroid = calculateCentroid(polygonVertices);
      const data = {
        geofence_type: activeMode,
        latitude: activeMode === 'circle' ? circleCenter.lat : centroid.lat,
        longitude: activeMode === 'circle' ? circleCenter.lng : centroid.lng,
        radius_meters: circleRadius,
        vertices: polygonVertices.map(v => ({ latitude: v.lat, longitude: v.lng }))
      };
      window.parent.postMessage(JSON.stringify({
        type: 'GEOFENCE_CHANGED',
        data: data
      }), '*');
    }
  