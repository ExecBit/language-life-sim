using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using FittingPlacer;

internal static class Program
{
    private const string UpstreamCommit = "1cdb703197b41d418e7ce686e74c7aad835ddb37";
    private const int Seed = 4242;

    private sealed record PlacementExport(
        string Id,
        string AssetId,
        string AssetPath,
        float[] Translation,
        float[] Rotation,
        float SolverX,
        float SolverY,
        float SolverOrientationRadians);

    private sealed record LayoutExport(
        string Solver,
        string UpstreamCommit,
        int Seed,
        float RoomWidth,
        float RoomDepth,
        float RoomHeight,
        float[] SouthDoor,
        PlacementExport[] Placements);

    public static int Main(string[] args)
    {
        if (args.Length != 2)
        {
            Console.Error.WriteLine("Usage: Runner <tavern.xml> <layout.json>");
            return 2;
        }

        var models = new List<string>
        {
            "bar_section_a", "bar_section_b",
            "customer_stool", "customer_stool", "customer_stool", "customer_stool",
            "dining_table",
            "dining_chair", "dining_chair", "dining_chair", "dining_chair",
            "kitchen_counter", "kitchen_stove", "kitchen_fridge"
        };
        var room = new Room(
            16f, 12f, 3f,
            new List<float[]> { new[] { 0f, -6f, 1.2f, (float)(Math.PI / 2) } },
            new List<float[]>());

        var placements = new Furnisher(args[0]).GeneratePlacements(room, models, Seed);
        Console.WriteLine($"requested={models.Count} placed={placements.Length} seed={Seed}");
        if (placements.Length != models.Count)
        {
            Console.Error.WriteLine("FittingPlacer returned an incomplete layout; JSON was not written.");
            return 1;
        }

        var assetByModel = new Dictionary<string, (string Id, string Path)>
        {
            ["bar_section_a"] = ("bar_section_a", "res://assets/kitchencounter_straight_A.gltf"),
            ["bar_section_b"] = ("bar_section_b", "res://assets/kitchencounter_straight_A.gltf"),
            ["customer_stool"] = ("customer_stool", "res://assets/chair_stool.gltf"),
            ["dining_table"] = ("dining_table", "res://assets/table_round_A.gltf"),
            ["dining_chair"] = ("dining_chair", "res://assets/chair_A.gltf"),
            ["kitchen_counter"] = ("kitchen_counter", "res://assets/kitchencounter_straight_A.gltf"),
            ["kitchen_stove"] = ("kitchen_stove", "res://assets/stove_single.gltf"),
            ["kitchen_fridge"] = ("kitchen_fridge", "res://assets/fridge_A.gltf")
        };
        var indices = new Dictionary<string, int>();
        var output = placements.Select(placement =>
        {
            var modelId = placement.RepresentationObject.FittingModelId;
            var asset = assetByModel[modelId];
            indices.TryGetValue(asset.Id, out var previous);
            var index = previous + 1;
            indices[asset.Id] = index;
            return new PlacementExport(
                $"{asset.Id}_{index:00}", asset.Id, asset.Path,
                new[] { placement.PositionX, 0f, placement.PositionY },
                new[] { 0f, -placement.Orientation, 0f },
                placement.PositionX, placement.PositionY, placement.Orientation);
        }).ToArray();

        var export = new LayoutExport(
            "FittingPlacer", UpstreamCommit, Seed, 16f, 12f, 3f,
            new[] { 0f, -6f, 1.2f, 90f }, output);
        var json = JsonSerializer.Serialize(export, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
        });
        File.WriteAllText(args[1], json + Environment.NewLine);
        foreach (var placement in output)
        {
            Console.WriteLine($"{placement.Id}: ({placement.SolverX:F3},{placement.SolverY:F3}) rot={placement.SolverOrientationRadians:F3}rad");
        }
        Console.WriteLine($"json={Path.GetFullPath(args[1])}");
        return 0;
    }
}
