local Services={
    ReplicatedStorage=game:GetService("ReplicatedStorage"),
    InsertService=game:GetService("InsertService"),
    HttpService=game:GetService("HttpService"),
    GeometryService=game:GetService("GeometryService"),
};
local mod={
    _VERSION="8.0.0",
    modules={
        b64=require(script.Parent.Base64), --b64
        json=require(script.Parent.JSON), --json
        modelAssembler=nil, --populated at runtime
        icloud=nil, --populated at runtime
    },
    debug_mode=false, --prints additional stuff to console
};
local parseUrl=nil;
export type UnionOptions={
    CollisionFidelity:Enum.CollisionFidelity,
    RenderFidelity:Enum.RenderFidelity,
    SplitApart:boolean,
};

function print_if_debug(...)
    if mod.debug_mode then
        print(...);
    end;
end;
function mod:initialize(url)
    parseUrl=url;
end;
function mod:applyAssetId(assetId:string,options:UnionOptions,isIntersection,isExperimental)
    local loadable=nil;
    local cache=script:FindFirstChild("UnionCache") or Instance.new("Folder",script);
    cache.Name="UnionCache";
    if typeof(assetId)=="string" then
        local id=assetId:match("(%d+)$");
        if id then
            local assetIdToLoad=tonumber(id);
            local childData=self.modules.icloud:LoadSolidModel(assetIdToLoad);
            if not childData then
                warn("Failed to load SolidModel asset with ID "..tostring(assetIdToLoad)..". Make sure the asset ID is correct and the asset is a valid SolidModel.");
                return nil;
            end;
            local cacheName="Union_"..tostring(assetIdToLoad);
            local findCache=cache:FindFirstChild(cacheName);
            if findCache then
                loadable=findCache:Clone();
            else
                loadable=(isExperimental) and self:applyChildDataNew(childData,options,isIntersection) or self:applyChildData(childData,options,isIntersection);
                local cached=loadable:Clone();
                cached.Parent=cache;
                cached.Name=cacheName;
            end;
        else
            warn("Asset ID is not valid. Make sure you have the correct asset ID for the union you want to insert.");
        end;
    else
        return error("Invalid Asset URI, expected string, got",typeof(assetId))
    end;
    return loadable;
end;
function mod:applyAssetData(assetData:string,options:UnionOptions,isIntersection,isExperimental)
    print("asset data called");
    local suc,res=pcall(function()
        local response=Services.HttpService:RequestAsync({
            Url=parseUrl,
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
    return (isExperimental) and self:applyChildDataNew(childData,options,isIntersection) or self:applyChildData(childData,options,isIntersection);
end;
function centerUnionPivot(union,options:UnionOptions,parent)
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
        new=Services.GeometryService:UnionAsync(centeredPart,{union},options)[1];
    end;
    union:SubstituteGeometry(new);
    new:Destroy();
    union.Parent=parent;
end;

function mod:applyChildData(childData,options:UnionOptions,isIntersection)
    local suc,res=pcall(function()
        local response=Services.HttpService:RequestAsync({
            Url=parseUrl,
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
        local replicated=Services.ReplicatedStorage;
        local loadFolder=replicated:FindFirstChild("UnionOperationLoadCache") or Instance.new("Folder",replicated);
        loadFolder.Name="UnionOperationLoadCache";
        local model=self.modules.modelAssembler:buildAsset({modelData=res},loadFolder);
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
                    partToAttachTo=partToAttachTo:IntersectAsync(parts,options.CollisionFidelity,options.RenderFidelity);
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo=old:IntersectAsync({partToAttachTo},options.CollisionFidelity,options.RenderFidelity); -- this is odd but fixes the problems
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
                    old:Destroy();
                    return partToAttachTo;
                end;
                print_if_debug(parts);
                partToAttachTo=partToAttachTo:UnionAsync(parts,options.CollisionFidelity,options.RenderFidelity);
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                old:Destroy();
                old=partToAttachTo;
                print_if_debug(negativeParts);
                if #negativeParts~=0 then
                    partToAttachTo=partToAttachTo:SubtractAsync(negativeParts,options.CollisionFidelity,options.RenderFidelity);
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    old:Destroy();
                end;
                centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
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
            partToAttachTo.Parent=loadFolder;
            model:Destroy();
            return partToAttachTo;
        end;
        return reconstruct(model);
    end;
end;

function mod:applyChildDataNew(childData,options:UnionOptions,isIntersection)
    local suc,res=pcall(function()
        local response=Services.HttpService:RequestAsync({
            Url=parseUrl,
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
        local replicated=Services.ReplicatedStorage;
        local loadFolder=replicated:FindFirstChild("UnionOperationLoadCache") or Instance.new("Folder",replicated);
        loadFolder.Name="UnionOperationLoadCache";
        local model=self.modules.modelAssembler:buildAsset({modelData=res},loadFolder);
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
                    partToAttachTo=Services.GeometryService:IntersectAsync(partToAttachTo,parts,options)[1];
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo=Services.GeometryService:IntersectAsync(old,{partToAttachTo},options)[1]; -- this is odd but fixes the problems
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
                    old:Destroy();
                    return partToAttachTo;
                end;
                print_if_debug(parts);
                partToAttachTo=Services.GeometryService:UnionAsync(partToAttachTo,parts,options)[1];
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                old:Destroy();
                old=partToAttachTo;
                print_if_debug(negativeParts);
                if #negativeParts~=0 then
                    partToAttachTo=Services.GeometryService:SubtractAsync(partToAttachTo,negativeParts,options)[1];
                    partToAttachTo.Parent=loadFolder;
                    partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                    old:Destroy();
                end;
                centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
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
            partToAttachTo.Parent=loadFolder;
            model:Destroy();
            return partToAttachTo;
        end;
        return reconstruct(model);
    end;
end;

return mod;