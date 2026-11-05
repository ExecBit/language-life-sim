using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using FittingPlacer;

internal static class Program
{
    private const string UpstreamCommit = "1cdb703197b41d418e7ce686e74c7aad835ddb37";
    private sealed record ZoneBrief(string Id, string Type, int Tables = 0, int ChairsPerTable = 0);
    private sealed record Brief(string Location, int Seed, ZoneBrief[] Zones, string[][] Adjacency);
    private sealed record Placement(string id, string zoneId, string assetPath, float[] translation, float[] rotation);
    private sealed record Zone(string id, string type, float width, float depth, float originX, float originZ);

    public static int Main(string[] args)
    {
        if (args.Length != 3) { Console.Error.WriteLine("Usage: runner <brief.json> <layout.json> <semantics.xml>"); return 2; }
        var brief = JsonSerializer.Deserialize<Brief>(File.ReadAllText(args[0]), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        if (brief.Zones.Length != 2 || brief.Adjacency.Length != 1 || brief.Adjacency[0].Length != 2)
        { Console.Error.WriteLine("Stage 1 expects exactly two adjacent zones."); return 2; }

        var hallBrief = brief.Zones.Single(z => z.Type == "public_hall");
        var kitchenBrief = brief.Zones.Single(z => z.Type == "kitchen");
        if (!brief.Adjacency[0].ToHashSet().SetEquals(new[] { hallBrief.Id, kitchenBrief.Id }))
        { Console.Error.WriteLine("Stage 1 adjacency must connect the public hall and kitchen."); return 2; }
        // Footprints measured from the existing KayKit glTFs; clearance allowance is added per zone.
        if (hallBrief.Tables != 1 || hallBrief.ChairsPerTable != 4)
        { Console.Error.WriteLine("Stage 1 requires one table with four chairs; this checkpoint does not yet support table variation."); return 2; }
        var hallSide = Math.Max(7.0f, hallBrief.Tables * 4.8f + 2.0f);
        const float counterWidth = 2.0f, stoveWidth = 2.0f, fridgeWidth = 2.0f;
        var kitchenWidth = counterWidth + stoveWidth + fridgeWidth + 2.0f; // 1m end clearance at either end.
        var kitchenDepth = MathF.Max(2.042f, MathF.Max(2.288f, 2.24f)) + 0.8f + 3.9f;
        // Measured deepest footprint + the authored 0.8m working front + room for circulation.
        var totalWidth = hallSide + kitchenWidth;
        var zones = new[] {
            new Zone(hallBrief.Id, hallBrief.Type, hallSide, hallSide, -totalWidth / 2 + hallSide / 2, 0),
            new Zone(kitchenBrief.Id, kitchenBrief.Type, kitchenWidth, kitchenDepth, totalWidth / 2 - kitchenWidth / 2, 0)
        };
        var placements = new List<Placement>();
        var furnisher = new Furnisher(args[2]);
        foreach (var zone in zones)
        {
            List<string> requested = new();
            if (zone.type == "public_hall")
            {
                for (var table = 0; table < hallBrief.Tables; table++)
                {
                    requested.Add("dining_table");
                    for (var chair = 0; chair < hallBrief.ChairsPerTable; chair++) requested.Add("dining_chair");
                }
            }
            else requested.AddRange(new[] { "kitchen_counter", "kitchen_stove", "kitchen_fridge" });
            var generated = furnisher.GeneratePlacements(new Room(zone.width, zone.depth, 3, new(), new()), requested, brief.Seed);
            Console.WriteLine($"zone={zone.id} requested={requested.Count} placed={generated.Length} seed={brief.Seed}");
            if (generated.Length != requested.Count) { Console.Error.WriteLine($"Incomplete FittingPlacer result in {zone.id}."); return 1; }
            foreach (var p in generated)
            {
                var (asset, path) = p.RepresentationObject.FittingModelId switch
                {
                    "dining_table" => ("table", "res://assets/table_round_A.gltf"),
                    "dining_chair" => ("chair", "res://assets/chair_A.gltf"),
                    "kitchen_counter" => ("counter", "res://assets/kitchencounter_straight_A.gltf"),
                    "kitchen_stove" => ("stove", "res://assets/stove_single.gltf"),
                    "kitchen_fridge" => ("fridge", "res://assets/fridge_A.gltf"),
                    _ => throw new InvalidOperationException(p.RepresentationObject.FittingModelId)
                };
                placements.Add(new Placement($"{zone.id}_{asset}_{placements.Count}", zone.id, path,
                    new[] { p.PositionX + zone.originX, 0f, p.PositionY + zone.originZ }, new[] { 0f, -p.Orientation, 0f }));
            }
        }
        var output = new { solver = "FittingPlacer", upstreamCommit = UpstreamCommit, seed = brief.Seed,
            doorWidth = 1.4f, totalWidth, roomHeight = 3f, zones, placements };
        File.WriteAllText(args[1], JsonSerializer.Serialize(output, new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
        return 0;
    }
}
