--!optimize 2

local Configuration={
    Caching=true,
    Sandboxed=true,
    DisableScripts=true,
    UnlockParts=true,
    DefaultSettings={
        AnchorParts=false,
        ApplyAttributes=true,
        DisableSolidModeling=false,
        EnableLegacyClientScripts=false,
        EnablePreciseMeshParts=true,
        ExperimentalUnions=false,
        FECompatible=false,
        RemoveDecals=false,
        RemoveScripts=false,
        GridSize=0.0, --no snap by default
        RotationSnap=45.0, -- 45 degrees default
    },
    DefaultParent=workspace,
    DefaultBuildParent=workspace,
    DebugMode=false,
    RetryOnRateLimit=true,
};
local HttpService=game:GetService("HttpService");
local ReplicatedStorage=game:GetService("ReplicatedStorage");
local modelAssembler=require(script.Dependancies.ModelAssembler);
local modelDefuser=require(script.Dependancies.ModelDefuser);
local serverplaceid=game.PlaceId; --server place id
local insertCloudCache={};
local SolidModeling={
    isInitialized=false,
    urlToFetch=nil,
};
export type QueueEntry={
    Sending:boolean,
    Send:()->(),
    AssetId:number,
    Fire:BindableEvent,
}
local queue={};
local queueSize=500;
--[[ Gets model center ]]
local function GetModelCenter(mdl:Model):CFrame
    local centercf,_=mdl:GetBoundingBox();
    local modelsize=mdl:GetExtentsSize();
    local baseCF=CFrame.new(centercf.Position)*CFrame.new(0,-modelsize.Y/2,0);
    return baseCF;
end;
local function initCenter(mdl:Model)
    local center=GetModelCenter(mdl);
    local cent_part=Instance.new("Part",mdl);
    cent_part.Name="CenterPart";
    cent_part.Anchored=true;
    cent_part.CanCollide=false;
    cent_part.Transparency=1;
    cent_part.Size=Vector3.new(1,1,1);
    cent_part.CFrame=center;
    mdl.PrimaryPart=cent_part;
end;
--[[
Logs various messages about the state of the module, and of <code>LoggerMessage.MessageType</code>
]]
export type LoggerMessage={
    MessageType: string,
    MessageText: string,
    Arguments: any,
}
local function logMsg(msg:LoggerMessage,...)
    local prefix="Insert Cloud:";
    if typeof(msg)=="string" then
        msg={
            MessageType="info",
            MessageText=msg,
        };
    end;
    if msg.MessageType=="warn" then
        warn(prefix.." "..msg.MessageText);
    elseif msg.MessageType=="info" then
        print(prefix,msg.MessageText);
    elseif msg.MessageType=="error" then
        warn(prefix.." ERR:"..msg.MessageText);
    else
        print(prefix,msg.MessageText); --indentical to info
    end;
    return msg.Arguments; -- return the error info if any
end;
--[[ PrintDebug ]]
local function print_if_debug(...)
    if Configuration.DebugMode then
        print(...);
    end;
end;
local function getDefaultSettings()
    return Configuration.DefaultSettings;
end;
local function handleQueue(url:string,assetId:number,ver:number,api_key:Secret,assetType:string)
    logMsg({
        MessageType="warn",
        MessageText="HTTP 429 (Too Many Requests) for asset " .. assetId .. " (Place ID: " .. serverplaceid .. ")."
    });
    local queueEntry:QueueEntry={
        IsRetry=true,
        Sending=false, --once this goes true, it will request the asset and remove it from queue
        Fire=Instance.new("BindableEvent");
        AssetId=assetId,
        Send=function()
            print("Retrying asset " .. assetId .. " (Place ID: " .. serverplaceid .. ") in queue.")
        end,
    };
    table.insert(queue,queueEntry);
    queueEntry.Fire.Event:Wait();
    local suc,res;
    return requestORQueue(url,assetId,ver,api_key,assetType); --try again
