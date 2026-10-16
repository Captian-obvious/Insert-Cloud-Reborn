local assetService=game:GetService("AssetService");
local sandbox_type="Normal";
local Templates=script.TEMPLATE_OBJECTS;
local contentUri=Content.fromUri;
local contentObj=Content.fromObject;
local table_find=table.find;
local table_insert=table.insert;
local table_clone=table.clone;
local table_remove=table.remove;
local coroutine_create=coroutine.create;
local coroutine_resume=coroutine.resume;
local coroutine_status=coroutine.status;
local coroutine_running=coroutine.running;
local coroutine_wrap=coroutine.wrap;
local task_spawn=task.spawn;
local task_wait=task.wait;
local task_delay=task.delay;
local string_upper=string.upper;
local string_sub=string.sub;
local string_gsub=string.gsub;
local string_split=string.split;
local string_format=string.format;
local string_gmatch=string.gmatch;
local string_char=string.char;
local table_clone=table.clone;
local b64=require(script.Parent.Base64); -- base64 encoding/decoding
local union=require(script.Parent.UnionOperation); -- Creates UnionOperations from their data
local b64_decode=b64.decode;
local b64_encode=b64.encode;

local mod={
    isInitialized=false,
    Configuration={},
    debug_mode=false, --prints additional stuff to console
};

function resolveEnumInteger(enum:Enum, int:number)
    local vals=enum:GetEnumItems();
    for i=1,#vals do
        local e=vals[i];
        if e.Value==int then
            return e;
        end;
    end;
    if int >= 0 and int < #vals then
        return vals[int + 1];-- Lua is 1-based
    end;
    return vals[1];
end;

--[[ PrintDebug --]]
function print_if_debug(...)
    if mod.debug_mode then
        print(...);
    end;
end;
local templateCache = {};
for _, child in ipairs(Templates:GetChildren()) do
    templateCache[child.Name] = child;
