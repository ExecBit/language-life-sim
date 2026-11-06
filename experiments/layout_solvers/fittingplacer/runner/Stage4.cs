using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

internal static class Stage4
{
    private const float Grid = 0.1f;
    private const float Radius = 0.4f;
    private sealed record Rect(string Id, float X0, float X1, float Z0, float Z1);
    private sealed record Target(string Id, float X, float Z, string Reason);

    public static int RunNegative(string[] args)
    {
        if(args.Length!=3)return Fail("Usage: Runner --stage4-negative <brief.json> <layout.json> <semantics.xml>");
        var testRoot=JsonNode.Parse("""
        {"rooms":[{"id":"hall","originX":0,"originZ":0,"width":8,"depth":8},{"id":"kitchen","originX":6.5,"originZ":0,"width":5,"depth":4},{"id":"storeroom","originX":11,"originZ":0,"width":4,"depth":4}],"doors":[{"from":"hall","to":"kitchen","centerZ":0,"width":1.4},{"from":"kitchen","to":"storeroom","centerZ":0,"width":1.4}],"placements":[],"mainEntrance":{"wall":"south","axis":"x","centerX":0,"centerZ":-4,"width":1.4}}
        """)!.AsObject();
        var normalPath=args[1]+".normal.tmp";
        var normal=ValidateRoot(testRoot.DeepClone().AsObject(),false,normalPath);
        if(normal["exitCode"]!.GetValue<int>()!=0)return Fail("Negative test fixture baseline could not traverse its clear doorway.");
        var normalReport=JsonNode.Parse(File.ReadAllText(normalPath))!;if(File.Exists(normalPath))File.Delete(normalPath);
        var blockedRoot=testRoot.DeepClone().AsObject();
        blockedRoot["testObstacles"]=new JsonArray(new JsonObject{["id"]="negative_hall_kitchen_door_blocker",["x0"]=4.85f,["x1"]=5.15f,["z0"]=-0.7f,["z1"]=0.7f});
        var negative=ValidateRoot(blockedRoot,true)["testReport"]!.AsObject();
        File.WriteAllText(args[1],negative.ToJsonString(new JsonSerializerOptions{WriteIndented=true}));
        var reportPath=args[1];var negativeReport=JsonNode.Parse(File.ReadAllText(reportPath))!;
        var normalDoor=normalReport["walkability"]!["targets"]!.AsArray().FirstOrDefault(n=>n!["target"]!.ToString()=="door_hall_kitchen");
        var doorResult=negativeReport["walkability"]!["targets"]!.AsArray().FirstOrDefault(n=>n!["target"]!.ToString()=="door_hall_kitchen");
        if(normalDoor==null||!normalDoor["reachable"]!.GetValue<bool>()||doorResult==null||doorResult["reachable"]!.GetValue<bool>()||negativeReport["diagnostic"]?.ToString()!="door_hall_kitchen")return Fail("Negative test failed: the valid baseline must traverse hall_kitchen and the test-only obstacle must block it.");
        Console.WriteLine("STAGE4 NEGATIVE PASS: test-only doorway obstacle makes door_hall_kitchen unreachable through normal validation.");return 0;
    }

    public static int Run(string[] args)
    {
        if (args.Length != 3) return Fail("Usage: Runner --stage4 <brief.json> <layout.json> <semantics.xml>");
        var temp = args[1] + ".stage3.tmp";
        var code = Stage3.Run(new[] { args[0], temp, args[2] });
        if (code != 0) { if (File.Exists(temp)) File.Delete(temp); return code; }
        var generatedRoot=JsonNode.Parse(File.ReadAllText(temp))!.AsObject();
        var hall=generatedRoot["rooms"]!.AsArray()[0]!.AsObject();
        var hallCenter=(float)hall["originX"]!;var hallSouth=(float)hall["originZ"]!-(float)hall["depth"]!/2;
        generatedRoot["mainEntrance"]=new JsonObject{["wall"]="south",["axis"]="x",["centerX"]=hallCenter,["centerZ"]=hallSouth,["width"]=1.4f};
        File.WriteAllText(temp,generatedRoot.ToJsonString(new JsonSerializerOptions{WriteIndented=true}));
        var validation=ValidateLayout(temp,args[1]);
        if(File.Exists(temp))File.Delete(temp);
        return validation;
    }