end;
function requestORQueue(url:string,assetId:number,ver:number,api_key:Secret,assetType:string)
    local full_url;
    if typeof(url)=="Secret" then
        local appended="/"..assetId.."?placeId="..serverplaceid;
        if ver then
            appended=appended.."&version="..tostring(ver); -- insert logs so we can load the same exact model (moderation purposes)
        end;
        if assetType then
            appended=appended.."&type="..assetType;
        end
        full_url=url:AddSuffix(appended);
    else
        full_url=url.."/"..assetId.."?placeId="..serverplaceid;
        if ver then
            full_url=full_url.."&version="..tostring(ver); -- insert logs so we can load the same exact model (moderation purposes)
        end;
        if assetType then
            full_url=full_url.."&type="..assetType
        end;
    end;
    local suc,res,errInf=nil,nil,nil;
    suc,res=pcall(function()
        local response=HttpService:RequestAsync({
            Url=full_url,
            Method="GET",
            Headers={
                ["Accept"]="application/json",
                ["x-api-key"]=api_key,
            },
        });
        if response.Success then
            --print("Response size:",#response.Body);
            local ok, parsed = pcall(function()
                return HttpService:JSONDecode(response.Body);
            end);
            if ok then
                return parsed;
            else
                logMsg({
                    MessageType="error",
                    MessageText="Failed to parse JSON for asset " .. assetId .. ": " .. tostring(parsed)
                });
                return nil;
            end;
        else
            local statusCode=response.StatusCode;
            local statusMessage=response.StatusMessage;
            if (statusCode==429 and #queue<=queueSize) and Configuration.RetryOnRateLimit then
                suc,res,errInf=handleQueue(url,assetId,ver,api_key,assetType)
                return (suc) and res or nil;
            else
                errInf=logMsg({
                    MessageType="error",
                    MessageText="Failed to load asset "..assetId.." due to request error: "..statusMessage.." ("..tostring(statusCode)..")",
                    Arguments={
                        StatusCode=statusCode,
                        StatusMessage=statusMessage
                    }
                });
            end;
            return nil;
        end;
    end);
    --if (not suc and tostring(res)=="Number of requests exceeded limit") and Configuration.RetryOnRateLimit then
    --    return handleQueue(url,assetId,placeId,ver,api_key,assetType);
    --end
    return suc,res,errInf;
end;
local function fetchAndDecode(assetid,ver,api_key,url,loadSettings,parent)
    local data={
        AssetIdParsed=assetid,
        modelData={},
    };
    local assetid_string=tostring(assetid);
    local suc,res,errInf=requestORQueue(url,assetid,ver,api_key);
    if suc then
        if res~=nil then
            data.modelData=res;
            local loaded=modelAssembler:buildAsset(data,parent,loadSettings or getDefaultSettings());
            initCenter(loaded);
            if loaded~=nil then
                logMsg({
                    MessageType="info",
                    MessageText="Loaded asset "..assetid_string.." successfully!"
                });
                return loaded;
            else
                logMsg({
                    MessageType="error",
                    MessageText="Failed to load asset "..assetid_string..": Model was nil"
                });
                return nil,errInf;
            end;
        else
            logMsg({
                MessageType="error",
                MessageText="Failed to load asset "..assetid_string..": Response was nil (did you do it correctly?)"
            });
            return nil,errInf;
        end;
    else
        errInf=tostring(res);
        logMsg({
            MessageType="error",
            MessageText="Failed to load asset "..assetid_string..": "..tostring(res)
        });
        return nil,errInf;
    end;
end;
local function PrepareAsset(model:Model,parent:Instance?,position:Vector3?,loadSettings)
    if typeof(model)~="Instance" or not model:IsA("Model") then
        logMsg({
            MessageType="error",
            MessageText="The model parameter must be a valid Model instance"
        });
        return nil;
    end;
    model:MakeJoints();
    if position then
        model:MoveTo(position);
    end;
    local anchorParts = loadSettings.AnchorParts;
    local removeDecals = loadSettings.RemoveDecals;
    local removeScripts = loadSettings.RemoveScripts;
    local desc=model:GetDescendants();
    for i=1,#desc do
        local v=desc[i];
        if (v:IsA("BasePart") and anchorParts) then
            v.Anchored=true;
        elseif (v:IsA("Decal") or v:IsA("Texture")) and removeDecals then
            v:Destroy();
        elseif (v:IsA("BaseScript") or v:IsA("ModuleScript")) and removeScripts then
            v:Destroy();
        end;
    end;
    model.Parent=parent or Configuration.DefaultParent or workspace;
end;
local mod={
    isInitialized=false,
    _VERSION="8.9.0", --module version
    _DEVELOPERS={
        ["Superduperdev2 (@Superduperbloxer2)"]="Lead Developer (RBXM Parser, LXM modifications, Insert Cloud Module)", -- aka Captian-obvious (Lead Developer)
        ["Fallen (@josejr0322)"]="Loadstring module", -- loadstring provided
        ["vxnquish (@TNA_Cup)"]="Collaborator (helped with a few things on the server side)", -- Collaborator
        ["god (@servertechnology)"]="the idea man", -- idea man
        ["metatablecat"]="LXM original code"
    },
    SolidModeling={
        isInitialized=false, --backwards compatible, since the primary initialize for solidModeling already checks if its initialized and does nothing if it is
    }
};
print("Insert Cloud v"..mod._VERSION.." by Superduperdev2 (@Superduperbloxer2) loaded successfully!");
--[[ Initializes the module ]]
function initialize()
    if mod.isInitialized then return end;
    mod.isInitialized=true;
    modelAssembler:initialize(Configuration,mod);
    local replicatedObjects=script:WaitForChild("ReplicatedStorage"):Clone();
    replicatedObjects.Parent=ReplicatedStorage;
    for i,v in pairs(replicatedObjects:GetChildren()) do
        if ReplicatedStorage:FindFirstChild(v.Name) then
            ReplicatedStorage:FindFirstChild(v.Name):Destroy();
        end;
        v.Parent=ReplicatedStorage;
        if v:FindFirstChild("MODULE") and v.MODULE:IsA("ObjectValue") then
            v.MODULE.Value=script;
        end;
    end;
    replicatedObjects:Destroy();
end;
--[[
Initializes the SolidModeling part of the module
]]
function initializeSolidModeling(fetchUrl:string|Secret)
    if SolidModeling.isInitialized then return end;
    if fetchUrl and typeof(fetchUrl)~="string" then return end;
    --if parseUrl and typeof(parseUrl)~="string" then return end;
    SolidModeling.isInitialized=true;
    SolidModeling.urlToFetch=fetchUrl;
    --modules.unionBuilder:initialize(parseUrl)
end;

initialize();
function mod:SetSolidModelingFetchUrl(url:string|Secret)
    SolidModeling.urlToFetch=url;
    if not SolidModeling.isInitialized then
        initializeSolidModeling(url);
    end;
end;

--[[
Loads model by ID <code>assetid</code> from <code>url</code> and returns a container model for it
]]
function mod:LoadAssetAsync(url:Secret|string,api_key:Secret,assetid:number,loadSettings,parent:Instance?,position:Vector3,ver:number):Model
    if type(url) ~= "string" and typeof(url)~="Secret" then return error("URL Parameter is invalid, must be a valid string") end;
    if type(assetid) ~= "number" then return error("AssetId Parameter is invalid, must be a valid number") end;
    if loadSettings and type(loadSettings) ~= "table" then return error("Settings Parameter is invalid, must be a valid table or nil") end;
    if not self.isInitialized then initialize(); end;
    if not SolidModeling.isInitialized then initializeSolidModeling(url); end;
    local modelContain=nil;
    local assetid_string=tostring(assetid);
    local ErrorInfo=nil;
    logMsg({
        MessageType="info",
        MessageText="Loading asset "..assetid_string
    });
    if Configuration.Caching then
        local cache=insertCloudCache[assetid_string];
        if cache then
            modelContain=cache:Clone();
            modelContain.Parent=parent;
            logMsg({
                MessageType="info",
                MessageText="Loaded asset "..assetid_string.." from cache successfully!"
            });
        else
            modelContain,ErrorInfo=fetchAndDecode(assetid,ver,api_key,url,loadSettings,parent);
            if modelContain then
                insertCloudCache[assetid_string]=modelContain:Clone();
            end;
        end;
    else
        modelContain,ErrorInfo=fetchAndDecode(assetid,ver,api_key,url,loadSettings,parent);
    end;
    PrepareAsset(modelContain,parent or mod.Configuration.DefaultBuildParent,position,loadSettings or getDefaultSettings());
    return modelContain,ErrorInfo;
end;
--[[ 
Loads a SolidModel asset and returns its ChildData property (used internally to make UnionOperations work)
]]
function mod:LoadSolidModel(assetid:number)
    if type(assetid) ~= "number" then return error("AssetId Parameter is invalid, must be a valid number") end;
    if not SolidModeling.isInitialized then
        logMsg({
            MessageType="error",
            MessageText="You must initialize the solid model part of module before calling the loadSolidModel method"
        });
        return nil;
    end;
    local assetid_string=tostring(assetid);
    local suc,res,err=requestORQueue(SolidModeling.urlToFetch,assetid,nil,nil,"SolidModel");
    if not suc then
        logMsg({
            MessageType="error",
            MessageText="Failed to load asset "..assetid_string..": "..tostring(res)
        });
        return nil;
    end;
    if res~=nil then
        print_if_debug(res);
        if res.tree then
            local instance=res.tree[1];
            if instance then
                return instance.properties.ChildData.value;
            end;
            return nil;
        end;
    else
        logMsg({
            MessageType="error",
            MessageText="Failed to load asset "..assetid_string..": Response was nil (did you do it correctly?)"
        });
        return nil;
    end;
end;
--[[ 
Gets default settings for loading assets 
]]
function mod:GetDefaultSettings()
    return getDefaultSettings();
end;

--[[ Clears the cache ]]
function mod:ClearCache()
    insertCloudCache={};
end;
function mod:RemoveFromCache(assetId:number)
    insertCloudCache[tostring(assetId)]=nil;
end;
--[[ 
Fixes model for completion of inserted object, insert tool also calls this for security 
]]
function mod:CompileAsset(model:Model,parent:Instance?)
    if not self.isInitialized then
        logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the compile_asset method"
        });
        return nil;
    end;
    if typeof(model)~="Instance" or not model:IsA("Model") then
        logMsg({
            MessageType="error",
            MessageText="The model parameter must be a valid Model instance"
        });
        return nil;
    end;
    pcall(function() model.PrimaryPart:Destroy() end);
    local desc=model:GetDescendants();
    modelDefuser:defuseInstances(desc);
    for i=1,#desc do
        local v=desc[i];
        if (v:IsA("Script") or v:IsA("LocalScript")) and v:GetAttribute("IC_Enabled") then
            v.Disabled=not v:GetAttribute("IC_Enabled");
        elseif v:IsA("Sound") then
            v.Playing=v:GetAttribute("IC_Playing");
        end;
    end;
    local root_instances=model:GetChildren();
    for i,v in pairs(root_instances) do
        v.Parent=parent or Configuration.DefaultParent or workspace;
    end;
    model:Destroy();
    return unpack(root_instances);
