--!optimize 2

local Debris = game:GetService("Debris");
local knownMaliciousScripts={
    "Script, or is it???", -- infamous obfuscator signature
    "Script.....Or is it...",
    "ROFL", -- old script kiddie favorite
    "iNfEcTiOn",-- another old favorite
    "H4CK3D_BY_1337", -- yet another old favorite
    "NukerScript", -- very common malicious script name
    "Spread", -- often used in scripts that spread themselves
    "Vaccine", --nice try, but we know what you mean
    "Anti-Lag" --ironically, this is often used to cause lag
};
local knownMaliciousNames={
    "No samurai plzzz",
    "Anti Lag",
};
local possiblyMaliciousInstances={
    "JointInstance",
    "RotateP",
    "BodyPosition",
    "BodyGyro",
    "BodyVelocity",
    "Fire"
};
local mod={
    modules={},
};

function defuseScript(s)
    for _,maliciousName in pairs(knownMaliciousScripts) do
        if string.find(s.Name:lower(),maliciousName:lower()) then
            s.Parent=nil;
            Debris:AddItem(s,0);
            return true;
        end;
    end;
    return false;
end;

function defuseInstance(inst)
    local malicious=false;
    for _,className in pairs(possiblyMaliciousInstances) do
        if inst:IsA(className) then
            local tocheck=inst:FindFirstChildWhichIsA("BaseScript");
            if (tocheck) then
                tocheck.Parent=nil;
                Debris:AddItem(tocheck,0);
                malicious=true;
            end;
        end;
    end;
    for _,maliciousName in pairs(knownMaliciousNames) do
        if string.find(inst.Name:lower(),maliciousName:lower()) then
            inst.Parent=nil;
            Debris:AddItem(inst,0);
            malicious=true;
        end;
    end;
    return malicious;
end;
function mod:defuseInstances(instances)
    if not instances then
        return;
    end;
    for i=1,#instances do
        local item=instances[i];
        if item:IsA("BaseScript") then
            if defuseScript(item) then
                print("Defused malicious script: "..item:GetFullName());
            end;
        else
            if defuseInstance(item) then
                print("Defused malicious instance: "..item:GetFullName());
            end;
        end;
    end;
end;

return mod;
