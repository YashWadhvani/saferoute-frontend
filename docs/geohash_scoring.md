Geohash scoring design

Goal
- Aggregate per-ride route feedback (5-factor ratings) into per-geohash scores along the route so we can display a safety/quality heatmap.

Key ideas
- Break each route polyline into consecutive geohash buckets at a chosen precision (e.g., precision 6 or 7).
  - Precision 6 geohash ~ 1.2km x 0.6km depending on lat; precision 7 is ~150m x 150m — choose 7 or 8 for street-level.
- For each ride feedback (ratings for entire route), distribute the route-level ratings to each geohash proportionally by segment distance.
  - Steps:
    1. Decode route polyline to list of lat/lng points.
    2. Compute segment length for each consecutive point pair.
    3. Compute geohash for each segment midpoint (or map segment into multiple geohashes if long) and assign the segment length to that geohash.
    4. For each geohash touched by the route, compute a weight equal to total length of segments mapped into it.
    5. For a submitted route rating with per-factor scores s_f, for each geohash g touched, increment counters:
       - count[g] += 1
       - sum_f[g] += s_f * weight_g_for_route / total_route_length
       (Alternatively: sum_f[g] += s_f * weight_g_for_route)
    6. The per-geohash average for factor f is sum_f[g] / count[g] (if normalized by route-level fraction first) or sum_f[g] / total_weight[g] if using weight denominators.

Storage schema (server-side recommended)
- Collection: geohash_feedback
  - geohash (string)
  - precision (int)
  - total_weight (double) // cumulative meters mapped into this geohash
  - submissions (int) // number of route submissions touching this geohash
  - sum_safety, sum_lighting, sum_traffic, sum_sidewalks, sum_signage (double)
  - last_updated (timestamp)

API sketch
- POST /api/route-feedback
  - body: {routeId, polyline, startTime, endTime, ratings: {safety, lighting, traffic, sidewalks, signage}, comments}
  - server decodes polyline and updates geohash_feedback by distributing rating values.
- GET /api/geohash-score?geohash=xxxx&precision=7
  - returns aggregated scores and counts for the requested geohash.

Notes and choices
- Precision: choose 7 for street-level buckets; 8 gives finer resolution but higher data volume.
- Normalization: prefer using weight-based normalization so long segments don't over-inflate per-route influence.
- Privacy: route-level feedback can be mapped to geohashes without storing user identifiers. If storing user ids, ensure privacy policies are followed.
- Edge cases: very short routes, missing GPS; ensure minimum route length or skip.

Client-side responsibilities
- Submit the polyline (encoded) and the user ratings together to POST /api/route-feedback.
- Optionally, the client may pre-slice the polyline into geohash buckets and send a condensed payload; server-side mapping is recommended.

This document is a starting point. I can scaffold a server-side batch worker or provide Dart code (client-side) to map polyline -> geohash buckets if you want.