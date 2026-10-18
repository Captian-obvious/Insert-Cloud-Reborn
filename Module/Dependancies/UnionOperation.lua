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
local b64=require(script.Parent.Base64); --b64
local parser=require(script.Parent.RobloxFileFormat); --parser
local b64_decode=b64.decode;
local table_insert=table.insert;
local table_sort=table.sort;
local table_remove=table.remove;
local table_pack=table.pack;
local table_unpack=table.unpack;

function parse(data)
    return parser(b64_decode(data));
end;
function mod:applyAssetId(assetId:string,options:UnionOptions,isIntersection:boolean,isExperimental:boolean)
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
    local childData=self.modules.icloud:LoadSolidModel(assetIdToLoad);
    if not childData then
        warn("Failed to load SolidModel asset with ID "..id..". Make sure the asset ID is correct and the asset is a valid SolidModel.");
        return nil;
    end;
    local cacheName="Union_"..id;
    local findCache=unionCache[cacheName];
    if findCache then
        return findCache:Clone();
    else
        local thefunc;
        if isExperimental then
            thefunc=self.applyChildDataNew;
        else
            thefunc=self.applyChildData;
        end;
        local loadable=thefunc(self,childData,options,isIntersection);
        if loadable then
            unionCache[cacheName]=loadable;
            return loadable:Clone();
        end;
    end;
    return nil;
end;
function mod:applyAssetData(assetData:string,options:UnionOptions,isIntersection:boolean,isExperimental:boolean)
    print("asset data called");
    local thefunc;
    if isExperimental then
        thefunc=self.applyChildDataNew;
    else
        thefunc=self.applyChildData;
    end;
    local suc,res=pcall(parse,assetData);
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
    return thefunc(self,childData,options,isIntersection)
end;
function centerUnionPivot(union,options,parent)
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
        new=geometryService:UnionAsync(centeredPart,{union},options)[1];
    end;
    union:SubstituteGeometry(new);
    new:Destroy();
    union.Parent=parent;
end;

function mod:applyChildData(childData,options:UnionOptions,isIntersection:boolean)
    local suc,res=pcall(parse,childData);
    if not suc then
        warn("Parse Failed: "..res);
        return nil;
    end;
    local model=self.modules.modelAssembler:buildAsset({modelData=res},geometryService);
    local function reconstruct(model:Model)
        if not model then return end;
        local partToAttachTo=nil;
        local theparts=model:GetChildren();
        local negativeParts={};
        local parts={};
        local partslen=#theparts;
        if partslen<1 then
            warn("Model has no children to union.");
            return nil;
        end;
        partToAttachTo=theparts[1];
        if partToAttachTo:GetAttribute("IsNegateOperation") then --fix orientation issues
            table_insert(negativeParts,partToAttachTo);
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
        for i=1,partslen do
            v=theparts[i];
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
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
                old:Destroy();
                return partToAttachTo;
            end;
            partToAttachTo=partToAttachTo:UnionAsync(parts,collisionFidelity,renderFidelity);
            partToAttachTo.Parent=model;
            partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
            old:Destroy();
            old=partToAttachTo;
            if #negativeParts~=0 then
                partToAttachTo=partToAttachTo:SubtractAsync(negativeParts,collisionFidelity,renderFidelity);
                partToAttachTo.Parent=model;
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
        if not Union then
            warn("Union operation failed: No part was returned.");
            return nil;
        end;
        return Union;
    end;
    local union=reconstruct(model);
    model:Destroy();
    if not union then
        return nil;
    end;
    return union;
end;

function mod:applyChildDataNew(childData,options:UnionOptions,isIntersection:boolean)
    local suc,res=pcall(parse,childData);
    if not suc then
        warn("Parse Failed: "..res);
        return nil;
    end;
    local model=self.modules.modelAssembler:buildAsset({modelData=res},geometryService);
    local function reconstruct(model:Model)
        if not model then return end;
        local partToAttachTo=nil;
        local theparts=model:GetChildren();
        local negativeParts={};
        local parts={};
        local partslen=#theparts;
        if partslen<1 then
            warn("Model has no children to union.");
            return nil;
        end;
        partToAttachTo=theparts[1];
        if partToAttachTo:GetAttribute("IsNegateOperation") then --fix orientation issues
            table_insert(negativeParts,partToAttachTo);
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
        for i=1,partslen do
            v=theparts[i];
            if v:IsA("BasePart") and v~=partToAttachTo then
                if v:GetAttribute("IsNegateOperation") then
                    table_insert(negativeParts,v);
                else
                    table_insert(parts,v);
                end;
            end;
        end;
        local old=partToAttachTo;
        local suc,Union=pcall(function()
            if isIntersection then
                partToAttachTo=geometryService:IntersectAsync(partToAttachTo,parts,options)[1];
                partToAttachTo.Parent=model;
                partToAttachTo=geometryService:IntersectAsync(partToAttachTo,{old},options)[1]; -- this is odd but fixes the problems
                partToAttachTo.Parent=model;
                partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
                centerUnionPivot(partToAttachTo,options,partToAttachTo.Parent);
                old:Destroy();
                return partToAttachTo;
            end;
            partToAttachTo=geometryService:UnionAsync(partToAttachTo,parts,options)[1];
            partToAttachTo.Parent=model;
            partToAttachTo:SetAttribute("IsNegateOperation", old:GetAttribute("IsNegateOperation"));
            old:Destroy();
            old=partToAttachTo;
            if #negativeParts~=0 then
                partToAttachTo=geometryService:SubtractAsync(partToAttachTo,negativeParts,options)[1];
                partToAttachTo.Parent=model;
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
        if not Union then
            warn("Union operation failed: No part was returned.");
            return nil;
        end;
        return Union;
    end;
    local union=reconstruct(model);
    model:Destroy();
    if not union then
        return nil;
    end;
    return union;
end;

return mod;