end;
--[[ 
Loads code based on a type, code, and the player
]]
function mod:LoadCode(code:string,typ:string,plr:Player,parent:Instance,enabled:boolean)
    local sandboxType=(Configuration.Sandboxed) and "Sandbox" or "Normal";
    local s = modelAssembler:NewScript((typ~="server") and true or false)
    s:SetAttribute("Source",tostring(code))
    if s:FindFirstChild("Player") then
        s.Player.Value=plr;
    end;
    s.Enabled = enabled;
    s.Parent = parent;
    return s;
end;

--[[ 
Restarts the server (requires *YOUR* API key) 
]]
function mod:RestartServer(url:string,apikey:string,reason:string):boolean?
    if not self.isInitialized then
        logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the RestartServer method"
        });
        return nil;
    end;
    if not url or type(url)~="string" or not apikey or type(apikey)~="string" then
        logMsg({
            MessageType="error",
            MessageText="The url and apikey parameters must be valid strings and must not be nil"
        });
        return nil;
    end;
    local full_url=url.."/restart";
    local suc,res=pcall(function()
        local response=HttpService:RequestAsync({
            Url=full_url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
                ["x-api-key"]=apikey,
            },
            Body=HttpService:JSONEncode({
                placeId=serverplaceid,
                jobId=game.JobId,
                reason=reason or "No reason provided",
            }),
        });
        if response.Success then
            return true;
        else
            logMsg({
                MessageType="error",
                MessageText="Failed to restart server due to request error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")"
            });
            return false;
        end;
    end);
    if not suc then
        logMsg({
            MessageType="error",MessageText="Failed to restart server: "..tostring(res)
        });
        return false;
    end;
    return res;
