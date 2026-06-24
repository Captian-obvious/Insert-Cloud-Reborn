local mod={
    isInitialized=false,
    _VERSION="5.3.0",
    _DEVELOPERS={
        ["Superduperdev2 (@Superduperbloxer2)"]="Lead Developer (RBXM Parser, Insert Cloud Module)", -- aka Captian-obvious (Lead Developer)
        ["Fallen (@josejr0322)"]="Loadstring module", -- loadstring provided
        ["vxnquish (@TNA_Cup)"]="Collaborator (helped with a few things on the server side)", -- Collaborator
        ["god (@servertechnology)"]="the idea man" -- idea man
    },
    modules={
        modelAssembler=require(script.Dependancies.ModelAssembler),
        json=require(script.Dependancies.JSON),
        unionBuilder=require(script.Dependancies.UnionOperation),
        modelDefuser=require(script.Dependancies.ModelDefuser),
    },
    Services={
        HttpService=game:GetService("HttpService"),
        ReplicatedStorage=game:GetService("ReplicatedStorage"),
        InsertService=game:GetService("InsertService"),
    },
    SolidModeling={
        isInitialized=false,
        urlToFetch=nil,
    },
    Configuration={
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
    },
    debug_mode=false,
};
function get_model_center_old(mdl:Model):CFrame
    local x_sum,z_sum,x_tot,z_tot,y_low=0,0,0,0,math.huge;
    for i,v in ipairs(mdl:GetDescendants())do
        if v:IsA("BasePart") then
            local pos=v.Position;
            x_tot = x_tot + 1;
            z_tot = z_tot + 1;
            x_sum = x_sum + pos.X;
            z_sum = z_sum + pos.Z;
            local y=pos.Y - v.Size.Y/2;
            if y < y_low then
                y_low = y;
            end;
        end;
    end;
    return CFrame.new(x_sum/x_tot,y_low,z_sum/z_tot);
end;
--[[ Gets model center ]]
function get_model_center(mdl:Model):CFrame
    local centercf,_=mdl:GetBoundingBox();
    local modelsize=mdl:GetExtentsSize();
    local baseCF=CFrame.new(centercf.Position)*CFrame.new(0,-modelsize.Y/2,0);
    return baseCF;
end;
function initCenter(mdl:Model)
    local center=get_model_center(mdl);
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
function mod:logMsg(msg:LoggerMessage,...)
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
function print_if_debug(...)
    if mod.debug_mode then
        print(...);
    end;
end;
--[[ Initializes the module ]]
function mod:initialize()
    if self.isInitialized then return end;
    self.isInitialized=true;
    self.modules.modelAssembler:initialize(self.Configuration,self);
    local replicatedObjects=script:WaitForChild("ReplicatedStorage"):Clone();
    replicatedObjects.Parent=self.Services.ReplicatedStorage;
    for i,v in pairs(replicatedObjects:GetChildren()) do
        if self.Services.ReplicatedStorage:FindFirstChild(v.Name) then
            self.Services.ReplicatedStorage:FindFirstChild(v.Name):Destroy();
        end;
        v.Parent=self.Services.ReplicatedStorage;
        if v:FindFirstChild("MODULE") and v.MODULE:IsA("ObjectValue") then
            v.MODULE.Value=script;
        end;
    end;
    replicatedObjects:Destroy();
end;
--[[
Initializes the SolidModeling part of the module
]]
function mod:initializeSolidModeling(fetchUrl:string, parseUrl:string)
    if self.SolidModeling.isInitialized then return end;
    if fetchUrl and typeof(fetchUrl)~="string" then return end;
    if parseUrl and typeof(parseUrl)~="string" then return end;
    self.SolidModeling.isInitialized=true;
    self.SolidModeling.urlToFetch=fetchUrl;
    self.modules.unionBuilder.parseUrl=parseUrl;
