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
    private sealed record Stage2RoomBrief(string Id, string Type);
    private sealed record Stage2ZoneBrief(string Id, string RoomId, string Type, int Tables = 0, int ChairsPerTable = 0, int Sections = 0, int Stools = 0);
    private sealed record Stage2Brief(string Location, int Seed, Stage2RoomBrief[] PhysicalRooms, Stage2ZoneBrief[] LogicalZones, string[][] Adjacency);
    private sealed record Placement(string id, string zoneId, string assetPath, float[] translation, float[] rotation);
    private sealed record Stage2Placement(string id, string zoneId, string assetId, string assetPath, float[] translation, float[] rotation);
    private sealed record Zone(string id, string type, float width, float depth, float originX, float originZ);
    private sealed record LegacyPlacement(string Id, string AssetId, string AssetPath, float[] Translation, float[] Rotation,
        float SolverX, float SolverY, float SolverOrientationRadians);

    public static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--stage1") return RunStage1(args[1..]);
        if (args.Length > 0 && args[0] == "--stage2") return RunStage2(args[1..]);
        return RunLegacy(args);
    }

    private static int RunStage2(string[] args)
    {
        if (args.Length != 3) { Console.Error.WriteLine("Usage: Runner --stage2 <brief.json> <layout.json> <semantics.xml>"); return 2; }
        var brief = JsonSerializer.Deserialize<Stage2Brief>(File.ReadAllText(args[0]), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        if (brief.PhysicalRooms.Length != 2 || brief.LogicalZones.Length != 2 || brief.Adjacency.Length != 1 || brief.Adjacency[0].Length != 2)
        { Console.Error.WriteLine("Stage 2 expects a hall+kitchen and exactly two logical hall zones."); return 2; }
        var hall = brief.PhysicalRooms.Single(r => r.Type == "public_hall");
        var kitchen = brief.PhysicalRooms.Single(r => r.Type == "kitchen");
        var dining = brief.LogicalZones.Single(z => z.Type == "dining" && z.RoomId == hall.Id);
        var bar = brief.LogicalZones.Single(z => z.Type == "bar" && z.RoomId == hall.Id);
        if (!brief.Adjacency[0].ToHashSet().SetEquals(new[] { hall.Id, kitchen.Id }) || dining.Tables < 1 || dining.ChairsPerTable != 4 || bar.Sections != 2 || bar.Stools != 4)
        { Console.Error.WriteLine("Stage 2 brief must connect hall+kitchen and request dining tables (4 chairs each), two bar sections, and four stools."); return 2; }

        const float grid = 0.1f, tablePitch = 7.0f;
        const float barSectionLength = 2.0f, barSectionDepth = 2.0419f, barWallGap = 0.9f;
        var columns = (int)Math.Ceiling(Math.Sqrt(dining.Tables));
        var rows = (int)Math.Ceiling((double)dining.Tables / columns);
        var diningWidth = columns * tablePitch + 1.0f;
        var diningDepth = rows * tablePitch + 1.0f;
        var staffSideDepth = barWallGap + barSectionDepth + 0.2f + 0.75f + 0.75f + 0.5f;
        var barRun = Math.Max(bar.Sections * barSectionLength, (bar.Stools - 1) * 0.75f + 0.75f);
        var barDepth = barRun + 2.0f * 0.9f + 0.2f;
        var barWidth = staffSideDepth;
        var hallWidth = diningWidth + barWidth;
        const float openCirculationGap = 1.2f;
        var hallDepth = diningDepth + barDepth + openCirculationGap;
        const float kitchenWidth = 8.0f;
        var kitchenDepth = MathF.Max(2.042f, MathF.Max(2.288f, 2.24f)) + 0.8f + 3.9f;
        var hallOriginX = -kitchenWidth / 2.0f;
        var kitchenOriginX = hallOriginX + hallWidth / 2.0f + kitchenWidth / 2.0f;
        var diningLocalX = -hallWidth / 2.0f + diningWidth / 2.0f;
        var diningLocalZ = -hallDepth / 2.0f + diningDepth / 2.0f;
        var barLocalX = hallWidth / 2.0f - barWidth / 2.0f;
        var barLocalZ = hallDepth / 2.0f - barDepth / 2.0f;
        var physicalZones = new[] {
            new Zone(hall.Id, hall.Type, hallWidth, hallDepth, hallOriginX, 0),
            new Zone(kitchen.Id, kitchen.Type, kitchenWidth, kitchenDepth, kitchenOriginX, 0)
        };
        var logicalZones = new[] {
            new Zone(dining.Id, dining.Type, diningWidth, diningDepth, hallOriginX + diningLocalX, diningLocalZ),
            new Zone(bar.Id, bar.Type, barWidth, barDepth, hallOriginX + barLocalX, barLocalZ)
        };
        var furnisher = new Furnisher(args[2]);
        var outputPlacements = new List<Stage2Placement>();

        var diningModels = new List<string>();
        for (var table = 0; table < dining.Tables; table++)
        {
            diningModels.Add("dining_table");
            for (var chair = 0; chair < dining.ChairsPerTable; chair++) diningModels.Add("dining_chair");
        }
        var diningResult = furnisher.GeneratePlacements(new Room(diningWidth, diningDepth, 3, grid), diningModels, brief.Seed);
        Console.WriteLine($"zone={dining.Id} requested={diningModels.Count} placed={diningResult.Length} seed={brief.Seed}");
        if (diningResult.Length != diningModels.Count) { Console.Error.WriteLine("Incomplete FittingPlacer dining result."); return 1; }
        AddStage2Placements(outputPlacements, diningResult, dining.Id, hallOriginX + diningLocalX, diningLocalZ);

        var barModels = new List<string> { "bar_section_a", "bar_section_b", "customer_stool", "customer_stool", "customer_stool", "customer_stool" };
        var barRoom = CreateBarRoom(hallWidth, hallDepth, barWidth, barDepth, grid);
        var barResult = furnisher.GeneratePlacements(barRoom, barModels, brief.Seed);
        Console.WriteLine($"zone={bar.Id} requested={barModels.Count} placed={barResult.Length} seed={brief.Seed}");
        if (barResult.Length != barModels.Count) { Console.Error.WriteLine("Incomplete FittingPlacer bar result."); return 1; }
        AddStage2Placements(outputPlacements, barResult, bar.Id, hallOriginX, 0);

        var kitchenModels = new List<string> { "kitchen_counter", "kitchen_stove", "kitchen_fridge" };
        var kitchenResult = furnisher.GeneratePlacements(new Room(kitchenWidth, kitchenDepth, 3, grid), kitchenModels, brief.Seed);
        Console.WriteLine($"zone={kitchen.Id} requested={kitchenModels.Count} placed={kitchenResult.Length} seed={brief.Seed}");
        if (kitchenResult.Length != kitchenModels.Count) { Console.Error.WriteLine("Incomplete FittingPlacer kitchen result."); return 1; }
        AddStage2Placements(outputPlacements, kitchenResult, kitchen.Id, kitchenOriginX, 0);

        if (!ValidateStage2(outputPlacements, dining.Tables, hallWidth, hallDepth, hallOriginX, kitchenOriginX)) return 1;

        var layout = new { solver = "FittingPlacer", upstreamCommit = UpstreamCommit, seed = brief.Seed, doorWidth = 1.4f,
            totalWidth = hallWidth + kitchenWidth, totalDepth = Math.Max(hallDepth, kitchenDepth), roomHeight = 3.0f,
            zones = physicalZones, logicalZones, placements = outputPlacements };
        File.WriteAllText(args[1], JsonSerializer.Serialize(layout, new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
        return 0;
    }

    private static Room CreateBarRoom(float hallWidth, float hallDepth, float barWidth, float barDepth, float grid)
    {
        var xSteps = (int)Math.Ceiling(hallWidth / grid);
        var zSteps = (int)Math.Ceiling(hallDepth / grid);
        var obstruction = new int[xSteps, zSteps];
        var maxHeight = new int[xSteps, zSteps];
        var minX = hallWidth / 2.0f - barWidth;
        var minZ = hallDepth / 2.0f - barDepth;
        for (var x = 0; x < xSteps; x++)
        for (var z = 0; z < zSteps; z++)
        {
            var worldX = -hallWidth / 2.0f + (x + 0.5f) * grid;
            var worldZ = -hallDepth / 2.0f + (z + 0.5f) * grid;
            if (worldX < minX || worldZ < minZ) obstruction[x, z] = -2;
        }
        // The bar solver gets the full physical hall envelope and its actual perimeter, with the
        // east partition split around the real kitchen doorway. The occupancy mask is not a wall.
        var eastSegmentLength = (hallDepth - 1.4f) / 2.0f;
        var walls = new List<Wall> {
            new(new Vector2D(0, hallDepth / 2.0f), hallWidth, 3),
            new(new Vector2D(0, -hallDepth / 2.0f), hallWidth, 1),
            new(new Vector2D(-hallWidth / 2.0f, 0), hallDepth, 0),
            new(new Vector2D(hallWidth / 2.0f, hallDepth / 2.0f - eastSegmentLength / 2.0f), eastSegmentLength, 2),
            new(new Vector2D(hallWidth / 2.0f, -hallDepth / 2.0f + eastSegmentLength / 2.0f), eastSegmentLength, 2)
        };
        var door = new Door(new Vector2D(hallWidth / 2.0f, 0), 1.4f, 2);
        return new Room(hallWidth, hallDepth, 3, walls, new List<Door> { door }, new List<Window>(), obstruction, maxHeight, grid);
    }

    private static void AddStage2Placements(List<Stage2Placement> output, FittingPlacement[] source, string zoneId, float originX, float originZ)
    {
        var counts = new Dictionary<string, int>();
        foreach (var p in source)
        {
            var model = p.RepresentationObject.FittingModelId;
            var (assetId, path) = model switch
            {
                "dining_table" => ("dining_table", "res://assets/table_round_A.gltf"),
                "dining_chair" => ("dining_chair", "res://assets/chair_A.gltf"),
                "bar_section_a" or "bar_section_b" => (model, "res://assets/kitchencounter_straight_A.gltf"),
                "customer_stool" => ("customer_stool", "res://assets/chair_stool.gltf"),
                "kitchen_counter" => (model, "res://assets/kitchencounter_straight_A.gltf"),
                "kitchen_stove" => (model, "res://assets/stove_single.gltf"),
                "kitchen_fridge" => (model, "res://assets/fridge_A.gltf"),
                _ => throw new InvalidOperationException(model)
            };
            counts.TryGetValue(assetId, out var index);
            counts[assetId] = ++index;
            output.Add(new Stage2Placement($"{zoneId}_{assetId}_{index:00}", zoneId, assetId, path,
                new[] { p.PositionX + originX, 0f, p.PositionY + originZ }, new[] { 0f, -p.Orientation, 0f }));
        }
    }

    private static bool ValidateStage2(List<Stage2Placement> placements, int tableCount, float hallWidth, float hallDepth,
        float hallOriginX, float kitchenOriginX)
    {
        bool Fail(string message) { Console.Error.WriteLine("STAGE2 VALIDATION FAIL: " + message); return false; }
        int Count(string assetId) => placements.Count(p => p.assetId == assetId);
        if (Count("dining_table") != tableCount || Count("dining_chair") != tableCount * 4 || Count("bar_section_a") != 1 ||
            Count("bar_section_b") != 1 || Count("customer_stool") != 4 || Count("kitchen_counter") != 1 ||
            Count("kitchen_stove") != 1 || Count("kitchen_fridge") != 1)
            return Fail("furniture counts do not match the brief.");

        var tables = placements.Where(p => p.assetId == "dining_table").ToArray();
        var chairs = placements.Where(p => p.assetId == "dining_chair").ToArray();
        var chairsPerTable = new int[tables.Length];
        foreach (var chair in chairs)
        {
            var chairPosition = chair.translation;
            var nearest = tables.Select((table, index) => new { table, index, distance = DistanceXZ(chairPosition, table.translation) })
                .OrderBy(candidate => candidate.distance).First();
            if (nearest.distance < 1.7f || nearest.distance > 2.6f) return Fail("a dining chair is not at a usable table edge.");
            chairsPerTable[nearest.index]++;
            var yaw = chair.rotation[1];
            var towardX = nearest.table.translation[0] - chairPosition[0];
            var towardZ = nearest.table.translation[2] - chairPosition[2];
            var length = MathF.Sqrt(towardX * towardX + towardZ * towardZ);
            var frontX = -MathF.Sin(yaw);
            var frontZ = -MathF.Cos(yaw);
            if ((frontX * towardX + frontZ * towardZ) / length < 0.75f) return Fail("a dining chair front is not facing its nearest table.");
        }
        if (chairsPerTable.Any(count => count != 4)) return Fail("each dining table must have four chairs.");

        var barSections = placements.Where(p => p.assetId.StartsWith("bar_section_", StringComparison.Ordinal)).ToArray();
        var eastWallX = hallOriginX + hallWidth / 2.0f;
        var barYaw = barSections[0].rotation[1];
        if (barSections.Any(section => MathF.Cos(section.rotation[1] - barYaw) < 0.99f))
            return Fail("the counter sections do not share the same facing orientation.");
        var runsAlongZ = MathF.Abs(MathF.Sin(barYaw)) > 0.99f;
        var sectionCenters = barSections.Select(section => section.translation).ToArray();
        var wallClearance = 0.0f;
        var serviceWall = "";
        foreach (var section in barSections)
        {
            var (width, depth) = AssetFootprint(section.assetId);
            var yaw = section.rotation[1];
            var extentX = (MathF.Abs(MathF.Cos(yaw)) * width + MathF.Abs(MathF.Sin(yaw)) * depth) / 2.0f;
            var extentZ = (MathF.Abs(MathF.Sin(yaw)) * width + MathF.Abs(MathF.Cos(yaw)) * depth) / 2.0f;
            var gap = runsAlongZ ? eastWallX - (section.translation[0] + extentX) : hallDepth / 2.0f - (section.translation[2] + extentZ);
            if (gap + 0.01f < 0.9f || gap > 1.05f) return Fail($"bar staff clearance is {gap:F3} m behind the counter.");
            wallClearance = gap;
        }
        if (runsAlongZ && sectionCenters.Any(p => p[2] - 1.0f < 0.71f)) return Fail("the east-wall bar overlaps the kitchen doorway opening.");
        serviceWall = runsAlongZ ? "east" : "north";
        foreach (var stool in placements.Where(p => p.assetId == "customer_stool"))
        {
            var nearestBar = sectionCenters.OrderBy(position => DistanceXZ(stool.translation, position)).First();
            var towardX = nearestBar[0] - stool.translation[0];
            var towardZ = nearestBar[2] - stool.translation[2];
            var length = MathF.Sqrt(towardX * towardX + towardZ * towardZ);
            var frontX = -MathF.Sin(stool.rotation[1]);
            var frontZ = -MathF.Cos(stool.rotation[1]);
            if (length < 0.01f || (frontX * towardX + frontZ * towardZ) / length < 0.75f)
                return Fail("a customer stool is not facing the bar.");
        }

        var hallDoorX = eastWallX;
        foreach (var placement in placements)
        {
            var (width, depth) = AssetFootprint(placement.assetId);
            var yaw = placement.rotation[1];
            var extentX = (MathF.Abs(MathF.Cos(yaw)) * width + MathF.Abs(MathF.Sin(yaw)) * depth) / 2.0f;
            var extentZ = (MathF.Abs(MathF.Sin(yaw)) * width + MathF.Abs(MathF.Cos(yaw)) * depth) / 2.0f;
            var x = placement.translation[0];
            var z = placement.translation[2];
            if (x + extentX > hallDoorX - 1.6f && x - extentX < kitchenOriginX + 1.4f &&
                z + extentZ > -1.1f && z - extentZ < 1.1f)
                return Fail($"{placement.id} blocks the hall-to-kitchen door approach.");
        }
        Console.WriteLine($"STAGE2 VALIDATION PASS tables={tableCount} chairs={chairs.Length} bar_sections=2 stools=4 wall={serviceWall} staff_clearance={wallClearance:F3}m kitchen_doorway=clear chair_facing=ok stool_facing=ok");
        return true;
    }

    private static float DistanceXZ(float[] a, float[] b)
    {
        var dx = a[0] - b[0]; var dz = a[2] - b[2];
        return MathF.Sqrt(dx * dx + dz * dz);
    }

    private static (float Width, float Depth) AssetFootprint(string assetId) => assetId switch
    {
        "dining_table" => (3.0f, 3.0f),
        "dining_chair" => (0.75f, 0.797f),
        "bar_section_a" or "bar_section_b" or "kitchen_counter" => (2.0f, 2.0419f),
        "customer_stool" => (0.75f, 0.75f),
        "kitchen_stove" => (2.0f, 2.288f),
        "kitchen_fridge" => (2.0f, 2.24f),
        _ => throw new InvalidOperationException(assetId)
    };

    private static int RunStage1(string[] args)
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

    // Preserve the LAY-01/LAY-01B CLI and output contract used by generate.ps1/capture.ps1.
    private static int RunLegacy(string[] args)
    {
        if (args.Length is < 2 or > 3) { Console.Error.WriteLine("Usage: Runner <tavern.xml> <layout.json> [seed]"); return 2; }
        var seed = args.Length == 3 ? int.Parse(args[2]) : 4242;
        var models = new List<string> {
            "bar_section_a", "bar_section_b", "customer_stool", "customer_stool", "customer_stool", "customer_stool",
            "dining_table", "dining_chair", "dining_chair", "dining_chair", "dining_chair",
            "kitchen_counter", "kitchen_stove", "kitchen_fridge"
        };
        var room = new Room(16f, 12f, 3f, new List<float[]> { new[] { 0f, -6f, 1.2f, (float)(Math.PI / 2) } }, new List<float[]>());
        var generated = new Furnisher(args[0]).GeneratePlacements(room, models, seed);
        Console.WriteLine($"requested={models.Count} placed={generated.Length} seed={seed}");
        if (generated.Length != models.Count) { Console.Error.WriteLine("FittingPlacer returned an incomplete layout; JSON was not written."); return 1; }
        var assetByModel = new Dictionary<string, (string Id, string Path)> {
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
        var placements = generated.Select(p => {
            var model = p.RepresentationObject.FittingModelId;
            var asset = assetByModel[model];
            indices.TryGetValue(asset.Id, out var previous);
            var index = previous + 1;
            indices[asset.Id] = index;
            return new LegacyPlacement($"{asset.Id}_{index:00}", asset.Id, asset.Path,
                new[] { p.PositionX, 0f, p.PositionY }, new[] { 0f, -p.Orientation, 0f }, p.PositionX, p.PositionY, p.Orientation);
        }).ToArray();
        var output = new { solver = "FittingPlacer", upstreamCommit = UpstreamCommit, seed, roomWidth = 16f, roomDepth = 12f,
            roomHeight = 3f, southDoor = new[] { 0f, -6f, 1.2f, 90f }, placements };
        File.WriteAllText(args[1], JsonSerializer.Serialize(output, new JsonSerializerOptions {
            WriteIndented = true, PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
        }) + Environment.NewLine);
        return 0;
    }
}
