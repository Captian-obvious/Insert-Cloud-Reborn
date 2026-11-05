--!optimize 2

local geometryService=game:GetService("GeometryService");
local mod={
    _VERSION="9.0.0",
    modules={
        modelAssembler=nil, --populated at runtime
        icloud=nil, --populated at runtime
    },
};
export type UnionOptions={
    CollisionFidelity:Enum.CollisionFidelity,
    RenderFidelity:Enum.RenderFidelity,
    SplitApart:boolean,
};

local unionCache={};
local unionQueue={};
local b64=require(script.Parent.Base64); --b64
local parseFile=require(script.Parent.RobloxFileFormat); --parser
local b64_decode=b64.decode;
local table_insert=table.insert;
local table_sort=table.sort;
local table_remove=table.remove;
local table_pack=table.pack;
local table_unpack=table.unpack;
local task_wait=task.wait;
local insertcloud=nil;
local modelAssembler=nil;

local function parse(data)
    if modelAssembler==nil then
        modelAssembler=mod.modules.modelAssembler;
    end;
    return modelAssembler:buildAsset({modelData=parseFile(data)},geometryService);
end;
local function loadSolidModel(assetId:number)
    if insertcloud==nil then
        insertcloud=mod.modules.icloud;
    end;
    return insertcloud:LoadSolidModel(assetId);
end;
function mod:applyAssetId(assetId:string,options:UnionOptions,isIntersection:boolean)
    if not assetId or type(assetId)~="string" then
        warn("AssetId is not a string.");
        return nil;
    end;
    local id=assetId:match("(%d+)$");
    if not id then
        warn("Asset ID is not valid. Make sure you have the correct asset ID for the union you want to insert.");
        return nil;
    end;
    local assetIdToLoad=tonumber(id);
    local cacheName="Union_"..id;
    local findCache=unionCache[cacheName];
    local isAssetLoading=unionQueue[assetId];
    if findCache~=nil then
        return findCache:Clone();
    elseif isAssetLoading then
        while unionQueue[assetId] do task_wait() end;
        findCache=unionCache[cacheName];
        if findCache~=nil then
            return findCache:Clone();
        end;
    else
        local thefunc;
        unionQueue[assetId]=true;
        local childData=loadSolidModel(assetIdToLoad);
        if not childData then
            warn("Failed to load SolidModel asset with ID "..id..". Make sure the asset ID is correct and the asset is a valid SolidModel.");
            return nil;
        end;
        local loadable=self:applyChildData(b64_decode(childData),options,isIntersection);
        if loadable then
            unionCache[cacheName]=loadable;
            unionQueue[assetId]=nil;
            return loadable:Clone();
        end;
        unionQueue[assetId]=nil;
    end;
    return nil;
end;
function mod:applyAssetData(assetData:string,options:UnionOptions,isIntersection:boolean)
    print("asset data called");
    local thefunc;
    assetData=string.sub(assetData,5); --assetId, 4 bytes, 5th byte where we start.
    local suc,res=pcall(parseFile,assetData);
    local childData=nil;
    if not suc then
        warn("Parse Failed: "..res);
        return nil;
    end;
    if res~=nil then
        if res.tree then
            local instance=res.tree[1];
            if instance then
                childData=instance.properties.ChildData.value;
            end;
        end;
    end;
    if not childData then
        return nil;
    end;
    return self:applyChildData(childData,options,isIntersection);
end;
function centerUnionPivot(union,options,parent)
    local tempModel = Instance.new("Model");
    union.Parent = tempModel;
    tempModel.PrimaryPart = union;
    local boxCFrame,_=tempModel:GetBoundingBox();
    local centeredPart=Instance.new("Part");
    centeredPart.Size=Vector3.new(0.001,0.001,0.001);
    centeredPart.CFrame=boxCFrame;
    centeredPart.Anchored=union.Anchored;
    centeredPart.Transparency=1;
    centeredPart.CanCollide=false;
    centeredPart.Parent=parent;
    local new;
    if union:IsA("UnionOperation") then
        new=centeredPart:UnionAsync({union},options.CollisionFidelity,options.RenderFidelity);
    elseif union:IsA("PartOperation") then
        new=geometryService:UnionAsync(centeredPart,{union},options)[1];
    end;
    union:SubstituteGeometry(new);
end;

function mod:applyChildData(childData,options:UnionOptions,isIntersection:boolean)
    local suc,model=pcall(parse,childData);
    if not suc then
        warn("Parse Failed: "..model);
        return nil;
    end;
    local partToAttachTo=nil;
    local theparts=model:GetChildren();
    local negativeParts={};
    local parts={};
    local partslen=#theparts;
    if partslen<1 then
        warn("Model has no children to union.");
        model:Destroy();
        return nil;
    end;
    partToAttachTo=theparts[1];
    if partToAttachTo:GetAttribute("IsNegateOperation") then --fix orientation issues
        table_insert(negativeParts,partToAttachTo);
        for i=2,partslen do
            local v=theparts[i];
            if not v:GetAttribute("IsNegateOperation") then
                local old=v;
                partToAttachTo=Instance.new("Part");
                partToAttachTo.Size=Vector3.new(0.001,0.001,0.001);
                partToAttachTo.Position=old.Position
                partToAttachTo.Anchored=old.Anchored;
                partToAttachTo.Transparency=1;
                partToAttachTo.CanCollide=false;
                partToAttachTo.Name="UnionBasePart";
                partToAttachTo.Parent=model;
                break;
            end;
        end;
    end;
    for i=1,partslen do
        local v=theparts[i];
        if v:IsA("BasePart") and v~=partToAttachTo then
            if v:GetAttribute("IsNegateOperation") then
                table_insert(negativeParts,v);
            else
                table_insert(parts,v);
            end;
        end;
    end;
    local old=partToAttachTo;
    local collisionFidelity=options.CollisionFidelity;
    local renderFidelity=options.RenderFidelity;
    if not collisionFidelity then
        collisionFidelity=Enum.CollisionFidelity.Default;
    end;
    if not renderFidelity then
        renderFidelity=Enum.RenderFidelity.Performance;
    end;
    local suc,Union=pcall(function()
        if isIntersection then
            partToAttachTo=partToAttachTo:IntersectAsync(parts,collisionFidelity,renderFidelity);
            partToAttachTo.Parent=model;
            partToAttachTo=partToAttachTo:IntersectAsync({old},collisionFidelity,renderFidelity); -- this is odd but fixes the problems
            partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
            centerUnionPivot(partToAttachTo,options,model);
            return partToAttachTo;
        end;
        partToAttachTo=partToAttachTo:UnionAsync(parts,collisionFidelity,renderFidelity);
        partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
        old=partToAttachTo;
        if #negativeParts~=0 then
            partToAttachTo.Parent=model;
            partToAttachTo=partToAttachTo:SubtractAsync(negativeParts,collisionFidelity,renderFidelity);
            partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
        end;
        centerUnionPivot(partToAttachTo,options,model);
        return partToAttachTo;
    end);
    model:Destroy();
    if not suc then
        warn("Union operation failed: "..tostring(Union));
        return nil;
    end;
    if not Union then
        warn("Union operation failed: No part was returned.");
        return nil;
    end;
    return Union;
end;


return mod;
