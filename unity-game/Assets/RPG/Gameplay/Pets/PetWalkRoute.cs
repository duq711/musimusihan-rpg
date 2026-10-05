using System.Collections.Generic;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Bounded floor-aware routing through the actual world collision geometry.</summary>
    public sealed class PetWalkRoute
    {
        const float Cell = .6f, Radius = .19f;
        const int Mask = 1 << DungeonCombatWorld.WorldLayer;
        static readonly Vector2Int[] Steps = { new Vector2Int(1,0), new Vector2Int(-1,0), new Vector2Int(0,1), new Vector2Int(0,-1), new Vector2Int(1,1), new Vector2Int(-1,1), new Vector2Int(1,-1), new Vector2Int(-1,-1) };
        readonly List<Vector3> route = new List<Vector3>();
        Vector3 goal;
        double retry;

        public static bool Floor(Vector3 candidate, out Vector3 ground)
        {
            ground = candidate;
            if (!Physics.Raycast(candidate + Vector3.up * .85f, Vector3.down, out var hit, 1.6f, Mask, QueryTriggerInteraction.Ignore) || hit.normal.y < .7f) return false;
            ground = hit.point;
            if (Mathf.Abs(ground.y - candidate.y) > .6f) return false;
            return !Physics.CheckCapsule(ground + Vector3.up * .23f, ground + Vector3.up * .47f, Radius, Mask, QueryTriggerInteraction.Ignore);
        }

        public static bool Clear(Vector3 from, Vector3 to)
        {
            Vector3 delta = to - from;
            if (Mathf.Abs(delta.y) > .3f) return false;
            if (delta.magnitude > .001f && Physics.CapsuleCast(from + Vector3.up * .23f, from + Vector3.up * .47f, Radius, delta.normalized, delta.magnitude, Mask, QueryTriggerInteraction.Ignore)) return false;
            int count = Mathf.Max(1, Mathf.CeilToInt(delta.magnitude / .5f));
            for (int i = 1; i <= count; i++) if (!Floor(Vector3.Lerp(from, to, i / (float)count), out var floor) || Mathf.Abs(floor.y - from.y) > .3f) return false;
            return true;
        }

        public void Reset() { route.Clear(); retry = 0; }
        public Vector3 Direction(Vector3 from, Vector3 requested, double delta)
        {
            retry -= delta;
            Vector3 flat = requested - from; flat.y = 0;
            Vector3 destination = from + Vector3.ClampMagnitude(flat, 11);
            destination.y = requested.y;
            if (Clear(from, destination)) { route.Clear(); return flat.normalized; }
            if (retry <= 0 && (route.Count == 0 || (goal - requested).sqrMagnitude > 1))
            { goal = requested; retry = .8; Build(from, destination); }
            while (route.Count > 0 && (Vector3.ProjectOnPlane(route[0] - from, Vector3.up)).magnitude < .25f) route.RemoveAt(0);
            if (route.Count == 0) return Vector3.zero;
            if (!Clear(from, route[0])) { route.Clear(); return Vector3.zero; }
            var toward = route[0] - from; toward.y = 0; return toward.normalized;
        }

        void Build(Vector3 origin, Vector3 destination)
        {
            route.Clear();
            Vector2Int target = new Vector2Int(Mathf.RoundToInt((destination.x - origin.x) / Cell), Mathf.RoundToInt((destination.z - origin.z) / Cell));
            var open = new List<Vector2Int> { Vector2Int.zero };
            var closed = new HashSet<Vector2Int>();
            var costs = new Dictionary<Vector2Int, float> { [Vector2Int.zero] = 0 };
            var parents = new Dictionary<Vector2Int, Vector2Int>();
            var points = new Dictionary<Vector2Int, Vector3> { [Vector2Int.zero] = origin };
            float Estimate(Vector2Int cell) => Vector2Int.Distance(cell, target);
            bool Point(Vector2Int cell, float approachHeight, out Vector3 point)
            {
                if (points.TryGetValue(cell, out point)) return true;
                var candidate = origin + new Vector3(cell.x * Cell, 0, cell.y * Cell);
                candidate.y = approachHeight;
                // A floor can be reachable from a higher stair neighbour after
                // being unreachable from the first, lower approach.
                if (!Floor(candidate, out point)) return false;
                points[cell] = point; return true;
            }
            for (int budget = 0; budget < 384 && open.Count > 0; budget++)
            {
                int best = 0;
                for (int i = 1; i < open.Count; i++) if (costs[open[i]] + Estimate(open[i]) < costs[open[best]] + Estimate(open[best])) best = i;
                var current = open[best]; open.RemoveAt(best); closed.Add(current);
                if (current == target || (points[current] - destination).sqrMagnitude < Cell * Cell && Clear(points[current], destination))
                {
                    var cursor = current;
                    while (cursor != Vector2Int.zero) { route.Insert(0, points[cursor]); cursor = parents[cursor]; }
                    if (Clear(points[current], destination)) route.Add(destination);
                    return;
                }
                foreach (var offset in Steps)
                {
                    var next = current + offset;
                    if (Mathf.Abs(next.x) > 20 || Mathf.Abs(next.y) > 20 || closed.Contains(next) || !Point(next, points[current].y, out var position) || !Clear(points[current], position)) continue;
                    float cost = costs[current] + offset.magnitude;
                    if (costs.TryGetValue(next, out float previous) && cost >= previous) continue;
                    costs[next] = cost; parents[next] = current;
                    if (!open.Contains(next)) open.Add(next);
                }
            }
        }
    }
}
