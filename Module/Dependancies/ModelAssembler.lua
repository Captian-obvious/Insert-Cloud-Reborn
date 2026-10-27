--!optimize 2
local assetService=game:GetService("AssetService");
local sandbox_type="Normal";
local Templates=script.TEMPLATE_OBJECTS;
local contentUri=Content.fromUri;
local contentObj=Content.fromObject;
local table_find=table.find;
local table_insert=table.insert;
local table_clone=table.clone;
local table_remove=table.remove;
local table_pack=table.pack;
local table_move=table.move;
local table_sort=table.sort;
local table_concat=table.concat;
local table_unpack=table.unpack;
local table_pack=table.pack;
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
local string_len=string.len;
local string_find=string.find;
local string_match=string.match;
local table_clone=table.clone;
local Instance_new=Instance.new;
local CFrame_new=CFrame.new;
local b64=require(script.Parent.Base64); -- base64 encoding/decoding
local union=require(script.Parent.UnionOperation); -- Creates UnionOperations from their data
local promise=require(script.Parent.Worker); -- Parallelization
local b64_decode=b64.decode;
local b64_encode=b64.encode;
local spawnWorker=promise.spawnWorker;
local spawnWorkerDeferred=promise.spawnWorkerDeferred;

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
local loadingMeshes={};
local function colorFunc(propType,value)
    if value then
        if propType=="brickcolor" then
            if type(value)=="number" then -- why is the internal id of brickcolor "Float"? (roblox, your wierd)
                return BrickColor.new(value);
            end;
        elseif propType=="color3" then
            return Color3.new(unpack(value));
        elseif propType=="rgbc3" then
            return Color3.fromRGB(unpack(value));
        end;
    elseif propType=="brickcolor" then
        return BrickColor.new("Medium stone grey");
    end;
    return Color3.new();