end;
--[[
Loads model by ID <code>assetid</code> from <code>url</code> and returns a container model for it
]]
function mod:LoadAssetAsync(url:string|Secret,assetid:number,loadSettings,parent:Instance?,position:Vector3,ver:number):Model
    if type(url) ~= "string" and typeof(url)~="Secret" then return error("URL Parameter is invalid, must be a valid string") end;
    if type(assetid) ~= "number" then return error("AssetId Parameter is invalid, must be a valid number") end;
    if loadSettings and type(loadSettings) ~= "table" then return error("Settings Parameter is invalid, must be a valid table or nil") end;
    if self.isInitialized then
        local theCache=self.Services.ReplicatedStorage:FindFirstChild("Cache") or Instance.new("Folder",self.Services.ReplicatedStorage);
        theCache.Name="Cache";
        local modelContain=nil;
        local assetid_string=tostring(assetid);
        local function fetchAndDecode()
            local data={
                AssetIdParsed=assetid,
                modelData={},
            };
            local full_url;
            if typeof(url)=="Secret" then
                appended="/"..assetid_string.."?placeId="..game.PlaceId;
                if ver then
                    appended=appended.."&version="..tostring(ver); -- insert logs so we can load the same exact model (moderation purposes)
                end;
                full_url=url:AddSuffix(appended)
            else
                full_url=url.."/"..assetid_string.."?placeId="..game.PlaceId;
                if ver then
                    full_url=full_url.."&version="..tostring(ver); -- insert logs so we can load the same exact model (moderation purposes)
                end;
            end;
            local errInf=nil;
            local suc,res=pcall(function()
                local response=self.Services.HttpService:RequestAsync({
                    Url=full_url,
                    Method="GET",
                    Headers={
                        ["Accept"]="application/json",
                    },
                });
                if response.Success then
                    print("Response size:",#response.Body);
                    local ok, parsed = pcall(function()
                        return self.modules.json.decode(response.Body);
                    end);
                    if ok then
                        return parsed;
                    else
                        self:logMsg({
                            MessageType="error",
                            MessageText="Failed to parse JSON for asset " .. assetid_string .. ": " .. tostring(parsed)
                        });
                        return nil;
                    end;
                else
                    local statusCode=response.StatusCode;
                    local statusMessage=response.StatusMessage;
                    errInf=self:logMsg({
                        MessageType="error",
                        MessageText="Failed to load asset "..assetid_string.." due to request error: "..statusMessage.." ("..tostring(statusCode)..")",
                        Arguments={
                            StatusCode=statusCode,
                            StatusMessage=statusMessage
                        }
                    });
                    return nil;
                end;
            end);
            if suc then
                if res~=nil then
                    data.modelData=res;
                    local loaded=self.modules.modelAssembler:buildAsset(data,parent,loadSettings or self:getDefaultSettings());
                    initCenter(loaded);
                    self.modules.modelDefuser:defuseModel(loaded);
                    if loaded~=nil then
                        self:logMsg({
                            MessageType="info",
                            MessageText="Loaded asset "..assetid_string.." successfully!"
                        });
                        return loaded;
                    else
                        self:logMsg({
                            MessageType="error",
                            MessageText="Failed to load asset "..assetid_string..": Model was nil"
                        });
                        return nil,errInf;
                    end;
                else
                    mod:logMsg({
                        MessageType="error",
                        MessageText="Failed to load asset "..assetid_string..": Response was nil (did you do it correctly?)"
                    });
                    return nil,errInf;
                end;
            else
                errInf=tostring(res);
                mod:logMsg({
                    MessageType="error",
                    MessageText="Failed to load asset "..assetid_string..": "..tostring(res)
                });
                return nil,errInf;
            end;
        end;
        local ErrorInfo=nil;
        self:logMsg({
            MessageType="info",
            MessageText="Loading asset "..assetid_string
        });
        if self.Configuration.Caching then
            local cache=theCache:FindFirstChild(assetid_string);
            if cache then
                modelContain=cache:Clone();
                modelContain.Parent=parent;
                self:logMsg({
                    MessageType="info",
                    MessageText="Loaded asset "..assetid_string.." from cache successfully!"
                });
            else
                modelContain,ErrorInfo=fetchAndDecode();
                if modelContain then
                    local newCache=modelContain:Clone();
                    newCache.Parent=theCache;
                end;
            end;
        else
            modelContain,ErrorInfo=fetchAndDecode();
        end;
        self:PrepareAsset(modelContain,parent or mod.Configuration.DefaultBuildParent,position,loadSettings or self:getDefaultSettings());
        return modelContain,ErrorInfo;
    else
        self:logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the LoadAsset method"
        });
        return nil;
    end;
end;
--[[ 
Loads a SolidModel asset and returns its ChildData property (used internally to make UnionOperations work)
]]
function mod:LoadSolidModel(assetid:number)
    if type(assetid) ~= "number" then return error("AssetId Parameter is invalid, must be a valid number") end;
    if self.SolidModeling.isInitialized then
        local assetid_string=tostring(assetid);
        local full_url=self.SolidModeling.urlToFetch.."/"..assetid_string.."?placeId="..game.PlaceId.."&type=SolidModel";
        local suc,res=pcall(function()
            local response=self.Services.HttpService:RequestAsync({
                Url=full_url,
                Method="GET",
                Headers={
                    ["Accept"]="application/json",
                },
            });
            if response.Success then
                local ok, parsed = pcall(function()
                    return self.modules.json.decode(response.Body);
                end);
                if ok then
                    return parsed;
                else
                    self:logMsg({
                        MessageType="error",
                        MessageText="Failed to parse JSON for asset " .. assetid_string .. ": " .. tostring(parsed)
                    });
                    return nil;
                end;
            else
                self:logMsg({
                    MessageType="error",
                    MessageText="Failed to load asset "..assetid_string.." due to request error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")"
                });
                return nil;
            end;
        end);
        if suc then
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
                mod:logMsg({
                    MessageType="error",
                    MessageText="Failed to load asset "..assetid_string..": Response was nil (did you do it correctly?)"
                });
                return nil;
            end;
        else
            mod:logMsg({
                MessageType="error",
                MessageText="Failed to load asset "..assetid_string..": "..tostring(res)
            });
            return nil;
        end;
    else
        self:logMsg({
            MessageType="error",
            MessageText="You must initialize the solid model part of module before calling the loadSolidModel method"
        });
        return nil;
    end;
