local mod={
    Services={
        ReplicatedStorage=game:GetService("ReplicatedStorage"),
        InsertService=game:GetService("InsertService"),
        HttpService=game:GetService("HttpService"),
        GeometryService=game:GetService("GeometryService"),
    },
    modules={
        b64=require(script.Parent.Base64), --b64
        json=require(script.Parent.JSON), --json
        modelAssembler=nil, --populated at runtime
        icloud=nil, --populated at runtime
    },
    parseUrl=nil,
    debug_mode=false, --prints additional stuff to console
};

function print_if_debug(...)
    if mod.debug_mode then
        print(...);
    end;
end;
function BufferedReader(source:string,allowOverflows:boolean)
    local stream={};
    stream.length=string.len(source);
    stream.source=source;
    stream.offset=0;
    stream.isFinished = false;
    stream.lastUnreadBytes = 0;
    stream.allowOverflows = (allowOverflows~=nil) and allowOverflows or false;
    function stream:read(len:number,shift:boolean)
        shift=(shift~=nil) and shift or true;
        len=len or 1;
        local data=self.source:sub(self.offset+1,self.offset+len);
        local dataLength = string.len(data);
        local unreadBytes = len - dataLength;
        if unreadBytes>0 and not self.allowOverflows then
            error("Buffer went out of bounds and allowOverflows is false");
        end;
        if shift then
            self:seek(len);
        end;
        self.lastUnreadBytes = unreadBytes;
        return data;
    end;
    function stream:peek(len:number)
        len=len or 1;
        local data=self.source:sub(self.offset+1,self.offset+len);
        local dataLength = string.len(data);
        local unreadBytes = len - dataLength;
        if unreadBytes>0 and not self.allowOverflows then
            error("Buffer went out of bounds and allowOverflows is false");
        end;
        self.lastUnreadBytes = unreadBytes;
        return data;
    end;
    function stream:seek(len)
        len=len or 1;
        self.offset = math.clamp(self.offset + len, 0, self.length);
        self.isFinished = self.offset >= self.length;
    end;
    function stream:append(data)
        self.source..=data;
        self.length=string.len(self.source)
        self:seek(0); --recalc isFinished flag
    end;
    function stream:toEnd()
        self:seek(self.length);
    end;
    function stream:reset()
        self.offset=0;
        self.isFinished=false;
    end;
    function stream:readNumber(fmt,shift:boolean)
        fmt=fmt or "I1";
        local numSize=string.packsize(fmt);
        local chunk=self:read(numSize,shift);
        local n=string.unpack(fmt,chunk);
        return n;
    end;
    return stream;
