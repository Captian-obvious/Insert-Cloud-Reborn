local Services={
    ReplicatedStorage=game:GetService("ReplicatedStorage"),
    InsertService=game:GetService("InsertService"),
    AssetService=game:GetService("AssetService"),
};
local modules={
    sstrParse=require(script.Parent.SSTRParse), --SSTR is not stored as a default string, it needs some additional processing
    b64=require(script.Parent.Base64), --b64
    unionBuilder=require(script.Parent.UnionOperation), -- Creates UnionOperations from their data
};
local sandbox_type="Normal";
local Templates=script.TEMPLATE_OBJECTS;
local mod={
    isInitialized=false,
    Configuration={},
    debug_mode=false, --prints additional stuff to console
};
function resolveEnumInteger(enum:Enum, int:number)
    local vals=enum:GetEnumItems();
    for _,e in vals do
        if e.Value==int then
            return e;
        end;
    end;
    if int >= 0 and int < #vals then
        return vals[int + 1]; -- Lua is 1-based
    end;
    return vals[1];
end;
--[[ PrintDebug --]]
function print_if_debug(...)
    if mod.debug_mode then
        print(...);
    end;
end;
local propertyTypes={
    -- things that need additonal parsing go here
    ["string"]=function(typed,value,refs,encoded)
        if encoded==nil then encoded=false end;
        if typed=="string" then
            if encoded then
                return modules.b64.decode(value);
            else
                return value;
            end;
        else
            return "";
        end;
    end,
    ["content"]=function(typed,value,refs,contentType)
        if typed~="content" then return end;
        if value=="" or value==nil then return end;
        if contentType=="obj" then
            return Content.fromObject(refs[value+1]); -- object references are base-0
        elseif contentType=="uri" then
            return Content.fromUri(value);
        else
            return Content.fromUri(value); -- default to uri
        end;
    end,
    ["sharedstr"]=function(typed,value,refs)
        if typed=="sharedstr" then
            return modules.sstrParse:ParseSharedStr(value);
        else
            return "";
        end;
    end,
    ["enum"]=function(typed,value,refs,prop_instance)
        if typed~="enum" then print("Not an enum") return nil; end;
        local actualValue=nil;
        local function inferEnumType(propName,prop_instance)
            local success, value = pcall(function() return prop_instance[propName]; end);
            if success and typeof(value) == "EnumItem" then
                return Enum[tostring(value.EnumType)];
            else
                print(value);
            end;
            return nil;
        end;
        local suc,enumItem=pcall(inferEnumType,prop_instance.propName,prop_instance.classInstance);
        if not suc then
            print("failed to resolve instance");
        end;
        if not enumItem then
            warn("Enum inference failed for property:", prop_instance.propName, "on", tostring(prop_instance.classInstance));
        end;
        if enumItem then
            actualValue=resolveEnumInteger(enumItem,value);
        end;
        return actualValue;
    end,
    ["cframe"]=function(typed,value,refs)
        if typed~="cframe" then return CFrame.new(); end;
        local pos=value.position.vector3 or {0,0,0};
        local rot=value.rotation;
        if pos and rot and #rot==9 then
            return CFrame.new(pos[1],pos[2],pos[3],rot[1],rot[2],rot[3],rot[4],rot[5],rot[6],rot[7],rot[8],rot[9]);
        elseif pos then
            return CFrame.new(Vector3.new(pos[1],pos[2],pos[3]));
        end;
        return CFrame.new();
    end,
    ["qcframe"]=function(typed,value,refs)
        if typed~="qcframe" then return CFrame.new(); end;
        if not value or typeof(value)~="table" or #value~=7 then return CFrame.new(); end;
        return CFrame.new(value[1],value[2],value[3],value[4],value[5],value[6],value[7]);
    end,
    ["vector3int16"]=function(typed,value,refs)
        if typed~="vector3int16" then return Vector3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Vector3.new(value[1],value[2],value[3]);
        end;
        return Vector3.new(); 
    end,
    ["vector3"]=function(typed,value,refs)
        if typed~="vector3" then return Vector3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Vector3.new(value[1],value[2],value[3]);
        end;
        return Vector3.new(); 
    end,
    ["vector2"]=function(typed,value,refs)
        if typed~="vector2" then return Vector2.new() end;
        if value and typeof(value)=="table" and #value==2 then
            return Vector2.new(value[1],value[2]);
        end;
        return Vector2.new(); 
    end,
    ["udim"]=function(typed,value,refs)
        if typed~="udim" then return UDim.new() end;
        if value and typeof(value)=="table" and value.scale and value.offset then
            return UDim.new(value.scale,value.offset)
        elseif value and typeof(value)=="table" and #value==2 then --backwards compatibility to python parser
            return UDim.new(value[1],value[2]);
        end;
        return UDim.new();
    end,
    ["udim2"]=function(typed,value,refs)
        if typed~="udim2" then return UDim2.new() end;
        if value and typeof(value)=="table" and value.x and value.y then
            local x = value.x;
            local y = value.y;
            if typeof(x)=="table" and x.scale and x.offset and typeof(y)=="table" and  y.scale and y.offset then 
                return UDim2.new(x.scale,x.offset,y.scale,y.offset);
            elseif typeof(x)=="table" and #x==2 and typeof(y)=="table" and  #y==2 then --backwards compatibility to python parser
                return UDim2.new(x[1],x[2],y[1],y[2]);
            end;
        end;
        return UDim2.new();
    end,
    ["brickcolor"]=function(typed,value,refs)
        if typed~="brickcolor" then return BrickColor.new("Medium stone grey") end;
        if value and typeof(value)=="number" then -- why is the internal id of brickcolor "Float"? (roblox, what are you doing)
            return BrickColor.new(value);
        end;
        return BrickColor.new("Medium stone grey");
    end,
    ["numberrange"]=function(typed,value,refs)
        if typed~="numberrange" then return NumberRange.new(1) end;
        if value and typeof(value)=="table" and #value==2 then
            return NumberRange.new(value[1],value[2]);
        end;
        return NumberRange.new(1); 
    end,
    ["numbersequence"]=function(typed,value,refs)
        if typed~="numbersequence" then return NumberSequence.new(1) end;
        if value and typeof(value)=="table" then
            local keypoints={};
            for _,kp in pairs(value) do
                local nskp=kp.nskp;
                if nskp and typeof(nskp)=="table" and #nskp==3 then
                    table.insert(keypoints,NumberSequenceKeypoint.new(nskp[1],nskp[2],nskp[3]))
                end;
            end;
            return NumberSequence.new(keypoints);
        end;
        return NumberSequence.new(1);
    end,
    ["colorsequence"]=function(typed,value,refs)
        if typed~="colorsequence" then return ColorSequence.new(Color3.new(1,1,1)) end;
        if value and typeof(value)=="table" then
            local keypoints={};
            for _,kp in pairs(value) do
                local cskp=kp.cskp;
                if cskp and typeof(cskp)=="table" then
                    table.insert(keypoints,ColorSequenceKeypoint.new(cskp.t,Color3.new(cskp.color3[1],cskp.color3[2],cskp.color3[3])));
                end;
            end;
            if #keypoints==0 then
                table.insert(keypoints,ColorSequenceKeypoint.new(0,Color3.new(1,1,1)));
                table.insert(keypoints,ColorSequenceKeypoint.new(1,Color3.new(1,1,1)));
            end;
            return ColorSequence.new(keypoints);
        end;
        return ColorSequence.new(Color3.new(1,1,1));
    end,
    ["rgbc3"]=function(typed,value,refs)
        if typed~="rgbc3" then return Color3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Color3.fromRGB(value[1],value[2],value[3]);
        end;
        return Color3.new();
    end,
    ["color3"]=function(typed,value,refs)
        if typed~="color3" then return Color3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Color3.new(value[1],value[2],value[3]);
        end;
        return Color3.new();
    end,
    ["physprops"]=function(typed,value,refs)
        if typed~="physprops" then return nil end;
        if value and typeof(value)=="table" and #value==6 then
            return PhysicalProperties.new(value[1],value[2],value[3],value[4],value[5],value[6]); --no breakage from format changes GRRRR
        end;
        return nil;
    end,
    ["font"]=function(typed,value,refs)
        if typed ~= "font" then return Font.new("rbxasset://fonts/families/LegacySerif.json") end
        if value and typeof(value) == "table" then
            local family = value.fontFamily or "rbxasset://fonts/families/LegacySerif.json";
            local weight = value.fontWeight or 400;
            local style = value.fontStyle or 0;
            return Font.new(family,resolveEnumInteger(Enum.FontWeight,weight),resolveEnumInteger(Enum.FontStyle,style));
        end;
        return Font.new("rbxasset://fonts/families/LegacySerif.json");
    end,
    ["rect"]=function(typed,value,refs)
        if typed~="rect" then return Rect.new() end;
        if typeof(value)~="table" then return Rect.new() end;
        if not value.pos1 or not value.pos2 then return Rect.new() end;
        if typeof(value.pos1)~="table" or typeof(value.pos2)~="table" then return Rect.new() end;
        if #value.pos1<2 or #value.pos2<2 then return Rect.new() end;
        return Rect.new(value.pos1[1],value.pos1[2],value.pos2[1],value.pos2[2]);
    end,
    ["ref"]=function(typed,value,refs)
        if typed~="ref" then return nil end;
        if value<0 then return nil end;
        return refs[value+1]; --We add 1 to correct the offset generated by the parser
    end,
};
function InstantiateSolidModel(class_name,parent,inst,prop,refs,loadSettings)
    if loadSettings.DisableSolidModeling then
        -- fallback to old behavior (js make the instance)
        local h=Instance.new(class_name);
        h.Parent=parent;
        return h;
    end;
    local experimental=loadSettings.ExperimentalUnions;
    local assetId=(prop.AssetId and prop.AssetId.value~=nil and prop.AssetId.value~="") and prop.AssetId.value or nil;
    local childData=(prop.ChildData and prop.ChildData.value~=nil and prop.ChildData.value~="") and prop.ChildData.value or nil;
    local childData2=(prop.ChildData2 and prop.ChildData2.value~=nil and prop.ChildData2.value~="") and prop.ChildData2.value or nil;
    local assetData=(prop.AssetData and prop.AssetData.value~=nil and prop.AssetData.value~="") and prop.AssetData.value or nil;
    local typeToInit=(class_name~="NegateOperation") and class_name or "UnionOperation";
    local isIntersection=(typeToInit=="IntersectOperation");
    local part=Instance.new(typeToInit);
    part.Parent=parent;
    local colfidelity,rendfidelity=Enum.CollisionFidelity.Default,Enum.RenderFidelity.Automatic;
    if prop.CollisionFidelity and prop.CollisionFidelity.value then
        colfidelity=resolveEnumInteger(Enum.CollisionFidelity,prop.CollisionFidelity.value) or Enum.CollisionFidelity.Default;
    end;
    if prop.RenderFidelity and prop.RenderFidelity.value then
        rendfidelity=resolveEnumInteger(Enum.RenderFidelity,prop.RenderFidelity.value) or Enum.RenderFidelity.Automatic;
    end;
    local options={
        CollisionFidelity=colfidelity,
        RenderFidelity=rendfidelity,
        SplitApart=false, --typically unions are not split apart, but this can be changed in the future if needed
    };
    local function readChildData(data)
        return pcall(function()
            return (experimental) and modules.unionBuilder:applyChildDataNew(data,options,isIntersection) or modules.unionBuilder:applyChildData(data,options,isIntersection);
        end);
    end;
    local function FinalizePart(part,model)
        if model==nil then return end;
        if model.ClassName=="PartOperation" then
            part.Parent=parent;
            part:SubstituteGeometry(model);
            model:Destroy();
        else
            part:Destroy();
            part=model;
            part.Parent=parent;
        end;
        return part;
    end;
    local suc,model;
    if assetId then
        suc,model=pcall(function()
            return modules.unionBuilder:applyAssetId(assetId,options,isIntersection,experimental);
        end);
    elseif childData then
        suc,model=readChildData(childData)
    elseif childData2 then
        suc,model=readChildData(childData2);
    elseif assetData then
        suc,model=pcall(function()
            return modules.unionBuilder:applyAssetData(assetData,options,isIntersection,experimental);
        end);
    end;
    if suc and model~=nil then
        part=FinalizePart(part,model);
    end;
    if (class_name=="NegateOperation") or (inst.tags and table.find(inst.tags,"rbxNegated")) then
        part:SetAttribute("IsNegateOperation",true);
    end;
    return part;
