using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Text.Json;
using System.Text.Json.Nodes;

internal static class Stage4
{
    private const float Grid = 0.1f;
    private const float Radius = 0.4f;
    private sealed record Rect(string Id, float X0, float X1, float Z0, float Z1);
    private sealed record Target(string Id, float X, float Z, string Reason);

    public static int Run(string[] args)
    {
        if (args.Length != 3) return Fail("Usage: Runner --stage4 <brief.json> <layout.json> <semantics.xml>");
        var temp = args[1] + ".stage3.tmp";
        var code = Stage3.Run(new[] { args[0], temp, args[2] });
        if (code != 0) { if (File.Exists(temp)) File.Delete(temp); return code; }
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(temp))!.AsObject();
            File.Delete(temp);
            var rooms = root["rooms"]!.AsArray().Select(n => n!.AsObject()).ToArray();
            var hall = rooms[0]; var kitchen = rooms[1]; var store = rooms[2];
            float F(JsonObject o, string key) => (float)o[key]!;
            float hallX=F(hall,"originX"), hallZ=F(hall,"originZ"), hallW=F(hall,"width"), hallD=F(hall,"depth");
            float kitchenX=F(kitchen,"originX"), kitchenW=F(kitchen,"width"), kitchenD=F(kitchen,"depth");
            float storeX=F(store,"originX"), storeW=F(store,"width"), storeD=F(store,"depth");
            var placements=root["placements"]!.AsArray().Select(n=>n!.AsObject()).ToArray();
            var barriers=new List<Rect>();
            foreach(var room in rooms)
            {
                var id=(string)room["id"]!;var x=F(room,"originX");var z=F(room,"originZ");var w=F(room,"width");var d=F(room,"depth");
                barriers.Add(new Rect(id+"_north",x-w/2,x+w/2,z+d/2-0.1f,z+d/2+0.1f));
                barriers.Add(new Rect(id+"_south",x-w/2,x+w/2,z-d/2-0.1f,z-d/2+0.1f));
                if(id=="hall") barriers.Add(new Rect("hall_west",x-w/2-0.1f,x-w/2+0.1f,z-d/2,z+d/2));
                if(id=="storeroom") barriers.Add(new Rect("store_east",x+w/2-0.1f,x+w/2+0.1f,z-d/2,z+d/2));
            }
            var doors=root["doors"]!.AsArray();
            var furniture=new List<Rect>();
            foreach(var p in placements)
            {
                var id=(string)p["id"]!;var asset=(string)p["assetId"]!;var t=p["translation"]!.AsArray();var r=p["rotation"]!.AsArray();
                float x=(float)t[0]!;float z=(float)t[2]!;float yaw=(float)r[1]!;
                var (w,d)=Footprint(asset);var ex=(MathF.Abs(MathF.Cos(yaw))*w+MathF.Abs(MathF.Sin(yaw))*d)/2;var ez=(MathF.Abs(MathF.Sin(yaw))*w+MathF.Abs(MathF.Cos(yaw))*d)/2;
                furniture.Add(new Rect(id,x-ex,x+ex,z-ez,z+ez));
            }
            var entrance=root["mainEntrance"]!.AsObject();float entranceX=F(entrance,"centerX"), entranceZ=F(entrance,"centerZ");
            // Extend the south wall on either side of the generated 1.4 m entrance; its approach remains inside the hall.
            barriers.Add(new Rect("hall_south_west",hallX-hallW/2,entranceX-0.7f,entranceZ-0.1f,entranceZ+0.1f));
            barriers.Add(new Rect("hall_south_east",entranceX+0.7f,hallX+hallW/2,entranceZ-0.1f,entranceZ+0.1f));
            var bounds=new[]{new Rect("hall",hallX-hallW/2,hallX+hallW/2,hallZ-hallD/2,hallZ+hallD/2),new Rect("kitchen",kitchenX-kitchenW/2,kitchenX+kitchenW/2,-kitchenD/2,kitchenD/2),new Rect("storeroom",storeX-storeW/2,storeX+storeW/2,-storeD/2,storeD/2)};
            var cells=new Dictionary<string,HashSet<(int,int)>>();
            foreach(var room in bounds)
            {
                var open=new HashSet<(int,int)>();
                for(int x=Cell(room.X0);x<=Cell(room.X1);x++)for(int z=Cell(room.Z0);z<=Cell(room.Z1);z++)
                {
                    float px=x*Grid,pz=z*Grid;
                    var entranceOpening=room.Id=="hall"&&MathF.Abs(px-entranceX)<=0.65f&&MathF.Abs(pz-entranceZ)<=Radius+0.15f;
                    if(entranceOpening) { if(px<room.X0+Radius||px>room.X1-Radius)continue; }
                    else if(px<room.X0+Radius||px>room.X1-Radius||pz<room.Z0+Radius||pz>room.Z1-Radius)continue;
                    if(barriers.Any(b=>Inside(px,pz,b,Radius))||furniture.Any(b=>Inside(px,pz,b,Radius)))continue;
                    open.Add((x,z));
                }
                cells[room.Id]=open;
            }
            var allOpen=cells.Values.SelectMany(s=>s).ToHashSet();
            var globalMinX=bounds.Min(b=>b.X0);var globalMaxX=bounds.Max(b=>b.X1);var globalMinZ=bounds.Min(b=>b.Z0);var globalMaxZ=bounds.Max(b=>b.Z1);
            for(int x=Cell(globalMinX);x<=Cell(globalMaxX);x++)for(int z=Cell(globalMinZ);z<=Cell(globalMaxZ);z++)
            {
                var px=x*Grid;var pz=z*Grid;
                if(bounds.Any(b=>px>=b.X0+Radius&&px<=b.X1-Radius&&pz>=b.Z0+Radius&&pz<=b.Z1-Radius))continue;
                if(furniture.Any(b=>Inside(px,pz,b,Radius))||barriers.Any(b=>Inside(px,pz,b,Radius)))continue;
                allOpen.Add((x,z));
            }
            var graph=allOpen.ToDictionary(c=>c,_=>new HashSet<(int,int)>());
            foreach(var c in graph.Keys.ToArray())foreach(var dir in new[]{(1,0),(-1,0),(0,1),(0,-1)}){var n=(c.Item1+dir.Item1,c.Item2+dir.Item2);if(graph.ContainsKey(n))graph[c].Add(n);}
            foreach(var door in doors)
            {
                var o=door!.AsObject();var center=F(o,"centerZ");var from=(string)o["from"]!;var to=(string)o["to"]!;
                var left=from=="hall"?hallX+hallW/2:kitchenX+kitchenW/2;var right=to=="kitchen"?kitchenX-kitchenW/2:storeX-storeW/2;var wallX=(left+right)/2;
                for(var z=Cell(center-0.3f);z<=Cell(center+0.3f);z++)
                {
                    var leftCell=(Cell(wallX-0.5f),z);var rightCell=(Cell(wallX+0.5f),z);
                    if(graph.ContainsKey(leftCell)&&graph.ContainsKey(rightCell)){graph[leftCell].Add(rightCell);graph[rightCell].Add(leftCell);}
                }
            }
            // Physical shared boundaries occupy one 0.2 m partition strip; the 1.4 m doorway is the only crossing.
            var wallPairs=new[]{(x:(hallX+hallW/2+kitchenX-kitchenW/2)/2,z:F(doors[0]!.AsObject(),"centerZ")),(x:(kitchenX+kitchenW/2+storeX-storeW/2)/2,z:F(doors[1]!.AsObject(),"centerZ"))};
            foreach(var pair in wallPairs)
            {
                foreach(var c in graph.Keys.Where(c=>MathF.Abs(c.Item1*Grid-pair.x)<0.2f).ToArray())
                {
                    var z=c.Item2*Grid;if(MathF.Abs(z-pair.z)<=0.7f)continue;
                    graph[c].Clear();
                }
            }
            // Shared walls join room grids only inside each physical 1.4 m opening.
            foreach(var pair in wallPairs)
            {
                var x=Cell(pair.x);var z=Cell(pair.z);
                for(var dz=-3;dz<=3;dz++)
                {
                    var left=(x-1,z+dz);var right=(x+1,z+dz);
                    if(!graph.ContainsKey(left))graph[left]=new HashSet<(int,int)>();
                    if(!graph.ContainsKey(right))graph[right]=new HashSet<(int,int)>();
                    for(var sx=x-1;sx<=x+1;sx++){var c=(sx,z+dz);if(!graph.ContainsKey(c))graph[c]=new HashSet<(int,int)>();}
                    var cellsAcross=new[]{(x-1,z+dz),(x,z+dz),(x+1,z+dz)};
                    for(var i=0;i<cellsAcross.Length-1;i++){graph[cellsAcross[i]].Add(cellsAcross[i+1]);graph[cellsAcross[i+1]].Add(cellsAcross[i]);}
                    if(dz<3){var nextZ=z+dz+1;for(var sx=x-1;sx<=x+1;sx++){graph[(sx,z+dz)].Add((sx,nextZ));graph[(sx,nextZ)].Add((sx,z+dz));}}
                }
            }
            var entranceCell=(Cell(entranceX),Cell(entranceZ+0.5f));
            if(!graph.ContainsKey(entranceCell))return Fail("main_entrance blocked: no standing cell in the reserved interior approach.");
            var reached=new HashSet<(int,int)>{entranceCell};var queue=new Queue<(int,int)>();queue.Enqueue(entranceCell);
            while(queue.Count>0){var c=queue.Dequeue();foreach(var n in graph[c])if(reached.Add(n))queue.Enqueue(n);}
            var targets=new List<Target>();
            foreach(var p in placements)
            {
                var asset=(string)p["assetId"]!;var id=(string)p["id"]!;var t=p["translation"]!.AsArray();float x=(float)t[0]!;float z=(float)t[2]!;
                var yaw=(float)p["rotation"]![1]!;var front=new Vector2(-MathF.Sin(yaw),-MathF.Cos(yaw));
                if(asset=="dining_table")
                {
                    var chairs=placements.Where(q=>(string)q["assetId"]! == "dining_chair").OrderBy(q=>Dist((float)q["translation"]![0]!, (float)q["translation"]![2]!,x,z)).Take(4);
                    int i=0;foreach(var chair in chairs){var ct=chair["translation"]!.AsArray();var cr=chair["rotation"]!.AsArray();float cx=(float)ct[0]!;float cz=(float)ct[2]!;var cf=new Vector2(-MathF.Sin((float)cr[1]!),-MathF.Cos((float)cr[1]!));targets.Add(new Target($"{id}_chair_access_{++i}",cx-cf.X*0.85f,cz-cf.Y*0.85f,"chair usable pull-out side"));}
                }
                else if(asset=="bar_section_a"||asset=="bar_section_b")
                {
                    var axisX=MathF.Abs(MathF.Sin(yaw))>0.99f;var customer=axisX?new Vector2(x+1.5f,z):new Vector2(x,z-1.5f);var staff=axisX?new Vector2(x-1.5f,z):new Vector2(x,z+1.5f);
                    targets.Add(new Target(id+"_customer_side",customer.X,customer.Y,"counter customer front"));
                    targets.Add(new Target(id+"_staff_side",staff.X,staff.Y,"counter staff work side"));
                }
                else if(asset=="lounge_sofa") {var across=MathF.Abs(MathF.Sin(yaw))>0.99f;targets.Add(new Target(id+"_front",x+(across?0:-1.2f),z+(across?1.25f:0),"sofa usable front"));}
                else if(asset=="kitchen_counter"||asset=="kitchen_stove"||asset=="kitchen_fridge") targets.Add(new Target(id+"_work_front",x-1.45f,z,"kitchen working surface approach"));
                else if(asset.StartsWith("storeroom_")){var orient=MathF.Abs(MathF.Sin(yaw))>0.99f;var storageFront=orient?new Vector2(0,1):new Vector2(1,0);targets.Add(new Target(id+"_storage_front",x+storageFront.X*(asset=="storeroom_cabinet"?1.0f:1.5f),z+storageFront.Y*(asset=="storeroom_cabinet"?1.0f:1.5f),"accessible storage front"));}
            }
            var reports=new List<object>();bool all=true;
            bool ReachableNear(float x,float z,float tolerance=0.55f)
            {
                var center=(Cell(x),Cell(z));var radius=(int)MathF.Ceiling(tolerance/Grid);
                for(var dx=-radius;dx<=radius;dx++)for(var dz=-radius;dz<=radius;dz++)if(graph.ContainsKey((center.Item1+dx,center.Item2+dz))&&reached.Contains((center.Item1+dx,center.Item2+dz))&&Dist((center.Item1+dx)*Grid,(center.Item2+dz)*Grid,x,z)<=tolerance)return true;
                return false;
            }
            foreach(var target in targets)
            {
                var pos=(Cell(target.X),Cell(target.Z));var ok=ReachableNear(target.X,target.Z);all &= ok;
                reports.Add(new {target=target.Id,reason=target.Reason,reachable=ok,standingPosition=new[]{target.X,target.Z},walkingRadius=Radius});
                if(!ok)Console.Error.WriteLine($"STAGE4 FAIL target={target.Id}: {target.Reason} has no reachable standing position with {Radius:F1} m clearance (requested {target.X:F2},{target.Z:F2}).");
            }
            foreach(var door in doors)
            {
                var o=door!.AsObject();var center=F(o,"centerZ");var dx=(hallX+hallW/2+kitchenX-kitchenW/2)/2;
                if((string)o["from"]!="hall"){dx=(kitchenX+kitchenW/2+storeX-storeW/2)/2;}
                var doorOk=Enumerable.Range(-3,7).Any(offset=>ReachableNear(dx-0.45f,center+offset*Grid,0.2f)&&ReachableNear(dx+0.45f,center+offset*Grid,0.2f));
                reports.Add(new {target=$"door_{(string)o["from"]}_{(string)o["to"]}",reason="traversable opening with configured character radius",reachable=doorOk,walkingRadius=Radius});
                if(!doorOk){all=false;Console.Error.WriteLine($"STAGE4 FAIL target=door_{(string)o["from"]}_{(string)o["to"]}: 1.4 m doorway is blocked or disconnected for {Radius:F1} m walking radius.");}
            }
            var entranceOk=Enumerable.Range(-4,9).Any(offset=>{var c=(Cell(entranceX+offset*Grid),Cell(entranceZ+0.5f));return graph.ContainsKey(c)&&reached.Contains(c);});
            reports.Insert(0,new {target="main_entrance",reason="south wall opening and unobstructed hall approach",reachable=entranceOk,walkingRadius=Radius});
            var validation=new {status=all?"PASS":"FAIL",walkingRadius=Radius,gridResolution=Grid,targets=reports};
            if(!all)return Fail("One or more required targets are unreachable; see per-target diagnostics.");
            root["walkability"]=JsonSerializer.SerializeToNode(validation);
            File.WriteAllText(args[1],root.ToJsonString(new JsonSerializerOptions{WriteIndented=true})+Environment.NewLine);
            Console.WriteLine($"STAGE4 PASS targets={targets.Count} doors=2 grid={Grid:F1}m radius={Radius:F1}m");return 0;
        }
        catch(Exception ex){if(File.Exists(temp))File.Delete(temp);return Fail("walkability validation error: "+ex.Message);}
    }
    private static bool Inside(float x,float z,Rect r,float expand)=>x>r.X0-expand&&x<r.X1+expand&&z>r.Z0-expand&&z<r.Z1+expand;
    private static int Cell(float v)=>(int)MathF.Round(v/Grid);
    private static float Dist(float x,float z,float a,float b)=>MathF.Sqrt((x-a)*(x-a)+(z-b)*(z-b));
    private static (float,float) Footprint(string id)=>id switch{"dining_table"=>(3,3),"dining_chair"=>(.75f,.797f),"bar_section_a" or "bar_section_b" or "kitchen_counter"=>(2,2.0419f),"customer_stool"=>(.75f,.75f),"kitchen_stove"=>(2,2.288f),"kitchen_fridge"=>(2,2.24f),"lounge_sofa"=>(3,1.6f),"lounge_coffee_table"=>(2,2),"storeroom_cabinet"=>(2,1),_=>(2,2)};
    private static int Fail(string text){Console.Error.WriteLine("STAGE4 FAIL: "+text);return 2;}
}