    private static int ValidateLayout(string inputPath,string outputPath)
    {
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(inputPath))!.AsObject();
            return ValidateRoot(root,false,outputPath)["exitCode"]!.GetValue<int>();
        }
        catch(Exception ex){return Fail("walkability validation error: "+ex.Message);}
    }

    private static JsonObject ValidateRoot(JsonObject root,bool negative,string outputPath="")
    {
        try
        {
            var rooms = root["rooms"]!.AsArray().Select(n => n!.AsObject()).ToArray();
            var hall = rooms[0]; var kitchen = rooms[1]; var store = rooms[2];
            float F(JsonObject o, string key) => (float)o[key]!;
            var entrance=root["mainEntrance"]!.AsObject();float entranceX=F(entrance,"centerX"), entranceZ=F(entrance,"centerZ");
            float hallX=F(hall,"originX"), hallZ=F(hall,"originZ"), hallW=F(hall,"width"), hallD=F(hall,"depth");
            float kitchenX=F(kitchen,"originX"), kitchenW=F(kitchen,"width"), kitchenD=F(kitchen,"depth");
            float storeX=F(store,"originX"), storeW=F(store,"width"), storeD=F(store,"depth");
            var placements=root["placements"]!.AsArray().Select(n=>n!.AsObject()).ToArray();
            var doors=root["doors"]!.AsArray();
            var bounds=new[]{new Rect("hall",hallX-hallW/2,hallX+hallW/2,hallZ-hallD/2,hallZ+hallD/2),new Rect("kitchen",kitchenX-kitchenW/2,kitchenX+kitchenW/2,-kitchenD/2,kitchenD/2),new Rect("storeroom",storeX-storeW/2,storeX+storeW/2,-storeD/2,storeD/2)};
            var wallPairs=new[]{(x:(hallX+hallW/2+kitchenX-kitchenW/2)/2,z:F(doors[0]!.AsObject(),"centerZ")),(x:(kitchenX+kitchenW/2+storeX-storeW/2)/2,z:F(doors[1]!.AsObject(),"centerZ"))};
            var barriers=new List<Rect>();
            foreach(var room in rooms)
            {
                var id=(string)room["id"]!;var x=F(room,"originX");var z=F(room,"originZ");var w=F(room,"width");var d=F(room,"depth");
                var southZ=z-d/2;var northZ=z+d/2;var eastX=x+w/2;var westX=x-w/2;
                if(id=="hall") barriers.Add(new Rect("hall_south_west",westX,entranceX-0.7f,southZ-0.1f,southZ+0.1f));
                else barriers.Add(new Rect(id+"_south",westX,eastX,southZ-0.1f,southZ+0.1f));
                barriers.Add(new Rect(id+"_north",westX,eastX,northZ-0.1f,northZ+0.1f));
                if(id=="hall")
                {
                    barriers.Add(new Rect("hall_south_east",entranceX+0.7f,eastX,southZ-0.1f,southZ+0.1f));
                    barriers.Add(new Rect("hall_west",westX-0.1f,westX+0.1f,z-d/2,z+d/2));
                }
                if(id=="kitchen")
                {
                    barriers.Add(new Rect("kitchen_west_south",westX-0.1f,westX+0.1f,z-d/2,wallPairs[0].z-0.7f));
                    barriers.Add(new Rect("kitchen_west_north",westX-0.1f,westX+0.1f,wallPairs[0].z+0.7f,z+d/2));
                    barriers.Add(new Rect("kitchen_east_south",eastX-0.1f,eastX+0.1f,z-d/2,wallPairs[1].z-0.7f));
                    barriers.Add(new Rect("kitchen_east_north",eastX-0.1f,eastX+0.1f,wallPairs[1].z+0.7f,z+d/2));
                    barriers.Add(new Rect("kitchen_south",westX,eastX,z-d/2-0.1f,z-d/2+0.1f));
                }
                if(id=="storeroom")
                {
                    barriers.Add(new Rect("store_west_south",westX-0.1f,westX+0.1f,z-d/2,wallPairs[1].z-0.7f));
                    barriers.Add(new Rect("store_west_north",westX-0.1f,westX+0.1f,wallPairs[1].z+0.7f,z+d/2));
                    barriers.Add(new Rect("store_south",westX,eastX,z-d/2-0.1f,z-d/2+0.1f));
                }
                if(id=="storeroom")barriers.Add(new Rect("store_east",eastX-0.1f,eastX+0.1f,z-d/2,z+d/2));
            }
            barriers.RemoveAll(b=>b.Id.StartsWith("kitchen_west",StringComparison.Ordinal)||b.Id.StartsWith("kitchen_east",StringComparison.Ordinal)||b.Id.StartsWith("store_west",StringComparison.Ordinal));
            barriers.Add(new Rect("hall_kitchen_wall_south",wallPairs[0].x-0.1f,wallPairs[0].x+0.1f,bounds[0].Z0-0.1f,wallPairs[0].z-0.7f));
            barriers.Add(new Rect("hall_kitchen_wall_north",wallPairs[0].x-0.1f,wallPairs[0].x+0.1f,wallPairs[0].z+0.7f,bounds[0].Z1+0.1f));
            barriers.Add(new Rect("kitchen_store_wall_south",wallPairs[1].x-0.1f,wallPairs[1].x+0.1f,bounds[1].Z0-0.1f,wallPairs[1].z-0.7f));
            barriers.Add(new Rect("kitchen_store_wall_north",wallPairs[1].x-0.1f,wallPairs[1].x+0.1f,wallPairs[1].z+0.7f,bounds[1].Z1+0.1f));
            var furniture=new List<Rect>();
            var placementObstacles=new List<Rect>();
            foreach(var p in placements)
            {
                var id=(string)p["id"]!;var asset=(string)p["assetId"]!;var t=p["translation"]!.AsArray();var r=p["rotation"]!.AsArray();
                float x=(float)t[0]!;float z=(float)t[2]!;float yaw=(float)r[1]!;
                var (w,d)=Footprint(asset);var ex=(MathF.Abs(MathF.Cos(yaw))*w+MathF.Abs(MathF.Sin(yaw))*d)/2;var ez=(MathF.Abs(MathF.Sin(yaw))*w+MathF.Abs(MathF.Cos(yaw))*d)/2;
                furniture.Add(new Rect(id,x-ex,x+ex,z-ez,z+ez));
                placementObstacles.Add(new Rect(id,x-ex,x+ex,z-ez,z+ez));
            }
            if(root["testObstacles"] is JsonArray injected)foreach(var item in injected){var obstacle=item!.AsObject();furniture.Add(new Rect((string)obstacle["id"]!,(float)obstacle["x0"]!,(float)obstacle["x1"]!,(float)obstacle["z0"]!,(float)obstacle["z1"]!));}
            var minX=Cell(bounds.Min(b=>b.X0)-0.2f);var maxX=Cell(bounds.Max(b=>b.X1)+0.2f);var minZ=Cell(bounds.Min(b=>b.Z0)-0.2f);var maxZ=Cell(bounds.Max(b=>b.Z1)+0.2f);
            var graph=new Dictionary<(int,int),HashSet<(int,int)>>();
            for(var ix=minX;ix<=maxX;ix++)for(var iz=minZ;iz<=maxZ;iz++)
            {
                var px=ix*Grid;var pz=iz*Grid;
                var inRoom=bounds.Any(b=>px>=b.X0&&px<=b.X1&&pz>=b.Z0&&pz<=b.Z1);
                var entranceApproach=MathF.Abs(px-entranceX)<=0.65f&&MathF.Abs(pz-(entranceZ+0.5f))<=Grid/2;
                var entranceOpeningCell=entranceApproach;
                var doorOpeningCell=wallPairs.Any(pair=>MathF.Abs(px-pair.x)<=0.15f&&MathF.Abs(pz-pair.z)<=0.7f);
                if(!inRoom&&!entranceOpeningCell&&!doorOpeningCell)continue;
                if(barriers.Any(b=>Inside(px,pz,b,Radius)&&!(entranceOpeningCell&&b.Id.StartsWith("hall_south",StringComparison.Ordinal)))||furniture.Any(b=>Inside(px,pz,b,Radius)))continue;
                graph[(ix,iz)]=new HashSet<(int,int)>();
            }
            foreach(var c in graph.Keys.ToArray())foreach(var dir in new[]{(1,0),(-1,0),(0,1),(0,-1)}){var n=(c.Item1+dir.Item1,c.Item2+dir.Item2);if(graph.ContainsKey(n))graph[c].Add(n);}
            // The only cells admitted through physical walls are the main entrance and shared door apertures.
            var entranceCell=(Cell(entranceX),Cell(entranceZ+0.5f));
            if(!graph.ContainsKey(entranceCell)){if(!negative)Fail("main_entrance blocked: no standing cell in the reserved interior approach.");var fail=new JsonObject{["exitCode"]=2,["testReport"]=new JsonObject{["diagnostic"]="main_entrance blocked"}};return fail;}
            var reached=new HashSet<(int,int)>{entranceCell};var queue=new Queue<(int,int)>();queue.Enqueue(entranceCell);
            while(queue.Count>0){var c=queue.Dequeue();foreach(var n in graph[c])if(reached.Add(n))queue.Enqueue(n);}
            var targets=new List<Target>();
            foreach(var p in placements)
            {
                var asset=(string)p["assetId"]!;var id=(string)p["id"]!;var t=p["translation"]!.AsArray();float x=(float)t[0]!;float z=(float)t[2]!;
                var yaw=(float)p["rotation"]![1]!;
                if(asset=="dining_table")
                {
                    var tableBox=placementObstacles.Single(b=>b.Id==id);
                    var chairCandidates=placements.Where(q=>(string)q["assetId"]! == "dining_chair").Where(q=>{
                        var ct=q["translation"]!.AsArray();var cr=(float)q["rotation"]![1]!;var front=FacingVector(cr,3);var cx=(float)ct[0]!;var cz=(float)ct[2]!;
                        var (chairWidth,chairDepth)=Footprint("dining_chair");var attachment=cx+front.X*(chairDepth/2+0.25f);var attachmentZ=cz+front.Y*(chairDepth/2+0.25f);
                        return attachment>=tableBox.X0-chairWidth/2-0.1f&&attachment<=tableBox.X1+chairWidth/2+0.1f&&attachmentZ>=tableBox.Z0-chairWidth/2-0.1f&&attachmentZ<=tableBox.Z1+chairWidth/2+0.1f;
                    }).ToArray();
                    int i=0;foreach(var chair in chairCandidates){var ct=chair["translation"]!.AsArray();var cr=chair["rotation"]!.AsArray();float cx=(float)ct[0]!;float cz=(float)ct[2]!;var back=FacingVector((float)cr[1]!,1);var chairDepth=Footprint("dining_chair").Item2;targets.Add(new Target($"{id}_chair_access_{++i}",cx+back.X*(chairDepth/2+Radius+0.1f),cz+back.Y*(chairDepth/2+Radius+0.1f),"associated chair pull-out side"));}
                }
                else if(asset=="bar_section_a"||asset=="bar_section_b")
                {
                    var barFront=FacingVector(yaw,3);var (width,depth)=Footprint(asset);var sideExtent=MathF.Abs(barFront.X)>0.5f?width/2:depth/2;var customer=new Vector2(x+barFront.X*(sideExtent+0.9f),z+barFront.Y*(sideExtent+0.9f));var staff=new Vector2(x-barFront.X*(sideExtent+0.9f),z-barFront.Y*(sideExtent+0.9f));
                    targets.Add(new Target(id+"_customer_side",customer.X,customer.Y,"counter customer front"));
                    targets.Add(new Target(id+"_staff_side",staff.X,staff.Y,"counter staff work side"));
                }
                else if(asset=="lounge_sofa") {var sofaFront=FacingVector(yaw,3);var (w,d)=Footprint(asset);var extent=MathF.Abs(sofaFront.X)>0.5f?w/2:d/2;targets.Add(new Target(id+"_front",x+sofaFront.X*(extent+0.4f),z+sofaFront.Y*(extent+0.4f),"sofa front clearance"));}
                else if(asset=="kitchen_counter"||asset=="kitchen_stove"||asset=="kitchen_fridge") {var workFront=FacingVector(yaw,3);var (w,d)=Footprint(asset);var extent=MathF.Abs(workFront.X)>0.5f?w/2:d/2;targets.Add(new Target(id+"_work_front",x+workFront.X*(extent+0.4f),z+workFront.Y*(extent+0.4f),"kitchen working front"));}
                else if(asset.StartsWith("storeroom_")) {var storageFront=FacingVector(yaw,3);var (w,d)=Footprint(asset);var extent=MathF.Abs(storageFront.X)>0.5f?w/2:d/2;targets.Add(new Target(id+"_storage_front",x+storageFront.X*(extent+0.9f),z+storageFront.Y*(extent+0.9f),"storage accessible front"));}
            }
            // Furniture interaction target checks are intentionally deferred for this checkpoint.
            var entranceOk=Enumerable.Range(-4,9).Any(offset=>{var c=(Cell(entranceX+offset*Grid),Cell(entranceZ+0.5f));return graph.ContainsKey(c)&&reached.Contains(c);});
            var roomTargets=new[]{
                (id:"hall_interior",room:bounds[0],x:hallX,z:entranceZ+2.0f),
                (id:"kitchen_door_inside",room:bounds[1],x:wallPairs[0].x+0.6f,z:wallPairs[0].z),
                (id:"kitchen_interior",room:bounds[1],x:kitchenX,z:0f),
                (id:"storeroom_door_inside",room:bounds[2],x:wallPairs[1].x+0.6f,z:wallPairs[1].z),
                (id:"storeroom_interior",room:bounds[2],x:storeX,z:0f)};
            var connectivity=new List<JsonObject>();bool roomsConnected=entranceOk;
            foreach(var item in roomTargets)
            {
                var candidate=graph.Keys.Where(c=>reached.Contains(c)&&item.room.X0+Radius<=c.Item1*Grid&&c.Item1*Grid<=item.room.X1-Radius&&item.room.Z0+Radius<=c.Item2*Grid&&c.Item2*Grid<=item.room.Z1-Radius)
                    .OrderBy(c=>Dist(c.Item1*Grid,c.Item2*Grid,item.x,item.z)).FirstOrDefault((int.MinValue,int.MinValue));
                var ok=candidate.Item1!=int.MinValue;roomsConnected &= ok;
                var px=ok?candidate.Item1*Grid:item.x;var pz=ok?candidate.Item2*Grid:item.z;
                var reason=ok?"reachable free cell in room":"no reachable free cell in room interior";
                connectivity.Add(JsonSerializer.SerializeToNode(new {target=item.id,reachable=ok,requestedPosition=new[]{item.x,item.z},standingPosition=ok?new[]{px,pz}:null,reason})!.AsObject());
                Console.WriteLine($"ROOM_CONNECTIVITY {(ok?"PASS":"FAIL")} target={item.id} requested=({item.x:F2},{item.z:F2}) actual={(ok?$"({px:F2},{pz:F2})":"none")} reason={reason}");
            }
            foreach(var door in doors)
            {
                var o=door!.AsObject();var center=F(o,"centerZ");var dx=(string)o["from"]=="hall"?wallPairs[0].x:wallPairs[1].x;
                var crossings=Enumerable.Range(-4,9).Select(k=>Cell(center+k*Grid)).Select(z=>Enumerable.Range(-5,11).All(k=>graph.ContainsKey((Cell(dx)+k,z)))).ToArray();
                var traversable=crossings.Any(v=>v);roomsConnected &= traversable;
                connectivity.Add(JsonSerializer.SerializeToNode(new {target=$"door_{(string)o["from"]}_{(string)o["to"]}",reachable=traversable,reason=traversable?"at least one complete 1.0 m cross-section has free adjacent cells":"no straight cross-section through door after wall and furniture clearance"})!.AsObject());
                Console.WriteLine($"ROOM_CONNECTIVITY {(traversable?"PASS":"FAIL")} target=door_{(string)o["from"]}_{(string)o["to"]} reason={(traversable?"clear adjacent-cell crossing":"opening obstructed in raster")}");
            }
            var validation=new {status=roomsConnected?"ROOM_CONNECTIVITY_PASS":"ROOM_CONNECTIVITY_FAIL",walkingRadius=Radius,gridResolution=Grid,roomConnectivity=connectivity,interactionTargets="DEFERRED"};
            WriteGridSvg(root,outputPath,graph,reached,minX,maxX,minZ,maxZ,bounds,barriers,furniture,entranceX,entranceZ,wallPairs,roomTargets);
            if(!roomsConnected)
            {
                root["walkability"]=JsonSerializer.SerializeToNode(validation);
                root["diagnostic"]="physical room connectivity failed";
                var serialized=root.ToJsonString(new JsonSerializerOptions{WriteIndented=true})+Environment.NewLine;
                if(negative)return new JsonObject{["exitCode"]=2,["testReport"]=JsonNode.Parse(serialized)};
                File.WriteAllText(outputPath,serialized);
                Fail(root["diagnostic"]!.ToString()+" is unreachable through the physical occupancy grid.");
                return new JsonObject{["exitCode"]=2,["testReport"]=JsonNode.Parse(serialized)};
            }
            root["walkability"]=JsonSerializer.SerializeToNode(validation);
            var passSerialized=root.ToJsonString(new JsonSerializerOptions{WriteIndented=true})+Environment.NewLine;
            if(!negative)File.WriteAllText(outputPath,passSerialized);
            Console.WriteLine($"ROOM CONNECTIVITY PASS doors=2 targets={connectivity.Count} grid={Grid:F1}m radius={Radius:F1}m; interaction targets deferred.");
            return new JsonObject{["exitCode"]=0,["testReport"]=JsonNode.Parse(passSerialized)};
        }
        catch(Exception ex){Fail("walkability validation error: "+ex.ToString());return new JsonObject{["exitCode"]=2,["testReport"]=new JsonObject{["diagnostic"]=ex.Message}};}
    }
    private static Vector2 FacingVector(float godotYaw,int solverFacing)
    {
        var angle=(solverFacing-3)*MathF.PI/2-godotYaw;
        return new Vector2(MathF.Cos(angle),MathF.Sin(angle));
    }
    private static void WriteGridSvg(JsonObject root,string layoutPath,Dictionary<(int,int),HashSet<(int,int)>> graph,HashSet<(int,int)> reached,int minX,int maxX,int minZ,int maxZ,Rect[] rooms,List<Rect> barriers,List<Rect> furniture,float entranceX,float entranceZ,(float x,float z)[] doors,(string id,Rect room,float x,float z)[] targets)
    {
        if(string.IsNullOrEmpty(layoutPath))return;
        var width=maxX-minX+1;var height=maxZ-minZ+1;const int scale=5;var svg=new StringBuilder();
        svg.AppendLine($"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width*scale+220}\" height=\"{height*scale+80}\" viewBox=\"0 0 {width*scale+220} {height*scale+80}\">");
        svg.AppendLine("<rect width=\"100%\" height=\"100%\" fill=\"#16191d\"/><g transform=\"translate(20,20)\" shape-rendering=\"crispEdges\">");
        svg.AppendLine($"<rect x=\"0\" y=\"0\" width=\"{width*scale}\" height=\"{height*scale}\" fill=\"#45494f\"/>");
        for(var ix=minX;ix<=maxX;ix++)for(var iz=minZ;iz<=maxZ;iz++)
        {
            var x=ix*Grid;var z=iz*Grid;var cell=(ix,iz);string color="";
            if(graph.ContainsKey(cell))color=reached.Contains(cell)?"#43b581":"#367da8";
            else if(barriers.Any(b=>Inside(x,z,b,Radius)))color="#d44c4c";
            else if(furniture.Any(b=>Inside(x,z,b,Radius)))color="#e19b3b";
            if(color.Length==0)continue;
            var sx=(ix-minX)*scale;var sy=(maxZ-iz)*scale;
            svg.Append($"<rect x=\"{sx}\" y=\"{sy}\" width=\"{scale}\" height=\"{scale}\" fill=\"{color}\"/>");
        }
        foreach(var room in rooms)
        {
            var x=(room.X0-minX*Grid)*scale;var y=(maxZ*Grid-room.Z1)*scale;
            svg.Append($"<rect x=\"{x:F1}\" y=\"{y:F1}\" width=\"{(room.X1-room.X0)/Grid*scale:F1}\" height=\"{(room.Z1-room.Z0)/Grid*scale:F1}\" fill=\"none\" stroke=\"#f3f3f3\" stroke-width=\"1\"/>");
            svg.Append($"<text x=\"{x+5:F1}\" y=\"{y+14:F1}\" fill=\"white\" font-size=\"11\">{System.Security.SecurityElement.Escape(room.Id)}</text>");
        }
        void Marker(float x,float z,string label,string color)
        {
            var sx=(x-minX*Grid)*scale;var sy=(maxZ*Grid-z)*scale;
            svg.Append($"<circle cx=\"{sx:F1}\" cy=\"{sy:F1}\" r=\"5\" fill=\"{color}\" stroke=\"white\" stroke-width=\"1\"/><text x=\"{sx+6:F1}\" y=\"{sy-5:F1}\" fill=\"white\" font-size=\"9\">{System.Security.SecurityElement.Escape(label)}</text>");
        }
        Marker(entranceX,entranceZ+0.5f,"entrance","#f2e85c");
        foreach(var d in doors)Marker(d.x,d.z,"door","#ff68c4");
        foreach(var t in targets)Marker(t.x,t.z,t.id,"#f2e85c");
        svg.AppendLine("</g>");
        var lx=width*scale+35;var ly=30;var legend=new[]{("reachable free","#43b581"),("unreachable free","#367da8"),("wall, radius expanded","#d44c4c"),("furniture, radius expanded","#e19b3b"),("outside room","#45494f"),("target / entrance","#f2e85c"),("door center","#ff68c4")};
        foreach(var item in legend){svg.Append($"<rect x=\"{lx}\" y=\"{ly}\" width=\"13\" height=\"13\" fill=\"{item.Item2}\"/><text x=\"{lx+20}\" y=\"{ly+11}\" fill=\"white\" font-size=\"11\">{item.Item1}</text>");ly+=22;}
        svg.AppendLine("</svg>");
        File.WriteAllText(Path.ChangeExtension(layoutPath,".occupancy.svg"),svg.ToString());
    }
    private static bool Inside(float x,float z,Rect r,float expand)=>x>r.X0-expand&&x<r.X1+expand&&z>r.Z0-expand&&z<r.Z1+expand;
    private static int Cell(float v)=>(int)MathF.Round(v/Grid);
    private static float Dist(float x,float z,float a,float b)=>MathF.Sqrt((x-a)*(x-a)+(z-b)*(z-b));
    private static (float,float) Footprint(string id)=>id switch{"dining_table"=>(3,3),"dining_chair"=>(.75f,.797f),"bar_section_a" or "bar_section_b" or "kitchen_counter"=>(2,2.0419f),"customer_stool"=>(.75f,.75f),"kitchen_stove"=>(2,2.288f),"kitchen_fridge"=>(2,2.24f),"lounge_sofa"=>(3,1.6f),"lounge_coffee_table"=>(2,2),"storeroom_cabinet"=>(2,1),_=>(2,2)};
    private static int Fail(string text){Console.Error.WriteLine("STAGE4 FAIL: "+text);return 2;}
}