end;
--[[
Deprecated, Module initializes itself now
]]
@deprecated
function mod:initialize()
    return initialize();
end;
--[[
Deprecated, SolidModeling initializes itself now and lets you set the fetchUrl with SetSolidModelingFetchUrl()
]]
@deprecated
function mod:initializeSolidModeling(fetchUrl:string)
    return initializeSolidModeling(fetchUrl);
end;
--[[
Deprecated varient of InsertCloud:LoadAssetAsync()
]]
@deprecated
function mod:LoadAsset(url:string,assetid:number,loadSettings,parent:Instance?,position:Vector3,ver:number):Model
    --logMsg("warn","The LoadAsset method is deprecated, please use LoadAssetAsync instead");
    return self:LoadAssetAsync(url,assetid,loadSettings,parent,position,ver);
end;
--[[ 
Deprecated Varient of InsertCloud:CompileAsset()
]]
@deprecated
function mod:compile_asset(model:Model,parent:Instance?)
    return self:CompileAsset(model,parent)
end
--[[
Deprecated Varient of InsertCloud:RestartServer()
]]
@deprecated
function mod:restart_server(url:string,apikey:string,reason:string)
    return self:RestartServer(url,apikey,reason)
end
--[[ 
Deprecated varient of InsertCloud:LoadSolidModel()
]]
@deprecated
function mod:loadSolidModel(assetid:number)
    return self:LoadSolidModel(assetid)
end
--[[ 
Deprecated varient of InsertCloud:GetDefaultSettings()
]]
@deprecated
function mod:getDefaultSettings()
    return getDefaultSettings();
end;
--[[
Prints the developers of the module to console.
]]
function mod:credits()
    print("Insert Cloud v"..self._VERSION.." by:");
    for name,v in pairs(self._DEVELOPERS) do
        print("-",name, ":", v);
    end;
end;
--[[
Returns the module version
]]
function mod:getVersion()
    return self._VERSION;
end;

task.spawn(function()
    while task.wait(2) do
        if #queue>0 then
            local job:QueueEntry=queue[1];
            if job then
                task.spawn(function()
                    job.Send();
                    job.Fire:Fire();
                    task.delay(.1,function()
                        job.Fire:Destroy();
                    end);
                end);
            end;
            table.remove(queue,1);
        end;
    end;
end);

return mod;
