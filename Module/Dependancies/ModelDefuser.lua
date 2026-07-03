local Services = {
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    Debris = game:GetService("Debris"),
};
local knownMaliciousScripts={
    "Script, or is it???", -- infamous obfuscator signature
    "ROFL", -- old script kiddie favorite
    "iNfEcTiOn",-- another old favorite
    "H4CK3D_BY_1337", -- yet another old favorite
    "NukerScript", -- very common malicious script name
    "Spread", -- often used in scripts that spread themselves
    "Vaccine", --nice try, but we know what you mean
    "Anti-Lag" --ironically, this is often used to cause lag
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
            Services.Debris:AddItem(s,0);
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
                Services.Debris:AddItem(tocheck,0);
                malicious=true;
            end;
        end;
    end;
    return malicious;
end;
function mod:defuseModel(parent)
    for _,item:Instance in pairs(parent:GetDescendants()) do
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