end;
function createSurfaceAppearanceAsync(prop) --the workaround, only color works though so....
    local uri=Content.fromUri
    local obj=Content.fromObject
    local propmaps={
        c=uri(prop.ColorMap.value),
        m=uri(prop.MetalnessMap.value),
        n=uri(prop.NormalMap.value),
        r=uri(prop.RoughnessMap.value),
    };
    local suc,surf=pcall(function()
        local sa= Services.AssetService:CreateSurfaceAppearanceAsync({
            ColorMap=propmaps.c,
            MetalnessMap=propmaps.m,
            NormalMap=propmaps.n,
            RoughnessMap=propmaps.r,
        });
        return sa;
    end);
    if not suc then
        warn("Failed to create SurfaceAppearance on MeshPart due to an error: "..tostring(surf));
    end;
    return (suc) and surf or Instance.new("SurfaceAppearance");
end;
function createMeshPartAsync(meshId,textureId,options)
    local obj=Instance.new("Part");
    local cache=script:FindFirstChild("MeshPartCache") or Instance.new("Folder",script);
    cache.Name="MeshPartCache";
    obj:SetAttribute("MeshId",meshId);
    obj:SetAttribute("TextureId",textureId);
    local idVal=meshId:match("(%d+)$");
    local idNum=tonumber(idVal);
    if idNum then
        local cacheName="Mesh_"..tostring(idNum);
        local findCache=cache:FindFirstChild(cacheName);
        if findCache~=nil and findCache:IsA("MeshPart") then
            obj:Destroy();
            obj=findCache:Clone();
            obj.TextureID=textureId;
        else
            local suc,new=pcall(function()
                return Services.AssetService:CreateMeshPartAsync(Content.fromUri(meshId),options)
            end);
            if not suc then
                warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: "..tostring(new));
            else
                obj:Destroy();
                obj=new;
                obj.TextureID=textureId;
                local cacheObj=obj:Clone();
                cacheObj.Parent=cache;
                cacheObj.Name=cacheName;
            end;
        end;
    else
        warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: ID is not a number.")
    end;
    return obj;