end;
--[[ 
Gets default settings for loading assets 
]]
function mod:GetDefaultSettings()
    return self.Configuration.DefaultSettings;
end;
--[[ 
Initializes model for compiling 
]]
function mod:PrepareAsset(model:Model,parent:Instance?,position:Vector3?,loadSettings)
    if not self.isInitialized then
        self:logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the PrepareAsset method"
        });
        return nil;
    end;
    if typeof(model)~="Instance" or not model:IsA("Model") then
        self:logMsg({
            MessageType="error",
            MessageText="The model parameter must be a valid Model instance"
        });
        return nil;
    end;
    model.Parent=workspace;
    model:MakeJoints();
    if position then
        model:MoveTo(position);
    end;
    local desc=model:GetDescendants();
    if loadSettings.AnchorParts then
        for i=1,#desc do
            local v=desc[i];
            if v:IsA("BasePart") then
                v.Anchored=true;
            end;
        end;
    end;
    if loadSettings.RemoveDecals then
        for i=1,#desc do
            local v=desc[i];
            if v:IsA("Decal") or v:IsA("Texture") then
                v:Destroy();
            end;
        end;
    end;
    if loadSettings.RemoveScripts then
        for i=1,#desc do
            local v=desc[i];
            if v:IsA("BaseScript") or v:IsA("ModuleScript") then
                v:Destroy();
            end;
        end;
    end;
    model.Parent=parent or self.Configuration.DefaultParent or workspace;
end;
--[[ 
Fixes model for completion of inserted object, insert tool also calls this for security 
]]
function mod:CompileAsset(model:Model,parent:Instance?)
    if not self.isInitialized then
        self:logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the compile_asset method"
        });
        return nil;
    end;
    if typeof(model)~="Instance" or not model:IsA("Model") then
        self:logMsg({
            MessageType="error",
            MessageText="The model parameter must be a valid Model instance"
        });
        return nil;
    end;
    pcall(function() model.PrimaryPart:Destroy() end);
    local desc=model:GetDescendants();
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
        v.Parent=parent or self.Configuration.DefaultParent or workspace;
    end;
    model:Destroy();
    return unpack(root_instances);
end;
--[[ 
Loads code based on a type, code, and the player
]]
function mod:LoadCode(code:string,typ:string,plr:Player,parent:Instance,enabled:boolean)
    local sandboxType=self.Configuration.Sandboxed and "Sandbox" or "Normal";
    if typ=="server" then
        local s = self.modules.modelAssembler.Templates:FindFirstChild(sandboxType.."Script"):Clone();
        s:SetAttribute("Source",tostring(code))
        s.Player.Value = plr;
        s.Parent = parent;
        s.Enabled = enabled;
        return s;
    elseif typ=="client" then
        local s = self.modules.modelAssembler.Templates:FindFirstChild(sandboxType.."LocalScript"):Clone();
        s:SetAttribute("Source",tostring(code));
        s.Parent = parent or plr.PlayerGui;
        s.Enabled = enabled;
        return s;
    end;
end;

--[[ 
Restarts the server (requires *YOUR* API key) 
]]
function mod:RestartServer(url:string,apikey:string,reason:string):boolean?
    if not self.isInitialized then
        self:logMsg({
            MessageType="error",
            MessageText="You must initialize the module before calling the RestartServer method"
        });
        return nil;
    end;
    if not url or type(url)~="string" or not apikey or type(apikey)~="string" then
        self:logMsg({
            MessageType="error",
            MessageText="The url and apikey parameters must be valid strings and must not be nil"
        });
        return nil;
    end;
    local full_url=url.."/restart";
    local suc,res=pcall(function()
        local response=self.Services.HttpService:RequestAsync({
            Url=full_url,
            Method="POST",
            Headers={
                ["Content-Type"]="application/json",
                ["x-api-key"]=apikey,
            },
            Body=self.modules.json.encode({
                placeId=game.PlaceId,
                jobId=game.JobId,
                reason=reason or "No reason provided",
            }),
        });
        if response.Success then
            return true;
        else
            self:logMsg({
                MessageType="error",
                MessageText="Failed to restart server due to request error: "..response.StatusMessage.." ("..tostring(response.StatusCode)..")"
            });
            return false;
        end;
    end);
    if not suc then
        self:logMsg({
            MessageType="error",MessageText="Failed to restart server: "..tostring(res)
        });
        return false;
    end;
    return res;
end;
--[[
Deprecated varient of InsertCloud:LoadAssetAsync()
]]
@deprecated
function mod:LoadAsset(url:string,assetid:number,loadSettings,parent:Instance?,position:Vector3,ver:number):Model
    --self:logMsg("warn","The LoadAsset method is deprecated, please use LoadAssetAsync instead");
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
Deprecated Varient of InsertCloud:PrepareAsset()
]]
@deprecated
function mod:prepare_asset(model:Model,parent:Instance?,position:Vector3?,loadSettings)
    return self:PrepareAsset(model,parent,position,loadSettings)
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
    return self:GetDefaultSettings();
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

return mod;