end;
local meshCache={};
local propertyTypes={
    -- things that need additonal parsing go here
    ["string"]=function(typed,value,refs,encoded)
        if encoded==nil then encoded=false end;
        if typed=="string" then
            if encoded then
                return b64_decode(value);
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
            return contentObj(refs[value+1]); -- object references are base-0
        elseif contentType=="uri" then
            return contentUri(value);
        else
            return contentUri(value); -- default to uri
        end;
    end,
    ["sharedstr"]=function(typed,value,refs)
        if typed=="sharedstr" then
            return b64_decode(value);
        else
            return "";
        end;
    end,
    ["enum"]=function(typed,value,refs,prop_instance)
        if typed~="enum" then print("Not an enum") return nil; end;
        local propName=prop_instance.propName;
        local classInstance=prop_instance.classInstance;
        if not classInstance then return nil; end;
        local success, defaultVal = pcall(function() return classInstance[propName]; end);
        if success and typeof(defaultVal) == "EnumItem" then
            return resolveEnumInteger(defaultVal.EnumType,value);
        end;
        warn("Enum inference failed for property:", propName, "on", tostring(classInstance));
        return nil;
    end,
    ["cframe"]=function(typed,value,refs)
        if typed~="cframe" then return CFrame.new(); end;
        local pos=value.position.vector3 or {0,0,0};
        local rot=value.rotation;
        if pos and rot and #rot==9 then
            local x,y,z=unpack(pos);
            return CFrame.new(x,y,z,unpack(rot));
        elseif pos then
            return CFrame.new(Vector3.new(unpack(pos)));
        end;
        return CFrame.new();
    end,
    ["qcframe"]=function(typed,value,refs)
        if typed~="qcframe" then return CFrame.new(); end;
        if not value or typeof(value)~="table" or #value~=7 then return CFrame.new(); end;
        return CFrame.new(unpack(value));
    end,
    ["vector3int16"]=function(typed,value,refs)
        if typed~="vector3int16" then return Vector3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Vector3.new(unpack(value));
        end;
        return Vector3.new(); 
    end,
    ["vector3"]=function(typed,value,refs)
        if typed~="vector3" then return Vector3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Vector3.new(unpack(value));
        end;
        return Vector3.new(); 
    end,
    ["vector2"]=function(typed,value,refs)
        if typed~="vector2" then return Vector2.new() end;
        if value and typeof(value)=="table" and #value==2 then
            return Vector2.new(unpack(value));
        end;
        return Vector2.new(); 
    end,
    ["udim"]=function(typed,value,refs)
        if typed~="udim" then return UDim.new() end;
        if value and typeof(value)=="table" and value.scale and value.offset then
            return UDim.new(value.scale,value.offset)
        elseif value and typeof(value)=="table" and #value==2 then --backwards compatibility to python parser
            return UDim.new(unpack(value));
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
                    table_insert(keypoints,NumberSequenceKeypoint.new(nskp[1],nskp[2],nskp[3]))
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
                    table_insert(keypoints,ColorSequenceKeypoint.new(cskp.t,Color3.new(cskp.color3[1],cskp.color3[2],cskp.color3[3])));
                end;
            end;
            if #keypoints==0 then
                table_insert(keypoints,ColorSequenceKeypoint.new(0,Color3.new(1,1,1)));
                table_insert(keypoints,ColorSequenceKeypoint.new(1,Color3.new(1,1,1)));
            end;
            return ColorSequence.new(keypoints);
        end;
        return ColorSequence.new(Color3.new(1,1,1));
    end,
    ["rgbc3"]=function(typed,value,refs)
        if typed~="rgbc3" then return Color3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Color3.fromRGB(unpack(value));
        end;
        return Color3.new();
    end,
    ["color3"]=function(typed,value,refs)
        if typed~="color3" then return Color3.new() end;
        if value and typeof(value)=="table" and #value==3 then
            return Color3.new(unpack(value));
        end;
        return Color3.new();
    end,
    ["physprops"]=function(typed,value,refs)
        if typed~="physprops" then return nil end;
        if value and typeof(value)=="table" and #value==6 then
            return PhysicalProperties.new(unpack(value)); --no breakage from format changes GRRRR
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
local function compile_prop(prop,v,refs,class)
    local value=v.value;
    local typed=v.type;
    local compile=propertyTypes[typed];
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
local function InstantiateSolidModel(class_name,parent,inst,prop,refs,loadSettings,workers)
    if loadSettings.DisableSolidModeling then
        -- fallback to old behavior (js make the instance)
        local h=Instance.new(class_name);
        h.Parent=parent;
        return h;
    end;
    local typeToInit=(class_name~="NegateOperation") and class_name or "UnionOperation";
    local isIntersection=(typeToInit=="IntersectOperation");
    local experimental=loadSettings.ExperimentalUnions;
    local part=Instance.new(typeToInit);
    part.Parent=parent;
    local function applyProps(co:thread)
        table_insert(workers.unionWorkers,co);
        local suc,err=pcall(function()
            local assetId=(prop.AssetId~=nil and prop.AssetId.value~=nil and type(prop.AssetId.value)=="string" and string.len(prop.AssetId.value)>0) and prop.AssetId.value or nil;
            local childData=(prop.ChildData~=nil and prop.ChildData.value~=nil and type(prop.ChildData.value)=="string" and string.len(prop.ChildData.value)>0) and prop.ChildData.value or nil;
            local childData2=(prop.ChildData2~=nil and prop.ChildData2.value~=nil and type(prop.ChildData2.value)=="string" and string.len(prop.ChildData2.value)>0) and prop.ChildData2.value or nil;
            local assetData=(prop.AssetData~=nil and prop.AssetData.value~=nil and type(prop.AssetData.value)=="string" and string.len(prop.AssetData.value)>0) and prop.AssetData.value or nil;
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
            local model;
            if assetId then
                model=union:applyAssetId(assetId,options,isIntersection,experimental);
            elseif childData~=nil or childData2~=nil then
                local data=(childData2~=nil) and childData2 or childData;
                local thefunc;
                if experimental then
                    thefunc=union.applyChildDataNew;
                else
                    thefunc=union.applyChildData;
                end;
                model=thefunc(union,data,options,isIntersection);
            elseif assetData then
                model=union:applyAssetData(assetData,options,isIntersection,experimental);
            end;
            
            if model~=nil then
                part:SubstituteGeometry(model);
                model:Destroy();
            end;
        end);
        table_remove(workers.unionWorkers,table_find(workers.unionWorkers,co));
        if not suc then
            warn("Error instantiating solid model: "..err);
        end;
    end;
    local co=coroutine_create(applyProps);
    coroutine_resume(co,co);
    --task_spawn(function() --watchdog
    --    task_wait(10);
    --    if coroutine_status(co)~="dead" then
    --        table_remove(workers.unionWorkers,table_find(workers.unionWorkers,co));
    --    end;
    --end);
    if (class_name=="NegateOperation") or (inst.tags and table_find(inst.tags,"rbxNegated")) then
        part:SetAttribute("IsNegateOperation",true);
    end;
    return part;
end;
local function createMeshPartAsync(meshId,textureId,options):MeshPart
    local obj=Instance.new("MeshPart");
    obj:SetAttribute("MeshId",meshId);
    obj:SetAttribute("TextureId",textureId);
    local idVal=meshId:match("(%d+)$");
    local idNum=tonumber(idVal);
    local isLocal=meshId:match("^rbxasset://");
    if not idNum and not isLocal then
        warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: ID is not a number or local asset.")
        return obj;
    end;
    local cacheName;
    if isLocal then
        local localfilekey,_=string_gsub(meshId,"[^%w]", "_");
        cacheName="Mesh_"..localfilekey;
    else
        cacheName="Mesh_"..tostring(idNum);
    end;
    local findCache=meshCache[cacheName];
    if findCache~=nil and findCache:IsA("MeshPart") then
        obj:Destroy();
        obj=findCache:Clone();
        obj.TextureID=textureId;
    else
        local suc,new=pcall(assetService.CreateMeshPartAsync,assetService,contentUri(meshId),options);
        if not suc then
            warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: "..tostring(new));
        else
            obj:Destroy();
            obj=new;
            obj.TextureID=textureId;
            meshCache[cacheName]=obj:Clone();
        end;
    end;
    return obj;
end;
local blocked_classes={
    "DialogChoice",
    "Dialog",
    "Message",
    "Hint",
    "SkateboardPlatform"
};
local class_initializers={
    ["Script"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local object=templateCache[sandbox_type..class_name]:Clone();
        object.Parent=parent;
        object.Enabled=false;
        return object;
    end,
    ["LocalScript"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local name=sandbox_type..class_name;
        if loadSettings.EnableLegacyClientScripts then
            name=name.."Legacy";
        end;
        local object=templateCache[name]:Clone();
        object.Parent=parent;
        object.Enabled=false;
        return object;
    end,
    ["ModuleScript"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local object=templateCache[sandbox_type..class_name]:Clone();
        object.Parent=parent;
        return object;
    end,
    ["MeshPart"]=function(class_name,parent,inst,prop,refs,loadSettings,workers)
        local meshPart=Instance.new("MeshPart");
        local midprop=prop.MeshId or prop.MeshID or prop.MeshContent;
        local tidprop=prop.TextureID or prop.TextureId or prop.TextureContent;
        if not midprop then
            warn("Failed to generate MeshPart with asset location \""..tostring(midprop).."\" due to error: MeshId is missing.")
            meshPart.Parent=parent;
            return meshPart;
        end;
        local meshId=midprop.value;
        local textureId="";
        if tidprop then
            textureId=tidprop.value;
        end;
        if loadSettings.EnablePreciseMeshParts then
            local colfidelity,rendfidelity=Enum.CollisionFidelity.Default,Enum.RenderFidelity.Automatic;
            if prop.CollisionFidelity and prop.CollisionFidelity.value then
                colfidelity=resolveEnumInteger(Enum.CollisionFidelity,prop.CollisionFidelity.value) or Enum.CollisionFidelity.Default;
            end;
            if prop.RenderFidelity and prop.RenderFidelity.value then
                rendfidelity=resolveEnumInteger(Enum.RenderFidelity,prop.RenderFidelity.value) or Enum.RenderFidelity.Automatic;
            end;
            local co=coroutine.create(function(co)
                table_insert(workers.meshWorkers,co);
                local suc,real=pcall(createMeshPartAsync,meshId,textureId,{
                    CollisionFidelity=colfidelity,
                    RenderFidelity=rendfidelity
                });
                if suc then
                    meshPart:ApplyMesh(real);
                    real:Destroy();
                end;
                table_remove(workers.meshWorkers,table_find(workers.meshWorkers,co));
            end);
            coroutine.resume(co,co);
        else
            meshPart:Destroy();
            meshPart=Instance.new("Part");
            local InitialSize=compile_prop("InitializeSize",prop.InitialSize,refs,class_name);
            local OrigSize=compile_prop("Size",prop.size,refs,class_name);
            -- everything else is applied during the properties step so we just need to set up the mesh
            local mesh=Instance.new("SpecialMesh",meshPart);
            mesh.MeshType=Enum.MeshType.FileMesh;
            mesh.MeshId=meshId;
            mesh.TextureId=textureId;
            mesh.Scale=OrigSize/InitialSize;
            mesh:SetAttribute("initialSize",InitialSize);
        end;
        meshPart.Parent=parent;
        return meshPart;
    end,
    --['SurfaceAppearance']=function(class_name,parent,inst,prop,refs,loadSettings)
    --    local propmaps={
    --        ColorMap=contentUri(prop.ColorMap.value),
    --        MetalnessMap=contentUri(prop.MetalnessMap.value),
    --        NormalMap=contentUri(prop.NormalMap.value),
    --        RoughnessMap=contentUri(prop.RoughnessMap.value),
    --    };
    --    local suc,surf=pcall(assetService.CreateSurfaceAppearanceAsync,assetService,propmaps);
    --    if not suc then
    --        warn("Failed to create SurfaceAppearance on MeshPart due to an error: "..tostring(surf));
    --        return Instance.new("SurfaceAppearance");
    --    end;
    --    surf.Parent=parent;
    --    return surf;
    --end,
    ["IntersectOperation"]=InstantiateSolidModel,
    ['NegateOperation']=InstantiateSolidModel,
    ["UnionOperation"]=InstantiateSolidModel,
    ["PartOperation"]=InstantiateSolidModel,
    ["Humanoid"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local humanoid=Instance.new("Humanoid");
        local healthprop=prop.Health or prop.Health_XML;
        humanoid.Parent=parent;
        humanoid.MaxHealth=prop.MaxHealth.value or 100;
        humanoid.Health=(healthprop~=nil and healthprop.value~=nil) and compile_prop("Health",healthprop,refs,class_name) or humanoid.MaxHealth;
        return humanoid;
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
    end
};
local InstancesCannotCreate={
    "PackageLink",
    "StockSound",
    "Geometry"
};
local propExceptions={
    "Attachment0",
    "Attachment1",
    "Part0",
    "Part1",
    "Value",
    "Adornee",
    "NextSelectionUp",
    "NextSelectionDown",
    "NextSelectionLeft",
    "NextSelectionRight",
    "SelectionImageObject",
    "PrimaryPart",
    "SoundGroup",
    "CameraSubject",
    "CustomPhysicalProperties",
    "MaterialVariant",
};
--[[ Build properties tree --]]
local function initProp(obj,propName,prop,refs,loadSettings)
    propName=string_upper(string_sub(propName,1,1))..string_sub(propName,2); --case the property correctly
    if (propName=="Color3uint8") then
        propName="Color"; -- fixes the format changes to RBXM
    elseif (propName=="Source") then
        obj:SetAttribute("Source",prop.value);
    elseif (propName=="Disabled" and prop.value==false) then
        obj:SetAttribute("IC_Enabled",not prop.value);
        if not mod.Configuration.DisableScripts then
            obj.Enabled=not prop.value;
        end;
    elseif ((propName=="Playing" or propName=="IsPlaying") and prop.value==true) then
        obj.Playing=false;
        obj:SetAttribute("IC_Playing",prop.value);
    elseif (propName=="Part1Internal") then
        obj.Part1=compile_prop("Part1",prop,refs,obj);
    elseif (propName=="Part0Internal") then
        obj.Part0=compile_prop("Part0",prop,refs,obj);
    elseif (propName=="MaterialVariantSerialized") then
        obj.MaterialVariant=compile_prop("MaterialVariant",prop,refs,obj);
    elseif (propName=="Locked" and mod.Configuration.UnlockParts) then
        obj.Locked=false;
        --some properties dont have the name they have ingame, we fix that here
    elseif (propName:find("_xml")) then
        propName=propName:match("(.*)_xml");
    end;
    if (obj and (obj[propName]~=nil or table_find(propExceptions,propName)) and propName~="Disabled" and propName~="Locked" and propName~="PivotOffset" and propName~="Playing" and propName~="IsPlaying") then
        obj[propName]=compile_prop(propName,prop,refs,obj);
    end;
end;
local function buildProps(instances,refs,loadSettings)
    for obj,inst in instances do
        for propName,prop in inst.properties do
            local suc,err=pcall(initProp,obj,propName,prop,refs,loadSettings);
            if not suc and mod.debug_mode then
                warn("Failed to apply property "..propName.." to instance: "..tostring(err));
            end;
        end;
        if loadSettings and loadSettings.ApplyAttributes and inst.attributes~=nil and type(inst.attributes)=="table" then
            for attrName,attr in inst.attributes do
                obj:SetAttribute(attrName,compile_prop(attrName,attr,refs,obj));
            end;
        end;
    end;
end;
--[[ Build model tree --]]
local function buildModel(base,parent,rbxmtree,refs,loadSettings)
    refs=refs or {};
    loadSettings=loadSettings or {};
    local unionWorkers={};
    local meshWorkers={};
    local instances={};
    local hierarcy={{parent,rbxmtree}};
    while #hierarcy>0 do
        local parent,tree=unpack(hierarcy[#hierarcy]);
        hierarcy[#hierarcy]=nil;
        for i=1,#tree do
            local inst=tree[i];
            local classname=inst.ClassName;
            if (not table_find(blocked_classes,inst.ClassName)) then
                local instance;
                local classInit=class_initializers[classname];
                if classInit then
                    --print_if_debug(loadSettings);
                    instance=classInit(classname,parent,inst,inst.properties,refs,loadSettings,{
                        unionWorkers=unionWorkers,
                        meshWorkers=meshWorkers,
                    });
                else
                    instance=Instance.new(classname);
                    instance.Parent=parent;
                end;
                if instance then
                    if instance:IsA("BasePart") then
                        instance.Anchored=true;
                        instance.CanCollide=false;
                    end;
                    refs[inst.Ref+1]=instance; -- refs are base-0
                    instances[instance]=inst;
                    if #inst.children>0 then
                        hierarcy[#hierarcy+1]={instance,inst.children};
                    end;
                end;
            end;
        end;
    end;
    while #unionWorkers>0 or #meshWorkers>0 do
        task_wait();
    end;
    buildProps(instances,refs,loadSettings);
    return parent;
end;
--[[ Initializes module --]]
function mod:initialize(config,main)
    if self.isInitialized then return end;
    self.isInitialized=true;
    self.Configuration=config;
    union.modules.modelAssembler=mod;
    union.modules.icloud=main;
    if self.Configuration.Sandboxed==true then
        sandbox_type="Sandbox";
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
        return buildModel(rootModel,rootModel,rbxm.tree,{},loadSettings);
    else
        warn("ModelAssembler is not initialized.");
        return nil;
    end;
end;
--[[ Creates a Script or LocalScript --]]
function mod:NewScript(isLocal)
    if isLocal then
        return templateCache[sandbox_type.."LocalScript"]:Clone();
    else
        return templateCache[sandbox_type.."Script"]:Clone();
    end;
end;
return mod;
