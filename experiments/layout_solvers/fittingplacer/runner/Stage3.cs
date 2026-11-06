using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Text.Json;
using FittingPlacer;

internal static class Stage3
{
    private sealed record RoomBrief(string Id, string Type, string Size = "standard");
    private sealed record ZoneBrief(string Id, string RoomId, string Type, int Tables = 0, int ChairsPerTable = 0,
        int Sections = 0, int Stools = 0, int Sofas = 0, int CoffeeTables = 0, int StorageObjects = 0);
    private sealed record Brief(string Location, int Seed, RoomBrief[] PhysicalRooms, ZoneBrief[] LogicalZones, string[][] Adjacency);
    private sealed record Rect(string id, string type, float width, float depth, float originX, float originZ);
    private sealed record Place(string id, string zoneId, string assetId, string assetPath, float[] translation, float[] rotation);
    private const float Grid = 0.1f;
    private const float DoorWidth = 1.4f;
    private const float Clearance = 0.9f;
    private const string Commit = "1cdb703197b41d418e7ce686e74c7aad835ddb37";

    public static int Run(string[] args)
    {
        if (args.Length != 3) { Console.Error.WriteLine("Usage: Runner --stage3 <brief.json> <layout.json> <semantics.xml>"); return 2; }
        var brief = JsonSerializer.Deserialize<Brief>(File.ReadAllText(args[0]), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        if (brief.PhysicalRooms.Length != 3 || brief.LogicalZones.Length != 4 || brief.Adjacency.Length != 2)
            return Fail("Stage 3 requires hall, kitchen, storeroom, and dining/bar/lounge/storage zones with two adjacencies.");
        var hall = brief.PhysicalRooms.SingleOrDefault(r => r.Type == "public_hall");
        var kitchen = brief.PhysicalRooms.SingleOrDefault(r => r.Type == "kitchen");
        var store = brief.PhysicalRooms.SingleOrDefault(r => r.Type == "storeroom");
        var dining = brief.LogicalZones.SingleOrDefault(z => z.Type == "dining" && z.RoomId == hall?.Id);
        var bar = brief.LogicalZones.SingleOrDefault(z => z.Type == "bar" && z.RoomId == hall?.Id);
        var lounge = brief.LogicalZones.SingleOrDefault(z => z.Type == "lounge" && z.RoomId == hall?.Id);
        var storage = brief.LogicalZones.SingleOrDefault(z => z.Type == "storage" && z.RoomId == store?.Id);
        if (hall is null || kitchen is null || store is null || dining is null || bar is null || lounge is null || storage is null ||
            dining.Tables < 1 || dining.ChairsPerTable != 4 || bar.Sections < 2 || bar.Stools < 1 || lounge.Sofas < 2 || lounge.CoffeeTables != 1 || storage.StorageObjects < 1 ||
            kitchen.Size is not ("standard" or "compact" or "generous") || store.Size is not ("standard" or "compact" or "large"))
            return Fail("Brief counts/types are invalid; dining needs four chairs per table, bar at least two sections, lounge at least two sofas/one table, and each room needs a supported size.");
        var edges = brief.Adjacency.Select(pair => pair.ToHashSet()).ToArray();
        if (!edges.Any(e => e.SetEquals(new[] { hall.Id, kitchen.Id })) || !edges.Any(e => e.SetEquals(new[] { kitchen.Id, store.Id })))
            return Fail("Physical room adjacency must connect hall to kitchen and kitchen to storeroom.");

        var columns = (int)Math.Ceiling(Math.Sqrt(dining.Tables));
        var rows = (int)Math.Ceiling((double)dining.Tables / columns);
        var diningW = columns * 7f + 1f;
        var diningD = rows * 7f + 1f;
        var staffSide = 0.9f + 2.0419f + 0.2f + 0.75f + 0.75f + 0.5f;
        var barRun = Math.Max(bar.Sections * 2f, (bar.Stools - 1) * 0.75f + 0.75f);
        // The KayKit counter run is laid along the zone depth; keep staff/customer aisles in width.
        var barW = staffSide;
        var barD = barRun + 2 * 0.9f + 0.2f;
        var loungeW = Math.Max(6.0f, lounge.Sofas * 2.5f + 1.0f);
        var loungeD = 5.5f + Math.Max(0, lounge.Sofas - 2) * 1.5f;
        var hallW = Math.Max(diningW + barW, loungeW + barW + 1.2f);
        var upperD = Math.Max(loungeD, barD);
        const float northCirculation = 3.0f;
        var hallD = diningD + upperD + 1.2f + northCirculation;
        var upperLocalZ = -hallD / 2 + diningD + 1.2f + upperD / 2;
        var kitchenW = kitchen.Size switch { "generous" => 12f, "compact" => 8f, _ => 9f };
        var kitchenD = kitchen.Size == "generous" ? 9f : MathF.Max(2.042f, MathF.Max(2.288f, 2.24f)) + 0.8f + 3.9f + 0.5f;
        var storeColumns = (int)Math.Ceiling(Math.Sqrt(storage.StorageObjects));
        var storeRows = (int)Math.Ceiling((double)storage.StorageObjects / storeColumns);
        var storeW = Math.Max(store.Size switch { "large" => 8.0f, "compact" => 5.0f, _ => 6.0f }, storeColumns * 2.0f + 2.0f);
        var storeD = Math.Max(store.Size switch { "large" => 7.0f, "compact" => 4.5f, _ => 5.5f }, storeRows * 1.8f + 2.0f);
        var storeDoorZ = 0f;
        var hallX = -(hallW + kitchenW + storeW) / 2 + hallW / 2;
        var kitchenX = hallX + hallW / 2 + kitchenW / 2;
        var storeX = kitchenX + kitchenW / 2 + storeW / 2;
        var rooms = new[] {
            new Rect(hall.Id, hall.Type, hallW, hallD, hallX, 0),
            new Rect(kitchen.Id, kitchen.Type, kitchenW, kitchenD, kitchenX, 0),
            new Rect(store.Id, store.Type, storeW, storeD, storeX, 0)
        };
        var logical = new[] {
            new Rect(dining.Id,dining.Type,diningW,diningD,hallX-hallW/2+diningW/2,-hallD/2+diningD/2),
            new Rect(bar.Id,bar.Type,barW,barD,hallX+hallW/2-barW/2,upperLocalZ),
            new Rect(lounge.Id,lounge.Type,loungeW,loungeD,hallX-hallW/2+loungeW/2,upperLocalZ),
            new Rect(storage.Id,storage.Type,storeW,storeD,storeX,0)
        };
        if (loungeW + barW + 1.2f > hallW + 0.01f) return Fail("Lounge and bar footprints do not fit their generated hall width.");

        var furnisher = new Furnisher(args[2]);
        var placements = new List<Place>();
        var diningModels = new List<string>();
        for (var i = 0; i < dining.Tables; i++) { diningModels.Add("dining_table"); for (var c = 0; c < 4; c++) diningModels.Add("dining_chair"); }
        var diningResult = furnisher.GeneratePlacements(new Room(diningW,diningD,3,Grid), diningModels, brief.Seed);
        if (!Append(diningResult,diningModels.Count,dining.Id,logical[0].originX,logical[0].originZ,placements)) return 1;

        var barModels = Enumerable.Range(0,bar.Sections).Select(i=>i%2==0?"bar_section_a":"bar_section_b").ToList();
        barModels.AddRange(Enumerable.Repeat("customer_stool",bar.Stools));
        var barResult = furnisher.GeneratePlacements(BarRoom(hallW,hallD,barW,barD,upperLocalZ),barModels,brief.Seed);
        var barShift=FitGroup(barResult,hallW/2-barW,hallW/2,upperLocalZ-barD/2,upperLocalZ+barD/2);
        if (!Append(barResult,barModels.Count,bar.Id,hallX+barShift.x,barShift.z,placements)) return 1;

        var kitchenModels = new List<string> { "kitchen_counter", "kitchen_stove", "kitchen_fridge" };
        var kitchenResult = furnisher.GeneratePlacements(new Room(kitchenW,kitchenD,3,Grid),kitchenModels,brief.Seed);
        var kitchenShift=FitGroup(kitchenResult,-kitchenW/2+0.25f,kitchenW/2-0.25f,-kitchenD/2+0.25f,kitchenD/2-0.25f);
        var kitchenWallX=kitchenX-kitchenW/2;
        var originalKitchenMinX=kitchenResult.Min(item=>item.PositionX-Extents(item.RepresentationObject.FittingModelId,item.Orientation).x)+kitchenShift.x+kitchenX;
        var kitchenEntryShift=Math.Max(0f,kitchenWallX+0.9f-originalKitchenMinX);
        if (!Append(kitchenResult,kitchenModels.Count,kitchen.Id,kitchenX+kitchenShift.x+kitchenEntryShift,kitchenShift.z,placements)) return 1;

        var loungeModels = new List<string> { "lounge_coffee_table" };
        for (var i=0;i<lounge.Sofas;i++) loungeModels.Add("lounge_sofa");
        var loungeResult = furnisher.GeneratePlacements(new Room(loungeW,loungeD,3,Grid),loungeModels,brief.Seed);
        if (!Append(loungeResult,loungeModels.Count,lounge.Id,logical[2].originX,logical[2].originZ,placements)) return 1;

        var storageModels = Enumerable.Range(0,storage.StorageObjects).Select(i=>i%2==0?"storeroom_crate":"storeroom_cabinet").ToList();
        for(var i=0;i<storageModels.Count;i+=4)storageModels[i]="storeroom_crate_potatoes";
        var storageResult = furnisher.GeneratePlacements(StorageRoom(storeW,storeD,storeDoorZ),storageModels,brief.Seed);
        if (!Append(storageResult,storageModels.Count,storage.Id,storeX,0,placements)) return 1;

        var storeDoorX=(kitchenX+kitchenW/2+storeX-storeW/2)/2;
        storeDoorZ=SelectDoorCenter(placements,new[]{kitchen.Id,storage.Id},storeDoorX,Math.Min(kitchenD,storeD)/2-DoorWidth/2-0.1f);
        if(float.IsNaN(storeDoorZ))return Fail("Could not find an unobstructed kitchen-to-storeroom doorway in the derived shared boundary.");
        var hallDoorX=(hallX+hallW/2+kitchenX-kitchenW/2)/2;
        var hallDoorZ=SelectKitchenDoorCenter(placements,new[]{dining.Id,bar.Id,lounge.Id,kitchen.Id},hallDoorX,Math.Min(hallD,kitchenD)/2-DoorWidth/2-0.1f);
        if(float.IsNaN(hallDoorZ))return Fail("Could not find an unobstructed hall-to-kitchen doorway in the derived shared boundary.");
        var entranceX=SelectEntranceCenter(placements,hallX,hallW,hallD);
        if(float.IsNaN(entranceX))return Fail("Could not find an unobstructed main entrance in the public hall.");
        if (!Validate(placements,dining.Tables,lounge.Sofas,storage.StorageObjects,rooms,logical,bar.Sections,bar.Stools,barW,barD,hallX,hallW,hallD,kitchenX,kitchenW,storeX,storeW,hallDoorZ,storeDoorZ)) return 1;
        var kitchenAccess=ValidateKitchenAccess(placements,rooms.Single(r=>r.id==kitchen.Id),hallDoorZ);
        if(kitchenAccess.width<0.9f||!kitchenAccess.reachable)return Fail("Kitchen entrance corridor or route to the working aisle is blocked.");
        var doors = new[] { new { from=hall.Id, to=kitchen.Id, width=DoorWidth, axis="x", centerZ=hallDoorZ }, new { from=kitchen.Id, to=store.Id, width=DoorWidth, axis="x", centerZ=storeDoorZ } };
        var layout = new { solver="FittingPlacer", upstreamCommit=Commit, seed=brief.Seed, totalWidth=hallW+kitchenW+storeW,
            totalDepth=Math.Max(hallD,Math.Max(kitchenD,storeD)), roomHeight=3f, doorWidth=DoorWidth, publicEntrance=new { axis="z", wall="south", centerX=entranceX, width=DoorWidth },
            kitchenAccess=new { entryCorridorWidth=kitchenAccess.width, workAreaReachable=kitchenAccess.reachable, route="around_furniture_front" }, rooms, zones=rooms,
            logicalZones=logical, doors, placements };
        File.WriteAllText(args[1],JsonSerializer.Serialize(layout,new JsonSerializerOptions{WriteIndented=true})+Environment.NewLine);
        Console.WriteLine($"STAGE3 PASS rooms={rooms.Length} dining_tables={dining.Tables} lounge_sofas={lounge.Sofas} storage_objects={storage.StorageObjects}");
        return 0;
    }

    private static Room BarRoom(float w,float d,float bw,float bd,float zoneCenterZ)
    {
        var nx=(int)Math.Ceiling(w/Grid); var nz=(int)Math.Ceiling(d/Grid); var block=new int[nx,nz]; var height=new int[nx,nz];
        var minX=w/2-bw; var minZ=zoneCenterZ-bd/2; var maxZ=zoneCenterZ+bd/2;
        for(var x=0;x<nx;x++) for(var z=0;z<nz;z++) { var wx=-w/2+(x+.5f)*Grid; var wz=-d/2+(z+.5f)*Grid; if(wx<minX||wz<minZ||wz>maxZ) block[x,z]=-2; }
        var seg=(d-DoorWidth)/2;
        var walls=new List<Wall>{new(new Vector2D(0,d/2),w,3),new(new Vector2D(0,-d/2),w,1),new(new Vector2D(-w/2,0),d,0),
            new(new Vector2D(w/2,d/2-seg/2),seg,2),new(new Vector2D(w/2,-d/2+seg/2),seg,2)};
        return new Room(w,d,3,walls,new List<Door>{new(new Vector2D(w/2,0),DoorWidth,2)},new List<Window>(),block,height,Grid);
    }
    private static Room StorageRoom(float w,float d,float doorZ)
    {
        var southLen=d/2+doorZ-DoorWidth/2; var northLen=d/2-doorZ-DoorWidth/2;
        var walls=new List<Wall>{new(new Vector2D(0,d/2),w,3),new(new Vector2D(0,-d/2),w,1),
            new(new Vector2D(-w/2,-d/2+southLen/2),southLen,0),new(new Vector2D(-w/2,doorZ+DoorWidth/2+northLen/2),northLen,0),new(new Vector2D(w/2,0),d,2)};
        var block=new int[(int)Math.Ceiling(w/Grid),(int)Math.Ceiling(d/Grid)]; var height=new int[block.GetLength(0),block.GetLength(1)];
        for(var x=0;x<block.GetLength(0);x++)for(var z=0;z<block.GetLength(1);z++)
        {
            var localX=-w/2+(x+0.5f)*Grid;var localZ=-d/2+(z+0.5f)*Grid;
            if(localX< -w/2+1.2f&&MathF.Abs(localZ-doorZ)<DoorWidth/2+0.2f)block[x,z]=-2;
        }
        return new Room(w,d,3,walls,new List<Door>{new(new Vector2D(-w/2,doorZ),DoorWidth,0)},new List<Window>(),block,height,Grid);
    }
    private static (float x,float z) FitGroup(FittingPlacement[] placements,float minBoundX,float maxBoundX,float minBoundZ,float maxBoundZ)
    {
        var xs=new List<(float min,float max)>();var zs=new List<(float min,float max)>();
        foreach(var p in placements)
        {
            var id=p.RepresentationObject.FittingModelId;
            var (w,d)=id switch {"kitchen_counter" or "bar_section_a" or "bar_section_b"=>(2f,2.0419f),"customer_stool"=>(.75f,.75f),"kitchen_stove"=>(2f,2.288f),"kitchen_fridge"=>(2f,2.24f),_=>throw new InvalidOperationException(id)};
            var yaw=p.Orientation;var ex=(MathF.Abs(MathF.Cos(yaw))*w+MathF.Abs(MathF.Sin(yaw))*d)/2;var ez=(MathF.Abs(MathF.Sin(yaw))*w+MathF.Abs(MathF.Cos(yaw))*d)/2;
            xs.Add((p.PositionX-ex,p.PositionX+ex));zs.Add((p.PositionY-ez,p.PositionY+ez));
        }
        var dx=0f;var dz=0f;var minX=xs.Min(v=>v.min);var maxX=xs.Max(v=>v.max);var minZ=zs.Min(v=>v.min);var maxZ=zs.Max(v=>v.max);
        if(maxX-minX>maxBoundX-minBoundX+0.01f||maxZ-minZ>maxBoundZ-minBoundZ+0.01f)throw new InvalidOperationException("The generated furniture group does not fit its planned zone.");
        dx=Math.Clamp(0f,minBoundX-minX,maxBoundX-maxX);
        dz=Math.Clamp(0f,minBoundZ-minZ,maxBoundZ-maxZ);
        return (dx,dz);
    }
    private static float SelectDoorCenter(List<Place> placements,string[] zoneIds,float wallX,float maxOffset)
    {
        var candidates=new List<float>{0};
        for(var step=1;step*Grid<=maxOffset;step++){candidates.Add(step*Grid);candidates.Add(-step*Grid);}
        foreach(var center in candidates)
        {
            var blocked=false;
            foreach(var item in placements.Where(p=>zoneIds.Contains(p.zoneId)))
            {
                var (ex,ez)=Extents(item);
                if(item.translation[0]+ex>wallX-0.15f&&item.translation[0]-ex<wallX+0.15f&&item.translation[2]+ez>center-DoorWidth/2&&item.translation[2]-ez<center+DoorWidth/2){blocked=true;break;}
            }
            if(!blocked)return center;
        }
        return float.NaN;
    }
    private static float SelectKitchenDoorCenter(List<Place> placements,string[] zoneIds,float wallX,float maxOffset)
    {
        var candidates=new List<float>{0};
        for(var step=1;step*Grid<=maxOffset;step++){candidates.Add(step*Grid);candidates.Add(-step*Grid);}
        var kitchen=placements.Where(p=>p.zoneId=="kitchen").ToArray();
        var viable=candidates.Where(center=>placements.Where(p=>zoneIds.Contains(p.zoneId)).All(item=>{
            var (ex,ez)=Extents(item);
            return !(item.translation[0]+ex>wallX-0.15f&&item.translation[0]-ex<wallX+0.15f&&item.translation[2]+ez>center-DoorWidth/2&&item.translation[2]-ez<center+DoorWidth/2);
        })).ToArray();
        return viable.OrderByDescending(center=>kitchen.Min(item=>{var (_,ez)=Extents(item);return MathF.Abs(item.translation[2]-center)-ez-DoorWidth/2;})).FirstOrDefault(float.NaN);
    }
    private static float SelectEntranceCenter(List<Place> placements,float hallX,float hallW,float hallD)
    {
        var candidates=new List<float>{hallX};
        for(var step=1;step*Grid<=hallW/2-DoorWidth/2-0.4f;step++){candidates.Add(hallX+step*Grid);candidates.Add(hallX-step*Grid);}
        return candidates.Where(center=>placements.Where(p=>p.zoneId is "dining" or "bar" or "lounge").All(item=>{
            var (ex,ez)=Extents(item);
            return !(item.translation[0]+ex>center-DoorWidth/2-0.15f&&item.translation[0]-ex<center+DoorWidth/2+0.15f&&item.translation[2]-ez<hallD/2*-1+0.15f);
        })).OrderBy(center=>MathF.Abs(center-hallX)).FirstOrDefault(float.NaN);
    }
    private static bool Append(FittingPlacement[] source,int requested,string zone,float ox,float oz,List<Place> dest)
    {
        Console.WriteLine($"zone={zone} requested={requested} placed={source.Length}"); if(source.Length!=requested){ Console.Error.WriteLine($"STAGE3 FAIL: Incomplete FittingPlacer result in {zone}."); return false; }
        var counts=new Dictionary<string,int>();
        foreach(var p in source)
        {
            var model=p.RepresentationObject.FittingModelId;
            var (id,path)=model switch {
                "dining_table"=>("dining_table","res://assets/table_round_A.gltf"), "dining_chair"=>("dining_chair","res://assets/chair_A.gltf"),
                "bar_section_a" or "bar_section_b"=>(model,"res://assets/kitchencounter_straight_A.gltf"), "customer_stool"=>("customer_stool","res://assets/chair_stool.gltf"),
                "kitchen_counter"=>(model,"res://assets/kitchencounter_straight_A.gltf"), "kitchen_stove"=>(model,"res://assets/stove_single.gltf"),
                "kitchen_fridge"=>(model,"res://assets/fridge_A.gltf"), "lounge_sofa"=>(model,"res://assets/couch.gltf"),
                "lounge_coffee_table"=>(model,"res://assets/table_medium.gltf"), "storeroom_cabinet"=>(model,"res://assets/cabinet_medium.gltf"),
                "storeroom_crate"=>(model,"res://assets/crate.gltf"), "storeroom_crate_potatoes"=>(model,"res://assets/crate_potatoes.gltf"), _=>throw new InvalidOperationException(model)};
            counts.TryGetValue(id,out var n); counts[id]=++n;
            dest.Add(new Place($"{zone}_{id}_{n:00}",zone,id,path,new[]{p.PositionX+ox,0f,p.PositionY+oz},new[]{0f,-p.Orientation,0f}));
        }
        return true;
    }
    private static bool Validate(List<Place> p,int tableCount,int sofas,int storage,Rect[] rooms,Rect[] logical,int barSections,int stools,float barW,float barD,float hallX,float hallW,float hallD,float kitchenX,float kitchenW,float storeX,float storeW,float hallDoorZ,float storeDoorZ)
    {
        bool Count(string id,int n)=>p.Count(x=>x.assetId==id)==n;
        var storageCount=p.Count(x=>x.zoneId=="storage"&&x.assetId.StartsWith("storeroom_"));
        if(!Count("dining_table",tableCount)||!Count("dining_chair",tableCount*4)||!Count("bar_section_a",(barSections+1)/2)||!Count("bar_section_b",barSections/2)||!Count("customer_stool",stools)||!Count("kitchen_counter",1)||!Count("kitchen_stove",1)||!Count("kitchen_fridge",1)||!Count("lounge_sofa",sofas)||!Count("lounge_coffee_table",1)||storageCount!=storage) { Console.Error.WriteLine("STAGE3 FAIL: Generated counts differ from the brief."); return false; }
        foreach(var r in rooms) if(r.width<=0||r.depth<=0){ Console.Error.WriteLine($"STAGE3 FAIL: Invalid physical boundary for {r.id}."); return false; }
        var table=p.Single(x=>x.assetId=="lounge_coffee_table");
        var facing=0;
        foreach(var sofa in p.Where(x=>x.assetId=="lounge_sofa")) { var dx=table.translation[0]-sofa.translation[0]; var dz=table.translation[2]-sofa.translation[2]; var len=MathF.Sqrt(dx*dx+dz*dz); var fx=-MathF.Sin(sofa.rotation[1]); var fz=-MathF.Cos(sofa.rotation[1]); if(len<0.1f||(fx*dx+fz*dz)/len<0.7f){ Console.Error.WriteLine("STAGE3 FAIL: A sofa does not face the lounge table."); return false; } facing++; }
        var sections=p.Where(x=>x.assetId.StartsWith("bar_section_")).ToArray(); var yaw=sections[0].rotation[1];
        if(sections.Any(s=>MathF.Cos(s.rotation[1]-yaw)<0.99f)){ Console.Error.WriteLine("STAGE3 FAIL: Bar section orientation mismatch."); return false; }
        var hallRight=hallX+hallW/2; var hallLeft=hallX-hallW/2; var hallNorth=hallD/2; var hallSouth=-hallD/2;
        var staffGaps=new List<float>();
        foreach(var section in sections)
        {
            var (sx,sz)=Extents(section); var alongZ=MathF.Abs(MathF.Sin(section.rotation[1]))>0.99f;
            var gaps=alongZ?new[]{hallRight-(section.translation[0]+sx),section.translation[0]-sx-hallLeft}:new[]{hallNorth-(section.translation[2]+sz),section.translation[2]-sz-hallSouth};
            var gap=gaps.Min(); if(gap+0.02f<0.9f)return FailBool($"Bar staff clearance is {gap:F3}m, below 0.9m."); staffGaps.Add(gap);
        }
        foreach(var cabinet in p.Where(x=>x.zoneId=="storage"&&x.assetId.StartsWith("storeroom_"))) { var yawC=cabinet.rotation[1]; var fx=-MathF.Sin(yawC); var fz=-MathF.Cos(yawC); if(MathF.Abs(fx)+MathF.Abs(fz)<0.99f){ Console.Error.WriteLine("STAGE3 FAIL: Storage furniture access orientation invalid."); return false; } }
        // The two openings are clear only if no furniture footprint intersects their 1.4m span.
        var zones=rooms.Concat(logical).GroupBy(r=>r.id).ToDictionary(g=>g.Key,g=>g.Last());
        var boxes=new List<(Place item,float x,float z)>();
        foreach(var item in p)
        {
            var (ex,ez)=Extents(item); var zone=zones[item.zoneId];
            if(item.translation[0]-ex<zone.originX-zone.width/2-0.05f||item.translation[0]+ex>zone.originX+zone.width/2+0.05f||item.translation[2]-ez<zone.originZ-zone.depth/2-0.05f||item.translation[2]+ez>zone.originZ+zone.depth/2+0.05f)
                return FailBool($"{item.id} exceeds its generated zone boundary: center=({item.translation[0]:F2},{item.translation[2]:F2}) extents=({ex:F2},{ez:F2}) zone={zone.id} origin=({zone.originX:F2},{zone.originZ:F2}) size={zone.width:F2}x{zone.depth:F2}.");
            foreach(var prior in boxes) if(MathF.Min(item.translation[0]+ex,prior.item.translation[0]+prior.x)-MathF.Max(item.translation[0]-ex,prior.item.translation[0]-prior.x)>0.05f&&MathF.Min(item.translation[2]+ez,prior.item.translation[2]+prior.z)-MathF.Max(item.translation[2]-ez,prior.item.translation[2]-prior.z)>0.05f)
                return FailBool($"Furniture overlap: {prior.item.id} and {item.id}.");
            boxes.Add((item,ex,ez));
        }
        if(!ValidateStorage(p,rooms[2]))return false;
        var doors=new[]{((hallX+hallW/2+kitchenX-kitchenW/2)/2,hallDoorZ,new[]{"dining","bar","lounge","kitchen"}),((kitchenX+kitchenW/2+storeX-storeW/2)/2,storeDoorZ,new[]{"kitchen","storage"})};
        foreach(var door in doors) foreach(var item in p.Where(i=>door.Item3.Contains(i.zoneId))) { var (ex,ez)=Extents(item); if(item.translation[0]+ex>door.Item1-0.1f&&item.translation[0]-ex<door.Item1+0.1f&&item.translation[2]+ez>door.Item2-DoorWidth/2&&item.translation[2]-ez<door.Item2+DoorWidth/2)return FailBool($"Furniture blocks a room doorway: {item.id} at ({item.translation[0]:F2},{item.translation[2]:F2}), door=({door.Item1:F2},{door.Item2:F2})."); }
        var staff=staffGaps.Min();
        Console.WriteLine($"counts PASS tables={tableCount} chairs={tableCount*4} sofas={facing} storage={storage} staff_clearance={staff:F3}m doorways=clear overlaps=none");
        return true;
    }
    private static bool ValidateStorage(List<Place> items,Rect room)
    {
        var cabinets=items.Where(p=>p.zoneId=="storage"&&p.assetId.StartsWith("storeroom_")).ToArray();
        foreach(var cabinet in cabinets)
        {
            var (ex,ez)=Extents(cabinet);
            var gaps=new[]{room.originZ+room.depth/2-(cabinet.translation[2]+ez),cabinet.translation[2]-ez-(room.originZ-room.depth/2),cabinet.translation[0]-ex-(room.originX-room.width/2),room.originX+room.width/2-(cabinet.translation[0]+ex)};
            var nearest=Array.IndexOf(gaps,gaps.Min());
            if(gaps[nearest]<-0.05f||gaps[nearest]>0.15f)return FailBool($"{cabinet.id} is not fitted along a storeroom wall.");
            var front=new Vector2(-MathF.Sin(cabinet.rotation[1]),-MathF.Cos(cabinet.rotation[1]));
            var toCenter=new Vector2(room.originX-cabinet.translation[0],room.originZ-cabinet.translation[2]);
            if(Vector2.Dot(front,toCenter)<=0)return FailBool($"{cabinet.id} faces away from the storeroom interior.");
            const float approach=0.9f;var right=new Vector2(MathF.Cos(cabinet.rotation[1]),-MathF.Sin(cabinet.rotation[1]));
            var halfDepth=cabinet.assetId=="storeroom_cabinet"?0.5f:1f;
            var cx=cabinet.translation[0]+front.X*(halfDepth+approach/2);var cz=cabinet.translation[2]+front.Y*(halfDepth+approach/2);
            var ax=(MathF.Abs(right.X)*2f+MathF.Abs(front.X)*approach)/2;var az=(MathF.Abs(right.Y)*2f+MathF.Abs(front.Y)*approach)/2;
            foreach(var other in items.Where(p=>p.zoneId=="storage"&&p.id!=cabinet.id))
            {
                var (ox,oz)=Extents(other);
                if(MathF.Min(cx+ax,other.translation[0]+ox)-MathF.Max(cx-ax,other.translation[0]-ox)>0.05f&&MathF.Min(cz+az,other.translation[2]+oz)-MathF.Max(cz-az,other.translation[2]-oz)>0.05f)
                    return FailBool($"Storage approach to {cabinet.id} is blocked by {other.id}.");
            }
        }
        Console.WriteLine($"storage PASS wall_aligned={cabinets.Length} accessible_fronts={cabinets.Length} crates={cabinets.Count(c=>c.assetId!="storeroom_cabinet")}");
        return true;
    }
    private static (float x,float z) Extents(Place p)
    {
        return Extents(p.assetId,p.rotation[1]);
    }
    private static (float x,float z) Extents(string id,float yaw)
    {
        var (w,d)=id switch {"dining_table"=>(3f,3f),"dining_chair"=>(.75f,.797f),"bar_section_a" or "bar_section_b" or "kitchen_counter"=>(2f,2.0419f),"customer_stool"=>(.75f,.75f),"kitchen_stove"=>(2f,2.288f),"kitchen_fridge"=>(2f,2.24f),"lounge_sofa"=>(3f,1.6f),"lounge_coffee_table"=>(2f,2f),"storeroom_cabinet"=>(2f,1f),"storeroom_crate" or "storeroom_crate_potatoes"=>(2f,2f),_=>throw new InvalidOperationException(id)};
        return ((MathF.Abs(MathF.Cos(yaw))*w+MathF.Abs(MathF.Sin(yaw))*d)/2,(MathF.Abs(MathF.Sin(yaw))*w+MathF.Abs(MathF.Cos(yaw))*d)/2);
    }
    private static (float width,bool reachable) ValidateKitchenAccess(List<Place> placements,Rect room,float doorZ)
    {
        const float walkRadius=0.4f;
        var kitchen=placements.Where(p=>p.zoneId=="kitchen").ToArray();
        var bounds=kitchen.Select(p=>{var e=Extents(p);return (minX:p.translation[0]-e.x,maxX:p.translation[0]+e.x,minZ:p.translation[2]-e.z,maxZ:p.translation[2]+e.z);}).ToArray();
        var wallX=room.originX-room.width/2;
        var corridorWidth=bounds.Min(b=>b.minX)-wallX;
        if(corridorWidth+0.001f<0.9f)return (corridorWidth,false);
        var minX=wallX+walkRadius+0.05f;var maxX=room.originX+room.width/2-walkRadius-0.05f;
        var minZ=room.originZ-room.depth/2+walkRadius+0.05f;var maxZ=room.originZ+room.depth/2-walkRadius-0.05f;
        var nx=(int)MathF.Floor((maxX-minX)/Grid)+1;var nz=(int)MathF.Floor((maxZ-minZ)/Grid)+1;
        var sx=(int)MathF.Round((wallX+0.45f-minX)/Grid);var sz=(int)MathF.Round((doorZ-minZ)/Grid);
        var counter=kitchen.Single(p=>p.assetId=="kitchen_counter");
        var tx=(int)MathF.Round((bounds.Max(b=>b.maxX)+0.45f-minX)/Grid);var tz=(int)MathF.Round((counter.translation[2]-minZ)/Grid);
        bool Open(int x,int z)
        {
            if(x<0||z<0||x>=nx||z>=nz)return false;
            var px=minX+x*Grid;var pz=minZ+z*Grid;
            return bounds.All(b=>px<b.minX-walkRadius||px>b.maxX+walkRadius||pz<b.minZ-walkRadius||pz>b.maxZ+walkRadius);
        }
        var seen=new bool[nx,nz];var q=new Queue<(int x,int z)>();
        if(!Open(sx,sz)||!Open(tx,tz))return (corridorWidth,false);
        q.Enqueue((sx,sz));seen[sx,sz]=true;var dirs=new[]{(1,0),(-1,0),(0,1),(0,-1)};
        while(q.Count>0){var (x,z)=q.Dequeue();if(x==tx&&z==tz){Console.WriteLine($"kitchen access PASS entry_corridor={corridorWidth:F3}m work_route=clear route=around_furniture_front");return (corridorWidth,true);}foreach(var (dx,dz) in dirs){var xx=x+dx;var zz=z+dz;if(xx>=0&&zz>=0&&xx<nx&&zz<nz&&!seen[xx,zz]&&Open(xx,zz)){seen[xx,zz]=true;q.Enqueue((xx,zz));}}}
        return (corridorWidth,false);
    }
    private static bool FailBool(string message){Console.Error.WriteLine("STAGE3 FAIL: "+message);return false;}
    private static int Fail(string message){Console.Error.WriteLine("STAGE3 FAIL: "+message);return 2;}
}