end;

local class_initializers={
    ["Script"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local object=Templates:FindFirstChild(sandbox_type..class_name):Clone();
        object.Parent=parent;
        object.Enabled=false;
        return object;
    end,
    ["LocalScript"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local object=Templates:FindFirstChild(sandbox_type..class_name):Clone();
        if loadSettings.EnableLegacyClientScripts then
            object:Destroy();
            object=Templates:FindFirstChild(sandbox_type..class_name.."Legacy"):Clone();
        end;
        object.Parent=parent;
        object.Enabled=false;
        return object;
    end,
    ["ModuleScript"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local object=Templates:FindFirstChild(sandbox_type..class_name):Clone();
        object.Parent=parent;
        return object;
    end,
    ["MeshPart"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local midprop=prop.MeshId or prop.MeshID;
        if not midprop or not midprop.value then
            warn("MeshPart missing MeshId property, creating default Part instead.");
            local part=Instance.new("Part");
            part.Parent=parent;
            return part;
        end;
        local meshId=midprop.value;
        local textureId=prop.TextureID.value;
        local meshPart;
        if loadSettings.EnablePreciseMeshParts then
            meshPart=createMeshPartAsync(meshId,textureId,{
                CollisionFidelity=Enum.CollisionFidelity.Default,
                RenderFidelity=Enum.RenderFidelity.Precise
            });
            meshPart.Parent=parent;
        else
            local InitialSize=compile_prop("InitializeSize",prop.InitialSize,refs,class_name);
            local OrigSize=compile_prop("Size",prop.size,refs,class_name);
            meshPart=Instance.new("Part");
            meshPart.Parent=parent;
            -- everything else is applied during the properties step so we just need to set up the mesh
            local mesh=Instance.new("SpecialMesh",meshPart);
            mesh.MeshType=Enum.MeshType.FileMesh;
            mesh.MeshId=meshId;
            mesh.TextureId=textureId;
            mesh.Scale=OrigSize/InitialSize;
            mesh:SetAttribute("initialSize",InitialSize);
        end;
        return meshPart;
    end,
    ['SurfaceAppearance']=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=createSurfaceAppearanceAsync(prop)
        obj.Parent=parent;
        return obj;
    end,
    ["IntersectOperation"]=InstantiateSolidModel,
    ['NegateOperation']=InstantiateSolidModel,
    ["UnionOperation"]=InstantiateSolidModel,
    ["PartOperation"]=InstantiateSolidModel,
    ["Humanoid"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local humanoid=Instance.new("Humanoid");
        humanoid.Parent=parent;
        humanoid.MaxHealth=prop.MaxHealth.value or 100;
        local suc,res=pcall(function() return prop.Health.value end);
        suc,res=pcall(function() return prop.Health_XML.value end);
        humanoid.Health=(suc) and res or humanoid.MaxHealth;
        return humanoid;
    end,
    ["DialogChoice"]=function(class_name,parent,inst,prop,refs,loadSettings)
        return nil;
    end,
    ["Dialog"]=function(class_name,parent,inst,prop,refs,loadSettings)
        return nil;
    end,
    ["PackageLink"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance.new("Folder");
        obj.Parent=parent;
        obj.Name="PackageLink";
        --obj:SetAttribute("AssetId",prop.AssetId.value);
        return obj;
    end,
    ["StockSound"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance.new("Folder");
        obj.Parent=parent;
        obj.Name="StockSound";
        return obj;
    end,
    ["Geometry"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance.new("Folder");
        obj.Parent=parent;
        obj.Name="Geometry";
        return obj;
    end,
    ["Message"]=function(class_name,parent,inst,prop,refs,loadSettings)
        return nil;
    end,
    ["Hint"]=function(class_name,parent,inst,prop,refs,loadSettings)
        return nil;
    end
};
local InstancesCannotCreate={
    "PackageLink",
    "StockSound",
    "Geometry"
};
local propExceptions={
    Attachment0=true,
    Attachment1=true,
    Part0=true,
    Part1=true,
    Value=true,
    Adornee=true,
    NextSelectionUp=true,
    NextSelectionDown=true,
    NextSelectionLeft=true,
    NextSelectionRight=true,
    SelectionImageObject=true,
    PrimaryPart=true,
    SoundGroup=true,
    CameraSubject=true,
    CustomPhysicalProperties=true,
    MaterialVariant=true,
};
function compile_prop(prop,v,refs,class)
    local value=v.value;
    local typed=v.type;
    local compile=propertyTypes[typed] or propertyTypes[prop];
    if compile then
        local new=nil;
        if typed=="enum" then
            new=compile(typed,value,refs,{propName=prop,classInstance=class});
        elseif typed=="string" then
            new=compile(typed,value,refs,v.enc);
        elseif typed=="content" then
            new=compile(typed,value,refs,v.ctyp);
        else
            new=compile(typed,value,refs);
        end;
        return new;
    else
        if value~=nil then
            return value;
        else
            return nil;
        end;
    end;
end;
--[[ Initializes module --]]
function mod:initialize(config,main)
    if self.isInitialized then return end;
    self.isInitialized=true;
    self.Configuration=config;
    modules.unionBuilder.modules.modelAssembler=mod;
    modules.unionBuilder.modules.icloud=main;
    if self.Configuration.Sandboxed==true then
        sandbox_type="Sandbox";
    end;
end;
--[[ Build model tree --]]
function mod.buildModel(base,parent,rbxmtree,refs,loadSettings)
    refs=refs or {};
    loadSettings=loadSettings or {};
    local instances={};
    local hierarcy={};
    local function build(base,parent,rbxmtree)
        for i=1,#rbxmtree do
            local inst=rbxmtree[i];
            local classname=inst.ClassName;
            local suc,err=pcall(function()
                if (classname~="Message" or classname~="Hint") then
                    local instance;
                    local classInit=class_initializers[classname];
                    if classInit then
                        --print_if_debug(loadSettings);
                        instance=classInit(classname,parent,inst,inst.properties,refs,loadSettings);
                    else
                        instance=Instance.new(classname);
                        --hierarcy[instance]=parent;
                        instance.Parent=parent;
                    end;
                    if instance:IsA("BasePart") then
                        instance.Anchored=true;
                        instance.CanCollide=false;
                    end;
                    refs[inst.Ref+1]=instance; -- refs are base-0
                    instances[instance]=inst;
                    build(base,instance,inst.children);
                end;
            end);
            if not suc then
                warn("Failed to init class: "..tostring(err));
            end;
        end;
    end;
    build(base,parent,rbxmtree);
    mod.buildProps(instances,refs,loadSettings);
    if loadSettings.ApplyAttributes then
        mod.buildAttr(instances,refs); --attributes are applied after properties for consistency
    end;
end;
--[[ Build properties tree --]]
function initProp(obj,propName,prop,refs,loadSettings)
    propName=string.upper(string.sub(propName, 0, 1))..string.sub(propName,2); --case the property correctly
    if (propName=="Color3uint8") then
        propName="Color"; -- fixes the format changes to RBXM
    elseif (propName=="SourceAssetId") then
        obj:SetAttribute("AssetID",prop.value);
    elseif (propName=="Source") then
        local brokenCodeToFix="^-%-%[%["..string.char(10).."%-%-%[%[";
        local source:string=prop.value;
        source=source:gsub(brokenCodeToFix,"--[[");
        obj:SetAttribute("Source",source);
    elseif (propName=="Disabled" and prop.value==false) then
        obj:SetAttribute("IC_Enabled",not prop.value);
        if not mod.Configuration.DisableScripts then
            obj.Enabled=not prop.value;
        end;
    elseif ((propName=="Playing" or propName=="IsPlaying") and prop.value==true) then
        obj.Playing=false;
        pcall(function() obj:Stop(); end);
        obj:SetAttribute("IC_Playing",prop.value);
    elseif (propName=="Part1Internal") then
        obj.Part1=compile_prop("Part1",prop,refs,obj);
    elseif (propName=="Part0Internal") then
        obj.Part0=compile_prop("Part0",prop,refs,obj);
    elseif (propName=="MaterialVariantSerialized") then
        obj.MaterialVariant=compile_prop("MaterialVariant",prop,refs,obj);
    elseif (propName=="PivotOffset" and obj:IsA("UnionOperation")) then
        local current=compile_prop(propName,prop,refs,obj);
        local baked=obj:GetAttribute("BakedInPivot");
        if baked then
            obj.PivotOffset=current * baked;
        else
            obj.PivotOffset=current;
        end;
    elseif (propName=="Locked" and mod.Configuration.UnlockParts) then
        obj.Locked=false;
        --some properties dont have the name they have ingame, we fix that here
    elseif (propName=="size_xml") then
        propName="Size"; 
    elseif (propName=="riseVelocity_xml") then
        propName="RiseVelocity"; 
    elseif (propName=="Health_XML") then
        propName="Health";
    elseif (propName=="heat_xml") then
        propName="Heat";
    elseif (propName=="opacity_xml") then
        propName="Opacity";
    end;
    if (obj and (obj[propName]~=nil or propExceptions[propName]) and propName~="Disabled" and propName~="Locked" and propName~="PivotOffset" and propName~="Playing" and propName~="IsPlaying") then
        obj[propName]=compile_prop(propName,prop,refs,obj);
    end;
end;
function mod.buildProps(instances,refs,loadSettings)
    for obj,inst in pairs(instances) do
        for propName,prop in pairs(inst.properties) do
            local suc,err=pcall(initProp,obj,propName,prop,refs,loadSettings);
            if not suc and mod.debug_mode then
                warn("Failed to apply property "..propName.." to instance: "..tostring(err));
            end;
        end;
    end;
end;
--[[ Build attributes tree --]]
function mod.buildAttr(instances,refs)
    for obj,inst in pairs(instances) do
        local attributes=inst.attributes or {};
        for attrName,attr in pairs(attributes) do
            local suc,err=pcall(function()
                if (obj) then
                    obj:SetAttribute(attrName,compile_prop(attrName,attr,refs,obj));
                end;
            end);
            if not suc and mod.debug_mode then
                warn("Failed to apply attribute "..attrName.." to instance: "..tostring(err));
            end;
        end;
    end;
end;
--[[ Builds asset from its tree and related data --]]
function mod:buildAsset(data,root_parent,loadSettings)
    if self.isInitialized then
        root_parent=root_parent or workspace;
        local rootModel=Instance.new("Model");
        rootModel.Parent=root_parent;
        rootModel.Name=data.AssetIdParsed or "UNNAMED_ASSET";
        local rbxm=data.modelData; -- this is json that is provided
        loadSettings=loadSettings or {};
        self.buildModel(rootModel,rootModel,rbxm.tree,{},loadSettings);
        return rootModel;
    else
        warn("ModelAssembler is not initialized.");
        return nil;
    end;
end;
--[[ Creates a Script or LocalScript --]]
function mod:NewScript(isLocal)
    local object=Templates:FindFirstChild(sandbox_type.."Script"):Clone();
    if isLocal then
        object=Templates:FindFirstChild(sandbox_type.."LocalScript"):Clone();
    end
    return object;
end;
return mod;