end;
function Mesh(buf)
    local vertexCount=buf:readNumber("<I4");
    print_if_debug("Vertex Float Count:",vertexCount);
    buf:readNumber("<I4");
    vertexCount=vertexCount/3;--stores number of floats so we must make it 3 times smaller
    print_if_debug("Vertex Count:",vertexCount);
    local mesh={
        VertexCount=vertexCount,
        Verticies={},
        FaceNorms={},
    };
    for i=1,vertexCount do
        mesh.Verticies[i]=Vector3.new(buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f"));
    end;
    local faceCount=buf:readNumber("<I4");
    faceCount=faceCount/3;--stores number of floats so we must make it 3 times smaller
    for i=1,vertexCount do
        mesh.FaceNorms[i]={buf:readNumber("<I4"),buf:readNumber("<I4"),buf:readNumber("<I4")};
    end;
    return mesh;
end;
function mod:applyAssetId(assetId:string,isIntersection,isExperimental)
    local loadable=nil;
    local cache=script:FindFirstChild("UnionCache") or Instance.new("Folder",script);
    cache.Name="UnionCache";
    if typeof(assetId)=="string" then
        local id=assetId:match("(%d+)$");
        if id then
            local assetIdToLoad=tonumber(id);
            local childData=self.modules.icloud:loadSolidModel(assetIdToLoad);
            if not childData then
                warn("Failed to load SolidModel asset with ID "..tostring(assetIdToLoad)..". Make sure the asset ID is correct and the asset is a valid SolidModel.");
                return nil;
            end;
            local findCache=cache:FindFirstChild(id);
            if findCache then
                loadable=findCache:GetChildren()[1]:Clone();
            else
                loadable=(isExperimental) and self:applyChildDataNew(childData,isIntersection) or self:applyChildData(childData,isIntersection);
                local cached=Instance.new("Model",cache);
                cached.Name=id;
                loadable:Clone().Parent=cached;
            end;
        else
            warn("Asset ID is not valid. Make sure you have the correct asset ID for the union you want to insert.");
        end;
    else
        return error("Invalid Asset URI, expected string, got",typeof(assetId))
    end;
    return loadable;
end;
function mod:parseVarientData(data:string,isIntersection,isExperimental)
    local buf=BufferedReader(self.modules.b64.decode(data));
    local magic=buf:read(6);
    local ver=string.byte(buf:read());
    print_if_debug("CSGv"..tostring(ver));
    if magic=="CSGPHS" then
        buf:read(4);
        local meshmagic="\x10\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x10\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x80\x3f";
        if ver==7 then
            local meshes={};
            local volume=buf:readNumber("<f");
            local cog=Vector3.new(buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f"));
            local moi={buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f"),buf:readNumber("<f")}
            print_if_debug("[ PhysInfo ]");
            print_if_debug("Volume:", volume);
            print_if_debug("COG:",cog);
            print_if_debug("MOI:",moi);
            print_if_debug("[ MeshInfo ]");
            local parsingMeshes=true;
            while parsingMeshes do
                task.wait();
                local suc,res=pcall(function()
                    local magic=buf:read(string.len(meshmagic));
                    if magic==meshmagic then
                        return Mesh(buf);
                    end;
                    return nil;
                end);
                if not suc then
                    parsingMeshes=false;
                else
                    table.insert(meshes,res);
                end;
            end;
        end;
    elseif magic=="CSGMDL" then
    elseif magic=="<roblo" then -- this ones a bit odd, MeshData2 can contain a RBXM blob, so we have to check for it
        return (isExperimental) and self:applyChildDataNew(data,isIntersection) or self:applyChildData(data,isIntersection);
    end;
end;
function mod:applyAssetData(assetData:string,isIntersection,isExperimental)
    print("asset data called");
    local suc,res=pcall(function()
        local response=self.Services.HttpService:RequestAsync({
            Url=self.parseUrl,
            Method="POST",
            Headers={
                ["Accept"]="application/json",
            },
            Body=assetData,
        });
        if response.Success then
            return self.modules.json.decode(response.Body);
        else
            return error("Could not fetch. Request Error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")\nWhat went wrong:\n"..response.Body);
        end;
    end);
    local childData=nil;
    if suc then
        if res~=nil then
            print_if_debug(res);
            if res.tree then
                local instance=res.tree[1];
                if instance then
                    childData=instance.properties.ChildData.value;
                end;
            else
                mod:logMsg("error","Failed to parse asset data: No tree data.");
            end;
        else
            mod:logMsg("error","Failed to parse asset data: No response data.");
        end;
    else
        warn("Failed to get data: "..res);
    end;
    if not childData then
        return nil;
    end;
    return (isExperimental) and self:applyChildDataNew(childData,isIntersection) or self:applyChildData(childData,isIntersection);
end;
--
function mod:parsePhysicsData(physdata:string)
    local buf=BufferedReader(self.modules.b64.decode(physdata));
    if buf:read(6)=="CSGPHS" then
        local hull_type=buf:readNumber(">I4");
        if hull_type==6 then
            print("TYPE: Constructive Hull");
            local volume=buf:readNumber(">f");
            local CENTER_OF_GRAVITY=Vector3.new(buf:readNumber(">f"),buf:readNumber(">f"),buf:readNumber(">f"));
            print(CENTER_OF_GRAVITY);
        elseif hull_type==0 then
            print("TYPE: Block");
        end;
    end;
end;
function mod:createBuffer(source:string,allowOverflows:boolean)
    return BufferedReader(source,allowOverflows);
end;
local options={
    CollisionFidelity=Enum.CollisionFidelity.Default,
    RenderFidelity=Enum.RenderFidelity.Precise,
    SplitApart=false,
};

function centerUnionPivot(union,parent)
    local tempModel = Instance.new("Model");
    union.Parent = tempModel;
    tempModel.PrimaryPart = union;
    local boxCFrame,_=tempModel:GetBoundingBox();
    local centeredPart=Instance.new("Part",parent);
    centeredPart.Size=Vector3.new(0.001,0.001,0.001);
    centeredPart.CFrame=boxCFrame;
    centeredPart.Anchored=union.Anchored;
    centeredPart.Transparency=1;
    centeredPart.CanCollide=false;
    local new;
    if union:IsA("UnionOperation") then
        new=centeredPart:UnionAsync({union},options.CollisionFidelity,options.RenderFidelity);
    elseif union:IsA("PartOperation") then
        new=mod.Services.GeometryService:UnionAsync(centeredPart,{union},options)[1];
    end;
    union:SubstituteGeometry(new);
    new:Destroy();
    union.Parent=parent;
end;

function mod:applyChildData(childData,isIntersection)
    local suc,res=pcall(function()
        local response=self.Services.HttpService:RequestAsync({
            Url=self.parseUrl,
            Method="POST",
            Headers={
                ["Accept"]="application/json",
            },
            Body=childData,
        });
        if response.Success then
            return self.modules.json.decode(response.Body);
        else
            return error("Could not fetch. Request Error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")\nWhat went wrong:\n"..response.Body);
        end;
    end);
    if not suc then
        warn("Failed to get data: "..res);
    else
        print_if_debug(res);
        local model=self.modules.modelAssembler:buildAsset({modelData=res},self.Services.ReplicatedStorage);
        local tocheck=model:GetDescendants();
        for i=1,#tocheck do
            local inst=tocheck[i];
            if inst:IsA("BaseScript") then
                inst:Destroy();
                warn("Union ChildData attempted to include a script: ", inst:GetFullName());
            end;
        end;
        local function reconstruct(model:Model)
            local partToAttachTo=nil;
            local theparts=model:GetChildren();
            local negativeParts={};
            local parts={};
            if #theparts<1 then
                warn("Model has no children to union.");
                return nil;
            end;
            partToAttachTo=theparts[1];
            if partToAttachTo:GetAttribute("IsNegateOperation") then --fix orientation issues
                print_if_debug("found");
                table.insert(negativeParts,partToAttachTo);
                local old=partToAttachTo;
                partToAttachTo=Instance.new("Part");
                partToAttachTo.Size=Vector3.new(0.001,0.001,0.001);
                partToAttachTo.Position=old.Position
                partToAttachTo.Anchored=old.Anchored;
                partToAttachTo.Transparency=1;
                partToAttachTo.CanCollide=false;
                partToAttachTo.Name="UnionBasePart";
                partToAttachTo.Parent=model;
            end;
            local toConnect=model:GetChildren();
            for i=1,#toConnect do
                v=toConnect[i];
                if v:IsA("BasePart") and v~=partToAttachTo then
                    if v:GetAttribute("IsNegateOperation") then
                        print_if_debug("found");
                        table.insert(negativeParts,v);
                    else
                        table.insert(parts,v);
                    end;
                end;
            end;
            local old=partToAttachTo;
            local suc,Union=pcall(function()
                if isIntersection then
                    partToAttachTo=partToAttachTo:IntersectAsync(parts,Enum.CollisionFidelity.Default,Enum.RenderFidelity.Precise);
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo=old:IntersectAsync({partToAttachTo},Enum.CollisionFidelity.Default,Enum.RenderFidelity.Precise); -- this is odd but fixes the problems
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    centerUnionPivot(partToAttachTo,partToAttachTo.Parent);
                    old:Destroy();
                    return partToAttachTo;
                end;
                print_if_debug(parts);
                partToAttachTo=partToAttachTo:UnionAsync(parts,Enum.CollisionFidelity.Default,Enum.RenderFidelity.Precise);
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                old:Destroy();
                old=partToAttachTo;
                print_if_debug(negativeParts);
                if #negativeParts~=0 then
                    partToAttachTo=partToAttachTo:SubtractAsync(negativeParts,Enum.CollisionFidelity.Default,Enum.RenderFidelity.Precise);
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    old:Destroy();
                end;
                centerUnionPivot(partToAttachTo,partToAttachTo.Parent);
                return partToAttachTo;
            end);
            if not suc then
                warn("Union operation failed: "..tostring(Union));
                return nil;
            end;
            for i=1,#toConnect do
                v=toConnect[i];
                if v:IsA("BasePart") and v~=partToAttachTo then
                    v:Destroy();
                end;
            end;
            if not Union then
                warn("Union operation failed: No part was returned.");
                return nil;
            end;
            partToAttachTo.Parent=self.Services.ReplicatedStorage;
            model:Destroy();
            return partToAttachTo;
        end;
        return reconstruct(model);
    end;
end;

function mod:applyChildDataNew(childData,isIntersection)
    local suc,res=pcall(function()
        local response=self.Services.HttpService:RequestAsync({
            Url=self.parseUrl,
            Method="POST",
            Headers={
                ["Accept"]="application/json",
            },
            Body=childData,
        });
        if response.Success then
            return self.modules.json.decode(response.Body);
        else
            return error("Could not fetch. Request Error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")\nWhat went wrong:\n"..response.Body);
        end;
    end);
    if not suc then
        warn("Failed to get data: "..res);
    else
        print_if_debug(res);
        local model=self.modules.modelAssembler:buildAsset({modelData=res},self.Services.ReplicatedStorage);
        local tocheck=model:GetDescendants();
        for i=1,#tocheck do
            local inst=tocheck[i];
            if inst:IsA("BaseScript") then
                inst:Destroy();
                warn("Union ChildData attempted to include a script: ", inst:GetFullName());
            end;
        end;
        local function reconstruct(model)
            local partToAttachTo=nil;
            local theparts=model:GetChildren();
            local negativeParts={};
            local parts={};
            if #theparts<1 then
                warn("Model has no children to union.");
                return nil;
            end;
            partToAttachTo=theparts[1];
            if partToAttachTo:GetAttribute("IsNegateOperation") then --fix orientation issues
                print_if_debug("found");
                table.insert(negativeParts,partToAttachTo);
                local old=partToAttachTo;
                partToAttachTo=Instance.new("Part");
                partToAttachTo.Size=Vector3.new(0.001,0.001,0.001);
                partToAttachTo.Position=old.Position
                partToAttachTo.Anchored=old.Anchored;
                partToAttachTo.Transparency=1;
                partToAttachTo.CanCollide=false;
                partToAttachTo.Name="UnionBasePart";
                partToAttachTo.Parent=model;
            end;
            local toConnect=model:GetChildren();
            for i=1,#toConnect do
                v=toConnect[i];
                if v:IsA("BasePart") and v~=partToAttachTo then
                    if v:GetAttribute("IsNegateOperation") then
                        print_if_debug("found");
                        table.insert(negativeParts,v);
                    else
                        table.insert(parts,v);
                    end;
                end;
            end;
            local old=partToAttachTo;
            local suc,Union=pcall(function()
                if isIntersection then
                    partToAttachTo=self.Services.GeometryService:IntersectAsync(partToAttachTo,parts,options)[1];
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo=self.Services.GeometryService:IntersectAsync(old,{partToAttachTo},options)[1]; -- this is odd but fixes the problems
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    centerUnionPivot(partToAttachTo,partToAttachTo.Parent);
                    old:Destroy();
                    return partToAttachTo;
                end;
                print_if_debug(parts);
                partToAttachTo=self.Services.GeometryService:UnionAsync(partToAttachTo,parts,options)[1];
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                old:Destroy();
                old=partToAttachTo;
                print_if_debug(negativeParts);
                if #negativeParts~=0 then
                    partToAttachTo=self.Services.GeometryService:SubtractAsync(partToAttachTo,negativeParts,options)[1];
                    partToAttachTo.Parent=self.Services.ReplicatedStorage;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    old:Destroy();
                end;
                centerUnionPivot(partToAttachTo,partToAttachTo.Parent);
                return partToAttachTo;
            end);
            if not suc then
                warn("Union operation failed: "..tostring(Union));
                return nil;
            end;
            for i=1,#toConnect do
                v=toConnect[i];
                if v:IsA("BasePart") and v~=partToAttachTo then
                    v:Destroy();
                end;
            end;
            if not Union then
                warn("Union operation failed: No part was returned.");
                return nil;
            end;
            partToAttachTo.Parent=self.Services.ReplicatedStorage;
            model:Destroy();
            return partToAttachTo;
        end;
        return reconstruct(model);
    end;
end;

return mod;