end;
local propertyTypes={
    -- things that need additonal parsing go here
    ["string"]=function(typed,value,refs,encoded)
        if encoded==nil then encoded=false end;
        if encoded then
            return b64_decode(value);
        else
            return value;
        end;
    end,
    ["content"]=function(typed,value,refs,contentType)
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
        return b64_decode(value);
    end,
    ["enum"]=function(typed,value,refs,prop_instance)
        local propName=prop_instance.propName;
        local classInstance=prop_instance.classInstance;
        if not classInstance then return nil; end;
        local success, defaultVal = pcall(function() return classInstance[propName]; end);
        if success then
            return resolveEnumInteger(defaultVal.EnumType,value);
        end;
        warn("Enum inference failed for property:", propName, "on", tostring(classInstance));
        return nil;
    end,
    ["cframe"]=function(typed,value,refs)
        local pos=value.position.vector3 or {0,0,0};
        local rot=value.rotation;
        if pos and rot and #rot==9 then
            local x,y,z=unpack(pos);
            return CFrame_new(x,y,z,unpack(rot));
        elseif pos then
            return CFrame_new(Vector3.new(unpack(pos)));
        end;
        return CFrame_new();
    end,
    ["qcframe"]=function(typed,value,refs)
        if not value or #value~=7 then return CFrame_new(); end;
        return CFrame_new(unpack(value));
    end,
    ["vector3int16"]=function(typed,value,refs)
        if value and #value==3 then
            return Vector3.new(unpack(value));
        end;
        return Vector3.new(); 
    end,
    ["vector3"]=function(typed,value,refs)
        if value and #value==3 then
            return Vector3.new(unpack(value));
        end;
        return Vector3.new(); 
    end,
    ["vector2"]=function(typed,value,refs)
        if value and #value==2 then
            return Vector2.new(unpack(value));
        end;
        return Vector2.new(); 
    end,
    ["udim"]=function(typed,value,refs)
        if value and value.scale and value.offset then
            return UDim.new(value.scale,value.offset)
        elseif value and #value==2 then --backwards compatibility to python parser
            return UDim.new(unpack(value));
        end;
        return UDim.new();
    end,
    ["udim2"]=function(typed,value,refs)
        if value and value.x and value.y then
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
        return colorFunc(typed,value);
    end,
    ["numberrange"]=function(typed,value,refs)
        if value and #value==2 then
            return NumberRange.new(value[1],value[2]);
        end;
        return NumberRange.new(1); 
    end,
    ["numbersequence"]=function(typed,value,refs)
        if value then
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
        if value then
            local keypoints={};
            for _,kp in pairs(value) do
                local cskp=kp.cskp;
                if cskp and typeof(cskp)=="table" then
                    table_insert(keypoints,ColorSequenceKeypoint.new(cskp.t,colorFunc("color3",cskp.color3)));
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
        return colorFunc(typed,value);
    end,
    ["color3"]=function(typed,value,refs)
        return colorFunc(typed,value);
    end,
    ["physprops"]=function(typed,value,refs)
        if value and #value==6 then
            return PhysicalProperties.new(unpack(value)); --no breakage from format changes GRRRR
        end;
        return nil;
    end,
    ["font"]=function(typed,value,refs)
        if value and typeof(value) == "table" then
            local family = value.fontFamily or "rbxasset://fonts/families/LegacySerif.json";
            local weight = value.fontWeight or 400;
            local style = value.fontStyle or 0;
            return Font.new(family,resolveEnumInteger(Enum.FontWeight,weight),resolveEnumInteger(Enum.FontStyle,style));
        end;
        return Font.new("rbxasset://fonts/families/LegacySerif.json");
    end,
    ["rect"]=function(typed,value,refs)
        if typeof(value)~="table" then return Rect.new() end;
        if not value.pos1 or not value.pos2 then return Rect.new() end;
        if typeof(value.pos1)~="table" or typeof(value.pos2)~="table" then return Rect.new() end;
        if #value.pos1<2 or #value.pos2<2 then return Rect.new() end;
        return Rect.new(value.pos1[1],value.pos1[2],value.pos2[1],value.pos2[2]);
    end,
    ["ref"]=function(typed,value,refs)
        if value<0 then return nil end;
        return refs[value];
    end,
};
local function compile_prop(prop,v,refs,class)
    local value=v.value;
    local typed=v.type;
    local compile=propertyTypes[typed];
    if compile then
        if typed=="enum" then
            return compile(typed,value,refs,{propName=prop,classInstance=class});
        elseif typed=="string" then
            return compile(typed,value,refs,v.enc);
        elseif typed=="content" then
            return compile(typed,value,refs,v.ctyp);
        else
            return compile(typed,value,refs);
        end;
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
        local h=Instance_new(class_name);
        h.Parent=parent;
        return h;
    end;
    local typeToInit=(class_name~="NegateOperation") and class_name or "UnionOperation";
    local isIntersection=(typeToInit=="IntersectOperation");
    local experimental=loadSettings.ExperimentalUnions;
    local part=Instance_new(typeToInit);
    part.Parent=parent;
    --spawnWorker(workers,function()
    local suc,err=pcall(function()
        local model;
        local childData=(prop.ChildData~=nil and prop.ChildData.value~=nil and type(prop.ChildData.value)=="string" and string_len(prop.ChildData.value)>0) and prop.ChildData.value or nil;
        local childData2=(prop.ChildData2~=nil and prop.ChildData2.value~=nil and type(prop.ChildData2.value)=="string" and string_len(prop.ChildData2.value)>0) and prop.ChildData2.value or nil;
        local assetData=(prop.AssetData~=nil and prop.AssetData.value~=nil and type(prop.AssetData.value)=="string" and string_len(prop.AssetData.value)>0) and prop.AssetData.value or nil;
        local assetId=(prop.AssetId~=nil and prop.AssetId.value~=nil and type(prop.AssetId.value)=="string" and string_len(prop.AssetId.value)>0) and prop.AssetId.value or nil;
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
        if childData~=nil or childData2~=nil then
            local data=(childData2~=nil) and childData2 or childData;
            local thefunc;
            if experimental then
                thefunc=union.applyChildDataNew;
            else
                thefunc=union.applyChildData;
            end;
            model=thefunc(union,data,options,isIntersection);
        elseif assetData~=nil then
            model=union:applyAssetData(assetData,options,isIntersection,experimental);
        elseif assetId~=nil then
            model=union:applyAssetId(assetId,options,isIntersection,experimental);
        end;
        if model~=nil then
            part:SubstituteGeometry(model);
            model:Destroy();
        end;
    end);
    if not suc then
        warn("Error instantiating solid model: "..err);
    end;
    --end);
    local tags=inst.tags;
    if (class_name=="NegateOperation") or (tags and table_find(tags,"rbxNegated")) then
        part:SetAttribute("IsNegateOperation",true);
    end;
    return part;
