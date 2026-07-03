local Services={
    ReplicatedStorage=game:GetService("ReplicatedStorage"),
    InsertService=game:GetService("InsertService"),
};
local modules={
    b64=require(script.Parent.Base64), --b64
};
local parser={};

function parser:ParseSharedStr(sstr)
    local actualString=modules.b64.decode(sstr);
    return actualString;
end;

return parser;