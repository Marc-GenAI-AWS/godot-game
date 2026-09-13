# Street Drive — world brief

References: `examples/man-driving-car-down-street/`, `examples/car-driving/`,
`examples/car-driving-2/` (driving family), plus the street-walk clips for
the on-foot variant later.

## Global

- Axes: road runs along Z; the player drives toward -Z in the right-hand lane
  (x = -1.9). Houses and verges either side; downtown far to -X.
- Camera: chase, ~7 m behind, ~2.4 m up, wide lens, slight look-ahead.
- Light: hard sun, blue sky with cumulus, long shadows from palms and lamps.

## Per segment

| Segment | Brief |
|---|---|
| ground | Grey asphalt with grain, darker wheel tracks in each lane, oil stains and patches; double yellow centre line and faded white edge lines, crosswalk and stop line per block, red-painted kerbs at the crossing, concrete sidewalks with joints, driveways, textured lawns. |
| architecture | Stucco / shingle / tile textures; houses with framed windows and sills, doors, porches, garages, gables, dormers and chimneys; garden walls and picket fences; glass towers on the far horizon. |
| vegetation | Tall thin fan palms and leafy trees (trunk + branches, leaf-card lobes) in the verge, hedges along lot fronts. Species shared in `segments/vegetation/species/`. |
| props | Glowing street lamps, power poles with wires, a lettered STOP sign and street-name plate facing the approaching player, bins, capped hydrants, a mailbox, a bus bench. |
| vehicles | Procedural cars (hatch, sedan, suv, pickup) with chamfered bodies, glossy paint, tinted glass, chrome trim, emissive lights, spoked rims and a contact shadow; parked along both kerbs; traffic in both lanes that follows at an honest gap. Player car: small yellow hatchback with a black roof. |
| crowd | Pedestrians on sidewalks in casual clothes, walking and standing. |
| player | Vehicle mode: accelerate / brake / reverse / steer; stays on the road; soft collisions with cars. |