end;
local blocked_classes={
    ["DialogChoice"]=true,
    ["Dialog"]=true,
    ["Message"]=true,
    ["Hint"]=true,
    ["SkateboardPlatform"]=true,
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
        local meshPart=Instance_new("MeshPart");
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
            meshPart:SetAttribute("MeshId",meshId);
            meshPart:SetAttribute("TextureId",textureId);
            local idVal=string_match(meshId,"(%d+)$");
            local idNum=tonumber(idVal);
            local isLocal=string_match(meshId,"^rbxasset://");
            if not idNum and not isLocal then
                warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: ID is not a number or local asset.")
                return meshPart;
            end;
            local cacheName;
            if isLocal then
                local localfilekey,_=string_gsub(meshId,"[^%w]", "_");
                cacheName="Mesh_"..localfilekey;
            else
                cacheName="Mesh_"..tostring(idNum);
            end;
            local findCache=meshCache[cacheName];
            local isAssetLoading=loadingMeshes[meshId];
            if findCache~=nil then
                meshPart:ApplyMesh(findCache);
            elseif isAssetLoading then
                while loadingMeshes[meshId] do
                    task_wait();
                end;
                findCache=meshCache[cacheName];
                if findCache~=nil then
                    meshPart:ApplyMesh(findCache);
                end;
            else
                spawnWorker(workers,function()
                    loadingMeshes[meshId]=true;
                    local suc,new=pcall(assetService.CreateMeshPartAsync,assetService,contentUri(meshId),{
                        CollisionFidelity=colfidelity,
                        RenderFidelity=rendfidelity
                    });
                    loadingMeshes[meshId]=nil;
                    if not suc then
                        warn("Failed to generate MeshPart with asset location \""..meshId.."\" due to error: "..tostring(new));
                        return;
                    else
                        meshPart:ApplyMesh(new);
                        meshCache[cacheName]=meshPart:Clone();
                        new:Destroy();
                    end;
                end);
            end;
            meshPart.TextureID=textureId;
        else
            meshPart:Destroy();
            meshPart=Instance.new("Part");
            local InitialSize=compile_prop("InitializeSize",prop.InitialSize,refs,class_name);
            local OrigSize=compile_prop("Size",prop.size,refs,class_name);
            -- everything else is applied during the properties step so we just need to set up the mesh
            local mesh=Instance_new("SpecialMesh",meshPart);
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
    --        return Instance_new("SurfaceAppearance");
    --    end;
    --    surf.Parent=parent;
    --    return surf;
    --end,
    ["IntersectOperation"]=InstantiateSolidModel,
    ['NegateOperation']=InstantiateSolidModel,
    ["UnionOperation"]=InstantiateSolidModel,
    ["PartOperation"]=InstantiateSolidModel,
    ["Humanoid"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local humanoid=Instance_new("Humanoid");
        local healthprop=prop.Health or prop.Health_XML;
        humanoid.Parent=parent;
        humanoid.MaxHealth=prop.MaxHealth.value or 100;
        humanoid.Health=(healthprop~=nil and healthprop.value~=nil) and compile_prop("Health",healthprop,refs,class_name) or humanoid.MaxHealth;
        return humanoid;
    end,
    ["PackageLink"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance_new("Folder");
        obj.Parent=parent;
        obj.Name="PackageLink";
        --obj:SetAttribute("AssetId",prop.AssetId.value);
        return obj;
    end,
    ["StockSound"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance_new("Folder");
        obj.Parent=parent;
        obj.Name="StockSound";
        return obj;
    end,
    ["Geometry"]=function(class_name,parent,inst,prop,refs,loadSettings)
        local obj=Instance_new("Folder");
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
    ["Attachment0"]=true,
    ["Attachment1"]=true,
    ["Part0"]=true,
    ["Part1"]=true,
    ["Value"]=true,
    ["Adornee"]=true,
    ["NextSelectionUp"]=true,
    ["NextSelectionDown"]=true,
    ["NextSelectionLeft"]=true,
    ["NextSelectionRight"]=true,
    ["SelectionImageObject"]=true,
    ["PrimaryPart"]=true,
    ["SoundGroup"]=true,
    ["CameraSubject"]=true,
    ["CustomPhysicalProperties"]=true,
    ["MaterialVariant"]=true,
};
--[[ Build properties tree --]]
local function initProp(obj,propName,prop,refs,loadSettings)
    propName=string_upper(string_sub(propName,1,1))..string_sub(propName,2); --case the property correctly
    local propVal=prop.value;
    if (propName=="Color3uint8") then
        propName="Color"; -- fixes the format changes to RBXM
    elseif (propName=="Source") then
        obj:SetAttribute("Source",propVal);
    elseif (propName=="Disabled" and propVal==false) then
        obj:SetAttribute("IC_Enabled",not propVal);
        if not mod.Configuration.DisableScripts then
            obj.Enabled=not propVal;
        end;
    elseif ((propName=="Playing" or propName=="IsPlaying") and propVal==true) then
        obj.Playing=false;
        obj:SetAttribute("IC_Playing",propVal);
    elseif (propName=="Part1Internal") then
        obj.Part1=compile_prop("Part1",prop,refs,obj);
    elseif (propName=="Part0Internal") then
        obj.Part0=compile_prop("Part0",prop,refs,obj);
    elseif (propName=="MaterialVariantSerialized") then
        obj.MaterialVariant=compile_prop("MaterialVariant",prop,refs,obj);
    elseif (propName=="Locked" and mod.Configuration.UnlockParts) then
        obj.Locked=false;
        --some properties dont have the name they have ingame, we fix that here
    elseif (string_find(propName,"_")) then
        propName=string_match(propName,"(.*)_");
    end;
    if (obj and (obj[propName]~=nil or propExceptions[propName]) and propName~="Disabled" and propName~="Locked" and propName~="PivotOffset" and propName~="Playing" and propName~="IsPlaying") then
        obj[propName]=compile_prop(propName,prop,refs,obj);
    end;
end;
local function buildProps(instances,refs,loadSettings)
    local applyAttrs=loadSettings and loadSettings.ApplyAttributes;
    for i=1,#instances do
        local obj,props,attrs=table_unpack(instances[i]);
        for propName, prop in props do
            pcall(initProp,obj,propName,prop,refs,loadSettings);
        end;
        if applyAttrs and attrs~=nil then
            for attrName,attr in attrs do
                pcall(obj.SetAttribute,obj,attrName,compile_prop(attrName,attr,refs,obj));
            end;
        end;
    end;
end;
--[[ Build model tree --]]
local function buildModel(base,parent,rbxmtree,refs,loadSettings)
    refs=refs or {};
    loadSettings=loadSettings or {};
    local maxWorkers=mod.Configuration.MaxChildrenPerFrame;
    local workers:promise.Worker={
        PendingWorkers={},
        MaxWorkers=maxWorkers,
        ActiveWorkers=0,
    };
    local instances={};
    local hierarcy={{parent,rbxmtree}};
    while #hierarcy>0 do
        local parent,tree=table_unpack(hierarcy[#hierarcy]);
        hierarcy[#hierarcy]=nil;
        for i=1,#tree do
            local inst=tree[i];
            local classname=inst.ClassName;
            if (not blocked_classes[classname]) then
                local instance;
                local props=inst.properties;
                local children=inst.children;
                local classInit=class_initializers[classname];
                if classInit then
                    --print_if_debug(loadSettings);
                    instance=classInit(classname,parent,inst,props,refs,loadSettings,workers);
                else
                    instance=Instance_new(classname);
                    instance.Parent=parent;
                end;
                if instance then
                    if instance:IsA("BasePart") then
                        instance.Anchored=true;
                        instance.CanCollide=false;
                    end;
                    refs[inst.Ref]=instance; -- refs are base-0
                    instances[#instances+1]={instance,props,inst.attributes};
                    if #children>0 then
                        hierarcy[#hierarcy+1]={instance,children};
                    end;
                end;
            end;
        end;
    end;
    promise.waitForWorkers(workers);
    buildProps(instances,refs,loadSettings);
    --local applyAttrs=loadSettings and loadSettings.ApplyAttributes;
    --for i=1,#instances do
    --    local obj,props,attrs=table_unpack(instances[i]);
    --    for propName, prop in props do
    --        pcall(initProp,obj,propName,prop,refs,loadSettings);
    --    end;
    --    if applyAttrs and attrs~=nil then
    --        for attrName,attr in attrs do
    --            pcall(obj.SetAttribute,obj,attrName,compile_prop(attrName,attr,refs,obj));
    --        end;
    --    end;
    --end;
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
        local rootModel=Instance_new("Model");
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
--[[ Creates a Script or LocalScript `LoadCode` --]]
function mod:NewScript(isLocal,sandboxType)
    local currentType = sandboxType or (self.Configuration.Sandboxed and "Sandbox" or "Normal");
    if isLocal then
        return templateCache[currentType.."LocalScript"]:Clone();
    else
        return templateCache[currentType.."Script"]:Clone();
    end;
end;
return mod;
